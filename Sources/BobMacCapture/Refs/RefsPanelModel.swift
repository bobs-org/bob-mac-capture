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

/// The source requested when the Refs panel is shown.
public enum RefsPresentationSource: Equatable, Sendable {
  /// Show the ordinary reference library.
  case library
  /// Show the current Highlights tabs.
  case highlightsTabs
  /// Show the default view after the user opens a scan notification.
  case scanResults
  /// Show the library via a Ctrl+Tab panel switch. Restores the
  /// remembered view like `.library` but never resets for a pending
  /// arrival: the fresh listing already contains the new reference at
  /// its ranked place.
  case panelSwitch
}

/// The state of the Highlights Tabs filter.
public enum RefsTabsState: Equatable, Sendable {
  /// The Tabs filter is off.
  case off
  /// A Highlights tab snapshot is being read.
  case loading
  /// A snapshot with at least one open document is available.
  case loaded
  /// Accessibility permission is needed before reading tabs.
  case needsPermission(adHoc: Bool)
  /// Highlights is not running.
  case notRunning
  /// Highlights is running with no open documents.
  case noDocuments
  /// A tab read failed; the previous rows may still be shown dimmed.
  case failed(message: String, hasStaleRows: Bool)
}

/// Every panel gesture the key router and the list funnel through.
public enum RefsCommand: Equatable, Sendable {
  case open(RefsOpenTarget)
  case move(RefsMove)
  case setScope(RefScope)
  /// Toggles the Highlights Tabs filter while keeping query and scope.
  case toggleTabs
  /// Sets the Highlights Tabs filter, used by the coordinator.
  case setTabsFilter(Bool)
  /// Resets the Refs view to its fresh-launch defaults.
  case resetView
  /// Toggles Newest order while keeping query and scope.
  case toggleNewest
  /// Sets Newest on or off, used by the token.
  case setNewest(Bool)
  /// Requests Accessibility access after an explicit card action.
  case requestTabsPermission
  /// Closes the selected Highlights tab. A stale dispatch with no
  /// closable row is a consumed no-op and never scrolls the preview.
  case closeSelectedTab
  /// Closes the identified Highlights tab row.
  case closeTab(id: String)
  /// Reopens the most recently closed Highlights tab, when one is available.
  case reopenClosedTab
  case escape
  case deleteBackwardOnEmpty
  case refresh
  case select(id: String)
  case activate(id: String)
  case showActions
  case showCopyCard
  case showRenameCard
  case showTodayLinkCard
  /// Toggle the selected row's NEW state (⌥N). Always consumed.
  case toggleNew
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
  /// The open Highlights tab represented by this row, when in Tabs mode.
  public var openTab: RefsOpenTab?
  /// Candidate references for a tab title that matches multiple notes.
  public var candidateItems: [RefItem]
  public var title: String
  public var caption: String
  /// The `Character` range of the matched stem or secondary part
  /// inside `caption`, when search mode appended one. The row renders
  /// it in the accent color.
  public var captionMatch: Range<Int>?
  public var whyHere: String
  public var match: RefsMatch?
  public var section: RefsSectionKind?
  public var isNew: Bool
  public var isMissingPDF: Bool
  public var isUnavailable: Bool

  public init(
    item: RefItem?,
    openTab: RefsOpenTab? = nil,
    candidateItems: [RefItem] = [],
    title: String,
    caption: String,
    captionMatch: Range<Int>? = nil,
    whyHere: String,
    match: RefsMatch?,
    section: RefsSectionKind?,
    isNew: Bool,
    isMissingPDF: Bool,
    isUnavailable: Bool
  ) {
    self.item = item
    self.openTab = openTab
    self.candidateItems = candidateItems
    self.title = title
    self.caption = caption
    self.captionMatch = captionMatch
    self.whyHere = whyHere
    self.match = match
    self.section = section
    self.isNew = isNew
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

/// Applied inputs for one materialized list row. Tests record these
/// through `RefsRowRenderProbe` to see what the lazy stack painted.
struct RefsRowRenderState: Equatable {
  var isSelected: Bool
  var section: RefsSectionKind?
  var caption: String
}

/// Test-only sink of applied row render state. Nil in production.
final class RefsRowRenderProbe {
  private(set) var rows: [String: RefsRowRenderState] = [:]

  func record(_ id: String, _ state: RefsRowRenderState) {
    rows[id] = state
  }
}

/// The Refs panel model: the query, the scope, the frozen listing, the
/// id-based selection, commands, open dispatch, and banners. Library
/// publications refresh row content in place and never re-rank: re-ranking
/// happens on `queryDidChange`, `setScope`, `setNewest`, `refresh`, and
/// presentation restoration.
@MainActor
public final class RefsPanelModel: ObservableObject {
  @Published public var query: String = ""
  @Published public private(set) var scope: RefScope = .all
  @Published public private(set) var listing: RefsListing
  /// Library vs Newest order. Tabs is exclusive with Newest.
  @Published public private(set) var listOrder: RefsListOrder = .ranked
  /// Whether the listing is filtered to the open Highlights tabs.
  @Published public private(set) var tabsFilter = false
  /// The current Tabs read state.
  @Published public private(set) var tabsState: RefsTabsState = .off
  /// The latest ranked tab rows, keyed by listing row id.
  @Published public private(set) var tabsListing: RefsTabsListing?
  /// Whether the selected row is an open tab that can be closed.
  public var canCloseSelectedTab: Bool {
    guard let selectedID else { return false }
    return canCloseTab(id: selectedID)
  }

  /// Whether id is an open tab row in the Tabs listing. False while
  /// a Rename or Link to Today vault write is running, so the row
  /// button, VoiceOver action, and actions menu hide their close
  /// affordances during either write.
  public func canCloseTab(id: String) -> Bool {
    guard !isRenaming, !isLinkingToday else { return false }
    return tabsFilter && tabsListing?.tabs[id] != nil
  }
  @Published public private(set) var selectedID: String? {
    didSet {
      if panelIsVisible(), let selectedID {
        arrivals.markSeen([selectedID])
      }
      if oldValue != selectedID {
        revealedPageID = nil
        revealedPage = nil
        inspectorPlace = nil
        if copyCard?.frozenItemID != selectedID {
          closeCopyCard()
        }
        if todayLinkCard?.frozenItemID != selectedID, !isLinkingToday {
          closeTodayLinkCard()
        }
        // A failed rename card survives selection changes so the
        // next presentation can re-show its inline error.
        if renameCard?.frozenItemID != selectedID, !isRenaming,
          renameCard?.isFailed != true
        {
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
  /// on selection or page-size changes. Read through
  /// `inspectorNotesPage(for:)`, which returns a fresh page for any
  /// other id.
  @Published private(set) var revealedPageID: String?
  @Published private(set) var revealedPage: RefsNotesPage?
  @Published public private(set) var unavailableIDs: Set<String> = []
  @Published public private(set) var banner: RefsBanner?
  /// Counts presentations: `prepareForPresentation` bumps it, so the
  /// panel view replays its scale-in on every show, not once per process.
  @Published public private(set) var presentationCount = 0
  /// Changes only on a full view reset, remounting the inspector at its top.
  @Published public private(set) var inspectorGeneration = 0
  /// Requests a list-to-top reset even when the first row is already selected.
  @Published public private(set) var listResetGeneration = 0
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
  /// The reference currently being linked to an open Pomodoro today.
  @Published public private(set) var todayLinkCard: RefsTodayLinkCard?
  @Published public private(set) var todayLinkCardGeneration: UInt64 = 0
  @Published private var todayLinkOverlay: [String: TodayLinkOverlay] = [:]

  public var isRenaming: Bool {
    renameCard?.phase == .running
  }

  public var isLinkingToday: Bool {
    todayLinkCard?.phase == .running
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
  /// Owns tab snapshots, reader generations, and in-memory recency.
  public let tabsSession: HighlightsTabsSession
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
  /// Called after a visible-panel Today link succeeds. The controller
  /// renders the shared glass toast without closing the panel.
  public var todayLinkCompletion: (RefsTodayLinkToast, String) -> Void = { _, _ in }
  /// Dismisses Refs through the coordinator path used by Copy after the
  /// final tab closes.
  public var tabCloseDismisser: () -> Void = {}
  /// Presents a verified tab-close toast. Last-tab toasts are shown even
  /// when Refs is hidden.
  public var tabCloseCompletion: (RefsTabCloseToast) -> Void = { _ in }
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
  /// Called with the inline message when a rename fails after the
  /// panel was hidden.
  public var renameFailureNotifier: (String, String?) -> Void = { _, _ in }
  /// Hidden-panel Today-link outcomes use system notifications.
  public var todayLinkNotifier: (RefsTodayLinkResponse, String) -> Void = { _, _ in }
  public var todayLinkFailureNotifier: (String, String?) -> Void = { _, _ in }
  public var todayLinkBeep: () -> Void = { NSSound.beep() }
  /// macOS "can't do that" cue for ineligible ⌥N presses.
  public var beep: () -> Void = { NSSound.beep() }
  public var todayLinkPreviewDebounce: @Sendable () async throws -> Void = {
    try await Task.sleep(for: .milliseconds(90))
  }

  private let library: RefsLibrary
  private let opener: RefsOpening
  private let highlights: RefsHighlightsLocating
  private let pasteboard: RefsPasteboardWriting
  private let isAdHocSigned: () -> Bool
  /// Matched only when a new tab snapshot lands; library publications
  /// update row content without changing which tabs are listed.
  private var matchedTabs: [RefsOpenTab] = []
  private var tabsHighlightsIsFrontmost = false
  private var closingRowIDs: Set<String> = []
  private struct PendingTabClose {
    let tab: RefsOpenTab
    let title: String
    let reopen: RefsClosedTab?
  }
  private var closeQueue: [PendingTabClose] = []
  private var closeWorker: Task<Void, Never>?
  private var pendingClosedTab: RefsClosedTab?
  private var tabsRefreshGeneration: UInt64 = 0
  private var preserveTabsSelectionOnNextSnapshot = false
  private var tabsSelectionConsumed = false
  private var inspectorPlace: (id: String, generation: Int, offset: CGFloat)?
  private var heldTabsOpen = false
  private let inspectorScrollSubject = PassthroughSubject<
    RefsInspectorScrollDirection, Never
  >()
  private let inspectorNoteRevealsSubject = PassthroughSubject<
    RefsInspectorNotesReveal, Never
  >()
  private var subscriptions = Set<AnyCancellable>()
  private struct PendingOpen {
    let id: String
    let target: RefsOpenTarget
    let recordsOpen: Bool
    let switchedFileName: String?
  }

  private var pendingOpen: PendingOpen?
  /// Set by ⌘R (and Retry) so the next completed refresh builds a fresh
  /// listing instead of a content-only update.
  private var pendingRefreshRerank = false
  /// The library item ids the visible listing was last ranked from.
  /// `libraryDidPublish` diffs the current ids against this set to find
  /// arrivals that landed while the panel was open.
  private var rankedItemIDs: Set<String> = []
  /// First-seen library ids waiting to reset an ordinary show.
  private var arrivals: RefsArrivalTracker
  /// Deadline after which a visible arrival only joins. Armed by a
  /// `.library` show; cleared by any command, query edit, or hide.
  private var visibleArrivalDeadline: Date?
  private let now: () -> Date
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
  private var todayLinkSequence: UInt64 = 0
  private var todayLinkListingSequence: UInt64 = 0
  private var todayLinkListingTask: Task<Void, Never>?
  private var todayLinkPreviewTask: Task<Void, Never>?
  private var todayLinkTask: Task<Void, Never>?
  private var todayLinkOverlaySequence: UInt64 = 0
  private var selectionAtScanStart: String?
  private var pendingScanBanner: RefsBanner?
  private var scanNoticeSeen = false

  private struct TodayLinkOverlay {
    let writeGeneration: UInt64
    let name: String
    var refreshGeneration: UInt64
    var snapshotGeneration: UInt64
    var refreshPending: Bool
  }

  public init(
    library: RefsLibrary,
    opener: RefsOpening,
    highlights: RefsHighlightsLocating,
    pasteboard: RefsPasteboardWriting = SystemRefsPasteboard(),
    tabs: HighlightsTabsSession? = nil,
    isAdHocSigned: @escaping () -> Bool = { false },
    imageProvider: RefsAnnotationImageProviding? = nil,
    now: @escaping () -> Date = { Date() }
  ) {
    self.library = library
    self.opener = opener
    self.highlights = highlights
    self.pasteboard = pasteboard
    self.now = now
    self.arrivals = RefsArrivalTracker(knownIDs: library.items.map(\.id))
    tabsSession =
      tabs
      ?? HighlightsTabsSession(
        reader: UnavailableHighlightsTabsReader()
      )
    self.isAdHocSigned = isAdHocSigned
    let initialListing = RefsRanker.listing(
      library.items,
      query: "",
      scope: .all,
      order: .ranked,
      signals: library.signals
    )
    listing = initialListing
    rankedItemIDs = Set(library.items.map(\.id))
    selectedID = RefsSelectionPolicy.initial(in: initialListing)
    inspectorLoader = RefsInspectorLoader(
      library: library,
      images: imageProvider
    )
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
    library.$todayRefreshGeneration.sink { [weak self] _ in
      Task { await self?.libraryDidPublish() }
    }.store(in: &subscriptions)
    library.$scanState.sink { [weak self] _ in
      Task { await self?.scanStateDidChange() }
    }.store(in: &subscriptions)
    library.$refreshState.sink { [weak self] _ in
      Task { await self?.refreshStateDidChange() }
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
    visibleArrivalDeadline = nil
    closeCopyCard()
    if !isLinkingToday {
      closeTodayLinkCard()
    }
    // A failed rename card survives hiding so the next presentation
    // can re-show its inline error.
    if !isRenaming, renameCard?.isFailed != true {
      closeRenameCard()
    }
    if scanNoticeSeen {
      scanNotice = nil
      scanNoticeSeen = false
    }
  }

  /// The Today Pomodoro name for an id, or nil when the row is not
  /// in Today. An empty name reads "NOW" in the pill. The join runs
  /// through the row's located task, so two references sharing one
  /// parent note do not both claim the pill.
  public func pomodoroName(for id: String) -> String? {
    if let overlay = todayLinkOverlay[id],
      library.todayRefreshGeneration <= overlay.refreshGeneration
    {
      return overlay.name
    }
    guard let item = library.item(id: id) else {
      return nil
    }
    return library.signals.today.entry(for: item)?.pomodoroName
  }

  /// The selected item, or nil when nothing is selected.
  public var selectedItem: RefItem? {
    guard let selectedID else {
      return nil
    }
    return library.item(id: selectedID)
  }

  /// The tab metadata for each row in the latest Tabs listing.
  public var openTabsByID: [String: RefsOpenTab] {
    tabsListing?.tabs ?? [:]
  }

  private var selectedOpenTab: RefsOpenTab? {
    guard let selectedID else { return nil }
    return openTabsByID[selectedID]
  }

  /// Restores the remembered view on ordinary shows, except when a newly
  /// added reference is pending: then the show resets to fresh-launch
  /// defaults and selects that reference. Scan-result shows start from
  /// fresh-launch defaults. A `.panelSwitch` show always restores the
  /// remembered view and never resets for a pending arrival. Per-show
  /// cards, banners, and presentation animation are still handled here.
  public func prepareForPresentation(source: RefsPresentationSource = .library) {
    presentationCount += 1
    selectedRowRect = nil
    renameStatus = nil
    if isRenaming || isLinkingToday {
      return
    }
    closeCopyCard()
    // A failed rename card is re-presented with its inline error and
    // draft instead of closed; refocus its field.
    let replayingFailedRename = renameCard?.isFailed == true
    if replayingFailedRename {
      renameCardGeneration &+= 1
    } else {
      closeRenameCard()
    }
    heldTabsOpen = false
    pendingClosedTab = nil
    preserveTabsSelectionOnNextSnapshot = false
    banner = nil
    pendingOpen = nil

    switch source {
    case .library:
      if !replayingFailedRename,
        arrivals.hasQualifying(
          item: { library.item(id: $0) },
          signals: library.signals
        )
      {
        resetForArrival()
      } else {
        restoreLastViewForPresentation()
        if !replayingFailedRename {
          arrivals.clearPending()
        }
      }
      visibleArrivalDeadline = now().addingTimeInterval(
        RefsArrivalTracker.visibleGraceSeconds
      )
    case .highlightsTabs:
      if tabsFilter {
        restoreTabsForPresentation()
      } else {
        tabsSelectionConsumed = false
        enterTabsFilter(preservingSelection: false)
      }
    case .scanResults:
      resetToDefaults(tabs: false)
      arrivals.clearPending()
      visibleArrivalDeadline = nil
    case .panelSwitch:
      // A switch keeps the remembered view even when a qualifying
      // arrival is pending: the fresh listing already contains the new
      // reference at its ranked place, so it joins without moving the
      // selection. Clearing pending keeps a later `.library` show from
      // resetting, and a nil deadline keeps an arrival that lands while
      // the switched-to panel is open on the join path.
      restoreLastViewForPresentation()
      arrivals.clearPending()
      visibleArrivalDeadline = nil
    }

    if let pending = pendingScanBanner {
      banner = pending
      pendingScanBanner = nil
    }
    if scanNotice != nil, !scanNoticeSeen {
      scanNoticeSeen = true
    }
    inspectorRequested()
  }

  private func restoreLastViewForPresentation() {
    guard tabsFilter else {
      tabsState = .off
      freshListingKeepingSelection()
      return
    }
    restoreTabsForPresentation()
  }

  private func restoreTabsForPresentation() {
    let preservingSelection = !tabsSelectionConsumed
    tabsSelectionConsumed = false
    tabsState = .loading
    rebuildTabsListing(preservingSelection: preservingSelection)
    beginTabsRefresh(preservingSelection: preservingSelection)
  }

  private func resetToDefaults(
    tabs: Bool,
    announcement: String? = "Bob Refs reset"
  ) {
    query = ""
    scope = .all
    listOrder = .ranked
    heldTabsOpen = false
    pendingClosedTab = nil
    preserveTabsSelectionOnNextSnapshot = false
    banner = nil
    pendingOpen = nil
    tabsSelectionConsumed = false
    revealedPageID = nil
    revealedPage = nil
    inspectorPlace = nil
    inspectorGeneration &+= 1
    listResetGeneration &+= 1
    if tabs {
      tabsFilter = true
      tabsState = .loading
    } else {
      leaveTabsFilter()
    }
    rerankSelectingFirst()
    if tabs {
      beginTabsRefresh(preservingSelection: false)
    }
    if let announcement {
      AccessibilityNotification.Announcement(announcement).post()
    }
  }

  /// Resets to fresh-launch defaults and selects the qualifying arrival
  /// from the latest pending batch. Keeps a banner that is already up.
  private func resetForArrival() {
    let keptBanner = banner
    resetToDefaults(tabs: false, announcement: nil)
    banner = keptBanner
    if let target = arrivals.target(
      orderedIDs: listing.orderedIDs,
      item: { library.item(id: $0) },
      signals: library.signals
    ) {
      selectedID = target
    }
    let title =
      selectedID.flatMap { library.item(id: $0)?.title.text } ?? "reference"
    AccessibilityNotification.Announcement("New reference: \(title)").post()
    arrivals.clearPending()
  }

  /// Re-ranks on every query edit, selects the first row, and dismisses
  /// any banner.
  public func queryDidChange() {
    visibleArrivalDeadline = nil
    heldTabsOpen = false
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
    visibleArrivalDeadline = nil
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
    case .toggleTabs:
      setTabsFilter(!tabsFilter)
      return true
    case .setTabsFilter(let enabled):
      setTabsFilter(enabled)
      return true
    case .resetView:
      if isRenaming || isLinkingToday {
        return true
      }
      resetToDefaults(tabs: false)
      return true
    case .toggleNewest:
      setNewest(listOrder != .newest)
      return true
    case .setNewest(let enabled):
      setNewest(enabled)
      return true
    case .requestTabsPermission:
      tabsSession.reader.requestTrust()
      beginTabsRefresh(preservingSelection: false)
      return true
    case .closeSelectedTab:
      if isRenaming || isLinkingToday {
        return true
      }
      // Stale closes never scroll and never close another tab.
      guard canCloseSelectedTab, let selectedID else {
        return true
      }
      return closeTab(id: selectedID)
    case .closeTab(let id):
      if isRenaming || isLinkingToday {
        return true
      }
      return closeTab(id: id)
    case .reopenClosedTab:
      if let pendingClosedTab {
        return reopenClosedTab(pendingClosedTab)
      }
      guard let closed = tabsSession.popClosedTab() else {
        return true
      }
      return reopenClosedTab(closed)
    case .escape:
      if todayLinkCard != nil {
        if !isLinkingToday {
          closeTodayLinkCard()
        }
        return true
      }
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
      hidePanel()
      return true
    case .deleteBackwardOnEmpty:
      guard query.isEmpty else {
        return false
      }
      if tabsFilter {
        setTabsFilter(false)
        return true
      }
      if listOrder == .newest {
        setNewest(false)
        return true
      }
      guard scope != .all else {
        return false
      }
      scope = .all
      rerankSelectingFirst()
      return true
    case .refresh:
      // Start the Tabs read synchronously so a close supersedes it; only the
      // library refresh waits for the single-flight `refs-pull` fast-forward.
      // The re-rank flag is set once the pull is done so an arrival during the
      // pull cannot consume ⌘R's re-rank with pre-pull data. A failed or
      // unsupported pull still refreshes.
      if tabsFilter {
        beginTabsRefresh(preservingSelection: true)
      }
      Task { [weak self] in
        await self?.library.pullAndWait()
        self?.pendingRefreshRerank = true
        self?.library.refresh(reason: .manual)
      }
      return true
    case .select(let id):
      if isRenaming || isLinkingToday {
        return true
      }
      closeRenameCard()
      closeCopyCard()
      guard listing.contains(id: id) else {
        return false
      }
      selectedID = id
      return true
    case .activate(let id):
      if isRenaming || isLinkingToday {
        return true
      }
      closeRenameCard()
      closeCopyCard()
      guard listing.contains(id: id) else {
        return false
      }
      selectedID = id
      return openSelected(.highlights)
    case .showActions:
      if isRenaming || isLinkingToday {
        return true
      }
      closeRenameCard()
      closeCopyCard()
      if let tab = selectedOpenTab, isSynthetic(tab) {
        showNoteActionWarning(for: tab)
        return true
      }
      guard selectedID != nil, selectedItem != nil else {
        return false
      }
      actionsPresenter()
      return true
    case .showCopyCard:
      if isLinkingToday { return true }
      if let tab = selectedOpenTab, isSynthetic(tab) {
        showNoteActionWarning(for: tab)
        return true
      }
      openCopyCard()
      return true
    case .showRenameCard:
      if isLinkingToday { return true }
      if let tab = selectedOpenTab, isSynthetic(tab) {
        showNoteActionWarning(for: tab)
        return true
      }
      openRenameCard()
      return true
    case .showTodayLinkCard:
      if isRenaming || isLinkingToday { return true }
      if let tab = selectedOpenTab, isSynthetic(tab) {
        showNoteActionWarning(for: tab)
        return true
      }
      openTodayLinkCard()
      return true
    case .toggleNew:
      toggleSelectedNew()
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
  /// time while the snapshot keeps its 60 s staleness rule. Also starts
  /// a throttled `refs-pull` fast-forward so references pushed from
  /// athena or apollo show up without waiting for the 15 s LaunchAgent.
  /// Never blocks presentation.
  public func refreshForOpen(maxAge: TimeInterval = 60) {
    library.refreshToday(reason: .panelOpen)
    library.requestPullForPanelOpen()
    refreshIfStale(maxAge: maxAge)
  }

  private func setTabsFilter(_ enabled: Bool) {
    guard tabsFilter != enabled else { return }
    heldTabsOpen = false
    banner = nil
    if enabled {
      enterTabsFilter(preservingSelection: false)
    } else {
      leaveTabsFilter()
      rerankSelectingFirst()
    }
  }

  private func enterTabsFilter(preservingSelection: Bool) {
    heldTabsOpen = false
    listOrder = .ranked
    tabsFilter = true
    tabsState = .loading
    preserveTabsSelectionOnNextSnapshot = false
    rebuildTabsListing(preservingSelection: preservingSelection)
    beginTabsRefresh(preservingSelection: preservingSelection)
  }

  /// Drops the Tabs filter without re-ranking, so a following Newest
  /// re-rank is the only one.
  private func leaveTabsFilter() {
    tabsFilter = false
    tabsRefreshGeneration &+= 1
    tabsState = .off
    preserveTabsSelectionOnNextSnapshot = false
  }

  private func setNewest(_ enabled: Bool) {
    let next: RefsListOrder = enabled ? .newest : .ranked
    if listOrder == next, !(enabled && tabsFilter) {
      return
    }
    heldTabsOpen = false
    banner = nil
    if enabled, tabsFilter {
      leaveTabsFilter()
    }
    listOrder = next
    rerankSelectingFirst()
    AccessibilityNotification.Announcement(
      enabled ? "Newest first" : "Library sections"
    ).post()
  }

  /// Starts a trusted, one-shot tab read. The reader itself never prompts.
  private func beginTabsRefresh(preservingSelection: Bool) {
    guard tabsFilter else { return }
    tabsRefreshGeneration &+= 1
    let requestGeneration = tabsRefreshGeneration
    preserveTabsSelectionOnNextSnapshot = preservingSelection
    guard tabsSession.reader.isTrusted() else {
      heldTabsOpen = false
      matchedTabs = []
      tabsHighlightsIsFrontmost = false
      tabsState = .needsPermission(adHoc: isAdHocSigned())
      rebuildTabsListing(preservingSelection: false)
      return
    }
    tabsState = .loading
    let session = tabsSession
    Task { [weak self] in
      let result = await session.refresh()
      guard let self,
        self.tabsFilter,
        self.tabsRefreshGeneration == requestGeneration,
        let result
      else {
        return
      }
      self.applyTabsReadResult(result)
    }
  }

  private func applyTabsReadResult(_ result: HighlightsTabsReadResult) {
    switch result {
    case .notRunning:
      matchedTabs = []
      tabsHighlightsIsFrontmost = false
      tabsState = .notRunning
      heldTabsOpen = false
      rebuildTabsListing(preservingSelection: false)
    case .notTrusted:
      matchedTabs = []
      tabsHighlightsIsFrontmost = false
      tabsState = .needsPermission(adHoc: isAdHocSigned())
      heldTabsOpen = false
      rebuildTabsListing(preservingSelection: false)
    case .failed(let message):
      let hasStaleRows = !listing.orderedIDs.isEmpty
      tabsState = .failed(message: message, hasStaleRows: hasStaleRows)
      heldTabsOpen = false
      if !hasStaleRows {
        rebuildTabsListing(preservingSelection: false)
      }
    case .snapshot(let snapshot):
      tabsHighlightsIsFrontmost = snapshot.highlightsIsFrontmost
      matchedTabs = HighlightsTabMatcher.match(
        snapshot,
        items: library.items,
        vaultRoot: library.vaultRootURL
      )
      tabsState = matchedTabs.isEmpty ? .noDocuments : .loaded
      let preserve = preserveTabsSelectionOnNextSnapshot
      preserveTabsSelectionOnNextSnapshot = false
      rebuildTabsListing(preservingSelection: preserve)
      if heldTabsOpen {
        heldTabsOpen = false
        if selectedID != nil {
          _ = perform(.open(.highlights))
        }
      }
    }
  }

  private func rebuildTabsListing(preservingSelection: Bool) {
    let keep = preservingSelection ? selectedID : nil
    rankedItemIDs = Set(library.items.map(\.id))
    let ranked = RefsTabsRanker.listing(
      tabs: matchedTabs.filter { !closingRowIDs.contains($0.rowID) },
      items: library.items,
      query: query,
      scope: scope,
      signals: library.signals,
      recency: tabsSession.recency,
      highlightsIsFrontmost: tabsHighlightsIsFrontmost
    )
    tabsListing = ranked
    listing = ranked.listing
    unavailableIDs = []
    if let keep, listing.contains(id: keep) {
      selectedID = keep
    } else {
      selectedID = ranked.preselectedID
    }
  }

  private func closeTab(id: String) -> Bool {
    guard canCloseTab(id: id),
      listing.contains(id: id),
      let tab = tabsListing?.tabs[id]
    else {
      return false
    }

    // Clean up non-running cards like the surrounding row actions;
    // the dispatch guards above keep an in-flight vault write alive.
    closeRenameCard()
    closeTodayLinkCard()
    closeCopyCard()

    let nextSelection = RefsSelectionPolicy.afterRemoving(id, in: listing)
    let title = rowContent(for: id)?.title ?? tab.fileName
    let reopen: RefsClosedTab?
    if let itemID = tab.itemID,
      let item = library.item(id: itemID),
      let url = library.pdfURL(for: item)
    {
      reopen = RefsClosedTab(
        title: item.title.text,
        fileName: tab.fileName,
        url: url,
        itemID: item.id
      )
    } else if let path = tab.documentPath {
      reopen = RefsClosedTab(
        title: tab.fileName,
        fileName: tab.fileName,
        url: URL(fileURLWithPath: path),
        itemID: nil
      )
    } else {
      reopen = nil
    }

    closingRowIDs.insert(id)
    let updateListing = {
      self.rebuildTabsListing(preservingSelection: false)
      if let nextSelection,
        self.listing.contains(id: nextSelection)
      {
        self.selectedID = nextSelection
      }
    }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      updateListing()
    } else {
      withAnimation(.snappy(duration: 0.2)) {
        updateListing()
      }
    }
    AccessibilityNotification.Announcement(
      RefsTabClosePresentation.announcement(
        title: title,
        countText: tabsCountText
      )
    ).post()

    closeQueue.append(PendingTabClose(tab: tab, title: title, reopen: reopen))
    startCloseWorkerIfNeeded()
    return true
  }

  /// Narrow test seam: how many close workers have started, and
  /// whether the queue is fully idle. Tests use these to prove a
  /// drained queue stops instead of chaining empty workers.
  var closeWorkerLaunchCountForTests = 0
  var rowContentEvaluationsForTests = 0
  var rowRenderProbeForTests: RefsRowRenderProbe?
  var isCloseIdleForTests: Bool {
    closeQueue.isEmpty && closeWorker == nil
  }

  private func startCloseWorkerIfNeeded() {
    guard closeWorker == nil, !closeQueue.isEmpty else { return }
    let requestGeneration = tabsRefreshGeneration
    closeWorkerLaunchCountForTests += 1
    closeWorker = Task { [weak self] in
      guard let self else { return }
      while let next = self.takeNextClose() {
        let outcome = await self.tabsSession.close(
          next.tab,
          reopen: next.reopen
        )
        self.finishClose(next, outcome: outcome)
      }
      // Settle a refresh superseded by a close, but never a fresh
      // read that started after this worker batch.
      if self.tabsFilter, self.tabsState == .loading,
        self.tabsRefreshGeneration == requestGeneration
      {
        self.tabsState = self.matchedTabs.isEmpty ? .noDocuments : .loaded
      }
      self.closeWorker = nil
      if !self.closeQueue.isEmpty {
        self.startCloseWorkerIfNeeded()
      }
    }
  }

  private func takeNextClose() -> PendingTabClose? {
    guard !closeQueue.isEmpty else { return nil }
    return closeQueue.removeFirst()
  }

  private func finishClose(
    _ pending: PendingTabClose,
    outcome: HighlightsTabCloseOutcome
  ) {
    closingRowIDs.remove(pending.tab.rowID)
    switch outcome {
    case .closed(let snapshot):
      applyCloseSnapshot(snapshot)
      let toast = RefsTabClosePresentation.toast(
        title: pending.title,
        canReopen: pending.reopen != nil
      )
      if panelIsVisible() {
        tabCloseCompletion(toast)
      }
    case .closedLast(let highlightsQuit):
      matchedTabs = []
      tabsHighlightsIsFrontmost = false
      closingRowIDs.removeAll()
      tabsState = .noDocuments
      if tabsFilter {
        rebuildTabsListing(preservingSelection: false)
      }
      AccessibilityNotification.Announcement(
        RefsTabClosePresentation.lastAnnouncement(
          title: pending.title,
          highlightsQuit: highlightsQuit
        )
      ).post()
      if panelIsVisible() {
        tabCloseDismisser()
      }
      tabCloseCompletion(
        RefsTabClosePresentation.lastToast(
          title: pending.title,
          highlightsQuit: highlightsQuit
        )
      )
    case .alreadyClosed:
      matchedTabs.removeAll { $0.rowID == pending.tab.rowID }
      if tabsFilter {
        beginTabsRefresh(preservingSelection: true)
      }
    case .notRunning:
      matchedTabs = []
      tabsHighlightsIsFrontmost = false
      heldTabsOpen = false
      tabsState = .notRunning
      if tabsFilter {
        rebuildTabsListing(preservingSelection: false)
      }
    case .notTrusted:
      matchedTabs = []
      tabsHighlightsIsFrontmost = false
      heldTabsOpen = false
      tabsState = .needsPermission(adHoc: isAdHocSigned())
      if tabsFilter {
        rebuildTabsListing(preservingSelection: false)
      }
    case .needsAttention:
      if panelIsVisible() {
        hidePanel()
      }
      if tabsFilter {
        beginTabsRefresh(preservingSelection: true)
      }
    case .failed:
      if tabsFilter {
        rebuildTabsListing(preservingSelection: false)
        if listing.contains(id: pending.tab.rowID) {
          selectedID = pending.tab.rowID
        }
        if panelIsVisible() {
          banner = RefsBanner(
            kind: .error,
            message: RefsTabClosePresentation.failureMessage(
              title: pending.title
            ),
            actions: []
          )
        }
        beginTabsRefresh(preservingSelection: true)
      }
    }
  }

  private func applyCloseSnapshot(_ snapshot: HighlightsTabsSnapshot) {
    tabsHighlightsIsFrontmost = snapshot.highlightsIsFrontmost
    matchedTabs = HighlightsTabMatcher.match(
      snapshot,
      items: library.items,
      vaultRoot: library.vaultRootURL
    )
    tabsState = matchedTabs.isEmpty ? .noDocuments : .loaded
    heldTabsOpen = false
    if tabsFilter {
      rebuildTabsListing(preservingSelection: true)
    }
  }

  private var tabsCountText: String {
    let isSearch: Bool
    if case .search = listing.mode {
      isSearch = true
    } else {
      isSearch = false
    }
    return RefsTabsCount.text(
      shown: listing.orderedIDs.count,
      total: listing.totalCount,
      isSearch: isSearch
    )
  }

  private func isSynthetic(_ tab: RefsOpenTab) -> Bool {
    tab.match == .collision || tab.match == .none
  }

  private func showNoteActionWarning(for tab: RefsOpenTab) {
    let message: String
    if tab.match == .collision {
      message =
        "“\(tab.fileName)” matches \(tab.candidateIDs.count) notes — press ⌘T and search to act on one."
    } else {
      message = "“\(tab.fileName)” isn't in your library."
    }
    banner = RefsBanner(kind: .warning, message: message, actions: [])
  }

  private func selectOpenTab(_ tab: RefsOpenTab) -> Bool {
    hidePanel()
    let session = tabsSession
    Task { [weak self] in
      let result = await session.select(tab)
      guard let self else { return }
      switch result {
      case .selected:
        self.tabsSelectionConsumed = true
      case .notFound:
        self.panelRepresenter()
        self.banner = RefsBanner(
          kind: .warning,
          message: "That tab was closed in Highlights.",
          actions: []
        )
      case .notRunning:
        self.tabsState = .notRunning
        self.panelRepresenter()
        self.banner = RefsBanner(
          kind: .warning,
          message: "Highlights isn't running.",
          actions: []
        )
      case .notTrusted:
        self.tabsState = .needsPermission(adHoc: self.isAdHocSigned())
        self.panelRepresenter()
      case .failed:
        self.panelRepresenter()
        self.banner = RefsBanner(
          kind: .error,
          message: "Couldn't switch to that tab in Highlights.",
          actions: []
        )
      }
    }
    return true
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
    rowContentEvaluationsForTests += 1
    guard listing.contains(id: id) else {
      return nil
    }
    let signals = library.signals
    let match = listing.matches[id]
    let section = listing.sectionKind(for: id)
    let openTab = tabsFilter ? tabsListing?.tabs[id] : nil
    if let openTab, isSynthetic(openTab) {
      let candidates = openTab.candidateIDs.compactMap { candidateID in
        library.item(id: candidateID)
      }
      let caption =
        openTab.match == .none
        ? "Not in your library"
        : "Matches \(openTab.candidateIDs.count) notes"
      return RefsRowContent(
        item: nil,
        openTab: openTab,
        candidateItems: candidates,
        title: openTab.fileName,
        caption: caption,
        whyHere: openTab.isCurrent ? "Current tab in Highlights" : "Open in Highlights",
        match: match,
        section: section,
        isNew: false,
        isMissingPDF: false,
        isUnavailable: false
      )
    }
    guard let item = library.item(id: id) else {
      return RefsRowContent(
        item: nil,
        openTab: openTab,
        title: listing.unavailableItems[id]?.title.text ?? id,
        caption: "No longer in your library",
        whyHere: "No longer in your library",
        match: nil,
        section: section,
        isNew: false,
        isMissingPDF: false,
        isUnavailable: true
      )
    }
    let captioned = RefsCaption.captionWithMatch(
      for: item, in: section, signals: signals, match: match
    )
    return RefsRowContent(
      item: item,
      openTab: openTab,
      title: item.title.text,
      caption: captioned.text,
      captionMatch: captioned.matchRange,
      whyHere: RefsExplanation.whyHere(item, listing: listing, signals: signals),
      match: match,
      section: section,
      isNew: RefsRanker.isNew(item, signals: signals),
      isMissingPDF: signals.missingPDFs.contains(id),
      isUnavailable: unavailableIDs.contains(id)
    )
  }

  /// Trailing hint on the NEW header while the selection is a row of
  /// that frozen section. Visual only.
  public var newSectionHint: String? {
    guard let selectedID, listing.sectionKind(for: selectedID) == .new else {
      return nil
    }
    guard let item = library.item(id: selectedID),
      !listing.unavailableIDs.contains(selectedID)
    else {
      return nil
    }
    return RefsRanker.isNew(item, signals: library.signals)
      ? "⌥N Mark Seen"
      : "⌥N Mark New"
  }

  /// Flips NEW on the selected Ready/Next row in place. Ineligible
  /// rows beep and write nothing. Always consumes ⌥N.
  private func toggleSelectedNew() {
    if isRenaming || isLinkingToday {
      return
    }
    guard let selectedID,
      !listing.unavailableIDs.contains(selectedID),
      library.item(id: selectedID) != nil
    else {
      ineligibleNewFeedback()
      return
    }
    switch library.toggleNew(id: selectedID) {
    case .ineligible:
      ineligibleNewFeedback()
    case .apply(_, let becomesNew):
      AccessibilityNotification.Announcement(
        becomesNew ? "Marked new" : "Marked seen"
      ).post()
    }
  }

  private func ineligibleNewFeedback() {
    beep()
    AccessibilityNotification.Announcement(
      "Only Ready and Next references can be New"
    ).post()
  }

  /// Runs one banner action.
  public func performBannerAction(_ action: RefsBanner.Action) {
    switch action {
    case .tryAgain:
      if let pendingClosedTab {
        _ = openClosedTab(pendingClosedTab)
        return
      }
      guard let pending = pendingOpen else {
        return
      }
      openStored(pending)
    case .openInDefaultApp:
      if let pendingClosedTab {
        openClosedTabInDefaultApp(pendingClosedTab)
        return
      }
      guard let pending = pendingOpen,
        let item = library.item(id: pending.id)
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
    listOrder: RefsListOrder = .ranked,
    scanState: RefsScanState = .idle,
    scanNotice: RefsScanOutcome? = nil,
    inspector: [String: RefsInspectorContent]? = nil,
    thumbnails: [String: NSImage]? = nil,
    images: [String: NSImage] = [:]
  ) {
    library.installSnapshotForPreviews(
      items: items,
      signals: signals,
      refreshState: refreshState
    )
    library.installScanStateForPreviews(scanState)
    self.query = query
    self.scope = scope
    self.listOrder = listOrder
    if listOrder == .newest, tabsFilter {
      leaveTabsFilter()
    }
    self.banner = banner
    self.scanNotice = scanNotice
    scanNoticeSeen = scanNotice != nil
    knownItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    rankedItemIDs = Set(items.map(\.id))
    if tabsFilter {
      rebuildTabsListing(preservingSelection: false)
    } else {
      listing = RefsRanker.listing(
        items,
        query: query,
        scope: scope,
        order: listOrder,
        signals: signals
      )
    }
    unavailableIDs = []
    revealedPageID = nil
    revealedPage = nil
    self.selectedID = selectedID
    arrivals = RefsArrivalTracker(knownIDs: items.map(\.id))
    if let inspector {
      inspectorLoader.installContentForPreviews(
        inspector,
        thumbnails: thumbnails ?? [:],
        images: images
      )
    } else {
      inspectorLoader.reset()
    }
  }

  /// Installs a canned tab snapshot and state for previews without invoking a reader.
  /// `closingIDs` hides those rows the same way an in-flight ⌃X does, so
  /// close-views can render a list mid-close.
  public func installTabsForPreviews(
    snapshot: HighlightsTabsSnapshot?,
    state: RefsTabsState,
    frontmost: Bool,
    closingIDs: Set<String> = []
  ) {
    tabsFilter = true
    listOrder = .ranked
    tabsState = state
    tabsHighlightsIsFrontmost = frontmost
    heldTabsOpen = false
    preserveTabsSelectionOnNextSnapshot = false
    closingRowIDs = closingIDs
    if let snapshot {
      matchedTabs = HighlightsTabMatcher.match(
        snapshot,
        items: library.items,
        vaultRoot: library.vaultRootURL
      )
    } else {
      matchedTabs = []
    }
    rebuildTabsListing(preservingSelection: false)
    unavailableIDs = []
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

  /// Records the current preview place without publishing a model change.
  public func noteInspectorOffset(id: String, generation: Int, offset: CGFloat) {
    guard selectedID == id,
      generation == inspectorGeneration,
      offset.isFinite
    else {
      return
    }
    inspectorPlace = (id, generation, offset)
  }

  /// The remembered place for the selected reference, when it is still
  /// valid for this inspector generation and is meaningfully below top.
  public func inspectorRestoreOffset(for id: String) -> CGFloat? {
    guard let place = inspectorPlace,
      place.id == id,
      place.generation == inspectorGeneration,
      place.offset > 0.5
    else {
      return nil
    }
    return place.offset
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

  /// Reveals the next page of the selected row's highlights.
  /// Returns false unless the selected id has hydrated content that
  /// still hides entries. On success it stores the page, announces
  /// the new count, and emits on `inspectorNoteReveals` for the
  /// controller's follow-tail scroll.
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
    inspectorNoteRevealsSubject.send(
      RefsInspectorNotesReveal(
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
    let newState: RefsNewMenuState
    if item.state == .ready || item.state == .next {
      newState =
        RefsRanker.isNew(item, signals: library.signals)
        ? .isNew
        : .isNotNew
    } else {
      newState = .none
    }
    return RefsActionsMenu.sections(
      for: item,
      audioURL: library.audioURL(for: item),
      canCloseTab: canCloseTab(id: item.id),
      newState: newState
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
    case .linkToday:
      openTodayLinkCard()
    case .markSeen, .markNew:
      _ = perform(.toggleNew)
    case .closeTab:
      guard let selectedID else { return }
      _ = perform(.closeTab(id: selectedID))
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
    guard !isRenaming, !isLinkingToday else { return }
    closeTodayLinkCard()
    closeRenameCard()
    closeCopyCard()
    guard let item = selectedItem,
      listing.contains(id: item.id),
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
    let notes =
      inspectorLoader.cachedShowRow(for: item)
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
    guard !isRenaming, !isLinkingToday,
      let item = selectedItem,
      listing.contains(id: item.id),
      !unavailableIDs.contains(item.id)
    else {
      return
    }
    closeTodayLinkCard()
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
        let failure =
          response.error
          ?? RefsRenameFailure(
            code: "invalid_response",
            message: "Bob returned an incomplete rename response."
          )
        failRename(message: failure.message, hint: failure.hint)
        libraryDidPublish()
        return
      }
      let stem =
        response.to?.stem
        ?? URL(fileURLWithPath: destination).deletingPathExtension().lastPathComponent
      let wasVisible = panelIsVisible()
      knownItems.removeValue(forKey: notePath)
      unavailableIDs.remove(notePath)
      unavailableIDs.remove(destination)
      // The selection change below clears the revealed page through
      // `selectedID`'s `didSet` (reveal_memory = reset), so there is
      // no remap to preserve here.
      if selectedID == notePath {
        selectedID = destination
      }
      arrivals.markSeen([destination])
      await inspectorLoader.discard(id: notePath)
      renameCard = nil
      renameTask = nil
      renameStatus = RefsRenamePresentation.status(
        stem: stem,
        rewrittenLinks: response.links?.rewritten ?? 0,
        outcome: response.outcome
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
      if let libraryError = error as? RefsLibraryError,
        libraryError == .busy
      {
        failRename(message: libraryError.message, hint: nil)
      } else {
        let problem = RefsRenameProblemMapping.transportProblem(for: error)
        failRename(message: problem.message, hint: problem.hint)
      }
      libraryDidPublish()
    }
  }

  private func failRename(message: String, hint: String?) {
    guard var card = renameCard, card.phase == .running else { return }
    card.fail(message: message, hint: hint)
    renameCard = card
    renameTask = nil
    // Refocus the rename field on the running-to-failed transition.
    renameCardGeneration &+= 1
    if !panelIsVisible() {
      renameFailureNotifier(message, hint)
    }
  }

  /// Opens Bob's Link to Today card for the selected real reference.
  /// The first dry run is the source of the default, rows, and preview.
  public func openTodayLinkCard() {
    guard !isRenaming, !isLinkingToday,
      let item = selectedItem,
      listing.contains(id: item.id),
      !unavailableIDs.contains(item.id)
    else {
      return
    }
    closeCopyCard()
    closeRenameCard()
    closeTodayLinkCard()
    todayLinkSequence &+= 1
    let token = todayLinkSequence
    todayLinkCard = RefsTodayLinkCard(item: item)
    todayLinkCardGeneration &+= 1
    AccessibilityNotification.Announcement(
      "Link to Today. Choose a Pomodoro."
    ).post()
    loadTodayLinkListing(token: token)
  }

  /// Maps the focused card's key without intercepting ordinary text
  /// editing or IME composition.
  public func todayLinkCardKeyCommand(
    keyCode: UInt16,
    modifiers: RefsCopyKeyModifiers,
    hasMarkedText: Bool
  ) -> RefsTodayLinkKeyCommand? {
    guard let card = todayLinkCard else { return nil }
    return RefsTodayLinkKeyMap.command(
      keyCode: keyCode,
      modifiers: modifiers,
      isRunning: card.phase == .running,
      hasMarkedText: hasMarkedText
    )
  }

  public func editTodayLinkQuery(_ value: String) {
    guard var card = todayLinkCard else { return }
    let effect = card.editQuery(value)
    todayLinkCard = card
    applyTodayLinkEffect(effect, token: todayLinkSequence)
  }

  public func selectTodayLinkRow(_ index: Int) {
    guard var card = todayLinkCard else { return }
    let effect = card.select(index: index)
    todayLinkCard = card
    applyTodayLinkEffect(effect, token: todayLinkSequence)
  }

  /// A click commits the row immediately, matching the Copy card's
  /// click-to-act behavior and skipping an unnecessary preview roundtrip.
  public func todayLinkRowTapped(_ index: Int) {
    guard var card = todayLinkCard,
      card.phase.canSelectDestination
    else { return }
    _ = card.select(index: index)
    let effect = card.handle(.submit)
    todayLinkCard = card
    applyTodayLinkEffect(effect, token: todayLinkSequence)
  }

  public func handleTodayLinkCardKey(_ command: RefsTodayLinkKeyCommand) {
    guard var card = todayLinkCard else { return }
    let effect = card.handle(command)
    if effect == .none,
      command == .submit,
      card.phase == .ready,
      card.selector == nil
    {
      todayLinkBeep()
    }
    todayLinkCard = card
    applyTodayLinkEffect(effect, token: todayLinkSequence)
  }

  private func closeTodayLinkCard() {
    guard !isLinkingToday else { return }
    todayLinkSequence &+= 1
    invalidateTodayLinkListing()
    invalidateTodayLinkPreview()
    todayLinkCard = nil
    todayLinkCardGeneration &+= 1
  }

  private func loadTodayLinkListing(token: UInt64) {
    guard let card = todayLinkCard,
      card.phase == .loading || card.phase == .reloading
    else { return }
    invalidateTodayLinkListing()
    let requestID = todayLinkListingSequence
    let path = card.notePath
    todayLinkListingTask = Task { [weak self, library] in
      do {
        let response = try await library.linkToToday(
          notePath: path, selector: .automatic, dryRun: true
        )
        guard !Task.isCancelled else { return }
        self?.applyTodayLinkListing(response, token: token, requestID: requestID)
      } catch {
        guard !Task.isCancelled else { return }
        self?.failTodayLinkListing(
          RefsTodayLinkProblemMapping.transportProblem(for: error),
          token: token,
          requestID: requestID
        )
      }
    }
  }

  private func applyTodayLinkListing(
    _ response: RefsTodayLinkResponse, token: UInt64, requestID: UInt64
  ) {
    guard token == todayLinkSequence,
      requestID == todayLinkListingSequence,
      var card = todayLinkCard,
      card.phase != .running
    else { return }
    todayLinkListingTask = nil
    let effect = card.applyListing(response)
    todayLinkCard = card
    if case .refused(let message, let hint) = card.phase, !panelIsVisible() {
      todayLinkFailureNotifier(message, hint)
    }
    applyTodayLinkEffect(effect, token: token)
  }

  private func failTodayLinkListing(
    _ problem: RefsTodayLinkFailure, token: UInt64, requestID: UInt64
  ) {
    guard token == todayLinkSequence,
      requestID == todayLinkListingSequence,
      var card = todayLinkCard,
      card.phase != .running
    else { return }
    todayLinkListingTask = nil
    let effect = card.fail(problem)
    todayLinkCard = card
    if !panelIsVisible() {
      todayLinkFailureNotifier(problem.message, problem.hint)
    }
    applyTodayLinkEffect(effect, token: token)
  }

  private func applyTodayLinkEffect(_ effect: RefsTodayLinkCardEffect, token: UInt64) {
    switch effect {
    case .none:
      break
    case .cancel:
      closeTodayLinkCard()
    case .reload:
      invalidateTodayLinkPreview()
      loadTodayLinkListing(token: token)
    case .preview(let selector):
      guard let card = todayLinkCard,
        let request = card.previewRequest,
        request.selector == selector
      else {
        return
      }
      invalidateTodayLinkPreview()
      let path = card.notePath
      let debounce = todayLinkPreviewDebounce
      todayLinkPreviewTask = Task { [weak self, library] in
        do {
          try await debounce()
          try Task.checkCancellation()
          let response = try await library.linkToToday(
            notePath: path, selector: selector, dryRun: true
          )
          guard !Task.isCancelled else { return }
          self?.applyTodayLinkPreview(response, request: request, token: token)
        } catch is CancellationError {
          return
        } catch {
          guard !Task.isCancelled else { return }
          self?.failTodayLinkPreview(
            RefsTodayLinkProblemMapping.transportProblem(for: error),
            request: request,
            token: token
          )
        }
      }
    case .submit(let selector):
      guard let card = todayLinkCard else { return }
      let path = card.notePath
      invalidateTodayLinkListing()
      invalidateTodayLinkPreview()
      guard todayLinkTask == nil else { return }
      todayLinkTask = Task { [weak self, library] in
        do {
          let response = try await library.linkToToday(
            notePath: path, selector: selector, dryRun: false
          )
          self?.finishTodayLink(response, token: token)
        } catch {
          self?.failTodayLinkWrite(
            RefsTodayLinkProblemMapping.transportProblem(for: error), token: token
          )
        }
      }
    }
  }

  private func applyTodayLinkPreview(
    _ response: RefsTodayLinkResponse,
    request: RefsTodayLinkPreviewRequest,
    token: UInt64
  ) {
    guard token == todayLinkSequence, var card = todayLinkCard else { return }
    guard card.applyPreview(response, for: request) else { return }
    todayLinkCard = card
  }

  private func failTodayLinkPreview(
    _ problem: RefsTodayLinkFailure,
    request: RefsTodayLinkPreviewRequest,
    token: UInt64
  ) {
    guard token == todayLinkSequence, var card = todayLinkCard,
      card.previewRequest == request
    else {
      return
    }
    let effect = card.fail(problem)
    todayLinkCard = card
    if !panelIsVisible() {
      todayLinkFailureNotifier(problem.message, problem.hint)
    }
    applyTodayLinkEffect(effect, token: token)
  }

  private func invalidateTodayLinkListing() {
    todayLinkListingSequence &+= 1
    todayLinkListingTask?.cancel()
    todayLinkListingTask = nil
  }

  private func invalidateTodayLinkPreview() {
    todayLinkPreviewTask?.cancel()
    todayLinkPreviewTask = nil
  }

  private func finishTodayLink(_ response: RefsTodayLinkResponse, token: UInt64) {
    guard token == todayLinkSequence, let card = todayLinkCard else { return }
    todayLinkTask = nil
    guard response.ok == true,
      let toast = RefsTodayLinkPresentation.toast(response: response, title: card.title)
    else {
      let problem =
        RefsTodayLinkProblemMapping.responseProblem(response)
        ?? RefsTodayLinkFailure(
          code: "invalid_response",
          message: RefsTodayLinkPresentation.invalidResponse
        )
      failTodayLinkWrite(problem, token: token)
      return
    }

    let itemID = card.frozenItemID
    let title = card.title
    let overlayGeneration = library.todayRefreshGeneration
    let snapshotGeneration = library.snapshotRefreshGeneration
    var overlayWriteGeneration: UInt64?
    if toast.style != .guarded, let linked = response.pomodoros.first(where: \.linked) {
      todayLinkOverlaySequence &+= 1
      let writeGeneration = todayLinkOverlaySequence
      overlayWriteGeneration = writeGeneration
      todayLinkOverlay[itemID] = TodayLinkOverlay(
        writeGeneration: writeGeneration,
        name: linked.name ?? "",
        refreshGeneration: overlayGeneration,
        snapshotGeneration: snapshotGeneration,
        refreshPending: true
      )
    }
    if toast.style != .guarded {
      library.markSeenIfNew(id: itemID)
    }
    todayLinkSequence &+= 1
    todayLinkCard = nil
    todayLinkCardGeneration &+= 1
    if panelIsVisible() {
      todayLinkCompletion(toast, title)
      if let announcement = RefsTodayLinkPresentation.announcement(
        response: response, title: title
      ) {
        AccessibilityNotification.Announcement(announcement).post()
      }
    } else {
      todayLinkNotifier(response, title)
    }
    let inspectorLoader = inspectorLoader
    Task { [weak self, library, inspectorLoader] in
      await inspectorLoader.discard(id: itemID)
      let refreshed = await library.refreshAndWait(reason: .todayLink)
      guard let overlayWriteGeneration,
        let self,
        let overlay = self.todayLinkOverlay[itemID],
        overlay.writeGeneration == overlayWriteGeneration
      else {
        return
      }
      let todayIsFresh =
        refreshed.today
        && library.todayRefreshGeneration > overlay.refreshGeneration
      let snapshotIsFresh =
        refreshed.snapshot
        && library.snapshotRefreshGeneration > overlay.snapshotGeneration
      if todayIsFresh {
        self.todayLinkOverlay.removeValue(forKey: itemID)
      } else {
        self.todayLinkOverlay[itemID] = TodayLinkOverlay(
          writeGeneration: overlay.writeGeneration,
          name: overlay.name,
          refreshGeneration: library.todayRefreshGeneration,
          snapshotGeneration: snapshotIsFresh
            ? library.snapshotRefreshGeneration
            : overlay.snapshotGeneration,
          refreshPending: false
        )
      }
    }
  }

  private func failTodayLinkWrite(_ problem: RefsTodayLinkFailure, token: UInt64) {
    guard token == todayLinkSequence, var card = todayLinkCard else { return }
    todayLinkTask = nil
    let effect = card.fail(problem)
    todayLinkCard = card
    todayLinkCardGeneration &+= 1
    if !panelIsVisible() {
      todayLinkFailureNotifier(problem.message, problem.hint)
    }
    applyTodayLinkEffect(effect, token: token)
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
    if tabsFilter {
      rebuildTabsListing(preservingSelection: false)
      return
    }
    listing = libraryListing()
    unavailableIDs = []
    selectedID = RefsSelectionPolicy.initial(in: listing)
  }

  /// A fresh listing from the latest data that keeps the selected id
  /// when it still exists, for a completed ⌘R or Retry.
  private func freshListingKeepingSelection() {
    pendingRefreshRerank = false
    pruneKnownItems()
    let keep = selectedID
    if tabsFilter {
      rebuildTabsListing(preservingSelection: true)
      return
    }
    listing = libraryListing()
    unavailableIDs = []
    if let keep, listing.contains(id: keep) {
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
    if tabsFilter {
      rebuildTabsListing(preservingSelection: false)
      if !listing.contains(id: id) {
        query = ""
        rebuildTabsListing(preservingSelection: false)
      }
      selectedID =
        listing.contains(id: id)
        ? id
        : RefsSelectionPolicy.initial(in: listing)
      return
    }
    var fresh = libraryListing()
    if !fresh.contains(id: id) {
      query = ""
      fresh = libraryListing()
    }
    listing = fresh
    unavailableIDs = []
    selectedID =
      listing.contains(id: id)
      ? id
      : RefsSelectionPolicy.initial(in: listing)
  }

  private func libraryListing(query: String? = nil) -> RefsListing {
    rankedItemIDs = Set(library.items.map(\.id))
    return RefsRanker.listing(
      library.items,
      query: query ?? self.query,
      scope: scope,
      order: listOrder,
      signals: library.signals
    )
  }

  /// Drops last-known items the library no longer has: a fresh listing
  /// drops vanished rows, so their titles go with them.
  private func pruneKnownItems() {
    knownItems = Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0) })
  }

  private func libraryDidPublish() {
    if todayLinkOverlay.values.contains(where: {
      !$0.refreshPending && $0.refreshGeneration < library.todayRefreshGeneration
    }) {
      todayLinkOverlay = todayLinkOverlay.filter {
        $0.value.refreshPending
          || $0.value.refreshGeneration >= library.todayRefreshGeneration
      }
    }
    // Keep the card's frozen listing intact while bob moves the bundle
    // and the library performs its single post-rename refresh. On
    // success, runRename installs a fresh listing at bob's `to.path`.
    if isRenaming {
      return
    }
    arrivals.observe(library.items.map(\.id))
    for item in library.items {
      knownItems[item.id] = item
    }
    var available = Set(library.items.map(\.id))
    if tabsFilter, let tabsListing {
      for tab in tabsListing.tabs.values where isSynthetic(tab) {
        available.insert(tab.rowID)
      }
    }
    let (next, unavailable) = listing.refreshingContent(
      availableIDs: available,
      lastKnownItems: knownItems
    )
    listing = next
    if tabsFilter, let tabsListing {
      self.tabsListing = RefsTabsListing(
        listing: next,
        tabs: tabsListing.tabs,
        preselectedID: tabsListing.preselectedID
      )
    }
    // Vanished rows leave the frozen listing, so intersecting with it
    // would drop the flag on the very next publish (every pass publishes
    // items and signals separately). Keep flags for every id that is
    // still missing from the library instead.
    unavailableIDs = unavailable.union(unavailableIDs.subtracting(available))
    let joinedIDs = Set(library.items.map(\.id)).subtracting(rankedItemIDs)
    let arrivalsCanJoin =
      !joinedIDs.isEmpty && !tabsFilter && copyCard == nil && renameCard == nil
      && todayLinkCard == nil && !isRenaming && !isLinkingToday && pendingOpen == nil
      && (selectedID == nil || available.contains(selectedID!))
    if shouldResetForVisibleArrival() {
      resetForArrival()
    } else if pendingRefreshRerank, library.refreshState != .refreshing {
      freshListingKeepingSelection()
      if arrivalsCanJoin {
        AccessibilityNotification.Announcement(
          joinedIDs.count == 1
            ? "1 new reference" : "\(joinedIDs.count) new references"
        ).post()
      }
    } else if arrivalsCanJoin {
      freshListingKeepingSelection()
      AccessibilityNotification.Announcement(
        joinedIDs.count == 1
          ? "1 new reference" : "\(joinedIDs.count) new references"
      ).post()
    } else if next.orderedIDs.isEmpty {
      selectedID = nil
    }
  }

  /// True when an untouched ordinary show is still inside its grace
  /// window and a qualifying arrival can reset the open panel.
  private func shouldResetForVisibleArrival() -> Bool {
    guard panelIsVisible(),
      let deadline = visibleArrivalDeadline,
      now() <= deadline,
      !tabsFilter,
      copyCard == nil,
      renameCard == nil,
      todayLinkCard == nil,
      !isRenaming,
      !isLinkingToday,
      pendingOpen == nil
    else {
      return false
    }
    return arrivals.hasQualifying(
      item: { library.item(id: $0) },
      signals: library.signals
    )
  }

  /// A refresh that just started clears a stale rename status so it
  /// never masks the refresh-failure state.
  private func refreshStateDidChange() {
    if case .refreshing = library.refreshState {
      renameStatus = nil
    }
  }

  /// A finished scan installs its notice or banner; a scan that just
  /// started clears a stale rename status so it never masks the
  /// scanning state.
  private func scanStateDidChange() {
    if case .scanning = library.scanState {
      renameStatus = nil
      return
    }
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
    arrivals.markSeen(outcome.created.map(\.path))
    if tabsFilter {
      freshListingKeepingSelection()
      return
    }
    if case .search = listing.mode {
      freshListingKeepingSelection()
      return
    }
    pruneKnownItems()
    let fresh = libraryListing()
    listing = fresh
    unavailableIDs = []
    if selectedID == selectionAtScanStart, !outcome.created.isEmpty {
      let createdIDs = outcome.created.map(\.path)
      if let first = createdIDs.first(where: { fresh.contains(id: $0) }) {
        selectedID = first
        return
      }
    }
    if let keep = selectedID, fresh.contains(id: keep) {
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
      if target == .highlights,
        tabsFilter,
        tabsState == .loading,
        listing.orderedIDs.isEmpty
      {
        heldTabsOpen = true
        return true
      }
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
    guard listing.contains(id: id) else {
      return false
    }
    if tabsFilter, let tab = tabsListing?.tabs[id], isSynthetic(tab) {
      if target == .highlights {
        return selectOpenTab(tab)
      }
      showNoteActionWarning(for: tab)
      return true
    }
    guard let item = library.item(id: id) else {
      return false
    }
    switch target {
    case .highlights:
      if tabsFilter, let tab = tabsListing?.tabs[id] {
        return openInHighlights(
          item,
          recordsOpen: false,
          switchedFileName: tab.fileName
        )
      }
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

  private func openStored(_ pending: PendingOpen) {
    guard let item = library.item(id: pending.id) else {
      banner = RefsBanner(
        kind: .warning,
        message: "“\(pending.id)” is no longer in your library.",
        actions: []
      )
      return
    }
    switch pending.target {
    case .highlights:
      openInHighlights(
        item,
        recordsOpen: pending.recordsOpen,
        switchedFileName: pending.switchedFileName
      )
    case .defaultApp:
      openWithDefaultApp(item)
    case .note, .reveal:
      openSelected(pending.target)
    }
  }

  private func reopenClosedTab(_ closed: RefsClosedTab) -> Bool {
    if let itemID = closed.itemID,
      let item = library.item(id: itemID)
    {
      pendingClosedTab = nil
      return openInHighlights(
        item,
        recordsOpen: false,
        switchedFileName: closed.fileName
      )
    }
    return openClosedTab(closed)
  }

  private func openClosedTab(_ closed: RefsClosedTab) -> Bool {
    guard let app = highlights.highlightsAppURL() else {
      pendingClosedTab = closed
      banner = RefsBanner(
        kind: .error,
        message: "Highlights isn’t installed where Bob Refs can find it.",
        actions: [.openInDefaultApp, .chooseHighlights]
      )
      return true
    }
    pendingClosedTab = nil
    hidePanel()
    opener.openInHighlights(closed.url, app: app) { [weak self] error in
      Task {
        await self?.finishClosedTabOpen(closed, error: error)
      }
    }
    return true
  }

  private func finishClosedTabOpen(_ closed: RefsClosedTab, error: Error?) {
    if let error {
      lastDiagnostic = RefsLibrary.boundedMessage(for: error)
      pendingClosedTab = closed
      panelRepresenter()
      banner = RefsBanner(
        kind: .error,
        message: "Highlights couldn’t open “\(closed.title)”.\n\(lastDiagnostic)",
        actions: [.tryAgain, .openInDefaultApp]
      )
    } else {
      pendingClosedTab = nil
      banner = nil
    }
  }

  private func openClosedTabInDefaultApp(_ closed: RefsClosedTab) {
    pendingClosedTab = nil
    hidePanel()
    opener.openWithDefaultApp(closed.url) { [weak self] error in
      Task {
        await self?.finishClosedTabDefaultAppOpen(closed, error: error)
      }
    }
  }

  private func finishClosedTabDefaultAppOpen(_ closed: RefsClosedTab, error: Error?) {
    if let error {
      lastDiagnostic = RefsLibrary.boundedMessage(for: error)
      pendingClosedTab = closed
      panelRepresenter()
      banner = RefsBanner(
        kind: .error,
        message: "Couldn’t open “\(closed.title)”.\n\(lastDiagnostic)",
        actions: [.tryAgain, .copyDiagnostic]
      )
    } else {
      pendingClosedTab = nil
      banner = nil
    }
  }

  @discardableResult
  private func openInHighlights(
    _ item: RefItem,
    recordsOpen: Bool = true,
    switchedFileName: String? = nil
  ) -> Bool {
    if library.signals.missingPDFs.contains(item.id) {
      opener.openNote(library.noteURL(for: item))
      return true
    }
    guard let pdf = library.pdfURL(for: item) else {
      opener.openNote(library.noteURL(for: item))
      return true
    }
    guard let app = highlights.highlightsAppURL() else {
      pendingOpen = PendingOpen(
        id: item.id,
        target: .highlights,
        recordsOpen: recordsOpen,
        switchedFileName: switchedFileName
      )
      banner = RefsBanner(
        kind: .error,
        message: "Highlights isn’t installed where Bob Refs can find it.",
        actions: [.openInDefaultApp, .chooseHighlights]
      )
      return true
    }
    pendingOpen = PendingOpen(
      id: item.id,
      target: .highlights,
      recordsOpen: recordsOpen,
      switchedFileName: switchedFileName
    )
    hidePanel()
    opener.openInHighlights(pdf, app: app) { [weak self] error in
      Task {
        await self?.finishHighlightsOpen(
          itemID: item.id,
          title: item.title.text,
          error: error,
          recordsOpen: recordsOpen,
          switchedFileName: switchedFileName
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
    pendingOpen = PendingOpen(
      id: item.id,
      target: .defaultApp,
      recordsOpen: true,
      switchedFileName: nil
    )
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

  private func finishHighlightsOpen(
    itemID: String,
    title: String,
    error: Error?,
    recordsOpen: Bool,
    switchedFileName: String?
  ) {
    if let error {
      lastDiagnostic = RefsLibrary.boundedMessage(for: error)
      pendingOpen = PendingOpen(
        id: itemID,
        target: .highlights,
        recordsOpen: recordsOpen,
        switchedFileName: switchedFileName
      )
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
      if recordsOpen {
        library.recordOpen(id: itemID)
      } else if let switchedFileName {
        tabsSession.recordSwitch(fileName: switchedFileName)
      }
    }
  }

  private func finishDefaultAppOpen(itemID: String, title: String, error: Error?) {
    if let error {
      lastDiagnostic = RefsLibrary.boundedMessage(for: error)
      pendingOpen = PendingOpen(
        id: itemID,
        target: .defaultApp,
        recordsOpen: true,
        switchedFileName: nil
      )
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
