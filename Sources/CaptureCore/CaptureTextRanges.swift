import Foundation

public struct ValidatedCaptureSpan: Equatable {
    public let span: CaptureSpan
    public let range: Range<String.Index>

    public init(span: CaptureSpan, range: Range<String.Index>) {
        self.span = span
        self.range = range
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
