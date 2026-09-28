import Foundation

/// One styled span of active-task display text: plain prose, a `code` span
/// (backticks hidden), or a `link` (wikilink brackets hidden, alias resolved).
/// `range` is a `Character`-offset range into `ActiveTaskDisplayText.text`.
public struct ActiveTaskDisplaySegment: Equatable, Sendable {
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

/// Parses task text for display: code spans and `[[wikilinks]]` become styled
/// segments with their delimiters dropped, and everything else stays literal
/// plain text. All fuzzy matching runs on `text`, so highlight offsets map
/// directly onto `segments`.
public struct ActiveTaskDisplayText: Equatable, Sendable {
    public let text: String
    public let segments: [ActiveTaskDisplaySegment]

    public init(parsing source: String) {
        var text = ""
        var segments: [ActiveTaskDisplaySegment] = []
        // Appends display characters, merging into the trailing segment when
        // the kind matches so segments tile `text` exactly.
        func append(_ display: String, kind: ActiveTaskDisplaySegment.Kind) {
            guard !display.isEmpty else {
                return
            }
            let start = text.count
            text += display
            if let last = segments.last, last.kind == kind, last.range.upperBound == start {
                segments[segments.count - 1] = ActiveTaskDisplaySegment(
                    kind: kind,
                    range: last.range.lowerBound..<text.count
                )
            } else {
                segments.append(ActiveTaskDisplaySegment(kind: kind, range: start..<text.count))
            }
        }

        let chars = Array(source)
        var index = 0
        while index < chars.count {
            let backtick = chars[index...].firstIndex(of: "`")
            let wikilink = findWikilinkOpen(in: chars, from: index)
            // Whichever delimiter appears first wins.
            if let wikilink, backtick == nil || wikilink < backtick! {
                append(String(chars[index..<wikilink]), kind: .plain)
                if let close = findWikilinkClose(in: chars, from: wikilink + 2) {
                    let inner = String(chars[(wikilink + 2)..<close])
                    append(displayText(forWikilinkTarget: inner), kind: .link)
                    index = close + 2
                } else {
                    append("[[", kind: .plain)
                    index = wikilink + 2
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
