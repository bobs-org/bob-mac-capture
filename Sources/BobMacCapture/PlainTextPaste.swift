import AppKit

@MainActor
enum PlainTextPaste {
    /// The clipboard's plain-text flavor, newline-normalized. `nil` when the pasteboard
    /// offers no plain text, so the caller can fall back to AppKit's native paste.
    static func plainText(from pasteboard: NSPasteboard) -> String? {
        guard let raw = pasteboard.string(forType: .string), !raw.isEmpty else {
            return nil
        }
        return normalized(raw)
    }

    /// Pure: CRLF and lone CR to LF.
    static func normalized(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Inserts the pasteboard's plain text into `responder` when it is an editable
    /// `NSTextView`. Returns `false` when the responder is not an editable text view or
    /// the pasteboard has no plain text, leaving native paste as the fallback.
    @discardableResult
    static func insert(
        into responder: NSResponder?,
        from pasteboard: NSPasteboard,
        willInsert: () -> Void = {}
    ) -> Bool {
        guard let textView = CapturePanelController.editableTextView(responder),
              let text = plainText(from: pasteboard)
        else {
            return false
        }

        willInsert()
        textView.insertText(text, replacementRange: textView.selectedRange())
        CaptureSignpost.event("paste-plain-text")
        return true
    }
}
