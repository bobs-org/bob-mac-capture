import Foundation

/// One styled span of active-task display text: plain prose, a `code` span
/// (backticks hidden), or a `link` (wikilink brackets hidden, alias resolved).
/// `range` is a `Character`-offset range into `TaskDisplayText.text`.
public struct TaskDisplaySegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case plain
        case code
        case link
    }

    public let kind: Kind
    public let range: Range<Int>

    public init(kind: Kind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

/// Parses task text for display: code spans, `[[wikilinks]]`, and Markdown
/// `[label](url)` links become styled segments with their delimiters dropped,
/// and everything else stays literal plain text. All fuzzy matching runs on
/// `text`, so highlight offsets map directly onto `segments`.
public struct TaskDisplayText: Equatable, Sendable {
    public let text: String
    public let segments: [TaskDisplaySegment]

    public init(parsing source: String) {
        var text = ""
        var segments: [TaskDisplaySegment] = []
        // Appends display characters, merging into the trailing segment when
        // the kind matches so segments tile `text` exactly.
        func append(_ display: String, kind: TaskDisplaySegment.Kind) {
            guard !display.isEmpty else {
                return
            }
            let start = text.count
            text += display
            if let last = segments.last, last.kind == kind, last.range.upperBound == start {
                segments[segments.count - 1] = TaskDisplaySegment(
                    kind: kind,
                    range: last.range.lowerBound..<text.count
                )
            } else {
                segments.append(TaskDisplaySegment(kind: kind, range: start..<text.count))
            }
        }

        let chars = Array(source)
        var index = 0
        while index < chars.count {
            let backtick = chars[index...].firstIndex(of: "`")
            let wikilink = findWikilinkOpen(in: chars, from: index)
            let markdownLink = findMarkdownLinkOpen(in: chars, from: index)
            // Whichever delimiter appears first wins.
            if let wikilink, (backtick == nil || wikilink < backtick!),
               (markdownLink == nil || wikilink < markdownLink!)
            {
                append(String(chars[index..<wikilink]), kind: .plain)
                if let close = findWikilinkClose(in: chars, from: wikilink + 2) {
                    let inner = String(chars[(wikilink + 2)..<close])
                    append(displayText(forWikilinkTarget: inner), kind: .link)
                    index = close + 2
                } else {
                    append("[[", kind: .plain)
                    index = wikilink + 2
                }
            } else if let markdownLink, (backtick == nil || markdownLink < backtick!) {
                if let (label, nextIndex) = parseMarkdownLink(in: chars, from: markdownLink) {
                    // A leading `!` belongs to the image syntax, never to
                    // the display text: `![alt](url)` shows `alt` as a link.
                    let bangStart = markdownLink > index && chars[markdownLink - 1] == "!"
                    if bangStart {
                        append(String(chars[index..<(markdownLink - 1)]), kind: .plain)
                    } else {
                        append(String(chars[index..<markdownLink]), kind: .plain)
                    }
                    append(label, kind: .link)
                    index = nextIndex
                } else {
                    // Not a well-formed `[label](url)`: keep the bracket
                    // literal and keep scanning after it.
                    append(String(chars[index...markdownLink]), kind: .plain)
                    index = markdownLink + 1
                }
            } else if let open = backtick {
                append(String(chars[index..<open]), kind: .plain)
                let close = chars[(open + 1)...].firstIndex(of: "`")
                if let close, close > open + 1 {
                    append(String(chars[(open + 1)..<close]), kind: .code)
                    index = close + 1
                } else if close == nil {
                    // Unmatched backtick stays literal; keep scanning after it
                    // so a later pair still parses.
                    append("`", kind: .plain)
                    index = open + 1
                } else {
                    // An empty pair stays literal.
                    append("``", kind: .plain)
                    index = open + 2
                }
            } else {
                append(String(chars[index...]), kind: .plain)
                break
            }
        }
        self.text = text
        self.segments = segments
    }
}

/// The display text of a wikilink target: the alias after the last `|` when
/// present, else the whole target.
private func displayText(forWikilinkTarget target: String) -> String {
    if let pipe = target.lastIndex(of: "|") {
        return String(target[target.index(after: pipe)...])
    }
    return target
}

private func findWikilinkOpen(in chars: [Character], from index: Int) -> Int? {
    var i = index
    while i + 1 < chars.count {
        if chars[i] == "[", chars[i + 1] == "[" {
            return i
        }
        i += 1
    }
    return nil
}

private func findWikilinkClose(in chars: [Character], from index: Int) -> Int? {
    var i = index
    while i + 1 < chars.count {
        if chars[i] == "]", chars[i + 1] == "]" {
            return i
        }
        i += 1
    }
    return nil
}

/// Finds the next single `[` that could open a Markdown `[label](url)` link,
/// skipping `[[` wikilink openers (those belong to the wikilink scan).
private func findMarkdownLinkOpen(in chars: [Character], from index: Int) -> Int? {
    var i = index
    while i < chars.count {
        if chars[i] == "[" {
            if i + 1 < chars.count, chars[i + 1] == "[" {
                i += 2
                continue
            }
            return i
        }
        i += 1
    }
    return nil
}

/// Parses a well-formed `[label](destination)` link at `open` (the `[`),
/// returning the display label and the index just past the closing `)`.
/// A double-quoted title after the destination — the form Keep captures
/// are stored in, `[💡](url "Open in Google Keep")` — parses the same way.
/// Returns nil when the brackets do not form a link, so the caller keeps
/// them literal.
private func parseMarkdownLink(in chars: [Character], from open: Int) -> (String, Int)? {
    var labelClose: Int?
    var i = open + 1
    while i < chars.count {
        if chars[i] == "]" {
            labelClose = i
            break
        }
        i += 1
    }
    guard let labelClose,
          labelClose + 1 < chars.count,
          chars[labelClose + 1] == "("
    else {
        return nil
    }
    // The destination runs to the first whitespace or `)`. An empty
    // destination (`[label]()`) is malformed, like an unclosed link.
    var j = labelClose + 2
    while j < chars.count, chars[j] != ")", !chars[j].isWhitespace {
        j += 1
    }
    guard j > labelClose + 2 else {
        return nil
    }
    if j < chars.count, chars[j] == ")" {
        return (String(chars[(open + 1)..<labelClose]), j + 1)
    }
    // Otherwise a double-quoted title must follow, then the close.
    while j < chars.count, chars[j] != ")", chars[j].isWhitespace {
        j += 1
    }
    guard j < chars.count, chars[j] == "\"" else {
        return nil
    }
    var titleClose: Int?
    var k = j + 1
    while k < chars.count {
        if chars[k] == "\"" {
            titleClose = k
            break
        }
        k += 1
    }
    guard let titleClose else {
        return nil
    }
    var end = titleClose + 1
    while end < chars.count, chars[end].isWhitespace {
        end += 1
    }
    guard end < chars.count, chars[end] == ")" else {
        return nil
    }
    return (String(chars[(open + 1)..<labelClose]), end + 1)
}
