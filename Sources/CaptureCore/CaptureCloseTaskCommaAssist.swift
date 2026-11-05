import Foundation

/// Snapshot of the draft the close-list spans describe. The assist only
/// runs when the snapshot draft still equals the visible text, so stale
/// spans can never arm an edit.
public struct CaptureParseSnapshot: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public let mode: String

        public init(start: Int, end: Int, mode: String) {
            self.start = start
            self.end = end
            self.mode = mode
        }
    }

    public let draft: String
    public let spans: [CaptureSpan]
    public let items: [Item]

    public init(draft: String, spans: [CaptureSpan], items: [Item] = []) {
        self.draft = draft
        self.spans = spans
        self.items = items
    }

    public init(draft: String, parse: CaptureParseResponse) {
        self.draft = draft
        spans = parse.spans
        if parse.items.isEmpty {
            items = [Item(start: 0, end: draft.utf8.count, mode: parse.mode)]
        } else {
            items = parse.items.map { item in
                Item(start: item.range.start, end: item.range.end, mode: item.mode)
            }
        }
    }
}

/// Deterministic single-point edit inserting `,` before a close task
/// number, plus the resulting collapsed caret. The shape matches
/// `CaptureSnippetEdit` so the controller applies it the same way.
public struct CaptureCloseTaskCommaEdit: Equatable, Sendable {
    public let replacementRange: NSRange
    public let replacementText: String
    public let resultingSelection: NSRange

    public init(
        replacementRange: NSRange,
        replacementText: String,
        resultingSelection: NSRange
    ) {
        self.replacementRange = replacementRange
        self.replacementText = replacementText
        self.resultingSelection = resultingSelection
    }
}

/// Pure decision helper for the close-list auto-comma. It never
/// recognizes close syntax itself: it only filters bob's `capture-parse`
/// close-list spans and item modes, and Bob stays authoritative.
public enum CaptureCloseTaskCommaAssist {
    public static let listSpanKinds: Set<String> = [
        "pomodoro_close_in_progress",
        "pomodoro_close_park",
        "pomodoro_close_complete",
        "pomodoro_close_drop",
    ]

    public static let pastItemMode = "pomodoro_past"

    /// The relevant lineup must have fewer than 10 numbered Task Links;
    /// with 10 or more, a multi-digit index is legitimate. `x` and link
    /// lists use the running count; `x=` uses the largest open lineup.
    public static let singleDigitLineupLimit = 10

    public static func isArmed(taskLinkCount: Int?) -> Bool {
        guard let taskLinkCount else {
            return false
        }
        return taskLinkCount < singleDigitLineupLimit
    }

    public static func isArmed(taskLinkCount: Int?, pastTaskLinkCount: Int?) -> Bool {
        isArmed(taskLinkCount: taskLinkCount)
            || isArmed(taskLinkCount: pastTaskLinkCount)
    }

    public nonisolated static func edit(
        typed: String,
        text: String,
        selectedRange: NSRange,
        snapshot: CaptureParseSnapshot?,
        taskLinkCount: Int?,
        pastTaskLinkCount: Int? = nil
    ) -> CaptureCloseTaskCommaEdit? {
        guard typed.count == 1,
              let scalar = typed.unicodeScalars.first,
              typed.unicodeScalars.count == 1,
              scalar.value >= 0x31,
              scalar.value <= 0x39
        else {
            return nil
        }
        let nsText = text as NSString
        guard selectedRange.length == 0,
              selectedRange.location >= 0,
              selectedRange.location <= nsText.length
        else {
            return nil
        }
        guard let snapshot, snapshot.draft == text else {
            return nil
        }
        let prefix = nsText.substring(to: selectedRange.location)
        let caretUTF8 = prefix.utf8.count
        let utf8Bytes = Array(text.utf8)
        guard caretUTF8 > 0, caretUTF8 <= utf8Bytes.count else {
            return nil
        }
        let previous = utf8Bytes[caretUTF8 - 1]
        guard previous >= 0x31, previous <= 0x39 else {
            return nil
        }
        guard let listSpan = snapshot.spans.first(where: { span in
            listSpanKinds.contains(span.kind)
                && span.start < caretUTF8
                && caretUTF8 <= span.end
        }) else {
            return nil
        }
        let owner = snapshot.items
            .filter { item in
                item.start <= listSpan.start && listSpan.end <= item.end
            }
            .min { left, right in
                (left.end - left.start) < (right.end - right.start)
            }
        let armed: Bool
        if owner?.mode == pastItemMode {
            armed = isArmed(taskLinkCount: pastTaskLinkCount)
        } else {
            armed = isArmed(taskLinkCount: taskLinkCount)
        }
        guard armed else {
            return nil
        }
        let replacementRange = NSRange(
            location: selectedRange.location,
            length: 0
        )
        let replacementText = "," + typed
        let resultingSelection = NSRange(
            location: selectedRange.location + 2,
            length: 0
        )
        return CaptureCloseTaskCommaEdit(
            replacementRange: replacementRange,
            replacementText: replacementText,
            resultingSelection: resultingSelection
        )
    }
}
