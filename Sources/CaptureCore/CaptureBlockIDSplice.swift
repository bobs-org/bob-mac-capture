import Foundation

/// Bob's additive `block_id.splice` for a `project_task_block_id` prompt. A
/// client writes `before + ID + after` over `range` (draft-global UTF-8 byte
/// offsets) and puts the caret at the end of what it wrote. That puts the
/// accepted ID on the line of the task that owns it, even when the prompt
/// opened on one of the task's nested lines, and leaves the caret where the
/// user was typing. For a same-line prompt `range` is the ID part and both
/// strings are empty, so the splice is the ordinary insertion.
public struct CaptureBlockIDSplice: Codable, Equatable, Sendable {
    public let range: CaptureRange
    public let before: String
    public let after: String

    public init(range: CaptureRange, before: String = "", after: String = "") {
        self.range = range
        self.before = before
        self.after = after
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(CaptureRange.self, forKey: .range)
        before = try container.decodeIfPresent(String.self, forKey: .before) ?? ""
        after = try container.decodeIfPresent(String.self, forKey: .after) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case before
        case after
    }

    /// A splice applied to a draft.
    public struct Applied: Equatable, Sendable {
        /// The draft after the edit.
        public let draft: String
        /// UTF-8 offset of the caret: the end of the text the splice wrote.
        public let caret: Int
        /// The text written over the range.
        public let written: String
    }

    /// Writes `before + id + after + remainder` over `range` in `draft`.
    /// `remainder` is text the user typed right after the ID in the same
    /// gesture (type-through); it lands where they were typing, after
    /// `after`, so the caret follows it. Returns nil when `range` is not a
    /// valid byte range on character boundaries of `draft`, so a stale draft
    /// is never edited.
    public func applied(id: String, remainder: String = "", to draft: String) -> Applied? {
        guard let target = stringRange(in: draft, byteRange: range) else {
            return nil
        }
        let written = before + id + after + remainder
        var text = draft
        text.replaceSubrange(target, with: written)
        return Applied(
            draft: text,
            caret: range.start + written.utf8.count,
            written: written
        )
    }
}

extension CaptureBlockIDField {
    /// 1-based physical line of the marker token Bob reports, counted in
    /// `draft` (the draft the snapshot belongs to). Nil without a marker range
    /// or when the range falls outside the draft.
    public func markerLine(in draft: String) -> Int? {
        guard let start = markerRange?.start, start >= 0, start <= draft.utf8.count else {
            return nil
        }
        return draft.utf8.prefix(start).filter { $0 == 0x0A }.count + 1
    }

    /// The owner task's text (trimmed for display) when the ID lands on a
    /// different line than the one the caret's marker sits on: a prompt opened
    /// on a nested line of a list or project-note task. Nil for a same-line
    /// prompt, a task with no text yet, and a response without `owner_line`,
    /// so those read exactly as before.
    public func ownerTaskText(markerLine: Int?) -> String? {
        guard let ownerLine, let markerLine, ownerLine != markerLine, !body.isEmpty else {
            return nil
        }
        let limit = 60
        guard body.count > limit else {
            return body
        }
        return String(body.prefix(limit)) + "\u{2026}"
    }
}

extension BlockIDPickerContext {
    /// The status line after an accept. A Block ID session names the marker it
    /// landed on (`Inserted @sase:id`); a project-task session has no route
    /// (`Inserted :id`) and, when the ID went to an owner on another line,
    /// names that task (`Inserted :fix-flaky-gkeep on ‘Fix flaky gkeep test’`).
    public func insertedAnnouncement(id: String, markerLine: Int?) -> String {
        if scope == .projectTask {
            let base = "Inserted \(marker)\(id)"
            if let owner = field?.ownerTaskText(markerLine: markerLine) {
                return "\(base) on \u{2018}\(owner)\u{2019}"
            }
            return base
        }
        return "Inserted @\(route)\(marker)\(id)"
    }
}
