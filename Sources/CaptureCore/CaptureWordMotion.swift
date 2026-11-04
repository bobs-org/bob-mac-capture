import Foundation

/// Vim-style word caret motion for the capture draft editor.
///
/// The router maps Ctrl-L / Ctrl-H to `.bigWord` (vim `W` / `B`) and
/// Ctrl-Shift-L / Ctrl-Shift-H to `.word` (vim `w` / `b`). The controller
/// applies the returned UTF-16 caret directly to the draft text view, so this
/// type never touches text, undo history, completion, or IME state.
public enum CaptureWordMotion {
    public enum Direction: Equatable, Sendable {
        case forward
        case backward
    }

    /// `.word` is vim's `w` / `b`; `.bigWord` is vim's `W` / `B`.
    public enum Unit: Equatable, Sendable {
        case word
        case bigWord
    }

    /// UTF-16 caret location after one motion, or nil only for invalid input
    /// (out-of-bounds selection, or an edge that is not a Character
    /// boundary). A motion that cannot move returns its starting edge
    /// unchanged.
    public static func targetLocation(
        _ direction: Direction,
        _ unit: Unit,
        in text: String,
        selectedRange: NSRange
    ) -> Int? {
        let nsLength = (text as NSString).length
        guard selectedRange.location >= 0,
            selectedRange.length >= 0,
            selectedRange.location <= nsLength,
            selectedRange.length <= nsLength - selectedRange.location
        else {
            return nil
        }
        let selectionEnd = selectedRange.location + selectedRange.length
        guard isCharacterBoundary(selectedRange.location, in: text),
            isCharacterBoundary(selectionEnd, in: text)
        else {
            return nil
        }

        let chars = Array(text)
        let count = chars.count
        var offsets = [Int](repeating: 0, count: count + 1)
        for index in 0..<count {
            offsets[index + 1] = offsets[index] + chars[index].utf16.count
        }

        let startUTF16 =
            direction == .forward ? selectionEnd : selectedRange.location
        guard let startIndex = offsets.firstIndex(of: startUTF16) else {
            return nil
        }

        var position = startIndex
        if direction == .forward {
            if position == count {
                return offsets[position]
            }
            let start = wordClass(chars[position], unit: unit)
            position += 1
            if start != .blank {
                while position < count
                    && wordClass(chars[position], unit: unit) == start
                {
                    position += 1
                }
            }
            while position < count
                && wordClass(chars[position], unit: unit) == .blank
                && !isEmptyLine(position, in: chars)
            {
                position += 1
            }
            return offsets[position]
        } else {
            if position == 0 {
                return 0
            }
            position -= 1
            while wordClass(chars[position], unit: unit) == .blank {
                if isEmptyLine(position, in: chars) {
                    return offsets[position]
                }
                if position == 0 {
                    return 0
                }
                position -= 1
            }
            let found = wordClass(chars[position], unit: unit)
            while wordClass(chars[position], unit: unit) == found {
                if position == 0 {
                    return 0
                }
                position -= 1
            }
            return offsets[position + 1]
        }
    }

    private enum WordClass: Equatable {
        case blank
        case hiragana
        case katakana
        case ideograph
        case hangul
        case keyword
        case emoji
        case punctuation
    }

    private static func wordClass(_ character: Character, unit: Unit) -> WordClass {
        if character.isWhitespace {
            return .blank
        }
        if unit == .bigWord {
            return .keyword
        }
        guard let scalar = character.unicodeScalars.first else {
            return .punctuation
        }
        let value = scalar.value
        if value >= 0x3040 && value <= 0x309F {
            return .hiragana
        }
        if value >= 0x30A0 && value <= 0x30FF {
            return .katakana
        }
        if value >= 0x3300 && value <= 0x9FFF || value >= 0xF900 && value <= 0xFAFF
            || value >= 0x20000 && value <= 0x2FA1F
        {
            return .ideograph
        }
        if value >= 0xAC00 && value <= 0xD7A3 {
            return .hangul
        }
        if scalar == "_" || isLetterMarkOrNumber(scalar) {
            return .keyword
        }
        if scalar.properties.isEmojiPresentation {
            return .emoji
        }
        if scalar.properties.isEmoji
            && character.unicodeScalars.contains(where: { $0.value == 0xFE0F })
        {
            return .emoji
        }
        return .punctuation
    }

    private static func isLetterMarkOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
            .modifierLetter, .otherLetter, .nonspacingMark, .spacingMark,
            .enclosingMark, .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static func isEmptyLine(_ index: Int, in chars: [Character]) -> Bool {
        let count = chars.count
        let afterNewline = index == 0 || chars[index - 1].isNewline
        let beforeNewline = index == count || chars[index].isNewline
        return afterNewline && beforeNewline
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
