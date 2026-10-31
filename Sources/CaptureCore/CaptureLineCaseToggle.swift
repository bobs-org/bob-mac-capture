import Foundation

/// Deterministic replacement that toggles the case of one or more physical
/// lines, plus the selection mapped through the same transform. The shape
/// matches `CaptureCloseTaskCommaEdit` so the controller applies it the same
/// way.
public struct CaptureLineCaseEdit: Equatable, Sendable {
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

/// Grammar-agnostic case toggle for the physical line(s) a selection
/// touches. Bob Mac Capture is a thin client of bob, so this edit never
/// inspects capture syntax; live parse re-reads the result.
public enum CaptureLineCaseToggle {
    public static func edit(in text: String, selectedRange: NSRange) -> CaptureLineCaseEdit? {
        let nsText = text as NSString
        let textLength = nsText.length
        guard selectedRange.location >= 0,
            selectedRange.length >= 0,
            selectedRange.location <= textLength,
            selectedRange.length <= textLength - selectedRange.location
        else {
            return nil
        }

        let selectionEnd = selectedRange.location + selectedRange.length
        guard isCharacterBoundary(selectedRange.location, in: text),
            isCharacterBoundary(selectionEnd, in: text)
        else {
            return nil
        }

        var firstLineStart = 0
        var firstContentsEnd = 0
        nsText.getLineStart(
            &firstLineStart,
            end: nil,
            contentsEnd: &firstContentsEnd,
            for: NSRange(location: selectedRange.location, length: 0)
        )

        let spanStart = firstLineStart
        let spanEnd: Int
        if selectedRange.length == 0 {
            spanEnd = firstContentsEnd
        } else {
            let lastLocation = selectedRange.location + selectedRange.length - 1
            var lastLineStart = 0
            var lastContentsEnd = 0
            nsText.getLineStart(
                &lastLineStart,
                end: nil,
                contentsEnd: &lastContentsEnd,
                for: NSRange(location: lastLocation, length: 0)
            )
            spanEnd = lastContentsEnd
        }

        guard spanEnd >= spanStart,
            isCharacterBoundary(spanStart, in: text),
            isCharacterBoundary(spanEnd, in: text),
            let spanStartIndex = characterIndex(atUTF16: spanStart, in: text),
            let spanEndIndex = characterIndex(atUTF16: spanEnd, in: text)
        else {
            return nil
        }

        let span = String(text[spanStartIndex..<spanEndIndex])
        let uppercased = span.uppercased()
        let useUpper: Bool
        if uppercased != span {
            useUpper = true
        } else if span.lowercased() != span {
            useUpper = false
        } else {
            return nil
        }

        let transformed = transform(span, useUpper: useUpper)
        guard
            let mappedLocation = mapEndpoint(
                selectedRange.location,
                spanStart: spanStart,
                spanStartIndex: spanStartIndex,
                spanEndIndex: spanEndIndex,
                useUpper: useUpper,
                newSpanEnd: spanStart + transformed.utf16.count,
                in: text
            ),
            let mappedEnd = mapEndpoint(
                selectionEnd,
                spanStart: spanStart,
                spanStartIndex: spanStartIndex,
                spanEndIndex: spanEndIndex,
                useUpper: useUpper,
                newSpanEnd: spanStart + transformed.utf16.count,
                in: text
            )
        else {
            return nil
        }

        return CaptureLineCaseEdit(
            replacementRange: NSRange(location: spanStart, length: spanEnd - spanStart),
            replacementText: transformed,
            resultingSelection: NSRange(
                location: mappedLocation,
                length: max(0, mappedEnd - mappedLocation)
            )
        )
    }

    private static func transform(_ value: String, useUpper: Bool) -> String {
        useUpper ? value.uppercased() : value.lowercased()
    }

    private static func mapEndpoint(
        _ original: Int,
        spanStart: Int,
        spanStartIndex: String.Index,
        spanEndIndex: String.Index,
        useUpper: Bool,
        newSpanEnd: Int,
        in text: String
    ) -> Int? {
        guard let originalIndex = characterIndex(atUTF16: original, in: text) else {
            return nil
        }
        let clampedIndex: String.Index
        if originalIndex < spanStartIndex {
            clampedIndex = spanStartIndex
        } else if originalIndex > spanEndIndex {
            clampedIndex = spanEndIndex
        } else {
            clampedIndex = originalIndex
        }
        let prefix = String(text[spanStartIndex..<clampedIndex])
        let mapped = spanStart + transform(prefix, useUpper: useUpper).utf16.count
        return min(mapped, newSpanEnd)
    }

    private static func isCharacterBoundary(_ utf16Offset: Int, in text: String) -> Bool {
        characterIndex(atUTF16: utf16Offset, in: text) != nil
    }

    private static func characterIndex(atUTF16 offset: Int, in text: String) -> String.Index? {
        let utf16 = text.utf16
        guard offset >= 0, offset <= utf16.count else {
            return nil
        }
        let position = utf16.index(utf16.startIndex, offsetBy: offset)
        return String.Index(position, within: text)
    }
}
