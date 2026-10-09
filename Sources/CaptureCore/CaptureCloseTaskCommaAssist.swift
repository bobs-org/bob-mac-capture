import Foundation

/// Snapshot of the draft the close-list spans describe. The assist only
/// runs when the snapshot draft still equals the visible text, so stale
/// spans can never arm an edit.
public struct CaptureParseSnapshot: Equatable, Sendable {
    public let draft: String
    public let spans: [CaptureSpan]

    public init(draft: String, spans: [CaptureSpan]) {
        self.draft = draft
        self.spans = spans
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
/// close-list spans, and Bob stays authoritative.
public enum CaptureCloseTaskCommaAssist {
    public static let listSpanKinds: Set<String> = [
        "pomodoro_close_in_progress",
        "pomodoro_close_park",
        "pomodoro_close_complete",
        "pomodoro_close_drop",
    ]

    /// The assist runs only when the running Pomodoro has fewer than 10
    /// numbered Task Links; with 10 or more a multi-digit index is
    /// legitimate.
    public static let singleDigitLineupLimit = 10

    public static func isArmed(taskLinkCount: Int?) -> Bool {
        guard let taskLinkCount else {
            return false
        }
        return taskLinkCount < singleDigitLineupLimit
    }

    public nonisolated static func edit(
        typed: String,
        text: String,
        selectedRange: NSRange,
        snapshot: CaptureParseSnapshot?,
        taskLinkCount: Int?
    ) -> CaptureCloseTaskCommaEdit? {
        guard typed.count == 1,
              let scalar = typed.unicodeScalars.first,
              typed.unicodeScalars.count == 1,
              scalar.value >= 0x31,
              scalar.value <= 0x39
        else {
            return nil
        }
        guard isArmed(taskLinkCount: taskLinkCount) else {
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
        let insideList = snapshot.spans.contains { span in
            listSpanKinds.contains(span.kind)
                && span.start < caretUTF8
                && caretUTF8 <= span.end
        }
        guard insideList else {
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
