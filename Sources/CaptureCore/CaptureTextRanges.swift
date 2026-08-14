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
