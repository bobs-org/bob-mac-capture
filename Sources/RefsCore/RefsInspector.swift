import Foundation

/// The `bob ref show <path> -f json -c` envelope (schema version 1) the
/// inspector hydrates from. Only the note path, the parsed annotations,
/// the `## Tasks` lines, and the annotations status matter here; every
/// other key is ignored. All three inspector fields are lossy and use
/// `decodeIfPresent`, and undecodable rows are skipped instead of
/// failing the whole response.
public struct RefsShowResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public let schemaVersion: Int
    public let refs: [RefsShowRow]

    public init(schemaVersion: Int, refs: [RefsShowRow] = []) {
        self.schemaVersion = schemaVersion
        self.refs = refs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case refs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let rows = try container.decodeIfPresent(
            [LossyShowRow].self,
            forKey: .refs
        ) ?? []
        refs = rows.compactMap(\.row)
    }
}

/// One shown reference row: the note path plus its content. `path` falls
/// back to empty so a malformed row degrades instead of failing the
/// envelope; callers match rows by path and ignore empty ones.
public struct RefsShowRow: Decodable, Equatable, Sendable {
    public let path: String
    public let annotations: [RefsShowAnnotation]
    public let tasks: [RefsShowTask]
    public let annotationsStatus: String?

    public init(
        path: String,
        annotations: [RefsShowAnnotation] = [],
        tasks: [RefsShowTask] = [],
        annotationsStatus: String? = nil
    ) {
        self.path = path
        self.annotations = annotations
        self.tasks = tasks
        self.annotationsStatus = annotationsStatus
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case annotations
        case tasks
        case annotationsStatus = "annotations_status"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        annotations = try container.decodeIfPresent(
            [RefsShowAnnotation].self,
            forKey: .annotations
        ) ?? []
        tasks = try container.decodeIfPresent(
            [RefsShowTask].self,
            forKey: .tasks
        ) ?? []
        annotationsStatus = try container.decodeIfPresent(
            String.self,
            forKey: .annotationsStatus
        )
    }

    /// Up to 3 commented highlights, in note order: the inspector's
    /// "Your notes" block. Images and standalone notes never appear here.
    public var commentedHighlights: [RefsShowAnnotation] {
        Array(annotations.filter(\.hasComment).prefix(3))
    }

    /// How many commented highlights exist beyond the shown three, for
    /// the "+N more" line.
    public var remainingCommentCount: Int {
        max(annotations.filter(\.hasComment).count - 3, 0)
    }

    /// Open `## Tasks` lines, for the "N open" fact.
    public var openTasks: [RefsShowTask] {
        tasks.filter { !$0.checked }
    }
}

/// One parsed annotation: the author's words (`quote`) and the user's
/// words (`comment`) travel in separate fields, exactly as `bob ref
/// show` keeps them.
public struct RefsShowAnnotation: Decodable, Equatable, Sendable {
    public let pageLabel: String?
    public let kind: String
    public let quote: String?
    public let comment: String?

    public init(
        pageLabel: String? = nil,
        kind: String = "highlight",
        quote: String? = nil,
        comment: String? = nil
    ) {
        self.pageLabel = pageLabel
        self.kind = kind
        self.quote = quote
        self.comment = comment
    }

    private enum CodingKeys: String, CodingKey {
        case pageLabel = "page_label"
        case kind
        case quote
        case comment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageLabel = try container.decodeIfPresent(String.self, forKey: .pageLabel)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "highlight"
        quote = try container.decodeIfPresent(String.self, forKey: .quote)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
    }

    /// A highlight carrying a user comment: the only annotation kind the
    /// inspector's "Your notes" block shows.
    public var hasComment: Bool {
        guard kind == "highlight" else {
            return false
        }
        guard let comment, !comment.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return false
        }
        return true
    }
}

/// One parsed `## Tasks` line: the checkbox state, its mark, and the
/// text with block links and inline fields stripped.
public struct RefsShowTask: Decodable, Equatable, Sendable {
    public let checked: Bool
    public let mark: String
    public let text: String

    public init(checked: Bool = false, mark: String = "", text: String = "") {
        self.checked = checked
        self.mark = mark
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case checked
        case mark
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        mark = try container.decodeIfPresent(String.self, forKey: .mark) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

/// One `refs` array element that never fails: an undecodable row becomes
/// nil and is dropped, so a single bad row cannot fail the inspector.
private struct LossyShowRow: Decodable {
    let row: RefsShowRow?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        row = try? container.decode(RefsShowRow.self)
    }
}

/// A Bottom-line or Abstract excerpt: either one paragraph or up to 3
/// bullets. The view labels bottom-line excerpts `SUMMARY` and paper
/// excerpts `ABSTRACT`.
public struct RefsSummary: Equatable, Sendable {
    public let label: String
    public let paragraph: String?
    public let bullets: [String]

    public init(label: String, paragraph: String? = nil, bullets: [String] = []) {
        self.label = label
        self.paragraph = paragraph
        self.bullets = bullets
    }
}

/// Extracts Bottom-line and Abstract excerpts from PDF lead text (the
/// first pages' text the intrinsics loader reads with PDFKit). Pure
/// string work, so it stays in RefsCore and runs on Linux.
public enum RefsSummaryExtractor {
    /// Maximum characters of a Bottom-line paragraph.
    public static let bottomLineParagraphCap = 360
    /// Maximum bullets of a Bottom-line list.
    public static let bottomLineBulletCap = 3
    /// Maximum characters of one Bottom-line bullet.
    public static let bottomLineBulletCapChars = 140
    /// Maximum characters of an Abstract excerpt.
    public static let abstractCap = 420

    /// The first paragraph or up to 3 bullets under a Bottom line (or
    /// TL;DR, Summary, Executive summary, Key findings) heading, or nil
    /// when no such heading exists. The excerpt ends at the next blank
    /// line or the next heading-like line.
    public static func bottomLine(fromLeadText text: String) -> RefsSummary? {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { isBottomLineHeading($0) }) else {
            return nil
        }
        var excerpt: [String] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if excerpt.isEmpty {
                    continue
                }
                break
            }
            if isHeadingLike(line) {
                break
            }
            excerpt.append(line)
        }
        let excerptLines = excerpt.drop(while: {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        })
        guard !excerptLines.isEmpty else {
            return nil
        }
        if excerptLines.allSatisfy({ isBullet($0) }) {
            let bullets = excerptLines.prefix(bottomLineBulletCap).map {
                truncateAtWordBoundary(
                    stripBullet($0),
                    cap: bottomLineBulletCapChars
                )
            }.filter { !$0.isEmpty }
            guard !bullets.isEmpty else {
                return nil
            }
            return RefsSummary(label: "SUMMARY", bullets: bullets)
        }
        let paragraph = truncateAtWordBoundary(
            excerptLines.joined(separator: " "),
            cap: bottomLineParagraphCap
        )
        guard !paragraph.isEmpty else {
            return nil
        }
        return RefsSummary(label: "SUMMARY", paragraph: paragraph)
    }

    /// Up to 420 characters after an "Abstract" line, or nil when no
    /// Abstract heading exists. The heading is a line equal to
    /// "Abstract" or one beginning "Abstract:" or "Abstract—".
    public static func abstract(fromLeadText text: String) -> RefsSummary? {
        let lines = text.components(separatedBy: "\n")
        var startIndex: Int?
        var remainder = ""
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.caseInsensitiveCompare("Abstract") == .orderedSame {
                startIndex = index + 1
                break
            }
            let lowered = trimmed.lowercased()
            for marker in ["abstract:", "abstract—", "abstract–", "abstract-"] {
                if lowered.hasPrefix(marker) {
                    startIndex = index + 1
                    remainder = String(trimmed.dropFirst(marker.count)).trimmingCharacters(
                        in: .whitespaces
                    )
                    break
                }
            }
            if startIndex != nil {
                break
            }
        }
        guard let start = startIndex else {
            return nil
        }
        var parts: [String] = []
        if !remainder.isEmpty {
            parts.append(remainder)
        }
        if start < lines.count {
            for line in lines[start...] {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    if parts.count <= (remainder.isEmpty ? 0 : 1) {
                        continue
                    }
                    break
                }
                if isHeadingLike(line) {
                    break
                }
                parts.append(trimmed)
            }
        }
        guard !parts.isEmpty else {
            return nil
        }
        let paragraph = truncateAtWordBoundary(
            parts.joined(separator: " "),
            cap: abstractCap
        )
        guard !paragraph.isEmpty else {
            return nil
        }
        return RefsSummary(label: "ABSTRACT", paragraph: paragraph)
    }

    /// Whether a line opens a Bottom-line section: an optional numeric
    /// prefix (`1`, `2.1`) plus one of the known headings, case-
    /// insensitive, with an optional trailing colon.
    public static func isBottomLineHeading(_ line: String) -> Bool {
        let names = "bottom line|tl;?dr|summary|executive summary|key findings"
        let pattern = "^\\s*(\\d+(\\.\\d+)*\\s*)?(" + names + ")\\s*:?\\s*$"
        return line.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// Whether a line looks like a section heading: a Markdown `#`
    /// heading, or a short line (at most 8 words) with no period and no
    /// terminal punctuation. A backstop so excerpts stop at the next
    /// section instead of running into it.
    public static func isHeadingLike(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 80 else {
            return false
        }
        if trimmed.hasPrefix("#") {
            return true
        }
        if isBottomLineHeading(line) {
            return true
        }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return false
        }
        if trimmed.contains(".") {
            return false
        }
        let words = trimmed.split(separator: " ")
        guard words.count <= 8 else {
            return false
        }
        guard let first = trimmed.first, first.isUppercase || first.isNumber else {
            return false
        }
        return true
    }

    private static func isBullet(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return false
        }
        for marker in ["- ", "* ", "• "] {
            if trimmed.hasPrefix(marker) {
                return true
            }
        }
        if trimmed.first == "-" || trimmed.first == "*" || trimmed.first == "•" {
            return true
        }
        let pattern = #"^\d+[.)]\s+\S"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private static func stripBullet(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "• ", "-", "*", "•"] {
            if trimmed.hasPrefix(marker) {
                trimmed = String(trimmed.dropFirst(marker.count)).trimmingCharacters(
                    in: .whitespaces
                )
                break
            }
        }
        if let range = trimmed.range(
            of: #"^\d+[.)]\s+"#,
            options: .regularExpression
        ) {
            trimmed = String(trimmed[range.upperBound...]).trimmingCharacters(
                in: .whitespaces
            )
        }
        return trimmed
    }

    /// Cuts text at a word boundary with "…": the longest prefix within
    /// `cap` characters that ends on whitespace, plus "…". Text within
    /// the cap returns unchanged.
    public static func truncateAtWordBoundary(_ text: String, cap: Int) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > cap else {
            return collapsed
        }
        let prefix = String(collapsed.prefix(cap))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "…"
        }
        return prefix + "…"
    }
}

/// A reading-time estimate: 230 words per minute, minimum 1 minute,
/// rounded to the nearest 5 at 20 minutes or more, plus Pomodoros at 25
/// minutes each. Always labeled as an estimate, never progress.
public struct RefsReadingTime: Equatable, Sendable {
    public let minutes: Int
    public let pomodoros: Int

    /// Words per minute.
    public static let wordsPerMinute = 230
    /// Pomodoro length in minutes.
    public static let pomodoroMinutes = 25
    /// Estimates at or above this long round to the nearest 5 minutes.
    public static let roundingThresholdMinutes = 20
    public static let roundingStepMinutes = 5

    public init(minutes: Int, pomodoros: Int) {
        self.minutes = minutes
        self.pomodoros = pomodoros
    }

    public static func estimate(words: Int) -> RefsReadingTime {
        let raw = max(1, Int((Double(max(words, 0)) / Double(wordsPerMinute)).rounded()))
        let minutes: Int
        if raw >= roundingThresholdMinutes {
            let step = roundingStepMinutes
            minutes = ((raw + step / 2) / step) * step
        } else {
            minutes = raw
        }
        let pomodoros = max(1, (minutes + pomodoroMinutes - 1) / pomodoroMinutes)
        return RefsReadingTime(minutes: minutes, pomodoros: pomodoros)
    }

    /// "≈ 17 min · 1 Pomodoro".
    public var formatted: String {
        let pomodoroWord = pomodoros == 1 ? "Pomodoro" : "Pomodoros"
        return "≈ \(minutes) min · \(pomodoros) \(pomodoroWord)"
    }
}

/// Cleans PDF outline headings for the inspector's Contents block and
/// for T3 heading matches: trims, drops empties and Contents/Table of
/// Contents, dedupes, and keeps at most 6.
public enum RefsOutline {
    /// Maximum headings kept.
    public static let maxHeadings = 6

    public static func clean(_ titles: [String]) -> [String] {
        var seen = Set<String>()
        var cleaned: [String] = []
        for raw in titles {
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                continue
            }
            let lowered = title.lowercased()
            guard lowered != "contents" && lowered != "table of contents" else {
                continue
            }
            guard seen.insert(title).inserted else {
                continue
            }
            cleaned.append(title)
            if cleaned.count == maxHeadings {
                break
            }
        }
        return cleaned
    }
}
