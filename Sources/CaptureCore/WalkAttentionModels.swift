import Foundation

/// One walk family in bob's `walks` attention report. Unknown family
/// strings decode to `.other` and are ignored by the presentation, never
/// thrown, so a future bob family cannot break an older app.
public enum WalkAttentionFamily: Hashable, Equatable, Sendable {
    case review
    case lanes
    case bank
    case other(String)

    /// Canonical single-letter family key from `docs/walks.md`: s, w, b.
    public var letter: String? {
        switch self {
        case .review: return "s"
        case .lanes: return "w"
        case .bank: return "b"
        case .other: return nil
        }
    }

    public init(family: String) {
        switch family {
        case "s": self = .review
        case "w": self = .lanes
        case "b": self = .bank
        default: self = .other(family)
        }
    }
}

/// One family's attention row from `bob walks --format json`. `counts`
/// carries the display count for the `s` (commitments) and `b` (waiting)
/// marks; `w` stays a bare mark because its label already lists the over
/// lanes. Counts come from bob's JSON, never from the app.
public struct WalkAttention: Decodable, Equatable, Sendable {
    public let family: WalkAttentionFamily
    public let name: String
    public let available: Bool
    public let attention: Bool
    public let tier: String?
    public let label: String?
    public let reason: String?
    /// Display count for the `s` (commitments) and `b` (waiting) marks.
    /// Nil for `w` and when bob omits the field.
    public let count: Int?

    public init(
        family: WalkAttentionFamily = .other(""),
        name: String = "",
        available: Bool = false,
        attention: Bool = false,
        tier: String? = nil,
        label: String? = nil,
        reason: String? = nil,
        count: Int? = nil
    ) {
        self.family = family
        self.name = name
        self.available = available
        self.attention = attention
        self.tier = tier
        self.label = label
        self.reason = reason
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawFamily = try container.decodeIfPresent(String.self, forKey: .family) ?? ""
        family = WalkAttentionFamily(family: rawFamily)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? false
        attention = try container.decodeIfPresent(Bool.self, forKey: .attention) ?? false
        tier = try container.decodeIfPresent(String.self, forKey: .tier)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        // Counts live under `counts` with per-family keys: `commitments`
        // for `s`, `waiting` for `b`. A missing block means no count.
        if let counts = try? container.decodeIfPresent(
            WalkAttentionCounts.self, forKey: .counts)
        {
            switch family {
            case .review: count = counts.commitments
            case .bank: count = counts.waiting
            case .lanes, .other: count = nil
            }
        } else {
            count = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case family
        case name
        case available
        case attention
        case tier
        case label
        case reason
        case counts
    }
}

private struct WalkAttentionCounts: Decodable {
    let walk: Int?
    let commitments: Int?
    let waiting: Int?
}

/// The whole `bob walks --format json` report (schema 1).
public struct WalkAttentionSnapshot: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let date: String?
    public let walks: [WalkAttention]

    public init(
        schemaVersion: Int = 1,
        date: String? = nil,
        walks: [WalkAttention] = []
    ) {
        self.schemaVersion = schemaVersion
        self.date = date
        self.walks = walks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        date = try container.decodeIfPresent(String.self, forKey: .date)
        walks = try container.decodeIfPresent([WalkAttention].self, forKey: .walks) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case date
        case walks
    }
}

extension WalkAttentionSnapshot: SchemaVersioned {}

/// One `walkAttention` fetch outcome: byte-identical output is `.unchanged`
/// (no decode happened), anything else is `.changed` with the snapshot and
/// the raw stdout bytes it came from.
public enum WalkAttentionFetch: Equatable, Sendable {
    case unchanged
    case changed(snapshot: WalkAttentionSnapshot, bytes: Data)
}
