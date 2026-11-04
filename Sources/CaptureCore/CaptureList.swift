import Foundation

// Lists under a lone `@file` (or `@file#section`) header. Bob splits the draft
// into one capture item per bullet and owns every rule; this file only decodes
// what Bob reports and shapes it for the panel. Nothing here parses draft
// grammar.

/// Bob's additive `list` object on a `bob capture` result: the position of one
/// bullet inside a list filed under a lone `@file` header. `kind` is `tasks`
/// for `@file` and `notes` for `@file#section`; `headerLine` is 1-based and
/// `position` is 1-based within the list. Older Bob and non-list results omit
/// the object. Every field decodes tolerantly so a newer Bob never breaks the
/// preview.
public struct CaptureListContext: Codable, Equatable, Sendable {
    public let kind: String
    public let route: String
    public let section: String?
    public let headerLine: Int
    public let position: Int
    public let count: Int

    public init(
        kind: String,
        route: String,
        section: String? = nil,
        headerLine: Int,
        position: Int,
        count: Int
    ) {
        self.kind = kind
        self.route = route
        self.section = section
        self.headerLine = headerLine
        self.position = position
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "tasks"
        route = try container.decodeIfPresent(String.self, forKey: .route) ?? ""
        section = try container.decodeIfPresent(String.self, forKey: .section)
        headerLine = try container.decodeIfPresent(Int.self, forKey: .headerLine) ?? 0
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case route
        case section
        case headerLine = "header_line"
        case position
        case count
    }

    /// True for a section list (`@file#section`), whose bullets become notes.
    public var isNotes: Bool {
        kind == "notes"
    }
}

/// One list's results stacked under a single capsule in the preview.
public struct CaptureListPreviewGroup: Equatable, Sendable {
    /// Index, in the batch, of the group's first result.
    public let startIndex: Int
    /// How many consecutive results belong to the group.
    public let memberCount: Int
    /// The capsule text: `3 tasks → dev.md` or `2 notes → dev.md · ideas`.
    public let title: String
    /// The VoiceOver phrase for the capsule.
    public let accessibilityLabel: String
}

/// Groups the results of a batch that came from lists. A list's bullets are
/// consecutive results that share one header, so each group is a run of
/// results with the same header line, kind, route, and section. Results with
/// no `list` object never group, and a batch with no lists yields no groups,
/// which leaves the preview exactly as it was.
public struct CaptureListPreview: Equatable, Sendable {
    public let groups: [CaptureListPreviewGroup]

    public init(captures: [CaptureCommandSuccess]) {
        var groups: [CaptureListPreviewGroup] = []
        var index = 0
        while index < captures.count {
            guard let list = captures[index].list else {
                index += 1
                continue
            }
            var end = index + 1
            while end < captures.count, let next = captures[end].list,
                Self.sharesHeader(list, next)
            {
                end += 1
            }
            let count = end - index
            let target = Self.target(for: captures[index], list: list)
            let noun = Self.noun(for: list, count: count)
            groups.append(
                CaptureListPreviewGroup(
                    startIndex: index,
                    memberCount: count,
                    title: "\(count) \(noun) \u{2192} \(target)",
                    accessibilityLabel: Self.accessibilityLabel(
                        count: count,
                        noun: noun,
                        capture: captures[index],
                        list: list
                    )
                )
            )
            index = end
        }
        self.groups = groups
    }

    /// The capsule that sits above the result at `index`, when that result
    /// opens a list.
    public func group(startingAt index: Int) -> CaptureListPreviewGroup? {
        groups.first { $0.startIndex == index }
    }

    /// True when the result at `index` continues the list the previous result
    /// started, so the preview stacks it without a divider.
    public func continuesGroup(at index: Int) -> Bool {
        groups.contains { index > $0.startIndex && index < $0.startIndex + $0.memberCount }
    }

    private static func sharesHeader(_ lhs: CaptureListContext, _ rhs: CaptureListContext)
        -> Bool
    {
        lhs.headerLine == rhs.headerLine && lhs.kind == rhs.kind && lhs.route == rhs.route
            && lhs.section == rhs.section
    }

    /// The destination note: Bob's `route_label` (`dev.md`) when present,
    /// then `<route>.md`, followed by the section selector for a section list.
    private static func target(for capture: CaptureCommandSuccess, list: CaptureListContext)
        -> String
    {
        var note = capture.routeLabel
        if note.isEmpty {
            note = list.route.isEmpty ? capture.relativeTarget : "\(list.route).md"
        }
        if let section = nonEmpty(list.section) {
            return "\(note) \u{00B7} \(section)"
        }
        return note
    }

    private static func noun(for list: CaptureListContext, count: Int) -> String {
        if list.isNotes {
            return count == 1 ? "note" : "notes"
        }
        return count == 1 ? "task" : "tasks"
    }

    private static func accessibilityLabel(
        count: Int,
        noun: String,
        capture: CaptureCommandSuccess,
        list: CaptureListContext
    ) -> String {
        var note = capture.routeLabel
        if note.isEmpty {
            note = list.route.isEmpty ? capture.relativeTarget : "\(list.route).md"
        }
        var label = "List of \(count) \(noun), filed to \(note)"
        if let section = nonEmpty(list.section) {
            label += ", section \(section)"
        }
        return label
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}

/// Starting the first bullet under a lone list header. When `capture-parse`
/// reports `list_item` for the item whose header the caret ends, the newline
/// key inserts `\n- ` so the next keystroke is the first bullet. Bob decides
/// that the header needs a bullet; this only checks where the caret sits.
public enum CaptureListHeaderNewline {
    /// What the newline key inserts instead of a bare newline.
    public static let insertion = "\n- "

    /// True when the caret ends the header line of an item `parse` reports as
    /// needing a `list_item` or as a `note_pull`, with no content after it.
    /// `caretUTF8` is a UTF-8 offset into `draft`, the draft `parse` was computed for.
    public static func startsFirstBullet(
        parse: CaptureParseResponse,
        draft: String,
        caretUTF8: Int
    ) -> Bool {
        guard let line = lineNumber(of: caretUTF8, in: draft),
            parse.items.contains(where: {
                ($0.needs.contains("list_item") || $0.mode == "note_pull")
                    && $0.lineStart == line && $0.lineEnd == line
            })
        else {
            return false
        }
        return caretEndsLine(caretUTF8, in: draft) && nothingFollowsLine(caretUTF8, in: draft)
    }

    /// 1-based physical line of a UTF-8 offset, or nil outside the draft.
    private static func lineNumber(of caretUTF8: Int, in draft: String) -> Int? {
        let bytes = Array(draft.utf8)
        guard caretUTF8 >= 0, caretUTF8 <= bytes.count else {
            return nil
        }
        return bytes[..<caretUTF8].filter { $0 == 0x0A }.count + 1
    }

    /// True when only spaces or tabs sit between the caret and the line end.
    private static func caretEndsLine(_ caretUTF8: Int, in draft: String) -> Bool {
        let bytes = Array(draft.utf8)
        var index = caretUTF8
        while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D {
            if bytes[index] != 0x20, bytes[index] != 0x09 {
                return false
            }
            index += 1
        }
        return true
    }

    /// True when the line after the caret's line is absent or blank, so the
    /// inserted bullet never doubles an existing placeholder row.
    private static func nothingFollowsLine(_ caretUTF8: Int, in draft: String) -> Bool {
        let bytes = Array(draft.utf8)
        var index = caretUTF8
        while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D {
            index += 1
        }
        if index < bytes.count, bytes[index] == 0x0D {
            index += 1
        }
        if index < bytes.count, bytes[index] == 0x0A {
            index += 1
        }
        while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D {
            if bytes[index] != 0x20, bytes[index] != 0x09 {
                return false
            }
            index += 1
        }
        return true
    }
}
