import AppKit
import CaptureCore
import Combine
import Foundation
import RefsCore
import SwiftUI

/// Where an open dispatches: Highlights, the reference note in Obsidian,
/// the PDF revealed in Finder, or the PDF in its default app. Only
/// Highlights and default-app opens count as opens.
public enum RefsOpenTarget: Equatable, Sendable {
    case highlights
    case note
    case reveal
    case defaultApp
}

/// Every panel gesture the key router and the list funnel through.
public enum RefsCommand: Equatable, Sendable {
    case open(RefsOpenTarget)
    case move(RefsMove)
    case setScope(RefScope)
    case escape
    case deleteBackwardOnEmpty
    case refresh
    case select(id: String)
    case activate(id: String)
    case showActions
    case showCopyCard
    case showRenameCard
    case scan
    /// Scroll the right-hand inspector by half its viewport.
    case scrollInspector(RefsInspectorScrollDirection)
    /// Swallows the key without acting (Shift-Tab while the panel is up).
    case consume
}

/// A banner above the list: orange card, callout text, action buttons. A
/// banner dismisses on the next query edit, on Esc, or on a successful
/// open — never on a re-rank alone.
public struct RefsBanner: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case error
        case warning
    }

    public enum Action: Equatable, Hashable, Sendable {
        case tryAgain
        case openInDefaultApp
        case chooseHighlights
        case copyDiagnostic
        case scanAgain
    }

    public var kind: Kind
    public var message: String
    public var actions: [Action]

    public init(kind: Kind, message: String, actions: [Action]) {
        self.kind = kind
        self.message = message
        self.actions = actions
    }
}

/// Everything the list and the inspector need for one frozen row: the item
/// (nil when the row vanished from the snapshot and shows as
/// unavailable), its caption, its why-here line, and its flags.
public struct RefsRowContent: Equatable, Sendable {
    public var item: RefItem?
    public var title: String
    public var caption: String
    /// The `Character` range of the matched stem or secondary part
    /// inside `caption`, when search mode appended one. The row renders
    /// it in the accent color.
    public var captionMatch: Range<Int>?
    public var whyHere: String
    public var match: RefsMatch?
    public var section: RefsSectionKind?
    public var isUnopened: Bool
    public var isMissingPDF: Bool
    public var isUnavailable: Bool

    public init(
        item: RefItem?,
        title: String,
        caption: String,
        captionMatch: Range<Int>? = nil,
        whyHere: String,
        match: RefsMatch?,
        section: RefsSectionKind?,
        isUnopened: Bool,
        isMissingPDF: Bool,
        isUnavailable: Bool
    ) {
        self.item = item
        self.title = title
        self.caption = caption
        self.captionMatch = captionMatch
        self.whyHere = whyHere
        self.match = match
        self.section = section
        self.isUnopened = isUnopened
        self.isMissingPDF = isMissingPDF
        self.isUnavailable = isUnavailable
    }
}

/// Opens dispatched through `NSWorkspace`, behind a protocol so tests
/// inject a fake.
public protocol RefsOpening: Sendable {
    func openInHighlights(_ pdf: URL, app: URL, completion: @escaping (Error?) -> Void)
    func openNote(_ url: URL)
    func reveal(_ url: URL)
    func openWithDefaultApp(_ url: URL, completion: @escaping (Error?) -> Void)
}

/// The concrete opener. It never builds a shell command, and it always
/// opens the library original so Highlights' annotations land where
/// bob's scan reads them.
public struct WorkspaceRefsOpener: RefsOpening, Sendable {
    public init() {}

    public func openInHighlights(
        _ pdf: URL,
        app: URL,
        completion: @escaping (Error?) -> Void
    ) {
        var configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [pdf],
            withApplicationAt: app,
            configuration: configuration
        ) { _, error in
            completion(error)
        }
    }

    public func openNote(_ url: URL) {
        guard let deep = ObsidianOpenURL.url(forAbsolutePath: url.path) else {
            return
        }
        _ = NSWorkspace.shared.open(deep)
    }

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openWithDefaultApp(_ url: URL, completion: @escaping (Error?) -> Void) {
        var configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            completion(error)
        }
    }
}

/// Locates Highlights, behind a protocol so tests inject a fake.
public protocol RefsHighlightsLocating: Sendable {
    func highlightsAppURL() -> URL?
}

/// The concrete locator: the Settings override path when it exists, else
/// Highlights by bundle id, else nil. The override path is injected so
/// Settings can re-point it live in `refs-entry-points`.
public struct HighlightsLocator: RefsHighlightsLocating, Sendable {
    public static let bundleIdentifier = "net.highlightsapp.universal"

    private let overridePath: @Sendable () -> String

    public init(overridePath: @escaping @Sendable () -> String = { "" }) {
        self.overridePath = overridePath
    }

    public func highlightsAppURL() -> URL? {
        let path = overridePath()
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.bundleIdentifier
        )
    }
}

/// One revealed-notes event: the model stored the page and the
/// controller should follow the new batch's tail. Not published: every
/// reveal must arrive, even successive identical ones.
public struct RefsInspectorNotesReveal: Equatable, Sendable {
    public let id: String
    public let generation: Int
    public let range: Range<Int>

    public init(id: String, generation: Int, range: Range<Int>) {
        self.id = id
        self.generation = generation
        self.range = range
    }
}

/// The Refs panel model: the query, the scope, the frozen listing, the
/// id-based selection, commands, open dispatch, and banners. Library
/// publications refresh row content in place and never re-rank: re-ranking
/// happens only on `queryDidChange`, `setScope`, `refresh`, and
/// `prepareForPresentation`.
@MainActor
public final class RefsPanelModel: ObservableObject {
    @Published public var query: String = ""
    @Published public private(set) var scope: RefScope = .all
    @Published public private(set) var listing: RefsListing
    @Published public private(set) var selectedID: String? {
        didSet {
            if oldValue != selectedID {
                revealedPageID = nil
                revealedPage = nil
                if copyCard?.frozenItemID != selectedID {
                    closeCopyCard()
                }
                if renameCard?.frozenItemID != selectedID, !isRenaming {
                    closeRenameCard()
                }
            }
        }
    }
    /// Notes shown on the inspector's first page, and revealed per page
    /// after. Clamped to `RefsNotesPage.sizeRange`; changing it clears
    /// the stored reveal so the next selection starts on the first page.
    @Published public var notesPageSize: Int = RefsNotesPage.defaultSize {
        didSet {
            let clamped = RefsNotesPage.clampedSize(notesPageSize)
            if notesPageSize != clamped {
                notesPageSize = clamped
            }
            revealedPageID = nil
            revealedPage = nil
        }
    }
    /// The revealed page plus the id it belongs to: one entry, cleared
    /// on every selection change and on every panel presentation
    /// (reveal_memory = reset). Read through
    /// `inspectorNotesPage(for:)`, which returns a fresh page for any
    /// other id.
    @Published private(set) var revealedPageID: String?
    @Published private(set) var revealedPage: RefsNotesPage?
    @Published public private(set) var unavailableIDs: Set<String> = []
    @Published public private(set) var banner: RefsBanner?
    /// Counts presentations: `prepareForPresentation` bumps it, so the
    /// panel view replays its scale-in on every show, not once per process.
    @Published public private(set) var presentationCount = 0
    /// The selected row's frame in the panel root's SwiftUI coordinate
    /// space, kept live by the list. The ⌘K menu pops below it, or at
    /// the list's center when it is unknown.
    @Published public var selectedRowRect: CGRect? = nil
    /// The visible row count from the list geometry; pages move by one less.
    @Published public var visibleRowBudget: Int = 10
    /// The active fixed-letter copy card, if one is open.
    @Published public private(set) var copyCard: RefsCopyCard?
    @Published public private(set) var copyAlternatesActive = false
    /// The editable filename card; Bob remains the authority for the
    /// rename rules and the returned destination path.
    @Published public private(set) var renameCard: RefsRenameCard?
    @Published public private(set) var renameCardGeneration: UInt64 = 0
    /// Last completed rename status, shown in the footer until the next
    /// panel operation replaces it.
    @Published public private(set) var renameStatus: String?

    public var isRenaming: Bool {
        renameCard?.phase == .running
    }

    /// Flags only affect an open card (including its picker layer).
    public func updateCopyModifiers(_ modifiers: RefsCopyKeyModifiers) {
        let active = copyCard != nil && modifiers.contains(.option)
        guard copyAlternatesActive != active else { return }
        copyAlternatesActive = active
    }
    /// The measured note capacity of the copy card. The card keeps this
    /// value when its size changes and drops note rows that no longer fit.
    @Published public var copyCardNoteCapacity = 0 {
        didSet {
            guard oldValue != copyCardNoteCapacity,
                  var card = copyCard
            else {
                return
            }
            card.setNoteCapacity(copyCardNoteCapacity)
            copyCard = card
        }
    }
    /// How many highlight-picker rows fit in the card. The picker
    /// window scrolls inside this budget.
    @Published public var copyCardPickerWindowSize = 9 {
        didSet {
            guard oldValue != copyCardPickerWindowSize,
                  var card = copyCard
            else {
                return
            }
            card.setPickerWindowSize(copyCardPickerWindowSize)
            copyCard = card
        }
    }
    /// The last scan outcome the footer reads, or nil when no scan has
    /// finished since the last explicit clear or hide-after-seen.
    @Published public private(set) var scanNotice: RefsScanOutcome?
    /// The inspector's hydrated content, published per selected id.
    public let inspectorLoader: RefsInspectorLoader
    /// Live inspector scroll requests. Not published: successive identical
    /// presses must all arrive, and trackpad movement must not redraw the
    /// panel model.
    public var inspectorScrolls: AnyPublisher<RefsInspectorScrollDirection, Never> {
        inspectorScrollSubject.eraseToAnyPublisher()
    }
    /// Live inspector note reveals. Not published, matching
    /// `inspectorScrolls`: the controller follows each reveal's tail.
    public var inspectorNoteReveals: AnyPublisher<RefsInspectorNotesReveal, Never> {
        inspectorNoteRevealsSubject.eraseToAnyPublisher()
    }

    public var panelDismisser: () -> Void = {}
    public var panelPresenter: () -> Void = {}
    /// Re-shows the panel after an open error without resetting it. The
    /// panel controller routes this through `BobPanelCoordinator`, so a
    /// visible Capture draft is retained exactly as on a normal open.
    public var panelRepresenter: () -> Void = {}
    public var settingsPresenter: () -> Void = {}
    /// Presents the ⌘K actions menu for the selected row. The panel
    /// controller sets this; it pops the menu over the panel.
    public var actionsPresenter: () -> Void = {}
    /// Called after one checked pasteboard write succeeds. The controller
    /// hides Refs and presents the confirmation HUD from this callback.
    public var copyCompletion: (RefsCopyRow) -> Void = { _ in }
    /// Whether the panel is currently visible. The controller sets this;
    /// the scan completion path reads it to decide between a live
    /// re-rank and a hidden notification.
    public var panelIsVisible: () -> Bool = { false }
    /// Called with the outcome when a scan finishes while the panel is
    /// hidden, unless it succeeded with nothing created. AppDelegate
    /// sets this to post the hidden-panel notification.
    public var scanNotifier: (RefsScanOutcome) -> Void = { _ in }
    /// Called when a rename finishes after the panel was hidden.
    public var renameNotifier: (RefsRenameResponse) -> Void = { _ in }

    private let library: RefsLibrary
    private let opener: RefsOpening
    private let highlights: RefsHighlightsLocating
    private let pasteboard: RefsPasteboardWriting
    private let inspectorScrollSubject = PassthroughSubject<
        RefsInspectorScrollDirection, Never
    >()
    private let inspectorNoteRevealsSubject = PassthroughSubject<
        RefsInspectorNotesReveal, Never
    >()
    private var subscriptions = Set<AnyCancellable>()
    private var pendingOpen: (id: String, target: RefsOpenTarget)?
    /// Set by ⌘R (and Retry) so the next completed refresh builds a fresh
    /// listing instead of a content-only update.
    private var pendingRefreshRerank = false
    /// Every item ever published, by id, so a freshly vanished row still
    /// draws its last known title. Current publications win on conflict;
    /// every fresh listing prunes rows the library no longer has.
    private var knownItems: [String: RefItem] = [:]
    private var lastDiagnostic = ""
    private var copyCardSequence: UInt64 = 0
    private var copyNotesTask: Task<Void, Never>?
    private var pendingCopyTimeoutTask: Task<Void, Never>?
    private var pendingCopyTimeoutKey: RefsCopyKey?
    private var pendingCopyTimeoutToken: UInt64?
    private var copyMessageTask: Task<Void, Never>?
    private var renameTask: Task<Void, Never>?
    private var selectionAtScanStart: String?
    private var pendingScanBanner: RefsBanner?
    private var scanNoticeSeen = false

    public init(
        library: RefsLibrary,
        opener: RefsOpening,
        highlights: RefsHighlightsLocating,
        pasteboard: RefsPasteboardWriting = SystemRefsPasteboard()
    ) {
        self.library = library
        self.opener = opener
        self.highlights = highlights
        self.pasteboard = pasteboard
        let initialListing = RefsRanker.listing(
            library.items,
            query: "",
            scope: .all,
            signals: library.signals
        )
        listing = initialListing
        selectedID = RefsSelectionPolicy.initial(in: initialListing)
        inspectorLoader = RefsInspectorLoader(library: library)
        inspectorLoader.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        let itemsSubscription = library.$items.sink { [weak self] _ in
            Task { await self?.libraryDidPublish() }
        }
        let signalsSubscription = library.$signals.sink { [weak self] _ in
            Task { await self?.libraryDidPublish() }
        }
        itemsSubscription.store(in: &subscriptions)
        signalsSubscription.store(in: &subscriptions)
        library.$scanState.sink { [weak self] _ in
            Task { await self?.scanStateDidChange() }
        }.store(in: &subscriptions)
    }

    /// Whether a scan is running on the library lane.
    public var isScanning: Bool {
        if case .scanning = library.scanState {
            return true
        }
        return false
    }

    /// When the running scan started, or nil when idle.
    public var scanStartedAt: Date? {
        if case .scanning(let startedAt) = library.scanState {
            return startedAt
        }
        return nil
    }

    /// Called by the controller from `hide()`, after `orderOut`.
    /// Clears the scan notice once it has been seen.
    public func panelDidHide() {
        closeCopyCard()
        if !isRenaming {
            closeRenameCard()
        }
        if scanNoticeSeen {
            scanNotice = nil
            scanNoticeSeen = false
        }
    }

    /// The Today Pomodoro name for an id, or nil when the row is not
    /// in Today. An empty name reads "TODAY" in the pill. The join runs
    /// through the row's located task, so two references sharing one
    /// parent note do not both claim the pill.
    public func pomodoroName(for id: String) -> String? {
        guard let item = library.items.first(where: { $0.id == id }) else {
            return nil
        }
        return library.signals.today.entry(for: item)?.pomodoroName
    }

    /// The selected item, or nil when nothing is selected.
    public var selectedItem: RefItem? {
        guard let selectedID else {
            return nil
        }
        return library.items.first { $0.id == selectedID }
    }

    /// Resets for presentation: a blank query, All scope, a fresh listing,
    /// and the first row selected. A pending scan banner installs here,
    /// and an unseen scan notice is marked seen. The fresh listing
    /// includes Just scanned through `signals.scan`, so its first row
    /// selects that section's first row.
    public func prepareForPresentation() {
        presentationCount += 1
        selectedRowRect = nil
        if isRenaming {
            return
        }
        closeCopyCard()
        closeRenameCard()
        query = ""
        scope = .all
        banner = nil
        pendingOpen = nil
        revealedPageID = nil
        revealedPage = nil
        rerankSelectingFirst()
        if let pending = pendingScanBanner {
            banner = pending
            pendingScanBanner = nil
        }
        if scanNotice != nil, !scanNoticeSeen {
            scanNoticeSeen = true
        }
    }

    /// Re-ranks on every query edit, selects the first row, and dismisses
    /// any banner.
    public func queryDidChange() {
        banner = nil
        rerankSelectingFirst()
    }

    /// Sets the query from the search field and re-ranks, in one place so
    /// the typed text always reaches the model.
    public func setQuery(_ query: String) {
        self.query = query
        queryDidChange()
    }

    /// Runs one command. Returns false only when the command had no row to
    /// act on, so the key router can pass the key through. Inspector scroll
    /// commands always consume, including with no selected row.
    @discardableResult
    public func perform(_ command: RefsCommand) -> Bool {
        switch command {
        case .open(let target):
            return openSelected(target)
        case .move(let step):
            let pageSize = max(visibleRowBudget - 1, 1)
            selectedID = RefsSelectionPolicy.move(
                step,
                from: selectedID,
                in: listing,
                pageSize: pageSize
            )
            return true
        case .setScope(let next):
            scope = next
            rerankSelectingFirst()
            return true
        case .escape:
            if renameCard != nil, !isRenaming {
                closeRenameCard()
                return true
            }
            if copyCard != nil {
                closeCopyCard()
                return true
            }
            if banner != nil {
                banner = nil
                return true
            }
            if !query.isEmpty {
                query = ""
                rerankSelectingFirst()
                return true
            }
            if scope != .all {
                scope = .all
                rerankSelectingFirst()
                return true
            }
            hidePanel()
            return true
        case .deleteBackwardOnEmpty:
            guard query.isEmpty, scope != .all else {
                return false
            }
            scope = .all
            rerankSelectingFirst()
            return true
        case .refresh:
            // The fresh listing lands when the refresh completes (see
            // `libraryDidPublish`): re-ranking now would pin the old data.
            pendingRefreshRerank = true
            library.refresh(reason: .manual)
            return true
        case .select(let id):
            if isRenaming {
                return true
            }
            closeRenameCard()
            closeCopyCard()
            guard listing.orderedIDs.contains(id) else {
                return false
            }
            selectedID = id
            return true
        case .activate(let id):
            if isRenaming {
                return true
            }
            closeRenameCard()
            closeCopyCard()
            guard listing.orderedIDs.contains(id) else {
                return false
            }
            selectedID = id
            return openSelected(.highlights)
        case .showActions:
            if isRenaming {
                return true
            }
            closeRenameCard()
            closeCopyCard()
            guard selectedID != nil, selectedItem != nil else {
                return false
            }
            actionsPresenter()
            return true
        case .showCopyCard:
            openCopyCard()
            return true
        case .showRenameCard:
            openRenameCard()
            return true
        case .scan:
            if isScanning {
                return true
            }
            if let current = banner, Self.isScanBanner(current) {
                banner = nil
            }
            scanNotice = nil
            scanNoticeSeen = false
            selectionAtScanStart = selectedID
            _ = library.scan()
            return true
        case .scrollInspector(let direction):
            inspectorScrollSubject.send(direction)
            return true
        case .consume:
            return true
        }
    }

    private static func isScanBanner(_ banner: RefsBanner) -> Bool {
        if banner.actions.contains(.scanAgain) {
            return true
        }
        return banner.kind == .warning && banner.actions == [.copyDiagnostic]
    }

    /// The snapshot refresh state the footer reads.
    public var refreshState: RefsRefreshState {
        library.refreshState
    }

    /// Whether any snapshot — cached or refreshed — has loaded.
    public var hasSnapshot: Bool {
        library.hasSnapshot
    }

    /// When the last snapshot refresh succeeded.
    public var lastSuccessAt: Date? {
        library.lastSuccessAt
    }

    /// Refreshes when the snapshot is older than `maxAge`. The panel
    /// controller calls this on every show.
    public func refreshIfStale(maxAge: TimeInterval = 60) {
        library.refreshIfStale(maxAge: maxAge)
    }

    /// Background refresh for every panel open: Today refreshes every
    /// time while the snapshot keeps its 60 s staleness rule.
    public func refreshForOpen(maxAge: TimeInterval = 60) {
        library.refreshToday(reason: .panelOpen)
        refreshIfStale(maxAge: maxAge)
    }

    /// The current library signals (Today, open stats, Spotlight
    /// facts, missing PDFs). The inspector reads these at render time.
    public var signals: RefsSignals {
        library.signals
    }

    /// The library, for design previews that reshape the snapshot
    /// after installing canned state (an unavailable-row render drops
    /// an id through this, so the frozen listing keeps it dimmed).
    var previewLibrary: RefsLibrary {
        library
    }

    /// The list and inspector content for one frozen row, or nil when the
    /// id is not in the listing.
    public func rowContent(for id: String) -> RefsRowContent? {
        guard listing.orderedIDs.contains(id) else {
            return nil
        }
        let signals = library.signals
        let match = listing.matches[id]
        let section = listing.sections.first { $0.ids.contains(id) }.flatMap(\.kind)
        guard let item = library.items.first(where: { $0.id == id }) else {
            return RefsRowContent(
                item: nil,
                title: listing.unavailableItems[id]?.title.text ?? id,
                caption: "No longer in your library",
                whyHere: "No longer in your library",
                match: nil,
                section: section,
                isUnopened: false,
                isMissingPDF: false,
                isUnavailable: true
            )
        }
        let captioned = RefsCaption.captionWithMatch(
            for: item, in: section, signals: signals, match: match
        )
        return RefsRowContent(
            item: item,
            title: item.title.text,
            caption: captioned.text,
            captionMatch: captioned.matchRange,
            whyHere: RefsExplanation.whyHere(item, listing: listing, signals: signals),
            match: match,
            section: section,
            isUnopened: RefsRanker.isUnopened(item, signals: signals),
            isMissingPDF: signals.missingPDFs.contains(id),
            isUnavailable: unavailableIDs.contains(id)
        )
    }

    /// Runs one banner action.
    public func performBannerAction(_ action: RefsBanner.Action) {
        switch action {
        case .tryAgain:
            guard let pending = pendingOpen else {
                return
            }
            openStored(pending)
        case .openInDefaultApp:
            guard let pending = pendingOpen,
                let item = library.items.first(where: { $0.id == pending.id })
            else {
                return
            }
            openWithDefaultApp(item)
        case .chooseHighlights:
            settingsPresenter()
        case .copyDiagnostic:
            // The load-failed card has no open error behind it, so it
            // copies the refresh failure's bounded message; an open-error
            // banner copies its own diagnostic first.
            if !lastDiagnostic.isEmpty {
                pasteboard.copy(lastDiagnostic)
            } else if case .failed(let message, _) = library.refreshState {
                pasteboard.copy(message)
            }
        case .scanAgain:
            _ = perform(.scan)
        }
    }

    /// Installs canned state for design tests and previews, skipping
    /// every process.
    public func installForPreviews(
        items: [RefItem],
        signals: RefsSignals,
        query: String,
        scope: RefScope,
        selectedID: String?,
        banner: RefsBanner?,
        refreshState: RefsRefreshState,
        scanState: RefsScanState = .idle,
        scanNotice: RefsScanOutcome? = nil,
        inspector: [String: RefsInspectorContent]? = nil,
        thumbnails: [String: NSImage]? = nil
    ) {
        library.installSnapshotForPreviews(
            items: items,
            signals: signals,
            refreshState: refreshState
        )
        library.installScanStateForPreviews(scanState)
        self.query = query
        self.scope = scope
        self.banner = banner
        self.scanNotice = scanNotice
        scanNoticeSeen = scanNotice != nil
        knownItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        listing = RefsRanker.listing(items, query: query, scope: scope, signals: signals)
        unavailableIDs = []
        self.selectedID = selectedID
        if let inspector {
            inspectorLoader.installContentForPreviews(
                inspector,
                thumbnails: thumbnails ?? [:]
            )
        } else {
            inspectorLoader.reset()
        }
    }

    /// Requests inspector hydration for the selected row. The loader
    /// debounces rapid movement and cancels the previous load.
    public func inspectorRequested() {
        guard let item = selectedItem else {
            inspectorLoader.cancel()
            return
        }
        inspectorLoader.request(item)
    }

    /// The hydrated inspector content for an id, or nil while it loads.
    public func inspectorContent(for id: String) -> RefsInspectorContent? {
        inspectorLoader.content(for: id)
    }

    /// The inspector thumbnail for an id, or nil while it loads.
    public func inspectorThumbnail(for id: String) -> NSImage? {
        inspectorLoader.thumbnail(for: id)
    }

    /// The revealed-notes page for an id: the stored page when the id
    /// matches, otherwise a fresh page at the current page size.
    public func inspectorNotesPage(for id: String) -> RefsNotesPage {
        if let revealedPage, revealedPageID == id {
            return revealedPage
        }
        return RefsNotesPage(size: notesPageSize)
    }

    /// Reveals the next page of the selected row's notes and
    /// highlights. Returns false unless the selected id has hydrated
    /// content that still hides entries. On success it stores the
    /// page, announces the new count, and emits on
    /// `inspectorNoteReveals` for the controller's follow-tail scroll.
    @discardableResult
    public func revealMoreInspectorNotes() -> Bool {
        guard let id = selectedID,
              let content = inspectorLoader.content(for: id)
        else {
            return false
        }
        var page = inspectorNotesPage(for: id)
        guard let range = page.reveal(total: content.feed.total) else {
            return false
        }
        revealedPageID = id
        revealedPage = page
        let visible = page.visibleCount(total: content.feed.total)
        AccessibilityNotification.Announcement(
            content.feed.revealAnnouncement(visible: visible)
        ).post()
        inspectorNoteRevealsSubject.send(RefsInspectorNotesReveal(
            id: id,
            generation: page.generation,
            range: range
        ))
        return true
    }

    /// The ⌘K menu sections for the selected row, or empty when nothing
    /// is selected.
    public func actionsSections() -> [[RefsAction]] {
        guard let item = selectedItem else {
            return []
        }
        return RefsActionsMenu.sections(
            for: item,
            audioURL: library.audioURL(for: item)
        )
    }

    /// Runs one ⌘K menu action for the selected row.
    public func performAction(_ action: RefsAction) {
        switch action {
        case .openHighlights:
            _ = openSelected(.highlights)
        case .openNote:
            _ = openSelected(.note)
        case .reveal:
            _ = openSelected(.reveal)
        case .copy:
            openCopyCard()
        case .rename:
            openRenameCard()
        case .openSourceURL(let url):
            _ = NSWorkspace.shared.open(url)
        case .openNarration(let url):
            _ = NSWorkspace.shared.open(url)
        case .openDefaultApp:
            _ = openSelected(.defaultApp)
        case .refreshLibrary:
            perform(.refresh)
        case .scanLibrary:
            _ = perform(.scan)
        }
    }

    /// Opens the in-panel copy card for the selected available reference.
    /// The target and filesystem facts are frozen until the card closes.
    public func openCopyCard(
        optionHeld: Bool = NSEvent.modifierFlags.contains(.option)
    ) {
        guard !isRenaming else { return }
        closeRenameCard()
        closeCopyCard()
        guard let item = selectedItem,
              listing.orderedIDs.contains(item.id),
              !unavailableIDs.contains(item.id)
        else {
            return
        }
        copyCardSequence &+= 1
        let token = copyCardSequence
        let pdfURL = library.pdfURL(for: item)
        let audioURL = library.audioURL(for: item).flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        }
        let notes = inspectorLoader.cachedShowRow(for: item)
            .map(RefsCopyNotesState.loaded) ?? .loading
        copyCard = RefsCopyCard(
            token: token,
            item: item,
            absolutePDFPath: pdfURL?.path,
            pdfExists: pdfURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
            notes: notes,
            noteCapacity: copyCardNoteCapacity,
            pickerWindowSize: copyCardPickerWindowSize,
            absoluteNotePath: library.noteURL(for: item).path,
            homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path,
            narrationFileURL: audioURL
        )
        copyAlternatesActive = optionHeld
        AccessibilityNotification.Announcement(
            "Copy menu. Press a letter or number."
        ).post()
        guard case .loading = notes else {
            return
        }
        let loader = inspectorLoader
        copyNotesTask = Task { [weak self, loader] in
            let row = await loader.showRow(for: item)
            guard let self else { return }
            if let row {
                self.copyCardNotesLoaded(token: token, path: item.id, row: row)
            } else {
                self.copyCardNotesFailed(token: token, path: item.id)
            }
        }
    }

    /// Opens a rename card for the selected, available row. Its title
    /// and note path stay frozen until the operation is cancelled or
    /// Bob returns a result.
    public func openRenameCard() {
        guard !isRenaming,
              let item = selectedItem,
              listing.orderedIDs.contains(item.id),
              !unavailableIDs.contains(item.id)
        else {
            return
        }
        closeCopyCard()
        closeRenameCard()
        renameStatus = nil
        renameCardGeneration &+= 1
        renameCard = RefsRenameCard(item: item)
    }

    /// The event monitor asks the pure key map first so keys it does not
    /// own can continue into AppKit's editable text field.
    public func renameCardKeyCommand(
        keyCode: UInt16,
        modifiers: RefsCopyKeyModifiers,
        hasMarkedText: Bool
    ) -> RefsRenameKeyCommand? {
        guard let card = renameCard else { return nil }
        return RefsRenameKeyMap.command(
            keyCode: keyCode,
            modifiers: modifiers,
            isRunning: card.phase == .running,
            hasMarkedText: hasMarkedText
        )
    }

    /// Applies one rename-card key. Draft keys not claimed by the key
    /// map never reach this method and remain native text editing.
    public func handleRenameCardKey(_ command: RefsRenameKeyCommand) {
        guard var card = renameCard else { return }
        let path = card.notePath
        let effect = card.handle(command)
        renameCard = card
        switch effect {
        case .none:
            break
        case .cancel:
            closeRenameCard()
        case .submit(let name):
            renameTask?.cancel()
            renameTask = Task { [weak self] in
                await self?.runRename(notePath: path, name: name)
            }
        }
    }

    /// Updates the editable stem. Bob will validate it and returns any
    /// refusal inline without discarding the user's draft.
    public func editRenameDraft(_ stem: String) {
        guard var card = renameCard else { return }
        card.editDraftStem(stem)
        renameCard = card
    }

    private func closeRenameCard() {
        guard !isRenaming else { return }
        renameCard = nil
        renameTask = nil
    }

    private func runRename(notePath: String, name: String) async {
        do {
            let response = try await library.rename(notePath: notePath, name: name)
            guard let current = renameCard, current.notePath == notePath else {
                renameTask = nil
                return
            }
            guard response.error == nil, response.ok != false,
                  let destination = response.to?.path
            else {
                let failure = response.error ?? RefsRenameFailure(
                    code: "invalid_response",
                    message: "Bob returned an incomplete rename response."
                )
                failRename(message: failure.message, hint: failure.hint)
                libraryDidPublish()
                return
            }
            let stem = response.to?.stem
                ?? URL(fileURLWithPath: destination).deletingPathExtension().lastPathComponent
            let wasVisible = panelIsVisible()
            knownItems.removeValue(forKey: notePath)
            unavailableIDs.remove(notePath)
            unavailableIDs.remove(destination)
            if revealedPageID == notePath {
                revealedPageID = destination
                revealedPage = nil
            }
            if selectedID == notePath {
                selectedID = destination
            }
            await inspectorLoader.discard(id: notePath)
            renameCard = nil
            renameTask = nil
            renameStatus = RefsRenamePresentation.footerStatus(
                stem: stem,
                rewrittenLinks: response.links?.rewritten ?? 0
            )
            freshListing(selecting: destination)
            if wasVisible {
                AccessibilityNotification.Announcement(
                    RefsRenamePresentation.announcement(stem: stem)
                ).post()
            } else {
                renameNotifier(response)
            }
        } catch {
            failRename(
                message: RefsRenameProblemMapping.transportProblem(for: error).message,
                hint: RefsRenameProblemMapping.transportProblem(for: error).hint
            )
            libraryDidPublish()
        }
    }

    private func failRename(message: String, hint: String?) {
        guard var card = renameCard else { return }
        card.fail(message: message, hint: hint)
        renameCard = card
        renameTask = nil
    }

    /// Feeds one key captured by the controller to the card state machine.
    public func handleCopyCardKey(
        characters: String?,
        keyCode: UInt16,
        modifiers: RefsCopyKeyModifiers
    ) {
        guard var card = copyCard else { return }
        updateCopyModifiers(modifiers)
        let token = card.token
        let command = RefsCopyKeyMap.command(
            characters: characters,
            keyCode: keyCode,
            modifiers: modifiers
        )
        let effect = card.handle(command, alternatesActive: copyAlternatesActive)
        copyCard = card
        updateCopyCardTimers(token: token)
        applyCopyCardEffect(effect, token: token)
    }

    /// A row tap copies that row immediately, matching its printed key.
    public func copyCardRowTapped(_ row: RefsCopyRow) {
        guard let card = copyCard,
              card.highlightPicker == nil,
              card.rows.contains(where: { $0.key == row.key && $0 == row })
        else {
            return
        }
        handleCopyCardKey(
            characters: row.key.glyph,
            keyCode: 0,
            modifiers: copyAlternatesActive ? .option : []
        )
    }

    /// A picker-row tap copies that window position, matching its digit.
    public func copyCardPickerRowTapped(_ windowPosition: Int) {
        guard copyCard?.highlightPicker != nil else { return }
        handleCopyCardKey(
            characters: String(windowPosition),
            keyCode: 0,
            modifiers: copyAlternatesActive ? .option : []
        )
    }

    private func copyCardNotesLoaded(token: UInt64, path: String, row: RefsShowRow) {
        guard var card = copyCard, card.token == token else { return }
        let effect = card.notesLoaded(path: path, row: row)
        copyCard = card
        updateCopyCardTimers(token: token)
        applyCopyCardEffect(effect, token: token)
    }

    private func copyCardNotesFailed(token: UInt64, path: String) {
        guard var card = copyCard, card.token == token else { return }
        card.notesFailed(path: path)
        copyCard = card
        updateCopyCardTimers(token: token)
    }

    private func updateCopyCardTimers(token: UInt64) {
        if let pending = copyCard?.pending {
            if pendingCopyTimeoutKey != pending || pendingCopyTimeoutToken != token {
                pendingCopyTimeoutTask?.cancel()
                pendingCopyTimeoutKey = pending
                pendingCopyTimeoutToken = token
                pendingCopyTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.copyCardPendingTimedOut(token: token)
                }
            }
        } else if pendingCopyTimeoutTask != nil || pendingCopyTimeoutKey != nil {
            pendingCopyTimeoutTask?.cancel()
            pendingCopyTimeoutTask = nil
            pendingCopyTimeoutKey = nil
            pendingCopyTimeoutToken = nil
        }

        copyMessageTask?.cancel()
        copyMessageTask = nil
        if copyCard?.message?.isTransient == true {
            copyMessageTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self?.clearTransientCopyMessage(token: token)
            }
        }
    }

    private func copyCardPendingTimedOut(token: UInt64) {
        guard var card = copyCard, card.token == token else { return }
        card.pendingTimedOut()
        copyCard = card
        pendingCopyTimeoutTask = nil
        pendingCopyTimeoutKey = nil
        pendingCopyTimeoutToken = nil
    }

    private func clearTransientCopyMessage(token: UInt64) {
        guard var card = copyCard, card.token == token else { return }
        card.clearTransientMessage()
        copyCard = card
        copyMessageTask = nil
    }

    private func applyCopyCardEffect(_ effect: RefsCopyEffect, token: UInt64) {
        switch effect {
        case .none:
            break
        case .write(let row):
            guard var card = copyCard, card.token == token else { return }
            guard copyPayloadIsAvailable(row.payload) else {
                card.writeUnavailable(key: row.key)
                copyCard = card
                updateCopyCardTimers(token: token)
                return
            }
            if pasteboard.write(row.payload) {
                closeCopyCard()
                copyCompletion(row)
            } else {
                card.writeFailed(key: row.key, attemptedRow: row)
                copyCard = card
                updateCopyCardTimers(token: token)
            }
        case .close:
            closeCopyCard()
        case .closeThenActions:
            closeCopyCard()
            actionsPresenter()
        }
    }

    private func copyPayloadIsAvailable(_ payload: RefsClipboardPayload) -> Bool {
        switch payload {
        case .text(let value):
            return !value.isEmpty
        case .fileURL(let url):
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    private func closeCopyCard() {
        if var card = copyCard {
            _ = card.handle(.close)
        }
        copyNotesTask?.cancel()
        copyNotesTask = nil
        pendingCopyTimeoutTask?.cancel()
        pendingCopyTimeoutTask = nil
        pendingCopyTimeoutKey = nil
        pendingCopyTimeoutToken = nil
        copyMessageTask?.cancel()
        copyMessageTask = nil
        copyCard = nil
        copyAlternatesActive = false
    }

    private func rerankSelectingFirst() {
        pendingRefreshRerank = false
        pruneKnownItems()
        listing = RefsRanker.listing(
            library.items,
            query: query,
            scope: scope,
            signals: library.signals
        )
        unavailableIDs = []
        selectedID = RefsSelectionPolicy.initial(in: listing)
    }

    /// A fresh listing from the latest data that keeps the selected id
    /// when it still exists, for a completed ⌘R or Retry.
    private func freshListingKeepingSelection() {
        pendingRefreshRerank = false
        pruneKnownItems()
        let keep = selectedID
        listing = RefsRanker.listing(
            library.items,
            query: query,
            scope: scope,
            signals: library.signals
        )
        unavailableIDs = []
        if let keep, listing.orderedIDs.contains(keep) {
            selectedID = keep
        } else {
            selectedID = RefsSelectionPolicy.initial(in: listing)
        }
    }

    /// Rebuilds from Bob's post-rename list and follows the destination
    /// that Bob reported, never a path inferred by the client.
    private func freshListing(selecting id: String) {
        pendingRefreshRerank = false
        pruneKnownItems()
        var fresh = RefsRanker.listing(
            library.items,
            query: query,
            scope: scope,
            signals: library.signals
        )
        if !fresh.orderedIDs.contains(id) {
            query = ""
            fresh = RefsRanker.listing(
                library.items,
                query: query,
                scope: scope,
                signals: library.signals
            )
        }
        listing = fresh
        unavailableIDs = []
        selectedID = listing.orderedIDs.contains(id)
            ? id
            : RefsSelectionPolicy.initial(in: listing)
    }

    /// Drops last-known items the library no longer has: a fresh listing
    /// drops vanished rows, so their titles go with them.
    private func pruneKnownItems() {
        knownItems = Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0) })
    }

    private func libraryDidPublish() {
        // Keep the card's frozen listing intact while bob moves the bundle
        // and the library performs its single post-rename refresh. On
        // success, runRename installs a fresh listing at bob's `to.path`.
        if isRenaming {
            return
        }
        for item in library.items {
            knownItems[item.id] = item
        }
        let available = Set(library.items.map(\.id))
        let (next, unavailable) = listing.refreshingContent(
            availableIDs: available,
            lastKnownItems: knownItems
        )
        listing = next
        // Vanished rows leave the frozen listing, so intersecting with it
        // would drop the flag on the very next publish (every pass publishes
        // items and signals separately). Keep flags for every id that is
        // still missing from the library instead.
        unavailableIDs = unavailable.union(unavailableIDs.subtracting(available))
        if pendingRefreshRerank, library.refreshState != .refreshing {
            freshListingKeepingSelection()
        } else if next.orderedIDs.isEmpty {
            selectedID = nil
        }
    }

    private func scanStateDidChange() {
        guard case .finished(let outcome) = library.scanState else {
            return
        }
        scanNotice = outcome
        if panelIsVisible() {
            if outcome.kind != .failed {
                buildFreshListingForScan(outcome)
            }
            switch outcome.kind {
            case .succeeded:
                break
            case .partial:
                banner = RefsBanner(
                    kind: .warning,
                    message: RefsScanPresentation.bannerMessage(outcome) ?? "",
                    actions: [.copyDiagnostic]
                )
                lastDiagnostic = outcome.diagnostic
            case .failed:
                banner = RefsBanner(
                    kind: .error,
                    message: RefsScanPresentation.bannerMessage(outcome) ?? "",
                    actions: [.scanAgain, .copyDiagnostic]
                )
                lastDiagnostic = outcome.diagnostic
            }
            AccessibilityNotification.Announcement(
                RefsScanPresentation.announcement(outcome)
            ).post()
            scanNoticeSeen = true
        } else {
            switch outcome.kind {
            case .succeeded:
                pendingScanBanner = nil
            case .partial:
                pendingScanBanner = RefsBanner(
                    kind: .warning,
                    message: RefsScanPresentation.bannerMessage(outcome) ?? "",
                    actions: [.copyDiagnostic]
                )
                lastDiagnostic = outcome.diagnostic
            case .failed:
                pendingScanBanner = RefsBanner(
                    kind: .error,
                    message: RefsScanPresentation.bannerMessage(outcome) ?? "",
                    actions: [.scanAgain, .copyDiagnostic]
                )
                lastDiagnostic = outcome.diagnostic
            }
            if outcome.kind != .succeeded || !outcome.created.isEmpty {
                scanNotifier(outcome)
            }
            scanNoticeSeen = false
        }
    }

    private func buildFreshListingForScan(_ outcome: RefsScanOutcome) {
        pendingRefreshRerank = false
        if case .search = listing.mode {
            freshListingKeepingSelection()
            return
        }
        pruneKnownItems()
        let fresh = RefsRanker.listing(
            library.items,
            query: query,
            scope: scope,
            signals: library.signals
        )
        listing = fresh
        unavailableIDs = []
        if selectedID == selectionAtScanStart, !outcome.created.isEmpty {
            let createdIDs = outcome.created.map(\.path)
            if let first = createdIDs.first(where: { fresh.orderedIDs.contains($0) }) {
                selectedID = first
                return
            }
        }
        if let keep = selectedID, fresh.orderedIDs.contains(keep) {
            selectedID = keep
        } else {
            selectedID = RefsSelectionPolicy.initial(in: fresh)
        }
    }

    private func hidePanel() {
        panelDismisser()
    }

    private func openSelected(_ target: RefsOpenTarget) -> Bool {
        CaptureSignpost.event("refs-open-dispatch")
        guard let id = selectedID else {
            return false
        }
        // A vanished selected id is no longer in the listing, so this check
        // must come before the listing membership guard.
        if unavailableIDs.contains(id) {
            banner = RefsBanner(
                kind: .warning,
                message: "“\(id)” is no longer in your library.",
                actions: []
            )
            return true
        }
        guard listing.orderedIDs.contains(id) else {
            return false
        }
        guard let item = library.items.first(where: { $0.id == id }) else {
            return false
        }
        switch target {
        case .highlights:
            return openInHighlights(item)
        case .note:
            opener.openNote(library.noteURL(for: item))
            return true
        case .reveal:
            let pdfMissing = library.signals.missingPDFs.contains(item.id)
            if pdfMissing || library.pdfURL(for: item) == nil {
                opener.openNote(library.noteURL(for: item))
            } else if let pdf = library.pdfURL(for: item) {
                opener.reveal(pdf)
            }
            return true
        case .defaultApp:
            return openWithDefaultApp(item)
        }
    }

    private func openStored(_ pending: (id: String, target: RefsOpenTarget)) {
        guard let item = library.items.first(where: { $0.id == pending.id }) else {
            banner = RefsBanner(
                kind: .warning,
                message: "“\(pending.id)” is no longer in your library.",
                actions: []
            )
            return
        }
        switch pending.target {
        case .highlights:
            openInHighlights(item)
        case .defaultApp:
            openWithDefaultApp(item)
        case .note, .reveal:
            openSelected(pending.target)
        }
    }

    @discardableResult
    private func openInHighlights(_ item: RefItem) -> Bool {
        if library.signals.missingPDFs.contains(item.id) {
            opener.openNote(library.noteURL(for: item))
            return true
        }
        guard let pdf = library.pdfURL(for: item) else {
            opener.openNote(library.noteURL(for: item))
            return true
        }
        guard let app = highlights.highlightsAppURL() else {
            pendingOpen = (item.id, .highlights)
            banner = RefsBanner(
                kind: .error,
                message: "Highlights isn’t installed where Bob Refs can find it.",
                actions: [.openInDefaultApp, .chooseHighlights]
            )
            return true
        }
        pendingOpen = (item.id, .highlights)
        hidePanel()
        opener.openInHighlights(pdf, app: app) { [weak self] error in
            Task {
                await self?.finishHighlightsOpen(
                    itemID: item.id,
                    title: item.title.text,
                    error: error
                )
            }
        }
        return true
    }

    @discardableResult
    private func openWithDefaultApp(_ item: RefItem) -> Bool {
        if library.signals.missingPDFs.contains(item.id) {
            opener.openNote(library.noteURL(for: item))
            return true
        }
        guard let pdf = library.pdfURL(for: item) else {
            opener.openNote(library.noteURL(for: item))
            return true
        }
        pendingOpen = (item.id, .defaultApp)
        hidePanel()
        opener.openWithDefaultApp(pdf) { [weak self] error in
            Task {
                await self?.finishDefaultAppOpen(
                    itemID: item.id,
                    title: item.title.text,
                    error: error
                )
            }
        }
        return true
    }

    private func finishHighlightsOpen(itemID: String, title: String, error: Error?) {
        if let error {
            lastDiagnostic = RefsLibrary.boundedMessage(for: error)
            pendingOpen = (itemID, .highlights)
            // Re-show without resetting: the query, scope, frozen
            // listing, selection, and pendingOpen all survive, and the
            // coordinator retains a visible Capture draft.
            panelRepresenter()
            banner = RefsBanner(
                kind: .error,
                message: "Highlights couldn’t open “\(title)”.\n\(lastDiagnostic)",
                actions: [.tryAgain, .openInDefaultApp]
            )
        } else {
            pendingOpen = nil
            banner = nil
            library.recordOpen(id: itemID)
        }
    }

    private func finishDefaultAppOpen(itemID: String, title: String, error: Error?) {
        if let error {
            lastDiagnostic = RefsLibrary.boundedMessage(for: error)
            pendingOpen = (itemID, .defaultApp)
            // Re-show without resetting, as above.
            panelRepresenter()
            banner = RefsBanner(
                kind: .error,
                message: "Couldn’t open “\(title)”.\n\(lastDiagnostic)",
                actions: [.tryAgain, .copyDiagnostic]
            )
        } else {
            pendingOpen = nil
            banner = nil
            library.recordOpen(id: itemID)
        }
    }
}
