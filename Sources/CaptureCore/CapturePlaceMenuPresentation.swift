import Foundation

/// Portable copy and grouping for Bob-authored drawer and notebook place menus.
/// Bob owns every destination, count, detail, refusal, consequence, and hint;
/// this type preserves their order and adds only legacy drawer fallback copy.
public struct CapturePlaceMenuPresentation: Equatable, Sendable {
    /// Legacy drawer row family. Unknown IDs remain task-like so a newer Bob
    /// group never causes its candidates to disappear.
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
        /// Index into Bob's candidate array and the completion selection.
        public let index: Int
        public let groupID: String?
        public let kind: Kind
        public let title: String
        public let label: String
        public let queryMatchRange: Range<Int>?
        public let detail: String?
        public let originBadge: String?
        public let refusal: String?
        public let consequence: String?
        public let creates: Bool
        public let isNotebookSection: Bool
        public let accessibilityLabel: String

        public var id: Int { index }
        public var isRefused: Bool { refusal != nil }
        public var isNew: Bool { creates }
    }

    public struct Group: Equatable, Sendable, Identifiable {
        public let id: String
        public let kind: Kind
        /// Nil means Bob returned an empty title or an unknown group ID.
        public let title: String?
        public let rows: [Row]
    }

    public static let title = "Drawer"
    public static let taskGroupTitle = "On this task"
    public static let recentGroupTitle = "Recent"
    public static let newRowPrefix = "\u{FF0B} New drawer"
    public static let selectedFooterHint = "⏎ choose · ⎋ close"

    public let menuKind: String
    public let title: String
    public let caption: String
    public let newRowPrefix: String
    public let resultsLabel: String
    public let emptyHint: String?
    public let groups: [Group]
    public let rows: [Row]
    public let footer: String
    public let listAccessibilityLabel: String
    public let usesPlaceMenuChrome: Bool
    /// Compatibility name retained for the legacy drawer-focused tests/hosts.
    public var headerCaption: String { caption }

    public init(
        response: CaptureCompletionResponse,
        selectedIndex: Int?,
        query: String = ""
    ) {
        let chrome = response.placeMenu
        let resolvedMenuKind = chrome?.kind ?? "drawer"
        let resolvedTitle = chrome.map { $0.title } ?? Self.title
        let resolvedCaption = chrome.map { $0.caption } ?? Self.caption(for: response.target)
        let resolvedPrefix = chrome?.newRowPrefix ?? (Self.newRowPrefix + " ")
        let resolvedResultsLabel = chrome?.resultsLabel ?? "results"
        let resolvedEmptyHint = chrome?.emptyHint

        let groupTitles = Dictionary(
            (chrome?.groups ?? []).map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        let builtRows = response.candidates.enumerated().map { index, candidate in
            Self.row(
                candidate,
                index: index,
                menuKind: resolvedMenuKind,
                newRowPrefix: resolvedPrefix,
                destinationCaption: resolvedCaption,
                isLegacyDrawer: chrome == nil,
                query: query
            )
        }

        var built: [Group] = []
        for row in builtRows {
            if let last = built.last, last.rows.last?.groupID == row.groupID {
                built[built.count - 1] = Group(
                    id: last.id,
                    kind: last.kind,
                    title: last.title,
                    rows: last.rows + [row]
                )
            } else {
                let groupID = row.groupID
                let title: String?
                if let groupID, let bobTitle = groupTitles[groupID] {
                    title = Self.nonEmpty(bobTitle)
                } else if chrome == nil {
                    title = Self.groupTitle(for: row.kind)
                } else {
                    title = nil
                }
                built.append(Group(
                    id: "\(groupID ?? "untitled")-\(row.index)",
                    kind: row.kind,
                    title: title,
                    rows: [row]
                ))
            }
        }
        let selectedRow = selectedIndex.flatMap { index in
            builtRows.first(where: { $0.index == index })
        }
        let resolvedFooter: String
        if let selectedRow {
            resolvedFooter = Self.footer(for: selectedRow, fallback: chrome?.footerHint)
        } else if let chrome, !chrome.footerHint.isEmpty {
            resolvedFooter = chrome.footerHint
        } else {
            resolvedFooter = CaptureCompletionMenu.unselectedFooterHint
        }

        let count = builtRows.count
        let countText = "\(count) \(resolvedResultsLabel)"
        let headerParts = [resolvedTitle, Self.nonEmpty(resolvedCaption), countText].compactMap { $0 }
        var accessible = headerParts.joined(separator: ", ")
        if count == 0, let emptyHint = Self.nonEmpty(resolvedEmptyHint) {
            accessible += ", \(emptyHint)"
        }
        if chrome == nil {
            accessible = "Drawer suggestions, \(count) result\(count == 1 ? "" : "s")"
        }

        usesPlaceMenuChrome = chrome != nil
        menuKind = resolvedMenuKind
        title = resolvedTitle
        caption = resolvedCaption
        newRowPrefix = resolvedPrefix
        resultsLabel = resolvedResultsLabel
        emptyHint = resolvedEmptyHint
        rows = builtRows
        groups = built
        footer = resolvedFooter
        listAccessibilityLabel = accessible
    }

    /// Legacy drawer caption: block ID, task text, then the note route.
    public static func caption(for target: CaptureDrawerTarget?) -> String {
        guard let target else { return "" }
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

    /// The drawer name or section selector. Bob's replacement can include the
    /// glued `#` and an opening quote; neither belongs in match emphasis.
    public static func queryText(fromTyped typed: String) -> String {
        var text = Substring(typed)
        if text.first == "#" { text = text.dropFirst() }
        if text.first == "\"" || text.first == "“" { text = text.dropFirst() }
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
        footer(for: row, fallback: nil)
    }

    private static func footer(for row: Row, fallback: String?) -> String {
        if let refusal = row.refusal, !refusal.isEmpty { return refusal }
        if let consequence = row.consequence, !consequence.isEmpty { return consequence }
        if let fallback, !fallback.isEmpty { return fallback }
        return selectedFooterHint
    }

    private static func row(
        _ candidate: CaptureCompletionCandidate,
        index: Int,
        menuKind: String,
        newRowPrefix: String,
        destinationCaption: String,
        isLegacyDrawer: Bool,
        query: String
    ) -> Row {
        let groupID = candidate.group
        let kind = Kind(group: groupID)
        let title = candidate.title ?? candidate.replacement
        let creates = candidate.creates || groupID == "new" || candidate.kind == "create"
        let isNewGroup = kind == .new
        let createLabel: String
        if let label = nonEmpty(candidate.label) {
            createLabel = label
        } else if isLegacyDrawer || menuKind == "drawer" {
            createLabel = "New drawer \(title)"
        } else {
            createLabel = title
        }
        let label = isNewGroup ? newRowPrefix + createLabel : title
        let detail = nonEmpty(candidate.detail)
        let refusal = candidate.refused.flatMap { nonEmpty($0) ?? "Not available" }
        let consequence = nonEmpty(candidate.consequence)
        let originBadge = groupID == "draft" ? detail : nil
        let notebookSection = menuKind == "notebook_section" && !creates
        let match: Range<Int>? = isNewGroup
            ? nil
            : completionMatchRange(in: title, query: query)

        var spoken: [String] = []
        if isLegacyDrawer {
            if kind == .new {
                spoken.append(label)
            } else {
                spoken.append(groupTitle(for: kind) ?? Self.title)
                spoken.append(title)
            }
            if let detail { spoken.append(detail) }
            if creates, kind != .new { spoken.append("creates the drawer") }
            if let refusal {
                spoken.append("unavailable: \(refusal)")
            } else if let consequence {
                spoken.append(consequence)
            }
        } else {
            if !destinationCaption.isEmpty { spoken.append(destinationCaption) }
            spoken.append(title)
            if creates {
                spoken.append(menuKind == "notebook_section" ? "New section" : "New")
            }
            if let detail { spoken.append(detail) }
            if let refusal {
                spoken.append("unavailable: \(refusal)")
            } else if let consequence {
                spoken.append(consequence)
            }
        }
        return Row(
            index: index,
            groupID: groupID,
            kind: kind,
            title: title,
            label: label,
            queryMatchRange: match,
            detail: groupID == "draft" ? nil : detail,
            originBadge: originBadge,
            refusal: refusal,
            consequence: consequence,
            creates: creates,
            isNotebookSection: notebookSection,
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
