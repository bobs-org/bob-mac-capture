import Foundation

/// One styled span of agenda display text. Extends `TaskDisplaySegment`
/// with the emphasis, field, and tag kinds the agenda needs; code and
/// link behave exactly as `TaskDisplayText` parses them. `range` is a
/// `Character`-offset range into `CaptureAgendaInlineText.text`.
public struct CaptureAgendaInlineSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case plain
        case code
        case link
        case strong
        case emphasis
        case field
        case tag
    }

    public let kind: Kind
    public let range: Range<Int>

    public init(kind: Kind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

/// Parses agenda display text for inline styling: code spans, wikilink
/// display text, Keep `[💡](url)` source links, `**strong**`, `*`/`_`
/// emphasis, dimmed `[key:: value]` fields, and `#tags` become styled
/// segments with their delimiters dropped or kept per kind, and
/// everything else stays literal plain text. A trailing `^block-id` is
/// hidden. Unmatched delimiters stay literal. Segments tile `text`
/// exactly, as `TaskDisplayText` guarantees for its own callers (whose
/// behavior is unchanged).
public struct CaptureAgendaInlineText: Equatable, Sendable {
    public let text: String
    public let segments: [CaptureAgendaInlineSegment]

    public init(parsing source: String) {
        let trimmed = Self.stripTrailingBlockID(source)
        var text = ""
        var segments: [CaptureAgendaInlineSegment] = []
        // Appends display characters, merging into the trailing segment
        // when the kind matches so segments tile `text` exactly.
        func append(_ display: String, kind: CaptureAgendaInlineSegment.Kind) {
            guard !display.isEmpty else {
                return
            }
            let start = text.count
            text += display
            if let last = segments.last, last.kind == kind, last.range.upperBound == start {
                segments[segments.count - 1] = CaptureAgendaInlineSegment(
                    kind: kind,
                    range: last.range.lowerBound..<text.count
                )
            } else {
                segments.append(CaptureAgendaInlineSegment(kind: kind, range: start..<text.count))
            }
        }

        let chars = Array(trimmed)
        var index = 0
        while index < chars.count {
            if chars[index] == "`" {
                index = Self.parseCode(chars: chars, from: index, append: append)
            } else if Self.startsWith(chars, index, "[[") {
                index = Self.parseLink(chars: chars, from: index, append: append)
            } else if Self.startsWith(chars, index, "**") {
                index = Self.parseStrong(chars: chars, from: index, append: append)
            } else if chars[index] == "*" {
                index = Self.parseStarEmphasis(chars: chars, from: index, append: append)
            } else if chars[index] == "_" {
                index = Self.parseUnderscoreEmphasis(chars: chars, from: index, append: append)
            } else if chars[index] == "[" {
                index = Self.parseKeepSourceLinkOrField(
                    chars: chars,
                    from: index,
                    append: append
                )
            } else if chars[index] == "#" {
                index = Self.parseTag(chars: chars, from: index, append: append)
            } else {
                append(String(chars[index]), kind: .plain)
                index += 1
            }
        }
        self.text = text
        self.segments = segments
    }

    /// Replaces each complete Keep source link with a bare `💡` and
    /// leaves every other character unchanged, including code spans
    /// and wikilink aliases, which stay opaque. Used for accessibility
    /// labels and one-row summaries so truncation cannot cut a URL.
    public static func projectingKeepSourceLinks(_ source: String) -> String {
        let chars = Array(source)
        var text = ""
        var index = 0
        while index < chars.count {
            if chars[index] == "`" {
                if let close = chars[(index + 1)...].firstIndex(of: "`"), close > index + 1 {
                    text += String(chars[index...close])
                    index = close + 1
                } else {
                    text.append("`")
                    index += 1
                }
            } else if startsWith(chars, index, "[[") {
                var cursor = index + 2
                var closed: Int?
                while cursor + 1 < chars.count {
                    if chars[cursor] == "]", chars[cursor + 1] == "]" {
                        closed = cursor + 1
                        break
                    }
                    cursor += 1
                }
                if let closed {
                    text += String(chars[index...closed])
                    index = closed + 1
                } else {
                    text += "[["
                    index += 2
                }
            } else if let end = keepSourceLinkEnd(chars: chars, from: index) {
                text += "💡"
                index = end
            } else {
                text.append(chars[index])
                index += 1
            }
        }
        return text
    }

    // MARK: - Block IDs

    /// Hides one trailing `^block-id` token (`"Title ^abc123"` parses
    /// as `"Title"`). Only the last token is stripped, and only when
    /// display text remains before it.
    static func stripTrailingBlockID(_ source: String) -> String {
        var end = source.endIndex
        while end > source.startIndex, source[source.index(before: end)].isWhitespace {
            end = source.index(before: end)
        }
        let trimmed = String(source[source.startIndex..<end])
        guard let caret = trimmed.lastIndex(of: "^") else {
            return source
        }
        let after = trimmed[trimmed.index(after: caret)...]
        let valid = after.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        guard !after.isEmpty, valid else {
            return source
        }
        let before = trimmed[trimmed.startIndex..<caret]
        guard before.hasSuffix(" "), before.dropLast().contains(where: { !$0.isWhitespace }) else {
            return source
        }
        return String(before.dropLast())
    }

    // MARK: - Scanners

    static func startsWith(_ chars: [Character], _ index: Int, _ token: String) -> Bool {
        let tokenChars = Array(token)
        guard index + tokenChars.count <= chars.count else {
            return false
        }
        return zip(chars[index...], tokenChars).allSatisfy { $0 == $1 }
    }

    /// Code spans behave exactly as in `TaskDisplayText`: a matched pair
    /// hides its backticks, an empty pair stays literal, and an unmatched
    /// backtick stays literal while later pairs still parse.
    static func parseCode(
        chars: [Character],
        from index: Int,
        append: (String, CaptureAgendaInlineSegment.Kind) -> Void
    ) -> Int {
        let close = chars[(index + 1)...].firstIndex(of: "`")
        if let close, close > index + 1 {
            append(String(chars[(index + 1)..<close]), .code)
            return close + 1
        } else if close == nil {
            append("`", .plain)
            return index + 1
        } else {
            append("``", .plain)
            return index + 2
        }
    }

    /// Wikilinks behave exactly as in `TaskDisplayText`: the alias after
    /// the last `|` shows link-tinted, and an unclosed `[[` stays literal.
    static func parseLink(
        chars: [Character],
        from index: Int,
        append: (String, CaptureAgendaInlineSegment.Kind) -> Void
    ) -> Int {
        var cursor = index + 2
        while cursor + 1 < chars.count {
            if chars[cursor] == "]", chars[cursor + 1] == "]" {
                let inner = String(chars[(index + 2)..<cursor])
                append(displayText(forWikilinkTarget: inner), .link)
                return cursor + 2
            }
            cursor += 1
        }
        append("[[", .plain)
        return index + 2
    }

    /// `**strong**`: both delimiters need a non-space on the inner side,
    /// and the content is non-empty. Unmatched `**` leaves its first `*`
    /// literal so a later single `*` can still open emphasis.
    static func parseStrong(
        chars: [Character],
        from index: Int,
        append: (String, CaptureAgendaInlineSegment.Kind) -> Void
    ) -> Int {
        guard index + 2 < chars.count, !chars[index + 2].isWhitespace else {
            append("*", .plain)
            return index + 1
        }
        var cursor = index + 2
        while cursor + 1 < chars.count {
            if chars[cursor] == "*", chars[cursor + 1] == "*" {
                if chars[cursor - 1].isWhitespace {
                    cursor += 1
                    continue
                }
                append(String(chars[(index + 2)..<cursor]), .strong)
                return cursor + 2
            }
            cursor += 1
        }
        append("*", .plain)
        return index + 1
    }

    /// `*emphasis*`: the opener needs a non-space after it, the closer a
    /// non-space before it, and neither side may touch another `*` (that
    /// is `**` territory). Unmatched `*` stays literal.
    static func parseStarEmphasis(
        chars: [Character],
        from index: Int,
        append: (String, CaptureAgendaInlineSegment.Kind) -> Void
    ) -> Int {
        guard index + 1 < chars.count, !chars[index + 1].isWhitespace else {
            append("*", .plain)
            return index + 1
        }
        guard chars[index + 1] != "*" else {
            append("*", .plain)
            return index + 1
        }
        var cursor = index + 1
        while cursor < chars.count {
            if chars[cursor] == "*" {
                let nextIsStar = cursor + 1 < chars.count && chars[cursor + 1] == "*"
                let prevIsStar = chars[cursor - 1] == "*"
                if !nextIsStar, !prevIsStar, !chars[cursor - 1].isWhitespace {
                    append(String(chars[(index + 1)..<cursor]), .emphasis)
                    return cursor + 1
                }
            }
            cursor += 1
        }
        append("*", .plain)
        return index + 1
    }

    /// `_emphasis_`: like `*` but with word boundaries, so `snake_case`
    /// stays literal. The opener needs a boundary before it and a
    /// non-space after it; the closer needs a non-space before it and a
    /// boundary after it.
    static func parseUnderscoreEmphasis(
        chars: [Character],
        from index: Int,
        append: (String, CaptureAgendaInlineSegment.Kind) -> Void
    ) -> Int {
        let prevIsBoundary = index == 0 || isBoundary(chars[index - 1])
        let nextOK = index + 1 < chars.count && !chars[index + 1].isWhitespace
        let nextIsUnderscore = index + 1 < chars.count && chars[index + 1] == "_"
        guard prevIsBoundary, nextOK, !nextIsUnderscore else {
            append("_", .plain)
            return index + 1
        }
        var cursor = index + 1
        while cursor < chars.count {
            if chars[cursor] == "_" {
                let beforeOK = !chars[cursor - 1].isWhitespace && chars[cursor - 1] != "_"
                let afterIsBoundary = cursor + 1 >= chars.count || isBoundary(chars[cursor + 1])
                if beforeOK, afterIsBoundary {
                    append(String(chars[(index + 1)..<cursor]), .emphasis)
                    return cursor + 1
                }
            }
            cursor += 1
        }
        append("_", .plain)
        return index + 1
    }

    /// A complete Keep source link `[💡](destination)` or
    /// `[💡](destination "title")` becomes one link-tinted `💡`. The
    /// destination is the nonempty percent-encoded form bob emits
    /// (no spaces, parens, quotes, or angle brackets). Tooltip and
    /// closing `)` are consumed together. Malformed or other-label
    /// Markdown links stay literal via `parseField`.
    static func parseKeepSourceLinkOrField(
        chars: [Character],
        from index: Int,
        append: (String, CaptureAgendaInlineSegment.Kind) -> Void
    ) -> Int {
        if let end = keepSourceLinkEnd(chars: chars, from: index) {
            append("💡", .link)
            return end
        }
        return parseField(chars: chars, from: index, append: append)
    }

    /// Index after a complete Keep source link starting at `index`, or
    /// `nil` when the span is missing, empty, or unclosed.
    static func keepSourceLinkEnd(chars: [Character], from index: Int) -> Int? {
        guard startsWith(chars, index, "[💡](") else {
            return nil
        }
        var cursor = index + Array("[💡](").count
        let destStart = cursor
        while cursor < chars.count {
            let char = chars[cursor]
            if char == ")" || char == "(" || char == "\"" || char == "<" || char == ">"
                || char.isWhitespace
            {
                break
            }
            cursor += 1
        }
        guard cursor > destStart else {
            return nil
        }
        if cursor < chars.count, chars[cursor] == ")" {
            return cursor + 1
        }
        guard cursor < chars.count, chars[cursor] == " " else {
            return nil
        }
        cursor += 1
        guard cursor < chars.count, chars[cursor] == "\"" else {
            return nil
        }
        cursor += 1
        while cursor < chars.count, chars[cursor] != "\"" {
            cursor += 1
        }
        guard cursor < chars.count, chars[cursor] == "\"" else {
            return nil
        }
        cursor += 1
        guard cursor < chars.count, chars[cursor] == ")" else {
            return nil
        }
        return cursor + 1
    }

    /// `[key:: value]` fields: the whole bracketed span (brackets kept)
    /// becomes one dimmed segment. A `[` without a `::` before its `]`
    /// stays literal.
    static func parseField(
        chars: [Character],
        from index: Int,
        append: (String, CaptureAgendaInlineSegment.Kind) -> Void
    ) -> Int {
        guard let close = chars[(index + 1)...].firstIndex(of: "]") else {
            append("[", .plain)
            return index + 1
        }
        let inner = String(chars[(index + 1)..<close])
        guard inner.contains("::") else {
            append("[", .plain)
            return index + 1
        }
        append(String(chars[index...close]), .field)
        return close + 1
    }

    /// `#tag`: `#` at a word start followed by tag characters
    /// (letters, numbers, `_`, `/`, `-`). A bare `#` stays literal.
    static func parseTag(
        chars: [Character],
        from index: Int,
        append: (String, CaptureAgendaInlineSegment.Kind) -> Void
    ) -> Int {
        let prev = index == 0 ? nil : chars[index - 1]
        let prevOK = prev == nil || prev?.isWhitespace == true || "([<'\"".contains(prev ?? "x")
        guard prevOK else {
            append("#", .plain)
            return index + 1
        }
        var cursor = index + 1
        while cursor < chars.count, isTagCharacter(chars[cursor]) {
            cursor += 1
        }
        guard cursor > index + 1 else {
            append("#", .plain)
            return index + 1
        }
        append(String(chars[index..<cursor]), .tag)
        return cursor
    }

    static func isBoundary(_ char: Character) -> Bool {
        char.isWhitespace || "([{<'\".,;:!?—–-()]}>".contains(char)
    }

    static func isTagCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || char == "/" || char == "-"
    }
}

/// The display text of a wikilink target: the alias after the last `|`
/// when present, else the whole target. Matches `TaskDisplayText`.
private func displayText(forWikilinkTarget target: String) -> String {
    if let pipe = target.lastIndex(of: "|") {
        return String(target[target.index(after: pipe)...])
    }
    return target
}
