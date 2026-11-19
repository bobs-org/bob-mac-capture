import Foundation

/// One cancel-history phrase from `bob logs list --format json`.
///
/// All fields decode additively (`decodeIfPresent`): an older or newer bob
/// that omits a field still decodes, so the band can keep working.
public struct LogRecallPhrase: Decodable, Equatable, Sendable {
    public let text: String
    public let key: String
    public let uses: Int
    public let lastUsed: String
    public let score: Double
    public let recencyRank: Int
    public let match: LogRecallMatch?

    public init(
        text: String,
        key: String,
        uses: Int = 1,
        lastUsed: String = "",
        score: Double = 0,
        recencyRank: Int = 0,
        match: LogRecallMatch? = nil
    ) {
        self.text = text
        self.key = key
        self.uses = uses
        self.lastUsed = lastUsed
        self.score = score
        self.recencyRank = recencyRank
        self.match = match
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        uses = try container.decodeIfPresent(Int.self, forKey: .uses) ?? 1
        lastUsed = try container.decodeIfPresent(String.self, forKey: .lastUsed) ?? ""
        score = try container.decodeIfPresent(Double.self, forKey: .score) ?? 0
        recencyRank =
            try container.decodeIfPresent(Int.self, forKey: .recencyRank) ?? Int.max
        match = try container.decodeIfPresent(LogRecallMatch.self, forKey: .match)
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case key
        case uses
        case lastUsed = "last_used"
        case score
        case recencyRank = "recency_rank"
        case match
    }
}

/// Literal match tier from `bob logs list -q`, in canonical order.
public enum LogRecallMatch: String, Decodable, Equatable, Sendable {
    case exact
    case prefix
    case word
    case substring
}

/// Per-kind exclusion counts from `bob logs list`.
public struct LogRecallExcluded: Decodable, Equatable, Sendable {
    public let machine: Int
    public let blank: Int
    public let tooLong: Int
    public let copies: Int
    public let unparsed: Int

    public init(
        machine: Int = 0,
        blank: Int = 0,
        tooLong: Int = 0,
        copies: Int = 0,
        unparsed: Int = 0
    ) {
        self.machine = machine
        self.blank = blank
        self.tooLong = tooLong
        self.copies = copies
        self.unparsed = unparsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        machine = try container.decodeIfPresent(Int.self, forKey: .machine) ?? 0
        blank = try container.decodeIfPresent(Int.self, forKey: .blank) ?? 0
        tooLong = try container.decodeIfPresent(Int.self, forKey: .tooLong) ?? 0
        copies = try container.decodeIfPresent(Int.self, forKey: .copies) ?? 0
        unparsed = try container.decodeIfPresent(Int.self, forKey: .unparsed) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case machine
        case blank
        case tooLong = "too_long"
        case copies
        case unparsed
    }
}

/// One log kind section from `bob logs list`.
public struct LogRecallLog: Decodable, Equatable, Sendable {
    public let kind: String
    public let label: String
    public let emoji: String
    public let recencyPrecision: String
    public let phrasesTotal: Int
    public let truncated: Bool
    public let excluded: LogRecallExcluded
    public let phrases: [LogRecallPhrase]

    public init(
        kind: String,
        label: String = "",
        emoji: String = "",
        recencyPrecision: String = "day",
        phrasesTotal: Int = 0,
        truncated: Bool = false,
        excluded: LogRecallExcluded = LogRecallExcluded(),
        phrases: [LogRecallPhrase] = []
    ) {
        self.kind = kind
        self.label = label
        self.emoji = emoji
        self.recencyPrecision = recencyPrecision
        self.phrasesTotal = phrasesTotal
        self.truncated = truncated
        self.excluded = excluded
        self.phrases = phrases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        recencyPrecision =
            try container.decodeIfPresent(String.self, forKey: .recencyPrecision) ?? "day"
        phrasesTotal = try container.decodeIfPresent(Int.self, forKey: .phrasesTotal) ?? 0
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        excluded =
            try container.decodeIfPresent(LogRecallExcluded.self, forKey: .excluded)
            ?? LogRecallExcluded()
        phrases =
            try container.decodeIfPresent([LogRecallPhrase].self, forKey: .phrases) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case label
        case emoji
        case recencyPrecision = "recency_precision"
        case phrasesTotal = "phrases_total"
        case truncated
        case excluded
        case phrases
    }
}

/// Top-level `bob logs list --format json` envelope (schema 1).
public struct LogRecallCatalog: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let ok: Bool
    public let query: String?
    public let halfLifeDays: Double
    public let logs: [LogRecallLog]
    public let warnings: [String]

    public init(
        schemaVersion: Int = 1,
        ok: Bool = true,
        query: String? = nil,
        halfLifeDays: Double = 7,
        logs: [LogRecallLog] = [],
        warnings: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.ok = ok
        self.query = query
        self.halfLifeDays = halfLifeDays
        self.logs = logs
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        query = try container.decodeIfPresent(String.self, forKey: .query)
        halfLifeDays =
            try container.decodeIfPresent(Double.self, forKey: .halfLifeDays) ?? 7
        logs = try container.decodeIfPresent([LogRecallLog].self, forKey: .logs) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case query
        case halfLifeDays = "half_life_days"
        case logs
        case warnings
    }

    /// Cancel phrases in catalog order (newest pin + frecency, as bob sent).
    public func cancelPhrases() -> [LogRecallPhrase] {
        logs.first(where: { $0.kind == "cancel" })?.phrases ?? []
    }
}
