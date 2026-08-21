import AppKit

@MainActor
protocol PlainTextPasteboardReading {
    var types: [NSPasteboard.PasteboardType]? { get }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
}

extension NSPasteboard: PlainTextPasteboardReading {}

struct PlainTextPasteEdit: Equatable {
    let replacementRange: NSRange
    let replacementText: String
}

enum PlainTextPasteEditResolver {
    static func resolve(
        in draft: String,
        selectedRange: NSRange,
        clipboardText: String
    ) -> PlainTextPasteEdit {
        let ordinaryEdit = PlainTextPasteEdit(
            replacementRange: selectedRange,
            replacementText: clipboardText
        )
        let nsDraft = draft as NSString

        guard selectedRange.location >= 0,
              selectedRange.length == 0,
              selectedRange.location <= nsDraft.length
        else {
            return ordinaryEdit
        }

        var lineStart = 0
        var contentsEnd = 0
        nsDraft.getLineStart(
            &lineStart,
            end: nil,
            contentsEnd: &contentsEnd,
            for: NSRange(location: selectedRange.location, length: 0)
        )
        guard selectedRange.location == contentsEnd else {
            return ordinaryEdit
        }

        let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
        guard let placeholder = parsePlaceholderLine(nsDraft.substring(with: lineRange)),
              let pastedList = parsePastedList(clipboardText)
        else {
            return ordinaryEdit
        }

        var replacementLines = [
            "\(placeholder.indentation)\(placeholder.marker) \(pastedList.firstBody)"
        ]
        replacementLines.append(
            contentsOf: pastedList.remainingLines.map { line in
                rebase(
                    line,
                    fromLeadingSpaceBaseline: pastedList.leadingSpaceBaseline,
                    toIndentation: placeholder.indentation
                )
            }
        )

        return PlainTextPasteEdit(
            replacementRange: lineRange,
            replacementText: replacementLines.joined(separator: "\n")
        )
    }

    private struct PlaceholderLine {
        let indentation: String
        let marker: Character
    }

    private struct PastedList {
        let leadingSpaceBaseline: Int
        let firstBody: String
        let remainingLines: [String]
    }

    private static func parsePlaceholderLine(_ line: String) -> PlaceholderLine? {
        let indentation: String
        let remainder: Substring
        if line.hasPrefix("  ") {
            indentation = "  "
            remainder = line.dropFirst(2)
        } else {
            indentation = ""
            remainder = line[...]
        }

        guard let marker = remainder.first,
              isSupportedMarker(marker)
        else {
            return nil
        }

        let trailing = remainder.dropFirst()
        guard trailing.allSatisfy(isHorizontalWhitespace) else {
            return nil
        }
        return PlaceholderLine(indentation: indentation, marker: marker)
    }

    private static func parsePastedList(_ text: String) -> PastedList? {
        let lines = text.components(separatedBy: "\n")
        guard let firstLine = lines.first,
              let firstBullet = parsePastedBulletLine(firstLine)
        else {
            return nil
        }
        return PastedList(
            leadingSpaceBaseline: firstBullet.leadingSpaces,
            firstBody: firstBullet.body,
            remainingLines: Array(lines.dropFirst())
        )
    }

    private static func parsePastedBulletLine(
        _ line: String
    ) -> (leadingSpaces: Int, body: String)? {
        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        var remainder = line.dropFirst(leadingSpaces)

        guard let marker = remainder.first,
              isSupportedMarker(marker)
        else {
            return nil
        }
        remainder = remainder.dropFirst()

        guard let separator = remainder.first,
              isHorizontalWhitespace(separator)
        else {
            return nil
        }

        let body = remainder.drop(while: isHorizontalWhitespace)
        guard !body.isEmpty else {
            return nil
        }
        return (leadingSpaces, String(body))
    }

    private static func rebase(
        _ line: String,
        fromLeadingSpaceBaseline baseline: Int,
        toIndentation indentation: String
    ) -> String {
        guard !line.allSatisfy(isHorizontalWhitespace) else {
            return ""
        }

        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        let targetSpaces = max(0, indentation.count + leadingSpaces - baseline)
        return String(repeating: " ", count: targetSpaces)
            + String(line.dropFirst(leadingSpaces))
    }

    private static func isSupportedMarker(_ character: Character) -> Bool {
        character == "-" || character == "*" || character == "+"
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }
}

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
        let edit = PlainTextPasteEditResolver.resolve(
            in: textView.string,
            selectedRange: textView.selectedRange(),
            clipboardText: text
        )
        textView.insertText(edit.replacementText, replacementRange: edit.replacementRange)
        CaptureSignpost.event("paste-plain-text")
        return true
    }
}
