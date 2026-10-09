import AppKit
import CaptureCore
import Combine
import CoreServices
import Foundation
import RefsCore

/// Why the library refreshed: launch, the vault watcher, a panel open that
/// found a stale snapshot, a manual request, wake from sleep, a capture
/// success (Today only), the 10-minute Today timer, or Recheck Bob.
public enum RefsRefreshReason: String, Sendable {
    case launch
    case watcher
    case panelOpen
    case manual
    case wake
    case captureSuccess
    case timer
    case recheck
    case scan
}

/// The scan lane state the panel model reads: idle, a scan in flight,
/// or the last outcome. The outcome publishes only after the post-scan
/// snapshot pass completes, so new rows are already in `items`.
public enum RefsScanState: Equatable, Sendable {
    case idle
    case scanning(startedAt: Date)
    case finished(RefsScanOutcome)
}

/// The snapshot refresh state the panel footer reads: idle, a refresh in
/// flight, or the last failure with its bounded message and date. A failed
/// refresh keeps the last good snapshot; it never empties the list.
public enum RefsRefreshState: Equatable, Sendable {
    case idle
    case refreshing
    case failed(message: String, at: Date)
}

/// One Spotlight lookup: the note id plus the absolute PDF URL to query.
public struct RefsSpotlightRequest: Sendable {
    public let id: String
    public let url: URL

    public init(id: String, url: URL) {
        self.id = id
        self.url = url
    }
}

/// The Spotlight facts per note: the last-used date and the page count.
/// Either may be absent when Spotlight knows nothing about the PDF.
public struct RefsSpotlightFacts: Sendable {
    public var lastUsed: Date?
    public var pageCount: Int?

    public init(lastUsed: Date? = nil, pageCount: Int? = nil) {
        self.lastUsed = lastUsed
        self.pageCount = pageCount
    }
}

/// The one-shot Spotlight metadata sweep behind the library: last-used
/// dates and page counts per PDF. Tests inject a fake.
public protocol RefsSpotlightProviding: Sendable {
    func sweep(_ requests: [RefsSpotlightRequest]) async -> [String: RefsSpotlightFacts]
}

/// The concrete sweep: `MDItemCreateWithURL` / `MDItemCopyAttribute` for
/// `kMDItemLastUsedDate` and `kMDItemNumberOfPages`, off the main actor on
/// a utility queue. It never starts a live query, so nothing can leak one.
public struct SpotlightRefsSignals: RefsSpotlightProviding, Sendable {
    public init() {}

    public func sweep(_ requests: [RefsSpotlightRequest]) async -> [String: RefsSpotlightFacts] {
        await Task.detached(priority: .utility) {
            var facts: [String: RefsSpotlightFacts] = [:]
            for request in requests {
                facts[request.id] = Self.facts(for: request.url)
            }
            return facts
        }.value
    }

    static func facts(for url: URL) -> RefsSpotlightFacts {
        var result = RefsSpotlightFacts()
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else {
            return result
        }
        if let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            result.lastUsed = lastUsed
        }
        if let pages = MDItemCopyAttribute(item, kMDItemNumberOfPages) as? NSNumber {
            result.pageCount = pages.intValue
        }
        return result
    }
}

/// Bound on refresh failure text so a backend dump cannot fill the callout.
private let refsMaxErrorMessageLength = 200

/// Why the inspector's detail load failed before it reached `bob`.
public enum RefsLibraryError: Error, Sendable {
    case unavailable
}

/// The Refs library refresh service: the cached snapshot, the git-date
/// backfill pass, Today, the Spotlight sweep, missing-PDF checks, and the
/// open log. The app filters, ranks, and presents what this service
/// publishes; it never parses frontmatter or note bodies, and opening a
/// reference never writes the vault — the open history lives only in the
/// app's Application Support directory.
@MainActor
public final class RefsLibrary: ObservableObject {
    /// The working set the panel ranks, newest snapshot first.
    @Published public private(set) var items: [RefItem] = []
    /// Today, open stats, Spotlight facts, missing PDFs, and the clock.
    @Published public private(set) var signals: RefsSignals
    /// The snapshot refresh state the footer reads.
    @Published public private(set) var refreshState: RefsRefreshState = .idle
    /// When the last snapshot refresh succeeded.
    @Published public private(set) var lastSuccessAt: Date?
    /// Whether any snapshot — cached or refreshed — has loaded.
    @Published public private(set) var hasSnapshot: Bool = false
    /// The scan lane state: idle, scanning, or the last outcome.
    @Published public private(set) var scanState: RefsScanState = .idle

    /// Seconds between background Today refreshes.
    public static let todayRefreshInterval: TimeInterval = 600

    private var fetcher: RefsFetching?
    private let snapshotStore: RefsSnapshotStore
    private let openLogStore: RefsOpenLogStore
    private let vaultRoot: () -> URL
    private let fileExists: (URL) -> Bool
    private let spotlight: RefsSpotlightProviding
    private let now: () -> Date

    private var snapshot: RefsSnapshot?
    private var today = RefsToday()
    private var openEvents: [RefsOpenEvent] = []

    private var snapshotTask: Task<Void, Never>?
    private var snapshotFollowUp = false
    private var todayTask: Task<Void, Never>?
    private var todayFollowUp = false
    private var gitTask: Task<Void, Never>?
    private var gitFollowUp = false
    private var scanTask: Task<Void, Never>?
    private var scanInFlight = false
    private var deferredWatcherRefresh = false

    private var watcher: VaultTargetWatcher?
    private var todayTimer: Timer?
    private var wakeObserver: Any?
    /// The center `NSWorkspace.didWakeNotification` is posted on. It is a
    /// parameter so tests can post wake on their own center.
    private let wakeCenter: NotificationCenter

    public init(
        fetcher: RefsFetching?,
        snapshotStore: RefsSnapshotStore,
        openLogStore: RefsOpenLogStore,
        vaultRoot: @escaping () -> URL,
        fileExists: @escaping (URL) -> Bool,
        spotlight: RefsSpotlightProviding,
        now: @escaping () -> Date,
        wakeCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.fetcher = fetcher
        self.snapshotStore = snapshotStore
        self.openLogStore = openLogStore
        self.vaultRoot = vaultRoot
        self.fileExists = fileExists
        self.spotlight = spotlight
        self.now = now
        self.wakeCenter = wakeCenter
        signals = RefsSignals(now: now())
    }

    /// Loads the cache and the open log so a cold launch paints
    /// immediately, starts the watcher, the Today timer, and the wake
    /// observer, then refreshes.
    public func start() {
        let file = snapshotStore.load()
        if let snapshot = file.snapshot {
            self.snapshot = snapshot
            items = RefsCatalog.items(from: snapshot)
            hasSnapshot = true
        }
        if let today = file.today {
            self.today = today
        }
        openEvents = openLogStore.load()
        signals.today = today
        publishOpenSignals()
        startWatcher()
        startTodayTimer()
        startWakeObserver()
        refresh(reason: .launch)
    }

    /// Stops the watcher, the Today timer, and the wake observer.
    /// AppDelegate calls this on terminate and before restarting the
    /// watcher for a new vault root.
    public func stop() {
        watcher?.invalidate()
        watcher = nil
        todayTimer?.invalidate()
        todayTimer = nil
        if let wakeObserver {
            wakeCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    /// Re-points the fetcher (Recheck Bob) without refreshing.
    public func setFetcher(_ fetcher: RefsFetching?) {
        self.fetcher = fetcher
    }

    /// Restarts the refs watcher for the current vault root.
    public func restartWatcher() {
        watcher?.invalidate()
        watcher = nil
        startWatcher()
    }

    /// Forgets the last success so the next panel open refreshes.
    /// A capture success calls this alongside `refreshToday`.
    public func markStale() {
        lastSuccessAt = nil
    }

    /// Refreshes the snapshot (with the git-date lane when needed) and
    /// Today. Triggers that arrive during a refresh schedule exactly one
    /// follow-up per lane.
    public func refresh(reason: RefsRefreshReason) {
        refreshSnapshot(reason: reason)
        refreshToday(reason: reason)
    }

    /// Refreshes when the snapshot is older than `maxAge`, or when no
    /// refresh has ever succeeded. The panel calls this on every open.
    public func refreshIfStale(maxAge: TimeInterval = 60) {
        if let last = lastSuccessAt, now().timeIntervalSince(last) < maxAge {
            return
        }
        refresh(reason: .panelOpen)
    }

    /// Refreshes Today in the background: every panel open, every
    /// successful capture, and every 10 minutes. The reason rides along
    /// so a trigger during a refresh re-runs the same lane.
    public func refreshToday(reason: RefsRefreshReason) {
        guard todayTask == nil else {
            todayFollowUp = true
            return
        }
        todayTask = Task { [weak self] in await self?.runTodayPass(reason: reason) }
    }

    /// Runs `bob ref scan -w -f json` on its own `refs-scan` lane.
    /// Returns false when a scan is already running and starts nothing.
    /// The outcome publishes as `scanState` only after the post-scan
    /// snapshot pass completes, so new rows are already in `items`.
    /// A scan never cancels another lane, and no other lane cancels it.
    @discardableResult
    public func scan() -> Bool {
        guard scanTask == nil, !scanInFlight else {
            return false
        }
        scanState = .scanning(startedAt: now())
        scanInFlight = true
        deferredWatcherRefresh = false
        scanTask = Task { [weak self] in await self?.runScanPass() }
        return true
    }

    /// The watcher seam: the watcher callback calls this, so tests can
    /// drive it. While a scan runs, a watcher change only records that
    /// one happened; it does not refresh. The post-scan refresh covers
    /// every deferred change in one pass.
    func handleWatcherChange() {
        if scanInFlight {
            deferredWatcherRefresh = true
        } else {
            refresh(reason: .watcher)
        }
    }

    /// Installs a scan state for design tests and previews, skipping
    /// every process.
    func installScanStateForPreviews(_ state: RefsScanState) {
        scanState = state
        scanInFlight = false
        deferredWatcherRefresh = false
        scanTask = nil
    }

    /// Records a Highlights or default-app open. Note opens, reveals,
    /// selections, and previews are never recorded.
    public func recordOpen(id: String) {
        openLogStore.append(RefsOpenEvent(path: id, at: now()))
        openEvents = openLogStore.load()
        publishOpenSignals()
    }

    /// Clears both the open log and the open stats.
    public func resetOpenHistory() {
        openLogStore.reset()
        openEvents = []
        publishOpenSignals()
    }

    /// The absolute PDF URL, or nil when the stored path is unsafe: only
    /// vault-relative paths without a `..` component resolve.
    public func pdfURL(for item: RefItem) -> URL? {
        guard RefItem.isSafePDFPath(item.pdfPath) else {
            return nil
        }
        return vaultRoot().appendingPathComponent(item.pdfPath)
    }

    /// The absolute note URL for Obsidian opens and Finder reveals.
    public func noteURL(for item: RefItem) -> URL {
        vaultRoot().appendingPathComponent(item.id)
    }

    /// The absolute narration-audio URL, or nil when the stored path is
    /// unsafe or absent.
    public func audioURL(for item: RefItem) -> URL? {
        guard let audio = item.audioPath,
              !audio.isEmpty,
              RefItem.isSafePDFPath(audio)
        else {
            return nil
        }
        return vaultRoot().appendingPathComponent(audio)
    }

    /// When the current snapshot was fetched: the inspector's `ref show`
    /// cache keys on (id, fetch time).
    public var snapshotFetchedAt: Date? {
        snapshot?.fetchedAt
    }

    /// Hydrates one note's annotations and tasks for the inspector on
    /// the `refs-show` lane. Throws when no fetcher is set.
    public func showDetail(path: String) async throws -> RefsShowResponse {
        guard let fetcher else {
            throw RefsLibraryError.unavailable
        }
        return try await fetcher.show(path: path)
    }

    /// Merges inspector-discovered facts into the signals: intrinsics
    /// page counts and outline headings. Publishing here refreshes row
    /// content in place; it never re-ranks.
    public func applyInspectorSignals(
        pageCounts: [String: Int],
        outlineHeadings: [String: [String]]
    ) {
        for (id, pages) in pageCounts {
            signals.pageCounts[id] = pages
        }
        for (id, headings) in outlineHeadings {
            signals.outlineHeadings[id] = headings
        }
        signals.now = now()
    }

    /// Installs canned state for design tests and previews, skipping
    /// every process.
    func installSnapshotForPreviews(
        items: [RefItem],
        signals: RefsSignals,
        refreshState: RefsRefreshState
    ) {
        self.items = items
        self.signals = signals
        self.refreshState = refreshState
        hasSnapshot = !items.isEmpty
    }

    private func refreshSnapshot(reason: RefsRefreshReason) {
        guard snapshotTask == nil else {
            snapshotFollowUp = true
            return
        }
        snapshotTask = Task { [weak self] in await self?.runSnapshotPass(reason: reason) }
    }

    private func runSnapshotPass(reason: RefsRefreshReason) async {
        defer {
            snapshotTask = nil
            if snapshotFollowUp {
                snapshotFollowUp = false
                refreshSnapshot(reason: reason)
            }
        }
        guard !Task.isCancelled else {
            return
        }
        refreshState = .refreshing
        guard let fetcher else {
            if !hasSnapshot {
                refreshState = .failed(message: "Bob is not available", at: now())
            } else {
                refreshState = .idle
            }
            return
        }
        let token = CaptureSignpost.begin("refs-refresh")
        defer { CaptureSignpost.end(token) }
        do {
            let response = try await fetcher.list(gitDates: false)
            var next = RefsSnapshot(
                fetchedAt: now(),
                records: response.refs,
                gitAddedDates: snapshot?.gitAddedDates ?? [:]
            )
            let paths = Set(response.refs.map(\.path))
            next.gitAddedDates = next.gitAddedDates.filter { paths.contains($0.key) }
            let items = RefsCatalog.items(from: next)
            let root = vaultRoot()
            let requests = items.map {
                RefsSpotlightRequest(id: $0.id, url: root.appendingPathComponent($0.pdfPath))
            }
            let (missing, facts) = await Self.checkFilesAndSweep(
                requests: requests,
                fileExists: fileExists,
                spotlight: spotlight
            )
            snapshot = next
            self.items = items
            var signals = signals
            signals.now = now()
            signals.missingPDFs = missing
            signals.externalLastUsed = facts.compactMapValues(\.lastUsed)
            signals.pageCounts = facts.compactMapValues(\.pageCount)
            self.signals = signals
            lastSuccessAt = now()
            refreshState = .idle
            hasSnapshot = true
            snapshotStore.save(snapshot: next, today: today)
            // The git-date lane runs after the snapshot publishes, so the
            // first paint never waits for `-g` and a `-g` failure cannot
            // take a good snapshot off the screen.
            refreshGitDates()
        } catch {
            refreshState = .failed(message: Self.boundedMessage(for: error), at: now())
        }
    }

    /// Runs the `refs-git` lane when some row still lacks an `added`
    /// date. Triggers during a run schedule exactly one follow-up, like
    /// the other lanes.
    private func refreshGitDates() {
        guard gitTask == nil else {
            gitFollowUp = true
            return
        }
        gitTask = Task { [weak self] in await self?.runGitDatePass() }
    }

    private func runGitDatePass() async {
        defer {
            gitTask = nil
            if gitFollowUp {
                gitFollowUp = false
                refreshGitDates()
            }
        }
        guard !Task.isCancelled else {
            return
        }
        guard let fetcher, let current = snapshot else {
            return
        }
        let needing = Set(current.pathsNeedingGitDates)
        guard !needing.isEmpty else {
            return
        }
        do {
            let git = try await fetcher.list(gitDates: true)
            guard var latest = snapshot else {
                return
            }
            let stillNeeding = Set(latest.pathsNeedingGitDates)
            var merged = latest.gitAddedDates
            for record in git.refs {
                guard let added = record.added,
                      needing.contains(record.path),
                      stillNeeding.contains(record.path),
                      record.addedSource == "git"
                else {
                    continue
                }
                merged[record.path] = added
            }
            latest.gitAddedDates = merged
            snapshot = latest
            items = RefsCatalog.items(from: latest)
            snapshotStore.save(snapshot: latest, today: today)
        } catch {
            // A `-g` failure keeps the published snapshot and the refresh
            // state as they are; it is logged and nothing else.
            NSLog("refs-git lane failed: %@", Self.boundedMessage(for: error))
        }
    }

    private func runTodayPass(reason: RefsRefreshReason) async {
        defer {
            todayTask = nil
            if todayFollowUp {
                todayFollowUp = false
                refreshToday(reason: reason)
            }
        }
        guard let fetcher else {
            return
        }
        do {
            let plan = try await fetcher.plan()
            today = RefsToday(plan: plan)
            signals.today = today
            if let snapshot {
                snapshotStore.save(snapshot: snapshot, today: today)
            }
        } catch {
            // A failed Today refresh — including a schema mismatch — keeps
            // the last Today value instead of clearing it.
        }
    }

    private func runScanPass() async {
        let token = CaptureSignpost.begin("refs-scan")
        defer {
            CaptureSignpost.end(token)
            scanTask = nil
        }
        let outcome: RefsScanOutcome
        if let fetcher {
            do {
                let response = try await fetcher.scan()
                let finishedAt = now()
                outcome = RefsScanOutcome(response: response, finishedAt: finishedAt)
            } catch {
                let finishedAt = now()
                outcome = RefsScanOutcome(
                    problem: Self.scanProblem(for: error),
                    finishedAt: finishedAt
                )
            }
        } else {
            outcome = RefsScanOutcome(
                problem: RefsScanProblem(
                    code: "bob_unavailable",
                    message: "Bob is not available.",
                    hint: "Check Settings › Diagnostics, then use Recheck Bob."
                ),
                finishedAt: now()
            )
        }
        scanInFlight = false
        deferredWatcherRefresh = false
        await runPostScanRefresh()
        var signals = signals
        switch outcome.kind {
        case .succeeded, .partial:
            if outcome.created.isEmpty {
                signals.scan = nil
            } else {
                signals.scan = RefsScanMark(
                    ids: outcome.created.map(\.path),
                    at: outcome.finishedAt
                )
            }
        case .failed:
            break
        }
        signals.now = now()
        self.signals = signals
        scanState = .finished(outcome)
    }

    private func runPostScanRefresh() async {
        while let current = snapshotTask {
            await current.value
            if snapshotTask == nil {
                break
            }
        }
        refresh(reason: .scan)
        while let current = snapshotTask {
            await current.value
            if snapshotTask == nil {
                break
            }
        }
    }

    nonisolated static func scanProblem(for error: Error) -> RefsScanProblem {
        if let clientError = error as? BobClientError {
            if case .timedOut = clientError {
                return RefsScanProblem(
                    code: "timed_out",
                    message: "The scan ran longer than 5 minutes and was stopped.",
                    hint: "Run `bob ref scan -w` in Terminal to see where it stalls."
                )
            }
            if case .processFailed(_, let exitStatus, _) = clientError,
                exitStatus == 2
            {
                return RefsScanProblem(
                    code: "bob_too_old",
                    message: "This bob can't report scans to Bob Refs yet.",
                    hint: "Update bob on this Mac, then press ⌘S again."
                )
            }
        }
        return RefsScanProblem(
            code: "transport",
            message: boundedMessage(for: error)
        )
    }

    private func publishOpenSignals() {
        signals.opens = RefsOpenStats(events: openEvents, now: now())
        signals.now = now()
    }

    private func startWatcher() {
        let root = vaultRoot()
        // Reading tasks live in root area/project/inbox notes and archive
        // into `done/`, so root-note edits must refresh like `ref/` and
        // `lib/` moves do. The stream is recursive, so the vault root
        // covers root `*.md` files and `done/`; the explicit entries keep
        // refreshing when the root itself is unavailable but a subdir is
        // not, and document what the panel depends on.
        let paths = [
            root.path,
            root.appendingPathComponent("ref").path,
            root.appendingPathComponent("lib").path,
            root.appendingPathComponent("done").path,
        ]
        let watcher = VaultTargetWatcher(paths: paths, latency: 0.5) { [weak self] in
            Task { await self?.handleWatcherChange() }
        } onFailure: { [weak self] message in
            Task { await self?.watcherFailed(message) }
        }
        self.watcher = watcher
        watcher.start()
    }

    private func watcherFailed(_ message: String) {
        if !hasSnapshot {
            refreshState = .failed(message: message, at: now())
        }
    }

    private func startTodayTimer() {
        todayTimer?.invalidate()
        todayTimer = Timer.scheduledTimer(
            withTimeInterval: Self.todayRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { await self?.refreshToday(reason: .timer) }
        }
    }

    private func startWakeObserver() {
        if wakeObserver != nil {
            return
        }
        // `didWakeNotification` is posted on the workspace center, not the
        // default center, so this must observe `wakeCenter`.
        wakeObserver = wakeCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh(reason: .wake) }
        }
    }

    /// Missing-PDF checks plus the Spotlight sweep, off the main actor,
    /// so both publish together without blocking the panel.
    nonisolated static func checkFilesAndSweep(
        requests: [RefsSpotlightRequest],
        fileExists: (URL) -> Bool,
        spotlight: RefsSpotlightProviding
    ) async -> (Set<String>, [String: RefsSpotlightFacts]) {
        var missing: Set<String> = []
        for request in requests {
            if !fileExists(request.url) {
                missing.insert(request.id)
            }
        }
        let facts = await spotlight.sweep(requests)
        return (missing, facts)
    }

    /// Bounds failure text so a backend dump cannot fill the callout card.
    nonisolated static func boundedMessage(for error: Error) -> String {
        let text = String(describing: error)
        guard text.count > refsMaxErrorMessageLength else {
            return text
        }
        return String(text.prefix(refsMaxErrorMessageLength)) + "…"
    }
}
