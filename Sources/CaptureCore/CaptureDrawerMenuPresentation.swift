import Foundation

/// Portable copy and grouping for the `drawer` completion menu that opens on a
/// glued `#` after `@route+id`. Bob owns every string that describes a drawer:
/// the counts and ages in `detail`, the refusal reasons, and the per-row
/// `consequence`. Swift only groups the rows Bob ranked, labels the three
/// groups, and picks the footer line.
public struct CaptureDrawerMenuPresentation: Equatable, Sendable {
    /// Which group a Bob row belongs to. Bob sends `group: "task"` for the
    /// target's own drawers (the first Bob that shipped the context sent
    /// `"drawers"`), `"recent"` for catalog drawers used elsewhere, and
    /// `"new"` for the single create row; anything else reads as a task row so a
    /// future group never drops a candidate.
    public enum Kind: Equatable, Sendable {
        case task
        case recent
        case new

        public init(group: String?) {
            switch group {
            case "recent": self = .recent
            case "new": self = .new
            default: self = .task
            }
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        /// Index into `CaptureCompletionResponse.candidates`, which is also the
        /// completion list's selection index.
        public let index: Int
        public let kind: Kind
        /// The drawer title exactly as Bob reports it (`PERF BUDGET`).
        public let title: String
        /// What the row shows: the title, or `＋ New drawer TITLE` on the create
        /// row.
        public let label: String
        public let queryMatchRange: Range<Int>?
        /// Bob's `detail` (`3 notes`, `used in 12 notes · 3 days ago`). Nil when
        /// Bob sent none; the app never counts items itself.
        public let detail: String?
        /// Bob's reason this row would refuse at commit. A refused row is dimmed
        /// and Return on it does nothing.
        public let refusal: String?
        /// Bob's one-line consequence of choosing the row.
        public let consequence: String?
        public let creates: Bool
        public let accessibilityLabel: String

        public var id: Int { index }
        public var isRefused: Bool { refusal != nil }
        public var isNew: Bool { kind == .new }
    }

    public struct Group: Equatable, Sendable, Identifiable {
        public let kind: Kind
        /// `On this task` / `Recent`; nil for the create row, which has no header.
        public let title: String?
        public let rows: [Row]

        public var id: String { "\(kind)-\(rows.first?.index ?? -1)" }
    }

    public static let title = "Drawer"
    public static let taskGroupTitle = "On this task"
    public static let recentGroupTitle = "Recent"
    public static let newRowPrefix = "\u{FF0B} New drawer"
    /// Footer for a selected row that Bob sent no `consequence` for.
    public static let selectedFooterHint = "⏎ choose · ⎋ close"

    /// The task the menu is about: `^bar Upgrade Postgres (foo)`. Empty when an
    /// older Bob sent no `target`.
    public let headerCaption: String
    public let groups: [Group]
    public let rows: [Row]
    /// Bob's `consequence` (or refusal) for the selected row, else a key hint.
    public let footer: String
    public let listAccessibilityLabel: String

    /// - Parameters:
    ///   - response: a `drawer` completion response.
    ///   - selectedIndex: the highlighted candidate; nil when the menu opened
    ///     unselected.
    ///   - query: the text typed after the `#`, used only for match emphasis.
    public init(
        response: CaptureCompletionResponse,
        selectedIndex: Int?,
        query: String = ""
    ) {
        headerCaption = Self.caption(for: response.target)
        rows = response.candidates.enumerated().map { index, candidate in
            Self.row(for: candidate, at: index, query: query)
        }
        var built: [Group] = []
        for row in rows {
            if let last = built.last, last.kind == row.kind {
                built[built.count - 1] = Group(
                    kind: last.kind, title: last.title, rows: last.rows + [row])
            } else {
                built.append(
                    Group(kind: row.kind, title: Self.groupTitle(for: row.kind), rows: [row]))
            }
        }
        groups = built
        if let selectedIndex, rows.indices.contains(selectedIndex) {
            footer = Self.footer(for: rows[selectedIndex])
        } else {
            footer = CaptureCompletionMenu.unselectedFooterHint
        }
        let count = rows.count
        listAccessibilityLabel =
            "Drawer suggestions, \(count) result\(count == 1 ? "" : "s")"
    }

    /// `^bar Upgrade Postgres (foo)`: the block ID, the task text, then the
    /// note in parentheses without its `.md`. Parts Bob left out are skipped.
    public static func caption(for target: CaptureDrawerTarget?) -> String {
        guard let target else {
            return ""
        }
        var parts: [String] = []
        if let blockID = target.blockID, !blockID.isEmpty {
            parts.append("^\(blockID)")
        }
        let text = target.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            parts.append(text)
        }
        var route = target.route
        if route.hasSuffix(".md") {
            route.removeLast(3)
        }
        if !route.isEmpty {
            parts.append("(\(route))")
        }
        return parts.joined(separator: " ")
    }

    /// The drawer name typed so far: Bob's replacement range can cover the glued
    /// `#`, and a quoted literal adds an opening `"`; neither is part of the name.
    public static func queryText(fromTyped typed: String) -> String {
        var text = Substring(typed)
        if text.first == "#" {
            text = text.dropFirst()
        }
        if text.first == "\"" {
            text = text.dropFirst()
        }
        return String(text)
    }

    public static func groupTitle(for kind: Kind) -> String? {
        switch kind {
        case .task: return taskGroupTitle
        case .recent: return recentGroupTitle
        case .new: return nil
        }
    }

    public static func footer(for row: Row) -> String {
        if let refusal = row.refusal, !refusal.isEmpty {
            return refusal
        }
        if let consequence = row.consequence, !consequence.isEmpty {
            return consequence
        }
        return selectedFooterHint
    }

    private static func row(
        for candidate: CaptureCompletionCandidate,
        at index: Int,
        query: String
    ) -> Row {
        let kind = Kind(group: candidate.group)
        let title = candidate.title ?? candidate.replacement
        let label = kind == .new ? "\(newRowPrefix) \(title)" : title
        let detail = nonEmpty(candidate.detail)
        let refusal = candidate.refused.flatMap { nonEmpty($0) ?? "Not available" }
        let consequence = nonEmpty(candidate.consequence)
        let creates = candidate.creates || kind == .new
        var spoken: [String] = []
        if kind == .new {
            spoken.append(label)
        } else {
            spoken.append(groupTitle(for: kind) ?? Self.title)
            spoken.append(title)
        }
        if let detail {
            spoken.append(detail)
        }
        if creates, kind != .new {
            spoken.append("creates the drawer")
        }
        if let refusal {
            spoken.append("unavailable: \(refusal)")
        } else if let consequence {
            spoken.append(consequence)
        }
        return Row(
            index: index,
            kind: kind,
            title: title,
            label: label,
            queryMatchRange: kind == .new ? nil : completionMatchRange(in: title, query: query),
            detail: detail,
            refusal: refusal,
            consequence: consequence,
            creates: creates,
            accessibilityLabel: spoken.joined(separator: ", ")
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
