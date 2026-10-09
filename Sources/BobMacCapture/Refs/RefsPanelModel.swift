import AppKit
import CaptureCore
import Combine
import Foundation
import RefsCore

/// Where an open dispatches: Highlights, the reference note in Obsidian,
/// the PDF revealed in Finder, or the PDF in its default app. Only
/// Highlights and default-app opens count as opens.
public enum RefsOpenTarget: Sendable {
    case highlights
    case note
    case reveal
    case defaultApp
}

/// Every panel gesture the key router and the list funnel through.
public enum RefsCommand: Sendable {
    case open(RefsOpenTarget)
    case move(RefsMove)
    case setScope(RefScope)
    case escape
    case deleteBackwardOnEmpty
    case refresh
    case select(id: String)
    case activate(id: String)
    case showActions
}

/// A banner above the list: orange card, callout text, action buttons. A
/// banner dismisses on the next query edit, on Esc, or on a successful
/// open — never on a re-rank alone.
public struct RefsBanner: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case error
        case warning
    }

    public enum Action: Equatable, Sendable {
        case retry
        case tryAgain
        case openInDefaultApp
        case chooseHighlights
        case copyDiagnostic
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
    @Published public private(set) var selectedID: String?
    @Published public private(set) var unavailableIDs: Set<String> = []
    @Published public private(set) var banner: RefsBanner?
    /// The visible row count from the list geometry; pages move by one less.
    @Published public var visibleRowBudget: Int = 10

    public var panelDismisser: () -> Void = {}
    public var panelPresenter: () -> Void = {}
    public var settingsPresenter: () -> Void = {}

    private let library: RefsLibrary
    private let opener: RefsOpening
    private let highlights: RefsHighlightsLocating
    private var subscriptions = Set<AnyCancellable>()
    private var presented = false
    private var pendingOpen: (id: String, target: RefsOpenTarget)?
    private var lastDiagnostic = ""

    public init(
        library: RefsLibrary,
        opener: RefsOpening,
        highlights: RefsHighlightsLocating
    ) {
        self.library = library
        self.opener = opener
        self.highlights = highlights
        listing = RefsRanker.listing(
            library.items,
            query: "",
            scope: .all,
            signals: library.signals
        )
        selectedID = RefsSelectionPolicy.initial(in: listing)
        let itemsSubscription = library.$items.sink { [weak self] _ in
            Task { await self?.libraryDidPublish() }
        }
        let signalsSubscription = library.$signals.sink { [weak self] _ in
            Task { await self?.libraryDidPublish() }
        }
        itemsSubscription.store(in: &subscriptions)
        signalsSubscription.store(in: &subscriptions)
    }

    /// The selected item, or nil when nothing is selected.
    public var selectedItem: RefItem? {
        guard let selectedID else {
            return nil
        }
        return library.items.first { $0.id == selectedID }
    }

    /// Resets for presentation: a blank query, All scope, a fresh listing,
    /// and the first row selected.
    public func prepareForPresentation() {
        presented = true
        query = ""
        scope = .all
        banner = nil
        pendingOpen = nil
        rerankSelectingFirst()
    }

    /// Re-ranks on every query edit, selects the first row, and dismisses
    /// any banner.
    public func queryDidChange() {
        banner = nil
        rerankSelectingFirst()
    }

    /// Runs one command. Returns false only when the command had no row to
    /// act on, so the key router can pass the key through.
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
            library.refresh(reason: .manual)
            rerankSelectingFirst()
            return true
        case .select(let id):
            guard listing.orderedIDs.contains(id) else {
                return false
            }
            selectedID = id
            return true
        case .activate(let id):
            guard listing.orderedIDs.contains(id) else {
                return false
            }
            selectedID = id
            return openSelected(.highlights)
        case .showActions:
            // A no-op until `refs-inspector` adds the actions menu.
            return false
        }
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
                title: id,
                caption: "No longer in your library",
                whyHere: "No longer in your library",
                match: nil,
                section: section,
                isUnopened: false,
                isMissingPDF: false,
                isUnavailable: true
            )
        }
        return RefsRowContent(
            item: item,
            title: item.title.text,
            caption: RefsCaption.caption(for: item, in: section, signals: signals, match: match),
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
        case .retry:
            banner = nil
            library.refresh(reason: .manual)
            rerankSelectingFirst()
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
            guard !lastDiagnostic.isEmpty else {
                return
            }
            NSPasteboard.general.clearContents()
            _ = NSPasteboard.general.setString(lastDiagnostic, forType: .string)
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
        refreshState: RefsRefreshState
    ) {
        presented = true
        library.installSnapshotForPreviews(
            items: items,
            signals: signals,
            refreshState: refreshState
        )
        self.query = query
        self.scope = scope
        self.banner = banner
        listing = RefsRanker.listing(items, query: query, scope: scope, signals: signals)
        unavailableIDs = []
        self.selectedID = selectedID
    }

    private func rerankSelectingFirst() {
        listing = RefsRanker.listing(
            library.items,
            query: query,
            scope: scope,
            signals: library.signals
        )
        unavailableIDs = []
        selectedID = RefsSelectionPolicy.initial(in: listing)
    }

    private func libraryDidPublish() {
        let available = Set(library.items.map(\.id))
        let (next, unavailable) = listing.refreshingContent(availableIDs: available)
        listing = next
        // Vanished rows leave the frozen listing, so intersecting with it
        // would drop the flag on the very next publish (every pass publishes
        // items and signals separately). Keep flags for every id that is
        // still missing from the library instead.
        unavailableIDs = unavailable.union(unavailableIDs.subtracting(available))
        if next.orderedIDs.isEmpty {
            selectedID = nil
        }
    }

    private func hidePanel() {
        presented = false
        panelDismisser()
    }

    private func openSelected(_ target: RefsOpenTarget) -> Bool {
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
            panelPresenter()
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
            panelPresenter()
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
