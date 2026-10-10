import Foundation

/// Decoded `bob capture-pomodoros --tasks --format json` snapshot: today's
/// agenda painted from the Pomodoro ledger. bob owns every fact here (roles,
/// numbering, link resolution, task blocks, line kinds, log tags); the app
/// only decodes, measures, plans folds, and draws.
///
/// Every field decodes with `decodeIfPresent` and a safe default, so a
/// payload from an older bob (or one without `--tasks`) still decodes:
/// entries without agenda fields land with empty notes and items, and
/// unknown enum strings land on `.other` instead of failing the whole
/// snapshot.
public struct CaptureAgendaSnapshot: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let schemaVersion: Int
    public let date: String?
    public let completedSummary: CaptureAgendaCompletedSummary
    public let pomodoros: [CaptureAgendaPomodoro]
    public let warnings: [String]

    public init(
        ok: Bool = false,
        schemaVersion: Int = 1,
        date: String? = nil,
        completedSummary: CaptureAgendaCompletedSummary = CaptureAgendaCompletedSummary(),
        pomodoros: [CaptureAgendaPomodoro] = [],
        warnings: [String] = []
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.date = date
        self.completedSummary = completedSummary
        self.pomodoros = pomodoros
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        date = try container.decodeIfPresent(String.self, forKey: .date)
        completedSummary = try container.decodeIfPresent(
            CaptureAgendaCompletedSummary.self,
            forKey: .completedSummary
        ) ?? CaptureAgendaCompletedSummary()
        pomodoros = try container.decodeIfPresent(
            [CaptureAgendaPomodoro].self,
            forKey: .pomodoros
        ) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    /// The `isCurrent` entry's `taskLinkCount`, or nil when there is no
    /// current entry or the field is absent (older bob). Matches
    /// `CapturePomodorosResponse`.
    public var currentTaskLinkCount: Int? {
        pomodoros.first(where: { $0.isCurrent })?.taskLinkCount
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case date
        case completedSummary = "completed_summary"
        case pomodoros
        case warnings
    }
}

/// Completed entries in today's ledger, and the summed minutes of their
/// time ranges.
public struct CaptureAgendaCompletedSummary: Decodable, Equatable, Sendable {
    public let count: Int
    public let minutes: Int

    public init(count: Int = 0, minutes: Int = 0) {
        self.count = count
        self.minutes = minutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case minutes
    }
}

/// One ledger entry in the agenda. Unknown JSON keys (the ledger fields the
/// agenda never reads, such as `child_count` or `time_range`) are ignored.
public struct CaptureAgendaPomodoro: Decodable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let isCurrent: Bool
    public let taskLinkCount: Int?
    public let role: CaptureAgendaRole
    public let startsAt: String?
    public let endsAt: String?
    public let retiredLinkCount: Int
    public let notes: [CaptureAgendaLine]
    public let items: [CaptureAgendaItem]
    public let slug: String?
    public let selectable: Bool

    public init(
        line: Int = 0,
        name: String? = nil,
        isCurrent: Bool = false,
        taskLinkCount: Int? = nil,
        role: CaptureAgendaRole = .open,
        startsAt: String? = nil,
        endsAt: String? = nil,
        retiredLinkCount: Int = 0,
        notes: [CaptureAgendaLine] = [],
        items: [CaptureAgendaItem] = [],
        slug: String? = nil,
        selectable: Bool = false
    ) {
        self.line = line
        self.name = name
        self.isCurrent = isCurrent
        self.taskLinkCount = taskLinkCount
        self.role = role
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.retiredLinkCount = retiredLinkCount
        self.notes = notes
        self.items = items
        self.slug = slug
        self.selectable = selectable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        taskLinkCount = try container.decodeIfPresent(Int.self, forKey: .taskLinkCount)
        // Entries from a bob without `--tasks` predate roles; `.open` is
        // the neutral "an open entry of unknown role" default.
        role = try container.decodeIfPresent(CaptureAgendaRole.self, forKey: .role) ?? .open
        startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(String.self, forKey: .endsAt)
        retiredLinkCount = try container.decodeIfPresent(Int.self, forKey: .retiredLinkCount) ?? 0
        notes = try container.decodeIfPresent([CaptureAgendaLine].self, forKey: .notes) ?? []
        items = try container.decodeIfPresent([CaptureAgendaItem].self, forKey: .items) ?? []
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        selectable = try container.decodeIfPresent(Bool.self, forKey: .selectable) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case isCurrent = "is_current"
        case taskLinkCount = "task_link_count"
        case role
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case retiredLinkCount = "retired_link_count"
        case notes
        case items
        case slug
        case selectable
    }
}

/// One Task Link line on an open entry, with its resolved task block.
public struct CaptureAgendaItem: Decodable, Equatable, Sendable {
    public let index: Int?
    public let ledgerLine: Int
    public let ledgerDepth: Int
    public let marker: CaptureAgendaMarker
    public let blockLink: String
    public let resolution: CaptureAgendaResolution
    public let relativeTarget: String?
    public let line: Int?
    public let blockID: String
    public let text: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let statusType: String?
    public let lines: [CaptureAgendaLine]
    public let linesTruncated: Int
    public let ledgerNotes: [CaptureAgendaLine]
    public let warning: String?

    public init(
        index: Int? = nil,
        ledgerLine: Int = 0,
        ledgerDepth: Int = 1,
        marker: CaptureAgendaMarker = .plain,
        blockLink: String = "",
        resolution: CaptureAgendaResolution = .unreadable,
        relativeTarget: String? = nil,
        line: Int? = nil,
        blockID: String = "",
        text: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        statusType: String? = nil,
        lines: [CaptureAgendaLine] = [],
        linesTruncated: Int = 0,
        ledgerNotes: [CaptureAgendaLine] = [],
        warning: String? = nil
    ) {
        self.index = index
        self.ledgerLine = ledgerLine
        self.ledgerDepth = ledgerDepth
        self.marker = marker
        self.blockLink = blockLink
        self.resolution = resolution
        self.relativeTarget = relativeTarget
        self.line = line
        self.blockID = blockID
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.statusType = statusType
        self.lines = lines
        self.linesTruncated = linesTruncated
        self.ledgerNotes = ledgerNotes
        self.warning = warning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        ledgerLine = try container.decodeIfPresent(Int.self, forKey: .ledgerLine) ?? 0
        ledgerDepth = try container.decodeIfPresent(Int.self, forKey: .ledgerDepth) ?? 1
        marker = try container.decodeIfPresent(CaptureAgendaMarker.self, forKey: .marker) ?? .plain
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink) ?? ""
        resolution = try container.decodeIfPresent(
            CaptureAgendaResolution.self,
            forKey: .resolution
        ) ?? .unreadable
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text)
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        statusType = try container.decodeIfPresent(String.self, forKey: .statusType)
        lines = try container.decodeIfPresent([CaptureAgendaLine].self, forKey: .lines) ?? []
        linesTruncated = try container.decodeIfPresent(Int.self, forKey: .linesTruncated) ?? 0
        ledgerNotes = try container.decodeIfPresent(
            [CaptureAgendaLine].self,
            forKey: .ledgerNotes
        ) ?? []
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case ledgerLine = "ledger_line"
        case ledgerDepth = "ledger_depth"
        case marker
        case blockLink = "block_link"
        case resolution
        case relativeTarget = "relative_target"
        case line
        case blockID = "block_id"
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case statusType = "status_type"
        case lines
        case linesTruncated = "lines_truncated"
        case ledgerNotes = "ledger_notes"
        case warning
    }
}

/// One display line inside a task block, a ledger note, or an entry note.
public struct CaptureAgendaLine: Decodable, Equatable, Sendable {
    public let text: String
    public let depth: Int
    public let kind: CaptureAgendaLineKind
    public let statusSymbol: String?
    public let log: CaptureAgendaLog?

    public init(
        text: String = "",
        depth: Int = 1,
        kind: CaptureAgendaLineKind = .bullet,
        statusSymbol: String? = nil,
        log: CaptureAgendaLog? = nil
    ) {
        self.text = text
        self.depth = depth
        self.kind = kind
        self.statusSymbol = statusSymbol
        self.log = log
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        depth = try container.decodeIfPresent(Int.self, forKey: .depth) ?? 1
        kind = try container.decodeIfPresent(CaptureAgendaLineKind.self, forKey: .kind) ?? .bullet
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        log = try container.decodeIfPresent(CaptureAgendaLog.self, forKey: .log)
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case depth
        case kind
        case statusSymbol = "status_symbol"
        case log
    }
}

/// Entry role in the agenda, from the ledger facts only. Unknown strings
/// decode to `.other` instead of failing the snapshot.
public enum CaptureAgendaRole: Hashable, Sendable, Decodable {
    case current
    case next
    case later
    case open
    case completed
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "current":
            self = .current
        case "next":
            self = .next
        case "later":
            self = .later
        case "open":
            self = .open
        case "completed":
            self = .completed
        default:
            self = .other(raw)
        }
    }
}

/// Display-line kind. Unknown strings decode to `.other`.
public enum CaptureAgendaLineKind: Equatable, Sendable, Decodable {
    case bullet
    case task
    case text
    case code
    case logMarker
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "bullet":
            self = .bullet
        case "task":
            self = .task
        case "text":
            self = .text
        case "code":
            self = .code
        case "log_marker":
            self = .logMarker
        default:
            self = .other(raw)
        }
    }
}

/// `work` or `schedule` log tag on a display line. Unknown strings decode
/// to `.other`.
public enum CaptureAgendaLog: Equatable, Sendable, Decodable {
    case work
    case schedule
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "work":
            self = .work
        case "schedule":
            self = .schedule
        default:
            self = .other(raw)
        }
    }
}

/// How one Task Link resolved. Unknown strings decode to `.other`.
public enum CaptureAgendaResolution: Equatable, Sendable, Decodable {
    case resolved
    case missingNote
    case ambiguousNote
    case missingBlock
    case duplicateBlock
    case notATask
    case unreadable
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "resolved":
            self = .resolved
        case "missing_note":
            self = .missingNote
        case "ambiguous_note":
            self = .ambiguousNote
        case "missing_block":
            self = .missingBlock
        case "duplicate_block":
            self = .duplicateBlock
        case "not_a_task":
            self = .notATask
        case "unreadable":
            self = .unreadable
        default:
            self = .other(raw)
        }
    }
}

/// Link spelling: plain `[[T]]`, deferred `[[T]]#`, or embedded `![[T]]`.
/// Unknown strings decode to `.other`.
public enum CaptureAgendaMarker: Equatable, Sendable, Decodable {
    case plain
    case deferred
    case embedded
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "plain":
            self = .plain
        case "deferred":
            self = .deferred
        case "embedded":
            self = .embedded
        default:
            self = .other(raw)
        }
    }
}

/// One `captureAgenda` fetch outcome: byte-identical output is `.unchanged`
/// (no decode happened), anything else is `.changed` with the snapshot and
/// the raw stdout bytes it came from.
public enum CaptureAgendaFetch: Equatable, Sendable {
    case unchanged
    case changed(snapshot: CaptureAgendaSnapshot, bytes: Data)
}
