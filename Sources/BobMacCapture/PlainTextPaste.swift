import AppKit

@MainActor
protocol PlainTextPasteboardReading {
    var types: [NSPasteboard.PasteboardType]? { get }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
}

extension NSPasteboard: PlainTextPasteboardReading {}

@MainActor
enum PlainTextPaste {
    /// The clipboard's plain-text flavor, newline-normalized. `nil` when the pasteboard
    /// offers no plain text, so the caller can fall back to AppKit's native paste.
    static func plainText(from pasteboard: NSPasteboard) -> String? {
        plainText(fromReader: pasteboard)
    }

    static func plainText<Pasteboard: PlainTextPasteboardReading>(
        from pasteboard: Pasteboard
    ) -> String? {
        plainText(fromReader: pasteboard)
    }

    private static func plainText<Pasteboard: PlainTextPasteboardReading>(
        fromReader pasteboard: Pasteboard
    ) -> String? {
        // `NSPasteboard.string(forType: .string)` synthesizes plain text from HTML/RTF
        // flavors even when the reader reports no `.string`, so gate on `types` first.
        guard let types = pasteboard.types, types.contains(.string) else {
            return nil
        }
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
        insert(into: responder, fromReader: pasteboard, willInsert: willInsert)
    }

    @discardableResult
    static func insert<Pasteboard: PlainTextPasteboardReading>(
        into responder: NSResponder?,
        from pasteboard: Pasteboard,
        willInsert: () -> Void = {}
    ) -> Bool {
        insert(into: responder, fromReader: pasteboard, willInsert: willInsert)
    }

    @discardableResult
    private static func insert<Pasteboard: PlainTextPasteboardReading>(
        into responder: NSResponder?,
        fromReader pasteboard: Pasteboard,
        willInsert: () -> Void
    ) -> Bool {
        guard let textView = CapturePanelController.editableTextView(responder),
              let text = plainText(fromReader: pasteboard)
        else {
            return false
        }

        willInsert()
        textView.insertText(text, replacementRange: textView.selectedRange())
        CaptureSignpost.event("paste-plain-text")
        return true
    }
}
