import Foundation

/// An Event Task's pre/post-event buffer, decoded from bob's additive
/// `buffer` object (`capture-pomodoros --tasks` rows and `items[].event`,
/// capture `event_run.events[]` and `event_conflict.event`). The buffered
/// span is what the event occupies; the meeting span is when it happens.
///
/// Agenda payloads carry `starts_at`/`ends_at` (the buffered span);
/// capture payloads carry only the minute counts and `time_range`.
/// Every field decodes tolerantly: a malformed buffer decodes as nil so
/// it never fails the whole snapshot.
public struct CaptureEventBuffer: Codable, Equatable, Sendable, Hashable {
    public let beforeMinutes: Int
    public let afterMinutes: Int
    public let timeRange: String?
    public let startsAt: String?
    public let endsAt: String?

    public init(
        beforeMinutes: Int = 0,
        afterMinutes: Int = 0,
        timeRange: String? = nil,
        startsAt: String? = nil,
        endsAt: String? = nil
    ) {
        self.beforeMinutes = max(0, beforeMinutes)
        self.afterMinutes = max(0, afterMinutes)
        self.timeRange = timeRange
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beforeMinutes = max(0, try container.decodeIfPresent(Int.self, forKey: .beforeMinutes) ?? 0)
        afterMinutes = max(0, try container.decodeIfPresent(Int.self, forKey: .afterMinutes) ?? 0)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(String.self, forKey: .endsAt)
    }

    private enum CodingKeys: String, CodingKey {
        case beforeMinutes = "before_minutes"
        case afterMinutes = "after_minutes"
        case timeRange = "time_range"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }

    /// True when neither side reserves time: renders and spans stay
    /// exactly as without a buffer.
    public var isEmpty: Bool {
        beforeMinutes <= 0 && afterMinutes <= 0
    }

    /// Human label with a typographic minus, matching bob: `"−30m"`,
    /// `"+15m"`, or `"−30m +15m"`. Nil when empty.
    public func label() -> String? {
        switch (beforeMinutes, afterMinutes) {
        case (0, 0):
            return nil
        case (let before, 0):
            return "\u{2212}\(before)m"
        case (0, let after):
            return "+\(after)m"
        case (let before, let after):
            return "\u{2212}\(before)m +\(after)m"
        }
    }

    /// Label of one buffered side, `"−30m"` or `"+15m"`. Nil when that
    /// side is zero.
    public func partLabel(_ part: CaptureBufferPart) -> String? {
        switch part {
        case .before:
            return beforeMinutes > 0 ? "\u{2212}\(beforeMinutes)m" : nil
        case .after:
            return afterMinutes > 0 ? "+\(afterMinutes)m" : nil
        }
    }

    /// Spoken buffer facts for accessibility labels:
    /// `"30-minute buffer before and 15-minute buffer after"`.
    /// Omits a zero side; nil when empty.
    public func spoken() -> String? {
        var parts: [String] = []
        if beforeMinutes > 0 {
            parts.append("\(beforeMinutes)-minute buffer before")
        }
        if afterMinutes > 0 {
            parts.append("\(afterMinutes)-minute buffer after")
        }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: " and ")
    }
}

/// Which buffered side an overlap sits wholly inside. Serialized by bob
/// as `"before"` / `"after"`; anything else decodes as nil.
public enum CaptureBufferPart: String, Equatable, Sendable, Hashable, Codable {
    case before
    case after
}

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
    public let planBudget: CapturePlanBudget?
    /// Largest numbered Task Link lineup among today's open entries. Nil
    /// when an older bob omits `max_task_link_count`, so `x=` stays unassisted.
    public let maxTaskLinkCount: Int?
    /// The additive calendar facts for the idle agenda's Calendar band
    /// (`capture-pomodoros --tasks` `events`). Nil on an older bob, so
    /// the band stays hidden.
    public let events: CaptureAgendaEvents?

    public init(
        ok: Bool = false,
        schemaVersion: Int = 1,
        date: String? = nil,
        completedSummary: CaptureAgendaCompletedSummary = CaptureAgendaCompletedSummary(),
        pomodoros: [CaptureAgendaPomodoro] = [],
        warnings: [String] = [],
        planBudget: CapturePlanBudget? = nil,
        events: CaptureAgendaEvents? = nil,
        maxTaskLinkCount: Int? = nil
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.date = date
        self.completedSummary = completedSummary
        self.pomodoros = pomodoros
        self.warnings = warnings
        self.planBudget = planBudget
        self.events = events
        self.maxTaskLinkCount = maxTaskLinkCount
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
        planBudget = try container.decodeIfPresent(CapturePlanBudget.self, forKey: .planBudget)
        events = try container.decodeIfPresent(
            CaptureAgendaEvents.self,
            forKey: .events
        )
        maxTaskLinkCount = try container.decodeIfPresent(Int.self, forKey: .maxTaskLinkCount)
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
        case planBudget = "plan_budget"
        case events
        case maxTaskLinkCount = "max_task_link_count"
    }
}

/// Completed entries in today's ledger, and the summed minutes of their
/// time ranges.
public struct CaptureAgendaCompletedSummary: Decodable, Equatable, Sendable {
    public let count: Int
    public let minutes: Int
    /// Closed Off-Clock Pomodoros in today's ledger. Older bob may only
    /// report their count through the deprecated `untracked_count` key.
    public let offClock: CaptureAgendaOffClockSummary

    public init(
        count: Int = 0,
        minutes: Int = 0,
        offClock: CaptureAgendaOffClockSummary = CaptureAgendaOffClockSummary()
    ) {
        self.count = count
        self.minutes = minutes
        self.offClock = offClock
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        offClock = try container.decodeIfPresent(
            CaptureAgendaOffClockSummary.self,
            forKey: .offClock
        ) ?? CaptureAgendaOffClockSummary(
            count: container.decodeIfPresent(Int.self, forKey: .untrackedCount) ?? 0
        )
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case minutes
        case offClock = "off_clock"
        case untrackedCount = "untracked_count"
    }
}

/// The additive `completed_summary.off_clock` object. Older bob exposes
/// only `untracked_count`, so its fallback has no minute total.
public struct CaptureAgendaOffClockSummary: Decodable, Equatable, Sendable {
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
    public let homes: CaptureAgendaHomes?
    /// Whether the entry's session is off the clock. Nil when an older
    /// bob reports neither `off_clock` nor the deprecated `tracked` key.
    public let offClock: Bool?
    /// Bob-owned theme refs for the entry name (`capture-pomodoros
    /// --tasks` `themes`). Older Bob omits the array; it decodes as
    /// empty and the agenda renders the plain name.
    public let themes: [CapturePomodoroThemeRef]

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
        selectable: Bool = false,
        homes: CaptureAgendaHomes? = nil,
        offClock: Bool? = nil,
        themes: [CapturePomodoroThemeRef] = []
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
        self.homes = homes
        self.offClock = offClock
        self.themes = themes
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
        homes = try container.decodeIfPresent(CaptureAgendaHomes.self, forKey: .homes)
        offClock = try container.decodeIfPresent(Bool.self, forKey: .offClock)
            ?? container.decodeIfPresent(Bool.self, forKey: .tracked).map { !$0 }
        themes =
            (try? container.decodeIfPresent(
                [CapturePomodoroThemeRef].self,
                forKey: .themes
            )) ?? []
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
        case homes
        case offClock = "off_clock"
        case tracked
        case themes
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
    /// Event details when this Task Link targets today's Event Task.
    /// Nil for ordinary tasks and on an older bob.
    public let event: CaptureAgendaItemEvent?

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
        warning: String? = nil,
        event: CaptureAgendaItemEvent? = nil
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
        self.event = event
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
        event = try container.decodeIfPresent(
            CaptureAgendaItemEvent.self,
            forKey: .event
        )
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
        case event
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

/// `work`, `schedule`, or `rotten` log tag on a display line. Unknown
/// strings decode to `.other`.
public enum CaptureAgendaLog: Equatable, Sendable, Decodable {
    case work
    case schedule
    case rotten
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "work":
            self = .work
        case "schedule":
            self = .schedule
        case "rotten":
            self = .rotten
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

/// Event details attached to a Task Link that targets today's Event
/// Task (`capture-pomodoros --tasks` item `event`). Older bob omits
/// the whole object.
public struct CaptureAgendaItemEvent: Decodable, Equatable, Sendable {
    public let timeRange: String?
    public let startsAt: String?
    public let endsAt: String?
    public let offClock: Bool
    public let title: String
    /// The event's pre/post-event buffer; nil on an older bob and when
    /// the event carries none. A malformed buffer decodes as nil.
    public let buffer: CaptureEventBuffer?

    public init(
        timeRange: String? = nil,
        startsAt: String? = nil,
        endsAt: String? = nil,
        offClock: Bool = false,
        title: String = "",
        buffer: CaptureEventBuffer? = nil
    ) {
        self.timeRange = timeRange
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.offClock = offClock
        self.title = title
        self.buffer = buffer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(String.self, forKey: .endsAt)
        offClock = try container.decodeIfPresent(Bool.self, forKey: .offClock)
            ?? container.decodeIfPresent(Bool.self, forKey: .untracked) ?? false
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        buffer = (try? container.decodeIfPresent(CaptureEventBuffer.self, forKey: .buffer)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case timeRange = "time_range"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case offClock = "off_clock"
        case untracked
        case title
        case buffer
    }
}

/// What an agenda event row describes: a real Event Task or a timed
/// context line. Unknown strings decode to `.other`.
public enum CaptureAgendaEventKind: Equatable, Sendable, Decodable {
    case task
    case timedContext
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "task":
            self = .task
        case "timed_context":
            self = .timedContext
        default:
            self = .other(raw)
        }
    }
}

/// Where an agenda event row sits relative to now. Unknown strings
/// decode to `.other`.
public enum CaptureAgendaEventPhase: Equatable, Sendable, Decodable {
    case ended
    case running
    case upcoming
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "ended":
            self = .ended
        case "running":
            self = .running
        case "upcoming":
            self = .upcoming
        default:
            self = .other(raw)
        }
    }
}

/// The home attribution of one agenda event row, from the Event
/// Task's root.
public struct CaptureAgendaEventHome: Decodable, Equatable, Sendable {
    public let label: String
    public let hue: PomodoroHomeHue?

    public init(label: String = "", hue: PomodoroHomeHue? = nil) {
        self.label = label
        self.hue = hue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        hue = try container.decodeIfPresent(PomodoroHomeHue.self, forKey: .hue)
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case hue
    }
}

/// The Pomodoro lineup entry linked from one agenda event row.
public struct CaptureAgendaEventPomodoro: Decodable, Equatable, Sendable {
    public let line: Int
    public let role: CaptureAgendaRole
    public let index: Int?

    public init(line: Int = 0, role: CaptureAgendaRole = .open, index: Int? = nil) {
        self.line = line
        self.role = role
        self.index = index
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        role = try container.decodeIfPresent(CaptureAgendaRole.self, forKey: .role) ?? .open
        index = try container.decodeIfPresent(Int.self, forKey: .index)
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case role
        case index
    }
}

/// One event in the agenda's `events` block: a timed calendar row.
public struct CaptureAgendaEventRow: Decodable, Equatable, Sendable {
    public let line: Int
    public let blockID: String?
    public let kind: CaptureAgendaEventKind
    public let qualifier: String?
    public let title: String
    public let timeRange: String?
    public let startsAt: String?
    public let endsAt: String?
    public let durationMinutes: Int?
    public let phase: CaptureAgendaEventPhase?
    public let statusSymbol: String?
    public let statusType: String?
    public let offClock: Bool
    public let root: String?
    public let home: CaptureAgendaEventHome?
    public let joinURL: String?
    public let calendarURL: String?
    public let location: String?
    public let pomodoro: CaptureAgendaEventPomodoro?
    /// The event's pre/post-event buffer; nil on an older bob and when
    /// the event carries none. A malformed buffer decodes as nil.
    public let buffer: CaptureEventBuffer?

    public init(
        line: Int = 0,
        blockID: String? = nil,
        kind: CaptureAgendaEventKind = .task,
        qualifier: String? = nil,
        title: String = "",
        timeRange: String? = nil,
        startsAt: String? = nil,
        endsAt: String? = nil,
        durationMinutes: Int? = nil,
        phase: CaptureAgendaEventPhase? = nil,
        statusSymbol: String? = nil,
        statusType: String? = nil,
        offClock: Bool = false,
        root: String? = nil,
        home: CaptureAgendaEventHome? = nil,
        joinURL: String? = nil,
        calendarURL: String? = nil,
        location: String? = nil,
        pomodoro: CaptureAgendaEventPomodoro? = nil,
        buffer: CaptureEventBuffer? = nil
    ) {
        self.line = line
        self.blockID = blockID
        self.kind = kind
        self.qualifier = qualifier
        self.title = title
        self.timeRange = timeRange
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.durationMinutes = durationMinutes
        self.phase = phase
        self.statusSymbol = statusSymbol
        self.statusType = statusType
        self.offClock = offClock
        self.root = root
        self.home = home
        self.joinURL = joinURL
        self.calendarURL = calendarURL
        self.location = location
        self.pomodoro = pomodoro
        self.buffer = buffer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        kind = try container.decodeIfPresent(
            CaptureAgendaEventKind.self,
            forKey: .kind
        ) ?? .task
        qualifier = try container.decodeIfPresent(String.self, forKey: .qualifier)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(String.self, forKey: .endsAt)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        phase = try container.decodeIfPresent(CaptureAgendaEventPhase.self, forKey: .phase)
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusType = try container.decodeIfPresent(String.self, forKey: .statusType)
        offClock = try container.decodeIfPresent(Bool.self, forKey: .offClock)
            ?? container.decodeIfPresent(Bool.self, forKey: .untracked) ?? false
        root = try container.decodeIfPresent(String.self, forKey: .root)
        home = try container.decodeIfPresent(CaptureAgendaEventHome.self, forKey: .home)
        joinURL = try container.decodeIfPresent(String.self, forKey: .joinURL)
        calendarURL = try container.decodeIfPresent(String.self, forKey: .calendarURL)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        pomodoro = try container.decodeIfPresent(
            CaptureAgendaEventPomodoro.self,
            forKey: .pomodoro
        )
        buffer = (try? container.decodeIfPresent(CaptureEventBuffer.self, forKey: .buffer)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case blockID = "block_id"
        case kind
        case qualifier
        case title
        case timeRange = "time_range"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case durationMinutes = "duration_minutes"
        case phase
        case statusSymbol = "status_symbol"
        case statusType = "status_type"
        case offClock = "off_clock"
        case untracked
        case root
        case home
        case joinURL = "join_url"
        case calendarURL = "calendar_url"
        case location
        case pomodoro
        case buffer
    }
}

/// One all-day calendar context line for the band's all-day row.
public struct CaptureAgendaAllDayContext: Decodable, Equatable, Sendable {
    public let line: Int
    public let title: String
    public let qualifier: String?

    public init(line: Int = 0, title: String = "", qualifier: String? = nil) {
        self.line = line
        self.title = title
        self.qualifier = qualifier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        qualifier = try container.decodeIfPresent(String.self, forKey: .qualifier)
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case title
        case qualifier
    }
}

/// Free time before the focus event, with the default-Pomodoro fit hint.
public struct CaptureAgendaEventGap: Decodable, Equatable, Sendable {
    public let from: String
    public let until: String
    public let minutes: Int
    public let fits: String?

    public init(from: String = "", until: String = "", minutes: Int = 0, fits: String? = nil) {
        self.from = from
        self.until = until
        self.minutes = minutes
        self.fits = fits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decodeIfPresent(String.self, forKey: .from) ?? ""
        until = try container.decodeIfPresent(String.self, forKey: .until) ?? ""
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        fits = try container.decodeIfPresent(String.self, forKey: .fits)
    }

    private enum CodingKeys: String, CodingKey {
        case from
        case until
        case minutes
        case fits
    }
}

/// The running Pomodoro collides with the focus event.
public struct CaptureAgendaEventConflict: Decodable, Equatable, Sendable {
    public let pomodoroLine: Int
    public let event: Int
    public let overlapMinutes: Int
    /// Which buffered side the overlap sits wholly inside (`before` /
    /// `after`); nil when the overlap reaches the meeting or the event
    /// has no buffer. A malformed value decodes as nil.
    public let bufferPart: CaptureBufferPart?

    public init(
        pomodoroLine: Int = 0,
        event: Int = 0,
        overlapMinutes: Int = 0,
        bufferPart: CaptureBufferPart? = nil
    ) {
        self.pomodoroLine = pomodoroLine
        self.event = event
        self.overlapMinutes = overlapMinutes
        self.bufferPart = bufferPart
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        event = try container.decodeIfPresent(Int.self, forKey: .event) ?? 0
        overlapMinutes = try container.decodeIfPresent(Int.self, forKey: .overlapMinutes) ?? 0
        bufferPart =
            (try? container.decodeIfPresent(CaptureBufferPart.self, forKey: .bufferPart)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case pomodoroLine = "pomodoro_line"
        case event
        case overlapMinutes = "overlap_minutes"
        case bufferPart = "buffer_part"
    }
}

/// Calendar facts and timing hints for the idle agenda's Calendar
/// band. Every field is optional-or-empty safe: an older bob omits
/// the whole block and the band stays hidden.
public struct CaptureAgendaEvents: Decodable, Equatable, Sendable {
    public let syncedAt: String?
    public let allDay: [CaptureAgendaAllDayContext]
    public let rows: [CaptureAgendaEventRow]
    public let focus: Int?
    public let gap: CaptureAgendaEventGap?
    public let conflict: CaptureAgendaEventConflict?
    public let startHint: String?
    public let refreshAt: String?

    public init(
        syncedAt: String? = nil,
        allDay: [CaptureAgendaAllDayContext] = [],
        rows: [CaptureAgendaEventRow] = [],
        focus: Int? = nil,
        gap: CaptureAgendaEventGap? = nil,
        conflict: CaptureAgendaEventConflict? = nil,
        startHint: String? = nil,
        refreshAt: String? = nil
    ) {
        self.syncedAt = syncedAt
        self.allDay = allDay
        self.rows = rows
        self.focus = focus
        self.gap = gap
        self.conflict = conflict
        self.startHint = startHint
        self.refreshAt = refreshAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncedAt = try container.decodeIfPresent(String.self, forKey: .syncedAt)
        allDay = try container.decodeIfPresent(
            [CaptureAgendaAllDayContext].self,
            forKey: .allDay
        ) ?? []
        rows = try container.decodeIfPresent(
            [CaptureAgendaEventRow].self,
            forKey: .rows
        ) ?? []
        focus = try container.decodeIfPresent(Int.self, forKey: .focus)
        gap = try container.decodeIfPresent(CaptureAgendaEventGap.self, forKey: .gap)
        conflict = try container.decodeIfPresent(
            CaptureAgendaEventConflict.self,
            forKey: .conflict
        )
        startHint = try container.decodeIfPresent(String.self, forKey: .startHint)
        refreshAt = try container.decodeIfPresent(String.self, forKey: .refreshAt)
    }

    private enum CodingKeys: String, CodingKey {
        case syncedAt = "synced_at"
        case allDay = "all_day"
        case rows
        case focus
        case gap
        case conflict
        case startHint = "start_hint"
        case refreshAt = "refresh_at"
    }
}
