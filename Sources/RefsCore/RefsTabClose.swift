import Foundation

/// A closed tab kept in memory for ⇧⌘T reopen. Titles and paths stay in
/// memory only: they never go into logs, diagnostics, or files.
public struct RefsClosedTab: Equatable, Sendable {
    /// The tab title as Highlights exposed it.
    public let title: String
    /// The tab title used to locate the document.
    public let fileName: String
    /// The document URL used to reopen the tab.
    public let url: URL
    /// The matched reference note id, when the closed row had one.
    public let itemID: String?

    /// Creates a closed-tab entry.
    public init(title: String, fileName: String, url: URL, itemID: String?) {
        self.title = title
        self.fileName = fileName
        self.url = url
        self.itemID = itemID
    }
}

/// The in-memory closed-tab stack for ⇧⌘T reopen, newest last.
public struct RefsClosedTabs: Equatable, Sendable {
    /// The most entries the stack keeps; older entries drop off.
    public static let capacity = 20

    private var entries: [RefsClosedTab]

    /// Creates an empty closed-tab stack.
    public init() {
        entries = []
    }

    /// Whether the stack holds no entries.
    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// The number of entries on the stack.
    public var count: Int {
        entries.count
    }

    /// Pushes an entry newest-last, moving a re-close of the same
    /// standardized URL to the top and dropping the oldest past capacity.
    public mutating func push(_ entry: RefsClosedTab) {
        let key = entry.url.standardizedFileURL
        entries.removeAll { $0.url.standardizedFileURL == key }
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    /// Pops the newest entry, or nil when the stack is empty.
    public mutating func popLast() -> RefsClosedTab? {
        entries.popLast()
    }
}

/// The glass toast shown for a tab close.
public struct RefsTabCloseToast: Equatable, Sendable {
    /// The toast headline: "Closed tab" or "Closed the last tab".
    public let title: String
    /// The closed tab's title.
    public let value: String
    /// The detail line: "⇧⌘T reopens", "Highlights quit", or nil.
    public let detail: String?
    /// Whether this toast closed the last tab.
    public let isLast: Bool

    /// Creates a close toast.
    public init(title: String, value: String, detail: String?, isLast: Bool) {
        self.title = title
        self.value = value
        self.detail = detail
        self.isLast = isLast
    }
}

/// The single home for close copy. Pure and tested.
public enum RefsTabClosePresentation {
    /// How long a close toast stays visible, matching Link to Today.
    public static let toastHoldDuration: TimeInterval = 2.2

    /// The toast for a close with tabs remaining. The detail line appears
    /// only when the tab can be reopened.
    public static func toast(title: String, canReopen: Bool) -> RefsTabCloseToast {
        RefsTabCloseToast(
            title: "Closed tab",
            value: title,
            detail: canReopen ? "⇧⌘T reopens" : nil,
            isLast: false
        )
    }

    /// The toast for closing the last tab. The detail line appears only
    /// once the Highlights exit is verified.
    public static func lastToast(title: String, highlightsQuit: Bool) -> RefsTabCloseToast {
        RefsTabCloseToast(
            title: "Closed the last tab",
            value: title,
            detail: highlightsQuit ? "Highlights quit" : nil,
            isLast: true
        )
    }

    /// The VoiceOver announcement for a close with tabs remaining.
    public static func announcement(title: String, countText: String?) -> String {
        guard let countText else {
            return "Closed \(title)."
        }
        return "Closed \(title). \(countText)."
    }

    /// The VoiceOver announcement for closing the last tab.
    public static func lastAnnouncement(title: String, highlightsQuit: Bool) -> String {
        highlightsQuit ? "Closed \(title). Highlights quit." : "Closed \(title)."
    }

    /// The error banner for a failed close.
    public static func failureMessage(title: String) -> String {
        "Couldn't close “\(title)” in Highlights."
    }
}
