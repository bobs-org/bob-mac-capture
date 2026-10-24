import Foundation

/// A value-only snapshot of the Highlights windows and their native tabs.
public struct HighlightsTabsSnapshot: Equatable, Sendable {
    /// One Highlights window in Accessibility window order.
    public struct Window: Equatable, Sendable {
        /// Whether Highlights reports this as its main window.
        public let isMain: Bool
        /// The visible document's formatted page caption, when available.
        public let pageCaption: String?
        /// Tabs in the window's native tab-bar order.
        public let tabs: [Tab]

        /// Creates a window snapshot.
        public init(isMain: Bool, pageCaption: String? = nil, tabs: [Tab]) {
            self.isMain = isMain
            self.pageCaption = pageCaption
            self.tabs = tabs
        }
    }

    /// One tab in a Highlights window.
    public struct Tab: Equatable, Sendable {
        /// The tab title as Highlights exposes it.
        public let fileName: String
        /// The absolute path for the visible tab in this window, if known.
        public let documentPath: String?
        /// Whether this tab is selected in its window.
        public let isSelected: Bool

        /// Creates a tab snapshot.
        public init(fileName: String, documentPath: String? = nil, isSelected: Bool) {
            self.fileName = fileName
            self.documentPath = documentPath
            self.isSelected = isSelected
        }
    }

    /// Windows in `AXWindows` order.
    public let windows: [Window]
    /// Whether Highlights is the frontmost application.
    public let highlightsIsFrontmost: Bool

    /// Creates a Highlights snapshot.
    public init(windows: [Window], highlightsIsFrontmost: Bool) {
        self.windows = windows
        self.highlightsIsFrontmost = highlightsIsFrontmost
    }

    /// The total number of tabs across all windows.
    public var documentCount: Int {
        windows.reduce(0) { $0 + $1.tabs.count }
    }

    /// The selected tab of the main window, or the first window if none is main.
    public var currentTab: Tab? {
        guard let window = windows.first(where: \.isMain) ?? windows.first else {
            return nil
        }
        return window.tabs.first(where: \.isSelected)
    }
}

/// A page caption parsed from a Highlights window title.
public enum HighlightsWindowTitle {
    private static let pageSuffix = try! NSRegularExpression(
        pattern: #"(?i)^.*?\s+[-–—]\s+page\s+(\d+)\s+of\s+(\d+)\s*$"#
    )

    /// Parses `name.pdf – Page 5 of 25` (or a hyphen separator) as `p. 5/25`.
    public static func pageCaption(fromTitle title: String) -> String? {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let match = pageSuffix.firstMatch(in: title, range: range),
              let pageRange = Range(match.range(at: 1), in: title),
              let countRange = Range(match.range(at: 2), in: title),
              let page = Int(title[pageRange]),
              let count = Int(title[countRange])
        else {
            return nil
        }
        return "p. \(page)/\(count)"
    }
}

/// The result of reading the current Highlights tabs.
public enum HighlightsTabsReadResult: Equatable, Sendable {
    /// Highlights is not running.
    case notRunning
    /// Accessibility permission is unavailable.
    case notTrusted
    /// The read failed for a bounded, name-free reason.
    case failed(String)
    /// A complete tab snapshot was read.
    case snapshot(HighlightsTabsSnapshot)
}

/// A tab identity used to select a tab after taking a fresh snapshot.
public struct HighlightsTabTarget: Equatable, Hashable, Sendable {
    /// The tab title exposed by Highlights.
    public let fileName: String
    /// The tab's window ordinal in the snapshot.
    public let windowOrdinal: Int

    /// Creates a selection target.
    public init(fileName: String, windowOrdinal: Int) {
        self.fileName = fileName
        self.windowOrdinal = windowOrdinal
    }
}

/// The outcome of selecting an existing Highlights tab.
public enum HighlightsTabSelectResult: Equatable, Sendable {
    /// The tab was selected and verified.
    case selected
    /// The tab is gone or no longer has an unambiguous identity.
    case notFound
    /// Highlights is not running.
    case notRunning
    /// Accessibility permission is unavailable.
    case notTrusted
    /// Selection failed for a bounded, name-free reason.
    case failed(String)
}

/// The reader's answer to a tab close request.
public enum HighlightsTabCloseResult: Equatable, Sendable {
    /// The close was verified. The payload is the post-close snapshot,
    /// which is empty when Highlights exited.
    case closed(HighlightsTabsSnapshot)
    /// No tab with that title remains.
    case notFound
    /// Highlights is not running.
    case notRunning
    /// Accessibility permission is unavailable.
    case notTrusted
    /// Highlights showed a sheet on that window instead of closing it.
    /// The reader has already brought Highlights forward.
    case needsAttention
    /// The close failed for a bounded, name-free reason.
    case failed(String)
}

/// The session's answer to a tab close request.
public enum HighlightsTabCloseOutcome: Equatable, Sendable {
    /// The close was verified and tabs remain.
    case closed(remaining: HighlightsTabsSnapshot)
    /// The close left no documents. The payload records whether
    /// Highlights then exited.
    case closedLast(highlightsQuit: Bool)
    /// The tab was already gone; the row stays gone.
    case alreadyClosed
    /// Highlights is not running.
    case notRunning
    /// Accessibility permission is unavailable.
    case notTrusted
    /// Highlights showed a save sheet instead of closing.
    case needsAttention
    /// The close failed for a bounded, name-free reason.
    case failed(String)
}

/// Reads and selects Highlights tabs without exposing Accessibility types to RefsCore.
public protocol HighlightsTabsReading: Sendable {
    /// Checks Accessibility permission without prompting.
    func isTrusted() -> Bool

    /// Requests Accessibility permission from an explicit user action.
    func requestTrust()

    /// Reads one tab snapshot.
    func read() async -> HighlightsTabsReadResult

    /// Selects a tab using its fresh-snapshot identity.
    func select(_ target: HighlightsTabTarget) async -> HighlightsTabSelectResult

    /// Closes a tab using its fresh-snapshot identity.
    func close(_ target: HighlightsTabTarget) async -> HighlightsTabCloseResult

    /// Quits Highlights when no documents remain. True means Highlights
    /// is not running afterwards. Implementations must re-check that no
    /// documents are open before quitting.
    func quitIfNoDocuments() async -> Bool
}

public extension HighlightsTabsReading {
    /// Reports that tab closing is unavailable in this build, so every
    /// existing conformer keeps compiling until it overrides `close`.
    func close(_ target: HighlightsTabTarget) async -> HighlightsTabCloseResult {
        .failed("Closing Highlights tabs isn't available in this build")
    }

    /// Reports that Highlights is still running, so every existing
    /// conformer keeps compiling until it overrides `quitIfNoDocuments`.
    func quitIfNoDocuments() async -> Bool {
        false
    }
}

/// Placeholder reader used until the app wires the live Highlights reader.
public struct UnavailableHighlightsTabsReader: HighlightsTabsReading {
    /// Creates the unavailable reader.
    public init() {}

    /// The feature is unavailable and cannot have permission.
    public func isTrusted() -> Bool { false }

    /// There is no permission prompt in this build.
    public func requestTrust() {}

    /// Reports that tab reading is unavailable.
    public func read() async -> HighlightsTabsReadResult {
        .failed("Highlights tabs aren't available in this build")
    }

    /// Reports that tab selection is unavailable.
    public func select(_ target: HighlightsTabTarget) async -> HighlightsTabSelectResult {
        .failed("Highlights tabs aren't available in this build")
    }
}

/// Finds a target by its window and title, never by its former tab index.
public enum HighlightsTabLocator {
    /// Locates the unique tab in its original window, or the unique matching tab anywhere.
    public static func locate(
        _ target: HighlightsTabTarget,
        in snapshot: HighlightsTabsSnapshot
    ) -> (window: Int, tab: Int)? {
        if snapshot.windows.indices.contains(target.windowOrdinal) {
            let local = snapshot.windows[target.windowOrdinal].tabs.enumerated().filter {
                $0.element.fileName == target.fileName
            }
            if local.count == 1, let match = local.first {
                return (target.windowOrdinal, match.offset)
            }
        }

        let matches = snapshot.windows.enumerated().flatMap { windowOrdinal, window in
            window.tabs.enumerated().compactMap { tabOrdinal, tab in
                tab.fileName == target.fileName ? (windowOrdinal, tabOrdinal) : nil
            }
        }
        guard matches.count == 1, let match = matches.first else {
            return nil
        }
        return (match.0, match.1)
    }
}

/// In-memory last-active times keyed by the tab's file name.
public struct RefsTabRecency: Equatable, Sendable {
    private var dates: [String: Date]

    /// Creates an empty recency map.
    public init() {
        dates = [:]
    }

    /// Records the latest activity time for a file name.
    public mutating func touch(fileName: String, at date: Date) {
        dates[fileName] = date
    }

    /// Returns the most recent activity time for a file name.
    public func lastActive(_ fileName: String) -> Date? {
        dates[fileName]
    }
}

/// Matches Highlights tabs to reference notes without consulting the open log.
public enum HighlightsTabMatcher {
    private struct Candidate {
        let tab: RefsOpenTab
        let sequence: Int
    }

    private static let trailingPageSuffix = try! NSRegularExpression(
        pattern: #"(?i)\s+[-–—]\s+page\s+\d+\s+of\s+\d+\s*$"#
    )

    /// Matches each tab by resolved path, then a unique file name, collision, or none.
    public static func match(
        _ snapshot: HighlightsTabsSnapshot,
        items: [RefItem],
        vaultRoot: URL
    ) -> [RefsOpenTab] {
        let currentWindow = snapshot.windows.firstIndex(where: \.isMain)
            ?? (snapshot.windows.isEmpty ? nil : 0)
        var candidates: [Candidate] = []
        var itemOccurrences: [String: Candidate] = [:]
        var syntheticOccurrences: [String: Int] = [:]
        var sequence = 0

        for (windowOrdinal, window) in snapshot.windows.enumerated() {
            for (tabOrdinal, tab) in window.tabs.enumerated() {
                let isCurrent = windowOrdinal == currentWindow && tab.isSelected
                let displayName = tab.fileName
                let comparableName = nameWithoutPageSuffix(displayName)
                let pathMatches: [RefItem]
                if let documentPath = tab.documentPath,
                   let relativePath = relativeResolvedPath(documentPath, vaultRoot: vaultRoot)
                {
                    pathMatches = items.filter { $0.pdfPath == relativePath }
                } else {
                    pathMatches = []
                }

                let matchedByName = items.filter { item in
                    Self.fileName(comparableName, matches: item.pdfPath)
                }

                let resolved: (item: RefItem?, candidateIDs: [String], match: RefsOpenTabMatch)
                if pathMatches.count == 1, let item = pathMatches.first {
                    resolved = (item, [], .path)
                } else if pathMatches.count > 1 {
                    resolved = (nil, pathMatches.map(\.id).sorted(), .collision)
                } else if matchedByName.count == 1, let item = matchedByName.first {
                    resolved = (item, [], .fileName)
                } else if matchedByName.count > 1 {
                    resolved = (nil, matchedByName.map(\.id).sorted(), .collision)
                } else {
                    resolved = (nil, [], .none)
                }

                let rowID: String
                if let item = resolved.item {
                    rowID = item.id
                } else {
                    let baseID = "highlights-tab:\(displayName)"
                    let occurrence = syntheticOccurrences[baseID, default: 0] + 1
                    syntheticOccurrences[baseID] = occurrence
                    rowID = occurrence == 1 ? baseID : "\(baseID)#\(occurrence)"
                }

                let row = RefsOpenTab(
                    rowID: rowID,
                    itemID: resolved.item?.id,
                    candidateIDs: resolved.candidateIDs,
                    fileName: displayName,
                    windowOrdinal: windowOrdinal,
                    tabOrdinal: tabOrdinal,
                    isCurrent: isCurrent,
                    pageCaption: window.pageCaption,
                    documentPath: tab.documentPath,
                    match: resolved.match
                )
                let candidate = Candidate(tab: row, sequence: sequence)
                sequence += 1

                if let itemID = resolved.item?.id {
                    if let previous = itemOccurrences[itemID] {
                        if row.isCurrent && !previous.tab.isCurrent {
                            itemOccurrences[itemID] = candidate
                        }
                    } else {
                        itemOccurrences[itemID] = candidate
                    }
                } else {
                    candidates.append(candidate)
                }
            }
        }

        candidates.append(contentsOf: itemOccurrences.values)
        return candidates.sorted { $0.sequence < $1.sequence }.map(\.tab)
    }

    private static func relativeResolvedPath(_ path: String, vaultRoot: URL) -> String? {
        guard vaultRoot.isFileURL else {
            return nil
        }
        let document = URL(fileURLWithPath: path)
            .standardizedFileURL.resolvingSymlinksInPath().path
        let root = vaultRoot.standardizedFileURL.resolvingSymlinksInPath().path
        if root == "/" {
            return document.hasPrefix("/") ? String(document.dropFirst()) : nil
        }
        guard document.hasPrefix(root + "/") else {
            return nil
        }
        return String(document.dropFirst(root.count + 1))
    }

    private static func nameWithoutPageSuffix(_ name: String) -> String {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = trailingPageSuffix.firstMatch(in: name, range: range),
              let suffixRange = Range(match.range, in: name)
        else {
            return name
        }
        return String(name[..<suffixRange.lowerBound])
    }

    static func titleStem(forFileName name: String) -> String {
        let cleanedName = nameWithoutPageSuffix(name)
        return cleanedName.lowercased().hasSuffix(".pdf")
            ? String(cleanedName.dropLast(4))
            : cleanedName
    }

    private static func fileName(_ tabName: String, matches pdfPath: String) -> Bool {
        let storedName = String(pdfPath.split(separator: "/").last ?? "")
        guard !storedName.isEmpty else {
            return false
        }
        let storedStem = storedName.lowercased().hasSuffix(".pdf")
            ? String(storedName.dropLast(4))
            : storedName
        let tabStem = titleStem(forFileName: tabName)
        return tabName == storedName || tabStem == storedStem
    }
}

/// A reference note matched to an open Highlights tab, or a synthetic tab row.
public struct RefsOpenTab: Equatable, Sendable {
    /// The row identity: note path for matches, reserved tab id otherwise.
    public let rowID: String
    /// The matched reference note id, when there is one unique note.
    public let itemID: String?
    /// Candidate note ids for a collision row.
    public let candidateIDs: [String]
    /// The tab title as exposed by Highlights.
    public let fileName: String
    /// The tab's window ordinal in the snapshot.
    public let windowOrdinal: Int
    /// The tab's ordinal in its window.
    public let tabOrdinal: Int
    /// Whether this is the selected tab of the main (or first) window.
    public let isCurrent: Bool
    /// The visible window's formatted page caption, if available.
    public let pageCaption: String?
    /// The absolute path for the visible tab, if available.
    public let documentPath: String?
    /// How the tab matched the library.
    public let match: RefsOpenTabMatch

    /// The title and window identity used for a fresh tab selection.
    public var target: HighlightsTabTarget {
        HighlightsTabTarget(fileName: fileName, windowOrdinal: windowOrdinal)
    }

    /// Creates a matched or synthetic tab row.
    public init(
        rowID: String,
        itemID: String?,
        candidateIDs: [String],
        fileName: String,
        windowOrdinal: Int,
        tabOrdinal: Int,
        isCurrent: Bool,
        pageCaption: String?,
        documentPath: String?,
        match: RefsOpenTabMatch
    ) {
        self.rowID = rowID
        self.itemID = itemID
        self.candidateIDs = candidateIDs
        self.fileName = fileName
        self.windowOrdinal = windowOrdinal
        self.tabOrdinal = tabOrdinal
        self.isCurrent = isCurrent
        self.pageCaption = pageCaption
        self.documentPath = documentPath
        self.match = match
    }
}

/// The matching strategy used for one Highlights tab.
public enum RefsOpenTabMatch: Equatable, Sendable {
    /// The resolved document path matched a library PDF path.
    case path
    /// The tab title matched exactly one PDF file name.
    case fileName
    /// More than one library note could match the tab.
    case collision
    /// No library note matched the tab.
    case none
}

/// Owns the latest tab snapshot, refresh generations, and in-memory recency.
@MainActor
public final class HighlightsTabsSession {
    /// The injected tab reader, exposed for trust and explicit permission requests.
    public let reader: any HighlightsTabsReading

    /// The most recently applied snapshot.
    public private(set) var lastSnapshot: HighlightsTabsSnapshot?

    /// Last-active times keyed by tab file name.
    public private(set) var recency = RefsTabRecency()

    /// The most recently closed tabs, newest last, for ⇧⌘T reopen.
    public private(set) var closedTabs = RefsClosedTabs()

    private let now: @Sendable () -> Date
    private var generation: UInt64 = 0

    /// Creates a session with an injectable clock for deterministic tests.
    public init(
        reader: any HighlightsTabsReading,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reader = reader
        self.now = now
    }

    /// Reads a snapshot; a result is applied only if no newer refresh has started.
    public func refresh() async -> HighlightsTabsReadResult? {
        generation &+= 1
        let requestGeneration = generation
        let result = await reader.read()
        guard requestGeneration == generation else {
            return nil
        }
        if case let .snapshot(snapshot) = result {
            lastSnapshot = snapshot
            touchCurrentTab(in: snapshot)
        }
        return result
    }

    /// Samples the current tab's recency without prompting or applying a new snapshot.
    public func sampleCurrentTab() async {
        guard reader.isTrusted() else {
            return
        }
        guard case let .snapshot(snapshot) = await reader.read() else {
            return
        }
        touchCurrentTab(in: snapshot)
    }

    /// Records a tab switch in the in-memory recency map.
    public func recordSwitch(fileName: String) {
        recency.touch(fileName: fileName, at: now())
    }

    /// Selects a tab and records recency only after a successful selection.
    public func select(_ tab: RefsOpenTab) async -> HighlightsTabSelectResult {
        let result = await reader.select(tab.target)
        if case .selected = result {
            recordSwitch(fileName: tab.fileName)
        }
        return result
    }

    /// Closes a tab, pushing `reopen` for ⇧⌘T when the close is verified.
    /// Bumps the refresh generation first, so a read that started earlier
    /// can never overwrite the close's result. When the close leaves no
    /// documents, quits Highlights and reports whether it exited.
    public func close(_ tab: RefsOpenTab, reopen: RefsClosedTab?) async -> HighlightsTabCloseOutcome {
        generation &+= 1
        switch await reader.close(tab.target) {
        case let .closed(snapshot):
            lastSnapshot = snapshot
            touchCurrentTab(in: snapshot)
            if let reopen {
                closedTabs.push(reopen)
            }
            if snapshot.documentCount == 0 {
                let highlightsQuit = await reader.quitIfNoDocuments()
                return .closedLast(highlightsQuit: highlightsQuit)
            }
            return .closed(remaining: snapshot)
        case .notFound:
            return .alreadyClosed
        case .notRunning:
            return .notRunning
        case .notTrusted:
            return .notTrusted
        case .needsAttention:
            return .needsAttention
        case let .failed(reason):
            return .failed(reason)
        }
    }

    /// Pops the newest closed tab for ⇧⌘T reopen, or nil when the stack is empty.
    public func popClosedTab() -> RefsClosedTab? {
        closedTabs.popLast()
    }

    private func touchCurrentTab(in snapshot: HighlightsTabsSnapshot) {
        guard let tab = snapshot.currentTab else {
            return
        }
        recency.touch(fileName: tab.fileName, at: now())
    }
}

