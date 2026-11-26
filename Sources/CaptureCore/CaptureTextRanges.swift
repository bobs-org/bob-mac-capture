import Foundation

public struct ValidatedCaptureSpan: Equatable {
    public let span: CaptureSpan
    public let range: Range<String.Index>

    public init(span: CaptureSpan, range: Range<String.Index>) {
        self.span = span
        self.range = range
    }
}

/// A Bob-reported drawer title or its literal `**` delimiter, mapped from the
/// validated UTF-8 span into the draft's String indices. Kept in CaptureCore so
/// editor styling and drawer keystrokes share the same span interpretation.
public struct CaptureDrawerTextSpan: Equatable {
    public enum Role: Equatable {
        case title
        case delimiter
    }

    public let span: CaptureSpan
    public let range: Range<String.Index>
    public let role: Role

    public init(span: CaptureSpan, range: Range<String.Index>, role: Role) {
        self.span = span
        self.range = range
        self.role = role
    }

    /// A caret on or beside either delimiter byte restores it to full ink.
    public func caretTouches(_ utf8Offset: Int?) -> Bool {
        guard let utf8Offset else {
            return false
        }
        return span.start <= utf8Offset && utf8Offset <= span.end
    }
}

/// The empty `****` drawer skeleton Bob reports around a caret: two literal
/// `**` markers with a zero-width `interactive_placeholder` between them.
/// Checks span kinds and byte order only; the caller confirms the draft bytes
/// are `****` inside a Bob-authorized range before deleting them.
public struct CaptureDrawerEmptySkeleton: Equatable {
    public let openingMarker: CaptureSpan
    public let closingMarker: CaptureSpan

    public init?(spans: [CaptureSpan], caretUTF8: Int) {
        var opening: CaptureSpan?
        var closing: CaptureSpan?
        var placeholder = false
        for span in spans {
            switch span.kind {
            case "drawer_marker"
                where span.end == caretUTF8 && span.end - span.start == 2
                && opening == nil:
                opening = span
            case "drawer_marker"
                where span.start == caretUTF8 && span.end - span.start == 2
                && closing == nil:
                closing = span
            case "interactive_placeholder"
                where span.start == caretUTF8 && span.end == caretUTF8:
                placeholder = true
            default:
                continue
            }
        }
        guard placeholder, let opening, let closing else {
            return nil
        }
        self.openingMarker = opening
        self.closingMarker = closing
    }

    /// The four `*` bytes to delete as one undoable edit.
    public var deletionStart: Int {
        openingMarker.start
    }

    public var deletionEnd: Int {
        closingMarker.end
    }
}

/// Select Bob's drawer spans from a validated parse while preserving their
/// UTF-8-backed String ranges for presentation and typing behavior.
public func captureDrawerTextSpans(
    from validatedSpans: [ValidatedCaptureSpan]
) -> [CaptureDrawerTextSpan] {
    validatedSpans.compactMap { item in
        let role: CaptureDrawerTextSpan.Role
        switch item.span.kind {
        case "drawer_bullet":
            role = .title
        case "drawer_marker":
            role = .delimiter
        default:
            return nil
        }
        return CaptureDrawerTextSpan(span: item.span, range: item.range, role: role)
    }
}

public func stringRange(
    in text: String,
    start: Int,
    end: Int
) -> Range<String.Index>? {
    guard start >= 0, end >= start else {
        return nil
    }

    let utf8 = text.utf8
    guard start <= utf8.count, end <= utf8.count else {
        return nil
    }

    guard
        let lower = String.Index(utf8.index(utf8.startIndex, offsetBy: start), within: text),
        let upper = String.Index(utf8.index(utf8.startIndex, offsetBy: end), within: text)
    else {
        return nil
    }

    return lower..<upper
}

public func stringRange(in text: String, byteRange: CaptureRange) -> Range<String.Index>? {
    stringRange(in: text, start: byteRange.start, end: byteRange.end)
}

/// UTF-16 `NSRange` for a validated UTF-8 byte range, or `nil` when the
/// bounds are not character boundaries in `text`.
public func utf16Range(in text: String, start: Int, end: Int) -> NSRange? {
    guard let range = stringRange(in: text, start: start, end: end) else {
        return nil
    }
    return NSRange(range, in: text)
}

public func utf16Range(in text: String, byteRange: CaptureRange) -> NSRange? {
    utf16Range(in: text, start: byteRange.start, end: byteRange.end)
}

/// UTF-8 byte offset of a UTF-16 caret, or `nil` when `utf16Offset` is not
/// a character boundary (for example inside a surrogate pair) or past the
/// end of `text`.
public func utf8Offset(in text: String, utf16Offset: Int) -> Int? {
    let utf16 = text.utf16
    guard utf16Offset >= 0, utf16Offset <= utf16.count else {
        return nil
    }
    // Validate explicitly: `Range(NSRange, in:)` rounds an interior
    // surrogate down to its scalar on current Foundation.
    let position = utf16.index(utf16.startIndex, offsetBy: utf16Offset)
    guard let index = String.Index(position, within: text) else {
        return nil
    }
    return text.utf8.distance(from: text.utf8.startIndex, to: index)
}

public func attributedStringIndex(
    in text: AttributedString,
    utf8Offset targetOffset: Int
) -> AttributedString.Index? {
    guard targetOffset >= 0 else {
        return nil
    }

    var offset = 0
    var index = text.startIndex
    while index < text.endIndex {
        if offset == targetOffset {
            return index
        }

        let character = text.characters[index]
        offset += String(character).utf8.count
        index = text.characters.index(after: index)
    }

    return offset == targetOffset ? text.endIndex : nil
}

public func utf8Offset(
    in text: AttributedString,
    at targetIndex: AttributedString.Index
) -> Int? {
    var offset = 0
    var index = text.startIndex
    while index < text.endIndex {
        if index == targetIndex {
            return offset
        }

        let character = text.characters[index]
        offset += String(character).utf8.count
        index = text.characters.index(after: index)
    }

    return targetIndex == text.endIndex ? offset : nil
}

public func validatedSpanRanges(
    in text: String,
    spans: [CaptureSpan]
) -> [ValidatedCaptureSpan]? {
    var previousEnd = 0
    var validated: [ValidatedCaptureSpan] = []

    for span in spans {
        guard span.start >= previousEnd else {
            return nil
        }
        guard let range = stringRange(in: text, start: span.start, end: span.end) else {
            return nil
        }
        validated.append(ValidatedCaptureSpan(span: span, range: range))
        previousEnd = span.end
    }

    return validated
}
