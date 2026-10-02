import Foundation

/// One display-only token of a Pomodoro block row: `text` keeps its exact
/// bytes, `role` names the Markdown shape for tinting, and `struck` marks
/// text inside `~~…~~`. Tokenizing never adds, drops, or reorders
/// characters: `tokens.map(\.text).joined()` always equals the input.
public struct CapturePomodoroLineToken: Equatable, Sendable {
    public let text: String
    public let role: CapturePomodoroLineTokenRole
    public let struck: Bool

    public init(text: String, role: CapturePomodoroLineTokenRole, struck: Bool = false) {
        self.text = text
        self.role = role
        self.struck = struck
    }
}

/// The Markdown shapes a block row can carry. `checkbox` holds the symbol
/// inside the brackets (` `, `x`, `/`, `*`, …); `wikilinkHeading` and
/// `wikilinkBlock` keep their leading `#` (and `^`); `wikilinkAlias` keeps
/// its leading `|`; `tag` is a `#tag` word; `blockID` is a trailing
/// `^block-id` (keeping its `^`).
public enum CapturePomodoroLineTokenRole: Equatable, Sendable {
    case syntax
    case checkbox(Character)
    case timeRange
    case field
    case name
    case tag
    case blockID
    case wikilinkDelimiter
    case wikilinkTarget
    case wikilinkHeading
    case wikilinkBlock
    case wikilinkAlias
    case code
    case text
}

/// Display-only tokenizer for Pomodoro block rows. One left-to-right scan
/// with no regex backtracking: headlines split into dash, checkbox,
/// timerange, fields, and name, while every other line scans inline for
/// links, fields, code, bold, and strikethrough. A legacy or unrecognized
/// headline falls back to plain `text` after the checkbox.
public enum CapturePomodoroLineTokens {
    public static func tokenize(
        _ content: String,
        isHeadline: Bool
    ) -> [CapturePomodoroLineToken] {
        var scanner = LineScanner(content)
        if isHeadline {
            scanner.scanHeadline()
        } else {
            scanner.scanInline()
        }
        return scanner.tokens
    }

    /// Display-only tokenizer for parent-task block rows: an optional list
    /// marker (`-`, `*`, `+`, `N.`, `N)`) as `.syntax`, then an optional
    /// `[c]` checkbox as `.checkbox(c)`, then the existing inline scan,
    /// then a byte-preserving post-pass that splits `#tag` words into
    /// `.tag` and a trailing ` ^block-id` into `.blockID`. Headline and
    /// body rows tokenize identically today; `isHeadline` keeps the call
    /// shape the card rows share. The hard invariant still holds:
    /// `tokens.map(\.text).joined()` always equals the input.
    public static func tokenizeTaskRow(
        _ content: String,
        isHeadline: Bool
    ) -> [CapturePomodoroLineToken] {
        var tokens: [CapturePomodoroLineToken] = []
        var remainder = content

        func takeMarker() {
            if let marker = taskListMarkerPrefix(remainder) {
                tokens.append(CapturePomodoroLineToken(text: marker, role: .syntax))
                remainder.removeFirst(marker.count)
                let spaces = remainder.prefix(while: { $0 == " " || $0 == "\t" })
                if !spaces.isEmpty {
                    tokens.append(CapturePomodoroLineToken(text: String(spaces), role: .text))
                    remainder.removeFirst(spaces.count)
                }
            }
        }

        takeMarker()
        if let checkbox = taskCheckboxPrefix(remainder) {
            tokens.append(
                CapturePomodoroLineToken(
                    text: String(remainder.prefix(3)),
                    role: .checkbox(checkbox)
                )
            )
            remainder.removeFirst(3)
            let spaces = remainder.prefix(while: { $0 == " " || $0 == "\t" })
            if !spaces.isEmpty {
                tokens.append(CapturePomodoroLineToken(text: String(spaces), role: .text))
                remainder.removeFirst(spaces.count)
            }
        }
        if !remainder.isEmpty {
            var scanner = LineScanner(remainder)
            scanner.scanInline()
            tokens.append(contentsOf: scanner.tokens)
        }
        return splitTaskSuffixes(tokens)
    }
}

/// A list marker at the start of `value` (`-`, `*`, `+`, `N.`, `N)`),
/// requiring trailing whitespace or end of line so `--foo` and `**bold**`
/// never read as markers. Nil when `value` opens with anything else.
private func taskListMarkerPrefix(_ value: String) -> String? {
    guard let first = value.first else {
        return nil
    }
    if first == "-" || first == "*" || first == "+" {
        let after = value.index(after: value.startIndex)
        if after == value.endIndex || value[after] == " " || value[after] == "\t" {
            return String(first)
        }
        return nil
    }
    let digits = value.prefix(while: { $0.isWholeNumber })
    guard !digits.isEmpty else {
        return nil
    }
    let rest = value.dropFirst(digits.count)
    guard let punct = rest.first, punct == "." || punct == ")" else {
        return nil
    }
    let after = rest.index(after: rest.startIndex)
    if after == rest.endIndex || rest[after] == " " || rest[after] == "\t" {
        return String(digits) + String(punct)
    }
    return nil
}

/// The checkbox symbol of a `[c]` prefix, or nil. Any single middle
/// character counts, matching the Pomodoro headline rule.
private func taskCheckboxPrefix(_ value: String) -> Character? {
    let prefix = Array(value.prefix(3))
    guard prefix.count == 3, prefix[0] == "[", prefix[2] == "]" else {
        return nil
    }
    return prefix[1]
}

private func isTaskTagChar(_ value: Character) -> Bool {
    value.isLetter || value.isWholeNumber || value == "_" || value == "/" || value == "-"
}

private func isTaskBoundary(_ value: Character?) -> Bool {
    guard let value else {
        return true
    }
    return value == " " || value == "\t"
}

/// Byte-preserving post-pass over task-row tokens: a trailing
/// ` ^block-id` becomes `.blockID`, and `#tag` words inside `.text`
/// tokens become `.tag`. Code, links, fields, and every other role pass
/// through untouched, so `` `#code` `` and `[[#target]]` never split.
private func splitTaskSuffixes(_ tokens: [CapturePomodoroLineToken]) -> [CapturePomodoroLineToken] {
    var tokens = tokens
    // A trailing ` ^block-id` only counts at the very end of the row, so
    // only the last token can carry it, and only when the inline scan left
    // it plain text.
    if let last = tokens.last, last.role == .text,
        let range = last.text.range(
            of: "[ \\t]+\\^[A-Za-z0-9-]+$",
            options: .regularExpression
        ),
        let idStart = last.text[range].firstIndex(of: "^")
    {
        let head = String(last.text[..<range.lowerBound])
        // The match always starts with whitespace by construction.
        let struck = last.struck
        tokens.removeLast()
        if !head.isEmpty {
            tokens.append(CapturePomodoroLineToken(text: head, role: .text, struck: struck))
        }
        let gap = String(last.text[range.lowerBound..<idStart])
        if !gap.isEmpty {
            tokens.append(CapturePomodoroLineToken(text: gap, role: .text, struck: struck))
        }
        tokens.append(
            CapturePomodoroLineToken(text: String(last.text[idStart...]), role: .blockID, struck: struck)
        )
    }

    var result: [CapturePomodoroLineToken] = []
    var previous: Character? = nil
    for token in tokens {
        if token.role != .text {
            result.append(token)
            previous = token.text.last
            continue
        }
        var cursor = token.text.startIndex
        var chunk = ""
        var boundary = isTaskBoundary(previous)
        let struck = token.struck
        func flush() {
            if !chunk.isEmpty {
                result.append(CapturePomodoroLineToken(text: chunk, role: .text, struck: struck))
                chunk = ""
            }
        }
        while cursor < token.text.endIndex {
            let char = token.text[cursor]
            if char == "#", boundary {
                let runStart = token.text.index(after: cursor)
                var runEnd = runStart
                while runEnd < token.text.endIndex, isTaskTagChar(token.text[runEnd]) {
                    runEnd = token.text.index(after: runEnd)
                }
                let run = String(token.text[runStart..<runEnd])
                if !run.isEmpty, run.contains(where: { !$0.isWholeNumber }) {
                    flush()
                    result.append(
                        CapturePomodoroLineToken(text: "#" + run, role: .tag, struck: struck)
                    )
                    previous = token.text[token.text.index(before: runEnd)]
                    cursor = runEnd
                    boundary = false
                    continue
                }
            }
            chunk.append(char)
            boundary = char == " " || char == "\t"
            previous = char
            cursor = token.text.index(after: cursor)
        }
        flush()
    }
    return result
}

private struct LineScanner {
    typealias Token = CapturePomodoroLineToken
    typealias Role = CapturePomodoroLineTokenRole

    let text: String
    var index: String.Index
    var struck = false
    var pendingText = ""
    var tokens: [Token] = []

    init(_ text: String) {
        self.text = text
        index = text.startIndex
    }

    var isAtEnd: Bool {
        index == text.endIndex
    }

    var rest: Substring {
        text[index...]
    }

    func starts(with prefix: String) -> Bool {
        rest.hasPrefix(prefix)
    }

    mutating func advance(by offset: Int = 1) {
        index = text.index(index, offsetBy: offset)
    }

    mutating func emit(_ value: String, role: Role, struck override: Bool? = nil) {
        guard !value.isEmpty else {
            return
        }
        tokens.append(Token(text: value, role: role, struck: override ?? struck))
    }

    mutating func flushText() {
        if !pendingText.isEmpty {
            emit(pendingText, role: .text)
            pendingText = ""
        }
    }

    // MARK: - Headlines

    mutating func scanHeadline() {
        // A Pomodoro headline is a list item. Anything else is legacy or
        // unrecognized: the whole line stays plain text.
        guard starts(with: "- ") || starts(with: "-\t") else {
            if !isAtEnd {
                emit(String(rest), role: .text)
            }
            return
        }
        emit("-", role: .syntax, struck: false)
        advance()
        let spacesStart = index
        while starts(with: " ") || starts(with: "\t") {
            advance()
        }
        if spacesStart != index {
            emit(String(text[spacesStart..<index]), role: .text)
        }
        // Optional `[x]` checkbox directly after the dash.
        if starts(with: "[") {
            let bracket = Array(rest.prefix(3))
            if bracket.count == 3 && bracket[0] == "[" && bracket[2] == "]" {
                emit(String(rest.prefix(3)), role: .checkbox(bracket[1]))
                advance(by: 3)
            }
        }
        scanHeadlineBody()
    }

    mutating func scanHeadlineBody() {
        // Timed `(**HHMM-HHMM** [t:: Nm])` or placeholder `()` headline,
        // then optionally ` — name`. Anything else is legacy or
        // unrecognized and stays one plain-text tail after the checkbox.
        let gapStart = index
        while starts(with: " ") || starts(with: "\t") {
            advance()
        }
        guard starts(with: "(") else {
            if gapStart != text.endIndex {
                emit(String(text[gapStart...]), role: .text)
            }
            return
        }
        if gapStart != index {
            emit(String(text[gapStart..<index]), role: .text)
        }
        emit("(", role: .syntax, struck: false)
        advance()
        if starts(with: ")") {
            emit(")", role: .syntax, struck: false)
            advance()
            scanHeadlineName()
            return
        }
        guard starts(with: "**") else {
            // `(` without a time range or empty parens: keep the emitted
            // `(` and scan the rest inline.
            scanInline()
            return
        }
        emit("**", role: .syntax, struck: false)
        advance(by: 2)
        if let closing = rest.range(of: "**") {
            let inner = String(rest[..<closing.lowerBound])
            emit(inner, role: isTimeRange(inner) ? .timeRange : .text)
            index = closing.upperBound
            emit("**", role: .syntax, struck: false)
        }
        // Fields and anything else up to the closing paren scan inline; a
        // missing `)` simply ends the headline where the line ends.
        scanInline(stopAt: ")")
        if starts(with: ")") {
            emit(")", role: .syntax, struck: false)
            advance()
        }
        scanHeadlineName()
    }

    mutating func scanHeadlineName() {
        guard !isAtEnd else {
            return
        }
        // The headline name follows ` — `; anything else is unrecognized
        // and stays plain text.
        guard starts(with: " — ") else {
            emit(String(rest), role: .text)
            return
        }
        emit(" — ", role: .text)
        advance(by: 3)
        if !isAtEnd {
            emit(String(rest), role: .name)
        }
    }

    // MARK: - Inline scan

    mutating func scanInline(stopAt stop: String? = nil) {
        while !isAtEnd {
            if let stop, starts(with: stop) {
                break
            }
            if starts(with: "~~") {
                flushText()
                emit("~~", role: .syntax, struck: false)
                advance(by: 2)
                struck.toggle()
                continue
            }
            if starts(with: "`") {
                flushText()
                scanCode()
                continue
            }
            if starts(with: "**") {
                flushText()
                scanBold()
                continue
            }
            if starts(with: "![[") {
                flushText()
                scanLink(opening: "![[")
                continue
            }
            if starts(with: "[[") {
                flushText()
                scanLink(opening: "[[")
                continue
            }
            if starts(with: "~") && rest.dropFirst().hasPrefix("[[") {
                flushText()
                emit("~", role: .syntax)
                advance()
                scanLink(opening: "[[")
                continue
            }
            if starts(with: "[") && fieldClosesAhead() {
                flushText()
                scanField()
                continue
            }
            if let char = rest.first {
                pendingText.append(char)
                advance()
            }
        }
        flushText()
    }

    mutating func scanCode() {
        // A maximal backtick run opens; the next lone backtick closes.
        let start = index
        while starts(with: "`") {
            advance()
        }
        let opening = String(text[start..<index])
        if let closing = rest.range(of: "`") {
            emit(opening, role: .syntax, struck: false)
            emit(String(rest[..<closing.lowerBound]), role: .code)
            index = closing.lowerBound
            emit("`", role: .syntax, struck: false)
            advance()
        } else {
            emit(opening, role: .syntax, struck: false)
        }
    }

    mutating func scanBold() {
        emit("**", role: .syntax, struck: false)
        advance(by: 2)
        if let closing = rest.range(of: "**") {
            emit(String(rest[..<closing.lowerBound]), role: .text)
            index = closing.lowerBound
            emit("**", role: .syntax, struck: false)
            advance(by: 2)
        }
        // Without a closer the opening `**` stays syntax and the rest
        // scans inline from the current position.
    }

    func fieldClosesAhead() -> Bool {
        guard starts(with: "[") else {
            return false
        }
        guard let closing = rest.range(of: "]") else {
            return false
        }
        return rest[..<closing.lowerBound].contains("::")
    }

    mutating func scanField() {
        // The caller verified a `]` ahead with `::` between: `[key:: value]`.
        if let closing = rest.range(of: "]") {
            emit(String(rest[...closing.lowerBound]), role: .field)
            index = closing.upperBound
        }
    }

    mutating func scanLink(opening: String) {
        // The caller is at `[[` (or `![[`); without a closing `]]` the
        // opening stays plain text.
        let afterOpening = text.index(index, offsetBy: opening.count)
        guard let closing = text[afterOpening...].range(of: "]]") else {
            emit(opening, role: .text)
            index = afterOpening
            return
        }
        emit(opening, role: .wikilinkDelimiter, struck: false)
        index = afterOpening
        let bodyEnd = closing.lowerBound
        // Target up to `#`, `|`, or the closer.
        var cursor = index
        while cursor < bodyEnd && text[cursor] != "#" && text[cursor] != "|" {
            cursor = text.index(after: cursor)
        }
        if cursor != index {
            emit(String(text[index..<cursor]), role: .wikilinkTarget)
            index = cursor
        }
        // Optional `#Heading` or `#^block` part, keeping its markers.
        if index < bodyEnd && text[index] == "#" {
            cursor = text.index(after: index)
            let isBlock = cursor < bodyEnd && text[cursor] == "^"
            while cursor < bodyEnd && text[cursor] != "|" {
                cursor = text.index(after: cursor)
            }
            emit(String(text[index..<cursor]), role: isBlock ? .wikilinkBlock : .wikilinkHeading)
            index = cursor
        }
        // Optional `|alias` part, keeping the pipe.
        if index < bodyEnd && text[index] == "|" {
            emit(String(text[index..<bodyEnd]), role: .wikilinkAlias)
        }
        index = bodyEnd
        emit("]]", role: .wikilinkDelimiter, struck: false)
        index = closing.upperBound
        // A deferred `#` suffix hugs the closer.
        if starts(with: "#") {
            emit("#", role: .syntax)
            advance()
        }
    }
}

private func isTimeRange(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2 else {
        return false
    }
    return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isWholeNumber) }
}
