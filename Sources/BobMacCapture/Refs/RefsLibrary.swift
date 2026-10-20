import AppKit
import CaptureCore
import Combine
import CoreServices
import Foundation
import RefsCore

/// Why the library refreshed: launch, the vault watcher, a panel open that
/// found a stale snapshot, a manual request, wake from sleep, a capture
/// success (Today only), a Today-link success (both lanes), the 10-minute
/// Today timer, or Recheck Bob.
public enum RefsRefreshReason: String, Sendable {
  case launch
  case watcher
  case panelOpen
  case manual
  case wake
  case captureSuccess
  case todayLink
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
  case busy

  /// Human message for the rename card when a rename is submitted
  /// during a scan.
  public var message: String {
    switch self {
    case .unavailable:
      return "Bob is not available."
    case .busy:
      return "A library scan is running — try again when it finishes."
    }
  }
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
  @Published public private(set) var items: [RefItem] = [] {
    didSet {
      rebuildItemIndex()
    }
  }
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
  /// Increments after each successful Today refresh, so optimistic
  /// Today pills can yield to the refreshed Bob snapshot.
  @Published public private(set) var todayRefreshGeneration: UInt64 = 0
  /// Increments after each successful reference snapshot refresh.
  @Published public private(set) var snapshotRefreshGeneration: UInt64 = 0

  /// Seconds between background Today refreshes.
  public static let todayRefreshInterval: TimeInterval = 600

  /// Minimum seconds between panel-open pulls on the `refs-pull` lane.
  public static let pullThrottleInterval: TimeInterval = 5

  private var fetcher: RefsFetching?
  private let snapshotStore: RefsSnapshotStore
  private let openLogStore: RefsOpenLogStore
  private let newMarkStore: RefsNewMarkStore
  private let vaultRoot: () -> URL
  private let fileExists: (URL) -> Bool
  private let spotlight: RefsSpotlightProviding
  private let now: () -> Date

  private var snapshot: RefsSnapshot?
  private var itemIndicesByID: [String: Int] = [:]
  private var today = RefsToday()
  private var openEvents: [RefsOpenEvent] = []

  private var snapshotTask: Task<Bool, Never>?
  private var snapshotFollowUp = false
  private var todayTask: Task<Bool, Never>?
  private var todayFollowUp = false
  private var lastPanelOpenTodayStartedAt: Date?
  private var gitTask: Task<Void, Never>?
  private var gitFollowUp = false
  private var scanTask: Task<Void, Never>?
  private var scanInFlight = false
  private var renameInFlight = false
  private var deferredWatcherRefresh = false
  private var pullTask: Task<Void, Never>?
  private var lastPullStartedAt: Date?

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
    newMarkStore: RefsNewMarkStore,
    vaultRoot: @escaping () -> URL,
    fileExists: @escaping (URL) -> Bool,
    spotlight: RefsSpotlightProviding,
    now: @escaping () -> Date,
    wakeCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
  ) {
    self.fetcher = fetcher
    self.snapshotStore = snapshotStore
    self.openLogStore = openLogStore
    self.newMarkStore = newMarkStore
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
    signals.newMarks = newMarkStore.load()
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

  /// Returns the first matching item, preserving the old
  /// `items.first(where:)` behavior for duplicate ids.
  public func item(id: String) -> RefItem? {
    guard let index = itemIndicesByID[id], items.indices.contains(index) else {
      return nil
    }
    return items[index]
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
  public func refreshIfStale(
    maxAge: TimeInterval = 60,
    includeToday: Bool = true
  ) {
    guard snapshotTask == nil else {
      return
    }
    if let last = lastSuccessAt, now().timeIntervalSince(last) < maxAge {
      return
    }
    if includeToday {
      refresh(reason: .panelOpen)
    } else {
      refreshSnapshot(reason: .panelOpen)
    }
  }

  /// Refreshes the ledger's Today value in the background: every panel
  /// open, every successful capture, and every 10 minutes. The reason
  /// rides along so a trigger during a refresh re-runs the same lane.
  public func refreshToday(reason: RefsRefreshReason) {
    guard todayTask == nil else {
      todayFollowUp = true
      return
    }
    todayTask = Task { [weak self] in
      guard let self else { return false }
      return await self.runTodayPass(reason: reason)
    }
  }

  /// Requests the panel-open Today refresh within the shared five-second
  /// show window. Other Today triggers remain unthrottled.
  public func requestTodayForPanelOpen() {
    let current = now()
    if let lastPanelOpenTodayStartedAt,
      current.timeIntervalSince(lastPanelOpenTodayStartedAt) < Self.pullThrottleInterval
    {
      CaptureSignpost.event("refs-today-skipped")
      return
    }
    lastPanelOpenTodayStartedAt = current
    refreshToday(reason: .panelOpen)
  }

  /// Refreshes Today and waits through a queued follow-up if another
  /// Today pass was already running. Returns whether the final pass
  /// completed successfully.
  @discardableResult
  public func refreshTodayAndWait(reason: RefsRefreshReason) async -> Bool {
    refreshToday(reason: reason)
    return await waitForTodayPasses()
  }

  /// Refreshes both the task-detail snapshot and the Today ledger, waiting
  /// through one queued follow-up on each coalescing lane.
  public func refreshAndWait(reason: RefsRefreshReason) async -> (snapshot: Bool, today: Bool) {
    refreshSnapshot(reason: reason)
    refreshToday(reason: reason)
    let snapshotSucceeded = await waitForSnapshotPasses()
    let todaySucceeded = await waitForTodayPasses()
    return (snapshotSucceeded, todaySucceeded)
  }

  /// Fast-forwards the vault on the `refs-pull` lane without
  /// refreshing: the existing vault watcher sees the fast-forward and
  /// runs the normal snapshot refresh. Single-flight: a trigger that
  /// arrives while a pull is running joins that pull. Throttled for
  /// panel opens; `pullAndWait` is the unthrottled ⌘R path. Skipped
  /// while a scan or rename is in flight. Failures are only logged and
  /// never touch `refreshState`, banners, or the footer.
  public func requestPullForPanelOpen() {
    guard !scanInFlight, !renameInFlight else {
      return
    }
    if let last = lastPullStartedAt,
      now().timeIntervalSince(last) < Self.pullThrottleInterval
    {
      return
    }
    guard pullTask == nil else {
      return
    }
    lastPullStartedAt = now()
    pullTask = Task { [weak self] in await self?.runPullPass() }
  }

  /// Awaits the single-flight `refs-pull` lane without throttling, then
  /// returns. Skipped while a scan or rename is in flight. Never throws:
  /// failures are only logged so a ⌘R refresh still runs.
  public func pullAndWait() async {
    if let existing = pullTask {
      await existing.value
      return
    }
    guard !scanInFlight, !renameInFlight else {
      return
    }
    guard fetcher != nil else {
      return
    }
    lastPullStartedAt = now()
    pullTask = Task { [weak self] in await self?.runPullPass() }
    await pullTask?.value
  }

  private func runPullPass() async {
    defer { pullTask = nil }
    guard let fetcher else {
      return
    }
    let token = CaptureSignpost.begin("refs-pull")
    defer { CaptureSignpost.end(token) }
    do {
      try await fetcher.pull()
    } catch {
      NSLog("refs-pull lane failed: %@", Self.boundedMessage(for: error))
    }
  }

  /// Runs `bob ref scan -w -f json` on its own `refs-scan` lane.
  /// Returns false when a scan is already running and starts nothing.
  /// The outcome publishes as `scanState` only after the post-scan
  /// snapshot pass completes, so new rows are already in `items`.
  /// A scan never cancels another lane, and no other lane cancels it.
  @discardableResult
  public func scan() -> Bool {
    guard scanTask == nil, !scanInFlight, !renameInFlight else {
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
    if scanInFlight || renameInFlight {
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

  /// Writes or removes the ⌥N mark for `id` and publishes
  /// synchronously, so a fast second press sees the new state.
  public func setNewMark(id: String, mark: RefsNewMark?) {
    newMarkStore.apply(path: id, mark: mark)
    signals.newMarks = newMarkStore.load()
    signals.now = now()
  }

  /// Flips NEW for `id` using the smallest-mark rule. Ineligible
  /// rows write nothing.
  @discardableResult
  public func toggleNew(id: String) -> RefsNewToggleResult {
    guard let item = item(id: id) else {
      return .ineligible
    }
    let result = RefsNewToggle.result(for: item, signals: signals, now: now())
    if case .apply(let mark, _) = result {
      setNewMark(id: id, mark: mark)
    }
    return result
  }

  /// Records the smallest mark that makes `id` not NEW, when it is
  /// currently NEW. Used after a successful Link to Today from Bob Refs.
  public func markSeenIfNew(id: String) {
    guard let item = item(id: id), RefsRanker.isNew(item, signals: signals) else {
      return
    }
    switch RefsNewToggle.result(for: item, signals: signals, now: now()) {
    case .apply(let mark, _):
      setNewMark(id: id, mark: mark)
    case .ineligible:
      break
    }
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

  /// The resolved vault root used to match open Highlights tabs to PDFs.
  public var vaultRootURL: URL {
    vaultRoot()
  }

  /// Hydrates one note's annotations and tasks for the inspector on
  /// the `refs-show` lane. Throws when no fetcher is set.
  public func showDetail(path: String) async throws -> RefsShowResponse {
    guard let fetcher else {
      throw RefsLibraryError.unavailable
    }
    return try await fetcher.show(path: path)
  }

  /// Runs Bob's reference-to-Pomodoro preview or write. Bob owns the
  /// selector semantics and the vault mutation.
  public func linkToToday(
    notePath: String,
    selector: RefsTodayLinkSelector = .automatic,
    dryRun: Bool
  ) async throws -> RefsTodayLinkResponse {
    guard let fetcher else {
      throw RefsLibraryError.unavailable
    }
    return try await fetcher.linkToToday(
      notePath: notePath, selector: selector, dryRun: dryRun
    )
  }

  /// Runs Bob's whole-file rename on its independent, non-cancelling
  /// lane. Watcher churn from the move is held until Bob returns, then
  /// one fresh listing replaces the old path before this method ends.
  public func rename(notePath: String, name: String) async throws -> RefsRenameResponse {
    guard !scanInFlight, !renameInFlight else {
      throw RefsLibraryError.busy
    }
    guard let fetcher else {
      throw RefsLibraryError.unavailable
    }
    renameInFlight = true
    deferredWatcherRefresh = false
    defer {
      renameInFlight = false
      deferredWatcherRefresh = false
    }

    do {
      let response = try await fetcher.rename(notePath: notePath, name: name)
      let succeeded = response.error == nil && response.ok != false
      if succeeded {
        if let destination = response.to?.path {
          openLogStore.rename(from: notePath, to: destination)
          openEvents = openLogStore.load()
          publishOpenSignals()
          newMarkStore.rename(from: notePath, to: destination)
          signals.newMarks = newMarkStore.load()
          signals.now = now()
        }
        await refreshSnapshotAfterRename()
      } else if deferredWatcherRefresh {
        await refreshSnapshotAfterRename()
      }
      return response
    } catch {
      if deferredWatcherRefresh {
        await refreshSnapshotAfterRename()
      }
      throw error
    }
  }

  private func refreshSnapshotAfterRename() async {
    while let current = snapshotTask {
      await current.value
    }
    refreshSnapshot(reason: .manual)
    while let current = snapshotTask {
      await current.value
    }
  }

  /// Merges inspector-discovered facts into the signals: intrinsics
  /// page counts and outline headings. Publishing here refreshes row
  /// content in place; it never re-ranks.
  public func applyInspectorSignals(
    pageCounts: [String: Int],
    outlineHeadings: [String: [String]]
  ) {
    var next = signals
    for (id, pages) in pageCounts {
      next.pageCounts[id] = pages
    }
    for (id, headings) in outlineHeadings {
      next.outlineHeadings[id] = headings
    }
    next.now = now()
    signals = next
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
    snapshotTask = Task { [weak self] in
      guard let self else { return false }
      return await self.runSnapshotPass(reason: reason)
    }
  }

  private func waitForSnapshotPasses() async -> Bool {
    var succeeded = false
    while let current = snapshotTask {
      succeeded = await current.value
    }
    return succeeded
  }

  private func waitForTodayPasses() async -> Bool {
    var succeeded = false
    while let current = todayTask {
      succeeded = await current.value
    }
    return succeeded
  }

  private func runSnapshotPass(reason: RefsRefreshReason) async -> Bool {
    defer {
      snapshotTask = nil
      if snapshotFollowUp {
        snapshotFollowUp = false
        refreshSnapshot(reason: reason)
      }
    }
    guard !Task.isCancelled else {
      return false
    }
    refreshState = .refreshing
    guard let fetcher else {
      if !hasSnapshot {
        refreshState = .failed(message: "Bob is not available", at: now())
      } else {
        refreshState = .idle
      }
      return false
    }
    let token = CaptureSignpost.begin("refs-refresh")
    defer { CaptureSignpost.end(token) }
    do {
      let response = try await fetcher.list(gitDates: false)
      var next = RefsSnapshot(
        fetchedAt: now(),
        records: response.refs,
        gitAddedDates: [:]
      )
      let root = vaultRoot()
      let requests = RefsCatalog.items(from: next).map {
        RefsSpotlightRequest(id: $0.id, url: root.appendingPathComponent($0.pdfPath))
      }
      let (missing, facts) = await Self.checkFilesAndSweep(
        requests: requests,
        fileExists: fileExists,
        spotlight: spotlight
      )
      // Carry git dates and instants forward only after the sweep:
      // the `-g` lane can merge while this pass awaits, and reading
      // them earlier would publish over that merge and re-run the
      // `-g` pass.
      let paths = Set(response.refs.map(\.path))
      next.gitAddedDates = (snapshot?.gitAddedDates ?? [:])
        .filter { paths.contains($0.key) }
      next.gitAddedAt = (snapshot?.gitAddedAt ?? [:])
        .filter { paths.contains($0.key) }
      let items = RefsCatalog.items(from: next)
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
      snapshotRefreshGeneration &+= 1
      snapshotStore.save(snapshot: next, today: today)
      // The git-date lane runs after the snapshot publishes, so the
      // first paint never waits for `-g` and a `-g` failure cannot
      // take a good snapshot off the screen.
      refreshGitDates()
      return true
    } catch {
      refreshState = .failed(message: Self.boundedMessage(for: error), at: now())
      return false
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
      guard let latest = snapshot else {
        return
      }
      let merged = latest.mergingGitDates(from: git.refs, needing: needing)
      snapshot = merged
      items = RefsCatalog.items(from: merged)
      snapshotStore.save(snapshot: merged, today: today)
    } catch {
      // A `-g` failure keeps the published snapshot and the refresh
      // state as they are; it is logged and nothing else.
      NSLog("refs-git lane failed: %@", Self.boundedMessage(for: error))
    }
  }

  private func runTodayPass(reason: RefsRefreshReason) async -> Bool {
    defer {
      todayTask = nil
      if todayFollowUp {
        todayFollowUp = false
        refreshToday(reason: reason)
      }
    }
    guard let fetcher else {
      return false
    }
    do {
      let plan = try await fetcher.plan()
      let refreshedToday = RefsToday(plan: plan)
      let todayChanged = today != refreshedToday
      if todayChanged {
        today = refreshedToday
        signals.today = refreshedToday
        if let snapshot {
          snapshotStore.save(snapshot: snapshot, today: refreshedToday)
        }
      }
      todayRefreshGeneration &+= 1
      return true
    } catch {
      // A failed Today refresh — including a schema mismatch — keeps
      // the last Today value instead of clearing it.
      return false
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
    let watcher = VaultTargetWatcher(
      paths: paths,
      latency: 0.5,
      onChange: {},
      onBatch: { [weak self] batch in
        guard
          RefsWatcherRelevance.isRelevant(
            batch,
            vaultRoot: root.path
          )
        else {
          return
        }
        Task { await self?.handleWatcherChange() }
      },
      onFailure: { [weak self] message in
        Task { await self?.watcherFailed(message) }
      }
    )
    self.watcher = watcher
    watcher.start()
  }

  private func rebuildItemIndex() {
    var indices: [String: Int] = [:]
    for (index, item) in items.enumerated() where indices[item.id] == nil {
      indices[item.id] = index
    }
    itemIndicesByID = indices
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
