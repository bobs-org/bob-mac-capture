import Foundation

public struct CaptureParseResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let input: String
    public let body: String
    public let mode: String
    public let route: String?
    public let section: String?
    public let blockID: String?
    public let needs: [String]
    public let spans: [CaptureSpan]
    public let diagnostics: [CaptureDiagnostic]
    public let globalDestination: CaptureGlobalDestination?
    // Additive to schema version 1: `bob capture-parse` omits these keys entirely when
    // a draft has no authored sub-bullets, and older bob versions omit depths even when
    // they provide bodies. Decode both tolerantly and synthesize depth 1 for older bob
    // responses rather than letting clients index mismatched arrays.
    public let subBullets: [String]
    public let subBulletDepths: [Int]
    public let items: [CaptureParseItem]
    // Additive `=<X>` start suffix on a `@<route>:<block-id>[#<name>]` marker.
    // Omitted for every older marker shape, so older bob output decodes as nil.
    public let pomodoroStart: PomodoroStartSpec?
    // Additive whole-item `+N`/`-N` adjustment spec. Omitted for every
    // non-adjustment mode, so older bob output decodes as nil.
    public let pomodoroAdjust: PomodoroAdjustSpec?
    // Additive whole-item `++N`/`--N` shift spec. Omitted for every
    // non-shift mode, so older bob output decodes as nil.
    public let pomodoroShift: PomodoroShiftSpec?
    // Additive `=x` close suffix on a whole item or a `@`/`^` link item.
    // Omitted for every non-close mode, so older bob output decodes as nil.
    public let pomodoroClose: PomodoroCloseSpec?

    public init(
        ok: Bool,
        schemaVersion: Int,
        input: String,
        body: String,
        mode: String,
        route: String? = nil,
        section: String? = nil,
        blockID: String? = nil,
        needs: [String] = [],
        spans: [CaptureSpan] = [],
        diagnostics: [CaptureDiagnostic] = [],
        globalDestination: CaptureGlobalDestination? = nil,
        subBullets: [String] = [],
        subBulletDepths: [Int]? = nil,
        items: [CaptureParseItem] = [],
        pomodoroStart: PomodoroStartSpec? = nil,
        pomodoroAdjust: PomodoroAdjustSpec? = nil,
        pomodoroShift: PomodoroShiftSpec? = nil,
        pomodoroClose: PomodoroCloseSpec? = nil
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.input = input
        self.body = body
        self.mode = mode
        self.route = route
        self.section = section
        self.blockID = blockID
        self.needs = needs
        self.spans = spans
        self.diagnostics = diagnostics
        self.globalDestination = globalDestination
        self.subBullets = subBullets
        self.subBulletDepths = Self.normalizedSubBulletDepths(
            subBulletDepths,
            bodyCount: subBullets.count
        )
        self.items = items
        self.pomodoroStart = pomodoroStart
        self.pomodoroAdjust = pomodoroAdjust
        self.pomodoroShift = pomodoroShift
        self.pomodoroClose = pomodoroClose
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        input = try container.decode(String.self, forKey: .input)
        body = try container.decode(String.self, forKey: .body)
        mode = try container.decode(String.self, forKey: .mode)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        needs = try container.decodeIfPresent([String].self, forKey: .needs) ?? []
        spans = try container.decodeIfPresent([CaptureSpan].self, forKey: .spans) ?? []
        diagnostics =
            try container.decodeIfPresent([CaptureDiagnostic].self, forKey: .diagnostics) ?? []
        globalDestination = try container.decodeIfPresent(
            CaptureGlobalDestination.self,
            forKey: .globalDestination
        )
        subBullets = try container.decodeIfPresent([String].self, forKey: .subBullets) ?? []
        let decodedDepths = try container.decodeIfPresent(
            [Int].self,
            forKey: .subBulletDepths
        )
        subBulletDepths = Self.normalizedSubBulletDepths(
            decodedDepths,
            bodyCount: subBullets.count
        )
        items = try container.decodeIfPresent([CaptureParseItem].self, forKey: .items) ?? []
        pomodoroStart = try container.decodeIfPresent(PomodoroStartSpec.self, forKey: .pomodoroStart)
        pomodoroAdjust = try container.decodeIfPresent(
            PomodoroAdjustSpec.self,
            forKey: .pomodoroAdjust
        )
        pomodoroShift = try container.decodeIfPresent(
            PomodoroShiftSpec.self,
            forKey: .pomodoroShift
        )
        pomodoroClose = try container.decodeIfPresent(
            PomodoroCloseSpec.self,
            forKey: .pomodoroClose
        )
    }

    private static func normalizedSubBulletDepths(
        _ depths: [Int]?,
        bodyCount: Int
    ) -> [Int] {
        guard bodyCount > 0 else {
            return []
        }
        guard let depths,
              depths.count == bodyCount,
              depths.allSatisfy({ $0 == 1 || $0 == 2 })
        else {
            return Array(repeating: 1, count: bodyCount)
        }
        return depths
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case input
        case body
        case mode
        case route
        case section
        case blockID = "block_id"
        case needs
        case spans
        case diagnostics
        case globalDestination = "global_destination"
        case subBullets = "sub_bullets"
        case subBulletDepths = "sub_bullet_depths"
        case items
        case pomodoroStart = "pomodoro_start"
        case pomodoroAdjust = "pomodoro_adjust"
        case pomodoroShift = "pomodoro_shift"
        case pomodoroClose = "pomodoro_close"
    }
}

public struct CaptureParseItem: Codable, Equatable {
    public let index: Int
    public let range: CaptureRange
    public let lineStart: Int
    public let lineEnd: Int
    public let body: String
    public let mode: String
    public let route: String?
    public let section: String?
    public let blockID: String?
    public let needs: [String]
    public let subBullets: [String]
    public let subBulletDepths: [Int]
    // Per-item additive `=<X>` start suffix. Omitted for items without one.
    public let pomodoroStart: PomodoroStartSpec?
    // Per-item additive whole-item `+N`/`-N` adjustment spec. Omitted for
    // items without one.
    public let pomodoroAdjust: PomodoroAdjustSpec?
    // Per-item additive whole-item `++N`/`--N` shift spec. Omitted for
    // items without one.
    public let pomodoroShift: PomodoroShiftSpec?
    // Per-item additive `=x` close suffix. Omitted for items without one.
    public let pomodoroClose: PomodoroCloseSpec?

    public init(
        index: Int,
        range: CaptureRange,
        lineStart: Int,
        lineEnd: Int,
        body: String,
        mode: String,
        route: String? = nil,
        section: String? = nil,
        blockID: String? = nil,
        needs: [String] = [],
        subBullets: [String] = [],
        subBulletDepths: [Int] = [],
        pomodoroStart: PomodoroStartSpec? = nil,
        pomodoroAdjust: PomodoroAdjustSpec? = nil,
        pomodoroShift: PomodoroShiftSpec? = nil,
        pomodoroClose: PomodoroCloseSpec? = nil
    ) {
        self.index = index
        self.range = range
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.body = body
        self.mode = mode
        self.route = route
        self.section = section
        self.blockID = blockID
        self.needs = needs
        self.subBullets = subBullets
        self.subBulletDepths = subBulletDepths
        self.pomodoroStart = pomodoroStart
        self.pomodoroAdjust = pomodoroAdjust
        self.pomodoroShift = pomodoroShift
        self.pomodoroClose = pomodoroClose
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        range = try container.decode(CaptureRange.self, forKey: .range)
        lineStart = try container.decode(Int.self, forKey: .lineStart)
        lineEnd = try container.decode(Int.self, forKey: .lineEnd)
        body = try container.decode(String.self, forKey: .body)
        mode = try container.decode(String.self, forKey: .mode)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        needs = try container.decodeIfPresent([String].self, forKey: .needs) ?? []
        subBullets = try container.decodeIfPresent([String].self, forKey: .subBullets) ?? []
        subBulletDepths = try container.decodeIfPresent([Int].self, forKey: .subBulletDepths) ?? []
        pomodoroStart = try container.decodeIfPresent(PomodoroStartSpec.self, forKey: .pomodoroStart)
        pomodoroAdjust = try container.decodeIfPresent(
            PomodoroAdjustSpec.self,
            forKey: .pomodoroAdjust
        )
        pomodoroShift = try container.decodeIfPresent(
            PomodoroShiftSpec.self,
            forKey: .pomodoroShift
        )
        pomodoroClose = try container.decodeIfPresent(
            PomodoroCloseSpec.self,
            forKey: .pomodoroClose
        )
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case range
        case lineStart = "line_start"
        case lineEnd = "line_end"
        case body
        case mode
        case route
        case section
        case blockID = "block_id"
        case needs
        case subBullets = "sub_bullets"
        case subBulletDepths = "sub_bullet_depths"
        case pomodoroStart = "pomodoro_start"
        case pomodoroAdjust = "pomodoro_adjust"
        case pomodoroShift = "pomodoro_shift"
        case pomodoroClose = "pomodoro_close"
    }
}

/// One typed Work Log entry from Bob's `pomodoro_close.log`: the 1-based
/// task index plus its literal entry text, in typed order. `index` is nil
/// for an unnumbered bullet (`- foo`) under a close without `<N>`/`*<P>`,
/// which `bob capture` resolves against the running session at execution;
/// `bob capture-parse` omits the key there. Additive: an older Bob that
/// omits `log` decodes as empty. `details` holds the nested detail lines
/// typed under the entry (`  - …` bullets), in typed order; an older Bob
/// that omits `details` decodes as empty.
public struct PomodoroCloseLogEntry: Codable, Equatable, Sendable {
    public let index: Int?
    public let text: String
    public let details: [String]

    public init(index: Int?, text: String, details: [String] = []) {
        self.index = index
        self.text = text
        self.details = details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        details = try container.decodeIfPresent([String].self, forKey: .details) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case text
        case details
    }
}

/// The typed close token from `bob capture-parse` (`=x[…]` or the `=*`/`=!`
/// aliases): `raw` preserves exactly what was typed (`"=x"`, `"=X1!2"`,
/// `"=x1~2"`, `"=x*2"`, `"=*"`, `"=!"`). `inProgress` is the sorted
/// `in_progress` list, or nil when `<N>` was omitted (plain `=x` leaves
/// unlisted links at their ledger outcome unless `*<P>` is present, which
/// activates selection mode like `<N>`); `parkAll`/`completeAll` preserve a
/// present-but-empty `*`/`!` group until Bob resolves the current lineup;
/// `park` and `complete` carry only concrete numbers.
/// `drop` is the sorted `~<K>` list, empty when no `~` list was typed.
/// Present on whole-item closes and on link and body-bearing items carrying
/// the close suffix. Older Bob binaries omit all four lists; they decode as
/// none/empty so the card is exactly today's.
public struct PomodoroCloseSpec: Codable, Equatable, Sendable {
    public let raw: String
    public let inProgress: [Int]?
    public let park: [Int]
    public let parkAll: Bool
    public let complete: [Int]
    public let completeAll: Bool
    public let drop: [Int]
    public let log: [PomodoroCloseLogEntry]

    public init(raw: String, inProgress: [Int]? = nil, park: [Int] = [], parkAll: Bool = false, complete: [Int] = [], completeAll: Bool = false, drop: [Int] = [], log: [PomodoroCloseLogEntry] = []) {
        self.raw = raw
        self.inProgress = inProgress
        self.park = park
        self.parkAll = parkAll
        self.complete = complete
        self.completeAll = completeAll
        self.drop = drop
        self.log = log
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        inProgress = try container.decodeIfPresent([Int].self, forKey: .inProgress)
        park = try container.decodeIfPresent([Int].self, forKey: .park) ?? []
        parkAll = try container.decodeIfPresent(Bool.self, forKey: .parkAll) ?? false
        complete = try container.decodeIfPresent([Int].self, forKey: .complete) ?? []
        completeAll = try container.decodeIfPresent(Bool.self, forKey: .completeAll) ?? false
        drop = try container.decodeIfPresent([Int].self, forKey: .drop) ?? []
        log = try container.decodeIfPresent([PomodoroCloseLogEntry].self, forKey: .log) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case inProgress = "in_progress"
        case park
        case parkAll = "park_all"
        case complete
        case completeAll = "complete_all"
        case drop
        case log
    }
}

public struct CaptureSpan: Codable, Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let kind: String

    public init(start: Int, end: Int, kind: String) {
        self.start = start
        self.end = end
        self.kind = kind
    }
}

public struct CaptureDiagnostic: Codable, Equatable {
    public let severity: String
    public let code: String
    public let message: String
    public let range: CaptureRange?

    public init(
        severity: String,
        code: String,
        message: String,
        range: CaptureRange? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.range = range
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decode(String.self, forKey: .severity)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        // Bob serializes diagnostic ranges as a nullable `[start, end]` pair, while
        // older fixtures use the `{"start":..,"end":..}` object. Accept both so an
        // `invalid_pomodoro_start` diagnostic never breaks parse decoding.
        // `decodeIfPresent` returns an optional and `try?` adds a second layer, so
        // flatten (`?? nil`) before binding: `if let` unwraps only one layer.
        let objectRange: CaptureRange? =
            (try? container.decodeIfPresent(CaptureRange.self, forKey: .range)) ?? nil
        if let objectRange {
            range = objectRange
        } else {
            let pairRange: [Int]? =
                (try? container.decodeIfPresent([Int].self, forKey: .range)) ?? nil
            if let pairRange, pairRange.count == 2 {
                range = CaptureRange(start: pairRange[0], end: pairRange[1])
            } else {
                range = nil
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case severity
        case code
        case message
        case range
    }
}

public struct CaptureRange: Codable, Equatable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// Validated additive `@<route>:<block-id>[#<name>]=<X>` start suffix from
/// `bob capture-parse`, and the whole-item `=`/`=<X>` start token's spec: the
/// raw `<X>` text plus its 5-minute duration/offset units. Omitted for every
/// older marker shape, so decoding stays backward compatible.
public struct PomodoroStartSpec: Codable, Equatable, Sendable {
    public let raw: String
    public let durationUnits: Int
    public let offsetUnits: Int
    /// The typed `~<K>` drop list, ascending. Omitted (decodes as empty) when
    /// no drop list was typed or the Bob build predates start drops.
    public let drop: [Int]

    public init(raw: String, durationUnits: Int = 0, offsetUnits: Int = 0, drop: [Int] = []) {
        self.raw = raw
        self.durationUnits = durationUnits
        self.offsetUnits = offsetUnits
        self.drop = drop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        durationUnits = try container.decodeIfPresent(Int.self, forKey: .durationUnits) ?? 0
        offsetUnits = try container.decodeIfPresent(Int.self, forKey: .offsetUnits) ?? 0
        drop = try container.decodeIfPresent([Int].self, forKey: .drop) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case durationUnits = "duration_units"
        case offsetUnits = "offset_units"
        case drop
    }
}

/// One queued Task Link row on a started Pomodoro, following the close row's
/// explicit-null convention: unresolved rows carry nil text/symbols and a
/// `warning` instead of failing the start. Every field decodes tolerantly so a
/// partial object still yields a (neutral, unresolved) row instead of failing
/// the whole capture.
public struct PomodoroStartTask: Codable, Equatable, Sendable {
    public let blockLink: String
    public let embedded: Bool
    public let ledgerLine: Int
    public let resolved: Bool
    public let relativeTarget: String?
    public let blockID: String
    public let text: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let warning: String?
    /// The 1-based lineup number Bob assigned this row, or nil for unnumbered
    /// rows (older Bob). Dropped rows carry their own lineup number too.
    public let index: Int?
    /// Non-blank descendant lines removed with a dropped link. Omitted
    /// (decodes as zero) on kept rows and when there were none.
    public let nestedLines: Int

    public init(
        blockLink: String,
        embedded: Bool = false,
        ledgerLine: Int = 0,
        resolved: Bool = false,
        relativeTarget: String? = nil,
        blockID: String = "",
        text: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        warning: String? = nil,
        index: Int? = nil,
        nestedLines: Int = 0
    ) {
        self.blockLink = blockLink
        self.embedded = embedded
        self.ledgerLine = ledgerLine
        self.resolved = resolved
        self.relativeTarget = relativeTarget
        self.blockID = blockID
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.warning = warning
        self.index = index
        self.nestedLines = nestedLines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink) ?? ""
        embedded = try container.decodeIfPresent(Bool.self, forKey: .embedded) ?? false
        ledgerLine = try container.decodeIfPresent(Int.self, forKey: .ledgerLine) ?? 0
        resolved = try container.decodeIfPresent(Bool.self, forKey: .resolved) ?? false
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text)
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        nestedLines = try container.decodeIfPresent(Int.self, forKey: .nestedLines) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case blockLink = "block_link"
        case embedded
        case ledgerLine = "ledger_line"
        case resolved
        case relativeTarget = "relative_target"
        case blockID = "block_id"
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case warning
        case index
        case nestedLines = "nested_lines"
    }
}

/// Resolved atomic start from `bob capture --format json`: the 5-minute-rounded
/// `start`/`end` clock times, duration, destination ledger line, and whether Bob
/// created the entry. Omitted when the draft carries no `=<X>` suffix, so older
/// bob binaries decode as nil. Every field decodes tolerantly (strings default
/// to empty, numbers to zero) so a partial object still previews instead of
/// failing the whole capture. `tasks` is present — possibly empty — only for a
/// whole-item `=`/`=<X>` start; link and task starts omit it and decode as nil.
public struct PomodoroStartSummary: Codable, Equatable, Sendable {
    public let start: String
    public let end: String
    public let durationMinutes: Int
    public let offsetUnits: Int
    public let pomodoroName: String?
    public let pomodoroLine: Int
    public let createdPomodoro: Bool
    public let timeRange: String
    public let tasks: [PomodoroStartTask]?
    /// The typed `~<K>` drop list, ascending. Omitted (decodes as empty) when
    /// no drop list was typed or the Bob build predates start drops.
    public let drop: [Int]
    /// Rows removed by `~<K>`, in lineup order. Omitted (decodes as empty)
    /// when nothing was dropped.
    public let dropped: [PomodoroStartTask]

    public init(
        start: String,
        end: String,
        durationMinutes: Int,
        offsetUnits: Int,
        pomodoroName: String? = nil,
        pomodoroLine: Int,
        createdPomodoro: Bool,
        timeRange: String,
        tasks: [PomodoroStartTask]? = nil,
        drop: [Int] = [],
        dropped: [PomodoroStartTask] = []
    ) {
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.offsetUnits = offsetUnits
        self.pomodoroName = pomodoroName
        self.pomodoroLine = pomodoroLine
        self.createdPomodoro = createdPomodoro
        self.timeRange = timeRange
        self.tasks = tasks
        self.drop = drop
        self.dropped = dropped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        offsetUnits = try container.decodeIfPresent(Int.self, forKey: .offsetUnits) ?? 0
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        createdPomodoro = try container.decodeIfPresent(Bool.self, forKey: .createdPomodoro) ?? false
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
        tasks = try container.decodeIfPresent([PomodoroStartTask].self, forKey: .tasks)
        drop = try container.decodeIfPresent([Int].self, forKey: .drop) ?? []
        dropped = try container.decodeIfPresent([PomodoroStartTask].self, forKey: .dropped) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case durationMinutes = "duration_minutes"
        case offsetUnits = "offset_units"
        case pomodoroName = "pomodoro_name"
        case pomodoroLine = "pomodoro_line"
        case createdPomodoro = "created_pomodoro"
        case timeRange = "time_range"
        case tasks
        case drop
        case dropped
    }
}

/// Validated whole-item `+N`/`-N` adjustment spec from `bob capture-parse`: the
/// trimmed signed token plus its sign and 5-minute unit count (`+5` is five
/// units, 25 minutes). Omitted for every non-adjustment mode, so decoding stays
/// backward compatible.
public struct PomodoroAdjustSpec: Codable, Equatable, Sendable {
    public let raw: String
    public let plus: Bool
    public let units: Int

    public init(raw: String, plus: Bool, units: Int) {
        self.raw = raw
        self.plus = plus
        self.units = units
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case plus
        case units
    }
}

/// Resolved duration adjustment from `bob capture --format json`: the requested
/// direction/units, the actual applied delta (which differs when subtraction
/// clamps at zero), before/after start/end/duration, destination ledger line,
/// and rendered new range. Omitted when the draft carries no adjustment, so
/// older bob binaries decode as nil.
public struct PomodoroAdjustSummary: Codable, Equatable, Sendable {
    public let direction: String
    public let requestedUnits: Int
    public let requestedMinutes: Int
    public let deltaMinutes: Int
    public let beforeStart: String
    public let beforeEnd: String
    public let beforeDurationMinutes: Int
    public let afterStart: String
    public let afterEnd: String
    public let afterDurationMinutes: Int
    public let pomodoroLine: Int
    public let pomodoroName: String?
    public let timeRange: String
    public let clamped: Bool

    public init(
        direction: String,
        requestedUnits: Int,
        requestedMinutes: Int,
        deltaMinutes: Int,
        beforeStart: String,
        beforeEnd: String,
        beforeDurationMinutes: Int,
        afterStart: String,
        afterEnd: String,
        afterDurationMinutes: Int,
        pomodoroLine: Int,
        pomodoroName: String? = nil,
        timeRange: String,
        clamped: Bool
    ) {
        self.direction = direction
        self.requestedUnits = requestedUnits
        self.requestedMinutes = requestedMinutes
        self.deltaMinutes = deltaMinutes
        self.beforeStart = beforeStart
        self.beforeEnd = beforeEnd
        self.beforeDurationMinutes = beforeDurationMinutes
        self.afterStart = afterStart
        self.afterEnd = afterEnd
        self.afterDurationMinutes = afterDurationMinutes
        self.pomodoroLine = pomodoroLine
        self.pomodoroName = pomodoroName
        self.timeRange = timeRange
        self.clamped = clamped
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case requestedUnits = "requested_units"
        case requestedMinutes = "requested_minutes"
        case deltaMinutes = "delta_minutes"
        case beforeStart = "before_start"
        case beforeEnd = "before_end"
        case beforeDurationMinutes = "before_duration_minutes"
        case afterStart = "after_start"
        case afterEnd = "after_end"
        case afterDurationMinutes = "after_duration_minutes"
        case pomodoroLine = "pomodoro_line"
        case pomodoroName = "pomodoro_name"
        case timeRange = "time_range"
        case clamped
    }
}

/// Validated whole-item `++N`/`--N` shift spec from `bob capture-parse`: the
/// trimmed doubled-sign token plus its direction and 5-minute unit count
/// (`++3` is three units, 15 minutes). Omitted for every non-shift mode, so
/// decoding stays backward compatible. Older Bob output decodes as nil.
public struct PomodoroShiftSpec: Codable, Equatable, Sendable {
    public let raw: String
    public let later: Bool
    public let units: Int

    public init(raw: String, later: Bool, units: Int) {
        self.raw = raw
        self.later = later
        self.units = units
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case later
        case units
    }
}

/// Resolved whole-session shift from `bob capture --format json`: the requested
/// direction/units, the signed applied delta, before/after start/end, unchanged
/// duration, destination ledger line, and rendered new range. Omitted when the
/// draft carries no shift, so older bob binaries decode as nil.
public struct PomodoroShiftSummary: Codable, Equatable, Sendable {
    public let direction: String
    public let requestedUnits: Int
    public let deltaMinutes: Int
    public let beforeStart: String
    public let beforeEnd: String
    public let afterStart: String
    public let afterEnd: String
    public let durationMinutes: Int
    public let pomodoroLine: Int
    public let pomodoroName: String?
    public let timeRange: String

    public init(
        direction: String,
        requestedUnits: Int,
        deltaMinutes: Int,
        beforeStart: String,
        beforeEnd: String,
        afterStart: String,
        afterEnd: String,
        durationMinutes: Int,
        pomodoroLine: Int,
        pomodoroName: String? = nil,
        timeRange: String
    ) {
        self.direction = direction
        self.requestedUnits = requestedUnits
        self.deltaMinutes = deltaMinutes
        self.beforeStart = beforeStart
        self.beforeEnd = beforeEnd
        self.afterStart = afterStart
        self.afterEnd = afterEnd
        self.durationMinutes = durationMinutes
        self.pomodoroLine = pomodoroLine
        self.pomodoroName = pomodoroName
        self.timeRange = timeRange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        requestedUnits = try container.decodeIfPresent(Int.self, forKey: .requestedUnits) ?? 0
        deltaMinutes = try container.decodeIfPresent(Int.self, forKey: .deltaMinutes) ?? 0
        beforeStart = try container.decodeIfPresent(String.self, forKey: .beforeStart) ?? ""
        beforeEnd = try container.decodeIfPresent(String.self, forKey: .beforeEnd) ?? ""
        afterStart = try container.decodeIfPresent(String.self, forKey: .afterStart) ?? ""
        afterEnd = try container.decodeIfPresent(String.self, forKey: .afterEnd) ?? ""
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case requestedUnits = "requested_units"
        case deltaMinutes = "delta_minutes"
        case beforeStart = "before_start"
        case beforeEnd = "before_end"
        case afterStart = "after_start"
        case afterEnd = "after_end"
        case durationMinutes = "duration_minutes"
        case pomodoroLine = "pomodoro_line"
        case pomodoroName = "pomodoro_name"
        case timeRange = "time_range"
    }
}

/// One Pomodoro block in its final after-state from Bob's additive
/// batch-level `pomodoro_blocks` key: a Pomodoro the capture touches,
/// creates, or reports, with every line of its block and a per-line diff
/// against the pre-capture ledger. `line` is the 1-based headline line in
/// the final staged day file; `created` marks an entry that did not exist
/// before the batch; `roles` is informational first-touch order the app
/// never depends on. Every field decodes tolerantly so a partial object
/// still yields a block instead of failing the whole capture.
public struct CapturePomodoroBlock: Codable, Equatable, Sendable {
    public let relativeTarget: String
    public let line: Int
    public let name: String?
    public let timeRange: String?
    public let status: CapturePomodoroBlockStatus
    public let created: Bool
    public let roles: [String]
    public let lines: [CapturePomodoroBlockLine]

    public init(
        relativeTarget: String,
        line: Int,
        name: String? = nil,
        timeRange: String? = nil,
        status: CapturePomodoroBlockStatus = .other,
        created: Bool = false,
        roles: [String] = [],
        lines: [CapturePomodoroBlockLine] = []
    ) {
        self.relativeTarget = relativeTarget
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.status = status
        self.created = created
        self.roles = roles
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        status =
            try container.decodeIfPresent(
                CapturePomodoroBlockStatus.self,
                forKey: .status
            ) ?? .other
        created = try container.decodeIfPresent(Bool.self, forKey: .created) ?? false
        roles = try container.decodeIfPresent([String].self, forKey: .roles) ?? []
        lines =
            try container.decodeIfPresent(
                [CapturePomodoroBlockLine].self,
                forKey: .lines
            ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case relativeTarget = "relative_target"
        case line
        case name
        case timeRange = "time_range"
        case status
        case created
        case roles
        case lines
    }
}

/// Whether Bob's Pomodoro entry is open with a time range (`running`), open
/// without one (`queued`), or done (`completed`). Unknown values decode to
/// `.other` so a newer Bob never breaks the panel.
public enum CapturePomodoroBlockStatus: String, Equatable, Sendable {
    case running
    case queued
    case completed
    case other

    public init(wireValue: String?) {
        self = (wireValue.flatMap(CapturePomodoroBlockStatus.init(rawValue:)) ?? .other)
    }
}

extension CapturePomodoroBlockStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self.init(wireValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One verbatim line of a Pomodoro block: `text` never carries a
/// terminator, and `before` holds the old text only on `changed` rows.
/// Unknown `change` values decode to `.unchanged` so a newer Bob never
/// breaks the panel.
public struct CapturePomodoroBlockLine: Codable, Equatable, Sendable {
    public let text: String
    public let depth: Int
    public let change: CapturePomodoroBlockChange
    public let before: String?

    public init(
        text: String,
        depth: Int = 0,
        change: CapturePomodoroBlockChange = .unchanged,
        before: String? = nil
    ) {
        self.text = text
        self.depth = depth
        self.change = change
        self.before = before
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        depth = try container.decodeIfPresent(Int.self, forKey: .depth) ?? 0
        change =
            try container.decodeIfPresent(
                CapturePomodoroBlockChange.self,
                forKey: .change
            ) ?? .unchanged
        before = try container.decodeIfPresent(String.self, forKey: .before)
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case depth
        case change
        case before
    }
}

/// How a block line differs from the pre-capture ledger: `changed` rows
/// carry the old text in `before`, and removed lines are interleaved where
/// they used to be. Unknown values decode to `.unchanged`.
public enum CapturePomodoroBlockChange: String, Equatable, Sendable {
    case unchanged
    case added
    case removed
    case changed

    public init(wireValue: String?) {
        self = (wireValue.flatMap(CapturePomodoroBlockChange.init(rawValue:)) ?? .unchanged)
    }
}

extension CapturePomodoroBlockChange: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self.init(wireValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Neutral alias for one verbatim line of any batch-level block diff, so new
/// block kinds share the Pomodoro line shape without a Pomodoro name.
public typealias CaptureBlockLine = CapturePomodoroBlockLine

/// Batch-level `task_blocks` entry: a parent task a sub-bullet capture wrote
/// under, in its final after-state, with every line of its block and a
/// per-line cumulative diff against the note before the capture. `line` is
/// the 1-based task line in the final staged note; `blockID` is the parent's
/// trailing block ID, nil when it has none (a picker task-ref parent);
/// `created` marks a parent that did not exist before the batch (every row
/// then reads `added`); `roles` is informational first-touch order the app
/// never depends on. Every field decodes tolerantly so a partial object
/// still yields a block instead of failing the whole capture.
public struct CaptureTaskBlock: Codable, Equatable, Sendable {
    public let relativeTarget: String
    public let route: String
    public let line: Int
    public let blockID: String?
    public let text: String
    public let statusSymbol: String
    public let statusName: String
    public let created: Bool
    public let roles: [String]
    public let lines: [CaptureBlockLine]

    public init(
        relativeTarget: String,
        route: String,
        line: Int,
        blockID: String? = nil,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        created: Bool = false,
        roles: [String] = [],
        lines: [CaptureBlockLine] = []
    ) {
        self.relativeTarget = relativeTarget
        self.route = route
        self.line = line
        self.blockID = blockID
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.created = created
        self.roles = roles
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        route = try container.decodeIfPresent(String.self, forKey: .route) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
        created = try container.decodeIfPresent(Bool.self, forKey: .created) ?? false
        roles = try container.decodeIfPresent([String].self, forKey: .roles) ?? []
        lines =
            try container.decodeIfPresent(
                [CaptureBlockLine].self,
                forKey: .lines
            ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case relativeTarget = "relative_target"
        case route
        case line
        case blockID = "block_id"
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case created
        case roles
        case lines
    }
}

/// One timing value from Bob's additive `pomodoro_close` result. Every field
/// decodes tolerantly so a partial or older-bob object still yields a row.
public struct PomodoroCloseTiming: Codable, Equatable, Sendable {
    public let start: String
    public let end: String
    public let durationMinutes: Int
    public let timeRange: String

    public init(
        start: String,
        end: String,
        durationMinutes: Int,
        timeRange: String
    ) {
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.timeRange = timeRange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case durationMinutes = "duration_minutes"
        case timeRange = "time_range"
    }
}

/// One numbered Task Link in Bob's `pomodoro_close.task_links` lineup: the
/// 1-based `index` shown as the row badge, the pre-image `ledgerLine`, the
/// link's pre-selection `marker` (`plain`, `deferred`, `embedded`), the
/// `outcome` the selection gives it (`in_progress`, `deferred`, `complete`),
/// and the `source` saying why (`ledger`, `listed`, `unlisted`). Every field
/// decodes tolerantly so older-bob objects without `task_links` still decode;
/// unknown marker/outcome/source strings are preserved verbatim and degrade
/// to neutral presentation.
public struct PomodoroCloseTaskLink: Codable, Equatable, Sendable {
    public let index: Int
    public let ledgerLine: Int
    public let blockLink: String
    public let blockID: String
    public let marker: String
    public let outcome: String
    public let source: String

    public init(
        index: Int,
        ledgerLine: Int = 0,
        blockLink: String = "",
        blockID: String = "",
        marker: String = "plain",
        outcome: String = "deferred",
        source: String = "ledger"
    ) {
        self.index = index
        self.ledgerLine = ledgerLine
        self.blockLink = blockLink
        self.blockID = blockID
        self.marker = marker
        self.outcome = outcome
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        ledgerLine = try container.decodeIfPresent(Int.self, forKey: .ledgerLine) ?? 0
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        marker = try container.decodeIfPresent(String.self, forKey: .marker) ?? "plain"
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome) ?? "deferred"
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "ledger"
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case ledgerLine = "ledger_line"
        case blockLink = "block_link"
        case blockID = "block_id"
        case marker
        case outcome
        case source
    }
}

/// A task or block-link effect Bob resolved while closing a Pomodoro. Every
/// field decodes tolerantly: booleans default to false, arrays to empty, and
/// `ledgerLine` stays decodable when absent, so older-bob and partial objects
/// still yield a (neutral, unresolved) row instead of failing the whole
/// capture. `index` is the number of the numbered line that produced the row,
/// or nil for unnumbered rows (struck, mentioned, subtask, Work-Log-only);
/// older Bob omits it and it decodes as nil. Unknown `role` strings are
/// preserved here and degrade to a neutral row in
/// `CapturePomodoroClosePresentation`.
public struct PomodoroCloseTask: Codable, Equatable, Sendable {
    public let role: String
    public let blockLink: String
    public let ledgerLine: Int
    public let index: Int?
    public let resolved: Bool
    public let relativeTarget: String?
    public let blockID: String
    public let text: String?
    public let previousStatusSymbol: String?
    public let previousStatusName: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let statusChanged: Bool
    public let carried: Bool
    public let workLog: [String]
    public let workLogCreated: Bool
    public let typedWorkLog: [String]
    /// Detail lines written under each typed entry, aligned 1:1 with
    /// `typedWorkLog`: element _i_ lists the detail lines under typed entry
    /// _i_. Additive: an older Bob that omits `typed_work_log_details`
    /// decodes as empty, and a missing element counts as empty.
    public let typedWorkLogDetails: [[String]]
    public let warning: String?

    public init(
        role: String,
        blockLink: String,
        ledgerLine: Int = 0,
        index: Int? = nil,
        resolved: Bool = false,
        relativeTarget: String? = nil,
        blockID: String = "",
        text: String? = nil,
        previousStatusSymbol: String? = nil,
        previousStatusName: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        statusChanged: Bool = false,
        carried: Bool = false,
        workLog: [String] = [],
        workLogCreated: Bool = false,
        typedWorkLog: [String] = [],
        typedWorkLogDetails: [[String]] = [],
        warning: String? = nil
    ) {
        self.role = role
        self.blockLink = blockLink
        self.ledgerLine = ledgerLine
        self.index = index
        self.resolved = resolved
        self.relativeTarget = relativeTarget
        self.blockID = blockID
        self.text = text
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.statusChanged = statusChanged
        self.carried = carried
        self.workLog = workLog
        self.workLogCreated = workLogCreated
        self.typedWorkLog = typedWorkLog
        self.typedWorkLogDetails = typedWorkLogDetails
        self.warning = warning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "unknown"
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink) ?? ""
        ledgerLine = try container.decodeIfPresent(Int.self, forKey: .ledgerLine) ?? 0
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        resolved = try container.decodeIfPresent(Bool.self, forKey: .resolved) ?? false
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text)
        previousStatusSymbol = try container.decodeIfPresent(
            String.self,
            forKey: .previousStatusSymbol
        )
        previousStatusName = try container.decodeIfPresent(
            String.self,
            forKey: .previousStatusName
        )
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        statusChanged = try container.decodeIfPresent(Bool.self, forKey: .statusChanged) ?? false
        carried = try container.decodeIfPresent(Bool.self, forKey: .carried) ?? false
        workLog = try container.decodeIfPresent([String].self, forKey: .workLog) ?? []
        workLogCreated = try container.decodeIfPresent(
            Bool.self,
            forKey: .workLogCreated
        ) ?? false
        typedWorkLog = try container.decodeIfPresent([String].self, forKey: .typedWorkLog) ?? []
        typedWorkLogDetails = try container.decodeIfPresent(
            [[String]].self,
            forKey: .typedWorkLogDetails
        ) ?? []
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case blockLink = "block_link"
        case ledgerLine = "ledger_line"
        case index
        case resolved
        case relativeTarget = "relative_target"
        case blockID = "block_id"
        case text
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case statusChanged = "status_changed"
        case carried
        case workLog = "work_log"
        case workLogCreated = "work_log_created"
        case typedWorkLog = "typed_work_log"
        case typedWorkLogDetails = "typed_work_log_details"
        case warning
    }
}

public struct PomodoroCloseCarriedItem: Codable, Equatable, Sendable {
    public let kind: String
    public let text: String

    public init(kind: String, text: String) {
        self.kind = kind
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "unknown"
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
    }
}

public struct PomodoroCloseNext: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let timeRange: String?
    public let created: Bool

    public init(line: Int, name: String? = nil, timeRange: String? = nil, created: Bool = false) {
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.created = created
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        created = try container.decodeIfPresent(Bool.self, forKey: .created) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case timeRange = "time_range"
        case created
    }
}

/// Bob's complete, resolved preview for a Pomodoro close. Every value is additive
/// to capture schema v1 and absent on older Bob binaries. Every field decodes
/// tolerantly (booleans default to false, arrays to empty, lines to zero) so a
/// partial object still previews instead of failing the whole capture.
/// `inProgress`/`park`/`complete`/`drop` report concrete selections;
/// `parkAll`/`completeAll` preserve wildcard intent after Bob expands it over
/// the resolved lineup. `taskLinks` is that numbered lineup, possibly empty.
/// Older Bob omits the additive flags and they decode as false.
public struct PomodoroCloseSummary: Codable, Equatable, Sendable {
    public let raw: String
    public let inProgress: [Int]?
    public let park: [Int]
    public let parkAll: Bool
    public let complete: [Int]
    public let completeAll: Bool
    public let drop: [Int]
    public let log: [PomodoroCloseLogEntry]
    public let pomodoroLine: Int
    public let pomodoroName: String?
    public let dayRelative: String?
    public let entryLine: String
    public let planned: PomodoroCloseTiming
    public let closed: PomodoroCloseTiming
    public let closedAt: String
    public let remainingMinutes: Int
    public let decrementedMinutes: Int
    public let tasks: [PomodoroCloseTask]
    public let taskLinks: [PomodoroCloseTaskLink]
    public let carried: [PomodoroCloseCarriedItem]
    public let notes: [String]
    public let nextPomodoro: PomodoroCloseNext?

    public init(
        raw: String,
        inProgress: [Int]? = nil,
        park: [Int] = [],
        parkAll: Bool = false,
        complete: [Int] = [],
        completeAll: Bool = false,
        drop: [Int] = [],
        log: [PomodoroCloseLogEntry] = [],
        pomodoroLine: Int = 0,
        pomodoroName: String? = nil,
        dayRelative: String? = nil,
        entryLine: String = "",
        planned: PomodoroCloseTiming = PomodoroCloseTiming(
            start: "",
            end: "",
            durationMinutes: 0,
            timeRange: ""
        ),
        closed: PomodoroCloseTiming = PomodoroCloseTiming(
            start: "",
            end: "",
            durationMinutes: 0,
            timeRange: ""
        ),
        closedAt: String = "",
        remainingMinutes: Int = 0,
        decrementedMinutes: Int = 0,
        tasks: [PomodoroCloseTask] = [],
        taskLinks: [PomodoroCloseTaskLink] = [],
        carried: [PomodoroCloseCarriedItem] = [],
        notes: [String] = [],
        nextPomodoro: PomodoroCloseNext? = nil
    ) {
        self.raw = raw
        self.inProgress = inProgress
        self.park = park
        self.parkAll = parkAll
        self.complete = complete
        self.completeAll = completeAll
        self.drop = drop
        self.log = log
        self.pomodoroLine = pomodoroLine
        self.pomodoroName = pomodoroName
        self.dayRelative = dayRelative
        self.entryLine = entryLine
        self.planned = planned
        self.closed = closed
        self.closedAt = closedAt
        self.remainingMinutes = remainingMinutes
        self.decrementedMinutes = decrementedMinutes
        self.tasks = tasks
        self.taskLinks = taskLinks
        self.carried = carried
        self.notes = notes
        self.nextPomodoro = nextPomodoro
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        inProgress = try container.decodeIfPresent([Int].self, forKey: .inProgress)
        park = try container.decodeIfPresent([Int].self, forKey: .park) ?? []
        parkAll = try container.decodeIfPresent(Bool.self, forKey: .parkAll) ?? false
        complete = try container.decodeIfPresent([Int].self, forKey: .complete) ?? []
        completeAll = try container.decodeIfPresent(Bool.self, forKey: .completeAll) ?? false
        drop = try container.decodeIfPresent([Int].self, forKey: .drop) ?? []
        log = try container.decodeIfPresent([PomodoroCloseLogEntry].self, forKey: .log) ?? []
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        dayRelative = try container.decodeIfPresent(String.self, forKey: .dayRelative)
        entryLine = try container.decodeIfPresent(String.self, forKey: .entryLine) ?? ""
        planned = try container.decodeIfPresent(
            PomodoroCloseTiming.self,
            forKey: .planned
        ) ?? PomodoroCloseTiming(start: "", end: "", durationMinutes: 0, timeRange: "")
        closed = try container.decodeIfPresent(
            PomodoroCloseTiming.self,
            forKey: .closed
        ) ?? PomodoroCloseTiming(start: "", end: "", durationMinutes: 0, timeRange: "")
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt) ?? ""
        remainingMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .remainingMinutes
        ) ?? 0
        decrementedMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .decrementedMinutes
        ) ?? 0
        tasks = try container.decodeIfPresent([PomodoroCloseTask].self, forKey: .tasks) ?? []
        taskLinks = try container.decodeIfPresent(
            [PomodoroCloseTaskLink].self,
            forKey: .taskLinks
        ) ?? []
        carried = try container.decodeIfPresent(
            [PomodoroCloseCarriedItem].self,
            forKey: .carried
        ) ?? []
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        nextPomodoro = try container.decodeIfPresent(
            PomodoroCloseNext.self,
            forKey: .nextPomodoro
        )
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case inProgress = "in_progress"
        case park
        case parkAll = "park_all"
        case complete
        case completeAll = "complete_all"
        case drop
        case log
        case pomodoroLine = "pomodoro_line"
        case pomodoroName = "pomodoro_name"
        case dayRelative = "day_relative"
        case entryLine = "entry_line"
        case planned
        case closed
        case closedAt = "closed_at"
        case remainingMinutes = "remaining_minutes"
        case decrementedMinutes = "decremented_minutes"
        case tasks
        case taskLinks = "task_links"
        case carried
        case notes
        case nextPomodoro = "next_pomodoro"
    }
}

/// One note-free `=x0` reset from Bob's additive `pomodoro_reset` result:
/// the current Pomodoro returned to the front of the future queue with its
/// session ledger cleared. Reset and `pomodoro_close` are mutually exclusive.
/// Older Bob binaries omit the key entirely; decode as nil.
public struct PomodoroResetSummary: Codable, Equatable, Sendable {
    public let raw: String
    public let dayRelative: String
    public let pomodoroName: String?
    public let previousPomodoroLine: Int
    public let pomodoroLine: Int
    public let previousEntryLine: String
    public let entryLine: String
    public let previousTimeRange: String
    public let timeRange: String?
    public let createdPomodoro: Bool
    public let moved: Bool

    public init(
        raw: String,
        dayRelative: String,
        pomodoroName: String? = nil,
        previousPomodoroLine: Int = 0,
        pomodoroLine: Int = 0,
        previousEntryLine: String = "",
        entryLine: String = "",
        previousTimeRange: String = "",
        timeRange: String? = nil,
        createdPomodoro: Bool = false,
        moved: Bool = false
    ) {
        self.raw = raw
        self.dayRelative = dayRelative
        self.pomodoroName = pomodoroName
        self.previousPomodoroLine = previousPomodoroLine
        self.pomodoroLine = pomodoroLine
        self.previousEntryLine = previousEntryLine
        self.entryLine = entryLine
        self.previousTimeRange = previousTimeRange
        self.timeRange = timeRange
        self.createdPomodoro = createdPomodoro
        self.moved = moved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        dayRelative = try container.decodeIfPresent(String.self, forKey: .dayRelative) ?? ""
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        previousPomodoroLine = try container.decodeIfPresent(Int.self, forKey: .previousPomodoroLine) ?? 0
        pomodoroLine = try container.decodeIfPresent(Int.self, forKey: .pomodoroLine) ?? 0
        previousEntryLine = try container.decodeIfPresent(String.self, forKey: .previousEntryLine) ?? ""
        entryLine = try container.decodeIfPresent(String.self, forKey: .entryLine) ?? ""
        previousTimeRange = try container.decodeIfPresent(String.self, forKey: .previousTimeRange) ?? ""
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        createdPomodoro = try container.decodeIfPresent(Bool.self, forKey: .createdPomodoro) ?? false
        moved = try container.decodeIfPresent(Bool.self, forKey: .moved) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case dayRelative = "day_relative"
        case pomodoroName = "pomodoro_name"
        case previousPomodoroLine = "previous_pomodoro_line"
        case pomodoroLine = "pomodoro_line"
        case previousEntryLine = "previous_entry_line"
        case entryLine = "entry_line"
        case previousTimeRange = "previous_time_range"
        case timeRange = "time_range"
        case createdPomodoro = "created_pomodoro"
        case moved
    }
}

public struct CaptureRewriteResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let input: String
    public let text: String
    public let changed: Bool
    public let cursor: Int?
    public let rule: String?
    public let edits: [CaptureRewriteEdit]
    public let summary: String?
    public let notices: [String]

    public init(
        ok: Bool,
        schemaVersion: Int,
        input: String,
        text: String,
        changed: Bool,
        cursor: Int? = nil,
        rule: String? = nil,
        edits: [CaptureRewriteEdit] = [],
        summary: String? = nil,
        notices: [String] = []
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.input = input
        self.text = text
        self.changed = changed
        self.cursor = cursor
        self.rule = rule
        self.edits = edits
        self.summary = summary
        self.notices = notices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        input = try container.decode(String.self, forKey: .input)
        text = try container.decode(String.self, forKey: .text)
        changed = try container.decode(Bool.self, forKey: .changed)
        cursor = try container.decodeIfPresent(Int.self, forKey: .cursor)
        rule = try container.decodeIfPresent(String.self, forKey: .rule)
        edits = try container.decodeIfPresent([CaptureRewriteEdit].self, forKey: .edits) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        notices = try container.decodeIfPresent([String].self, forKey: .notices) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case input
        case text
        case changed
        case cursor
        case rule
        case edits
        case summary
        case notices
    }
}

public struct CaptureRewriteEdit: Codable, Equatable {
    public let range: CaptureRange
    public let replacement: String

    public init(range: CaptureRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

public struct CaptureGlobalDestination: Codable, Equatable {
    public let range: CaptureRange?
    public let mode: String
    public let route: String?
    public let blockID: String?
    public let needs: [String]

    public init(
        range: CaptureRange? = nil,
        mode: String,
        route: String? = nil,
        blockID: String? = nil,
        needs: [String] = []
    ) {
        self.range = range
        self.mode = mode
        self.route = route
        self.blockID = blockID
        self.needs = needs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decodeIfPresent(CaptureRange.self, forKey: .range)
        mode = try container.decode(String.self, forKey: .mode)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        needs = try container.decodeIfPresent([String].self, forKey: .needs) ?? []
    }

    public var destinationLabel: String {
        route.map { "\($0).md" } ?? "global destination"
    }

    public var scopeSummary: String {
        guard let blockID, !blockID.isEmpty else {
            return destinationLabel
        }
        return "\(destinationLabel) \u{00b7} under ^\(blockID)"
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case mode
        case route
        case blockID = "block_id"
        case needs
    }
}

// `bob capture --format json` has no schema_version: success and failure are
// distinguished only by `ok`, and a failure keeps `error` as its sole other field.
// Bob may omit empty collections and nil scalars, so collection fields decoded from bob
// use `decodeIfPresent(...) ?? []` while optional scalars stay optional.
public enum CaptureCommandResponse: Equatable, Decodable {
    case success(CaptureCommandSuccess)
    case failure(CaptureCommandFailure)

    public var ok: Bool {
        switch self {
        case .success(let value):
            return value.ok
        case .failure(let value):
            return value.ok
        }
    }

    private enum DiscriminatorKeys: String, CodingKey {
        case ok
    }

    public init(from decoder: Decoder) throws {
        let discriminator = try decoder.container(keyedBy: DiscriminatorKeys.self)
        if try discriminator.decode(Bool.self, forKey: .ok) {
            self = .success(try CaptureCommandSuccess(from: decoder))
        } else {
            self = .failure(try CaptureCommandFailure(from: decoder))
        }
    }
}

public struct PomodoroLinkEndpoint: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let timeRange: String?
    // Additive plan-budget destination role: `current` (the running timed
    // entry), `next_up` (implicitly chosen and not running), `named` (an
    // existing entry matched by `#NAME`), or `created` (a new entry).
    // Older Bob omits it and it decodes as nil; unknown values are
    // preserved verbatim and degrade to neutral presentation.
    public let role: String?

    public init(line: Int, name: String? = nil, timeRange: String? = nil, role: String? = nil) {
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.role = role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        role = try container.decodeIfPresent(String.self, forKey: .role)
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case timeRange = "time_range"
        case role
    }
}

/// One cap warning inside `plan_budget`: only the theme and link caps ever
/// fire here, and only while growing past the cap. Every field decodes
/// tolerantly so a partial object still yields a row instead of failing
/// the whole capture.
public struct CapturePlanBudgetWarning: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

/// A before/after meter inside `plan_budget`. `before` is the pre-batch
/// count; it is optional because older Bob binaries omit it.
public struct CapturePlanBudgetMeter: Codable, Equatable, Sendable {
    public let count: Int
    public let cap: Int
    public let over: Bool
    public let before: Int?

    public init(count: Int, cap: Int, over: Bool, before: Int? = nil) {
        self.count = count
        self.cap = cap
        self.over = over
        self.before = before
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        cap = try container.decodeIfPresent(Int.self, forKey: .cap) ?? 0
        over = try container.decodeIfPresent(Bool.self, forKey: .over) ?? false
        before = try container.decodeIfPresent(Int.self, forKey: .before)
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case cap
        case over
        case before
    }
}

/// Top-level `plan_budget` on a `bob capture --format json` success:
/// present only when the batch changed today's Pomodoros section. It is
/// not per item. Older Bob omits it entirely and it decodes as nil.
public struct CapturePlanBudget: Codable, Equatable, Sendable {
    public let status: String
    public let themes: CapturePlanBudgetMeter
    public let links: CapturePlanBudgetMeter
    public let addedThemes: [String]
    public let warnings: [CapturePlanBudgetWarning]

    public init(
        status: String,
        themes: CapturePlanBudgetMeter,
        links: CapturePlanBudgetMeter,
        addedThemes: [String] = [],
        warnings: [CapturePlanBudgetWarning] = []
    ) {
        self.status = status
        self.themes = themes
        self.links = links
        self.addedThemes = addedThemes
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        themes = try container.decodeIfPresent(
            CapturePlanBudgetMeter.self,
            forKey: .themes
        ) ?? CapturePlanBudgetMeter(count: 0, cap: 0, over: false)
        links = try container.decodeIfPresent(
            CapturePlanBudgetMeter.self,
            forKey: .links
        ) ?? CapturePlanBudgetMeter(count: 0, cap: 0, over: false)
        addedThemes = try container.decodeIfPresent([String].self, forKey: .addedThemes) ?? []
        warnings = try container.decodeIfPresent(
            [CapturePlanBudgetWarning].self,
            forKey: .warnings
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case themes
        case links
        case addedThemes = "added_themes"
        case warnings
    }
}

/// One named project task Bob linked into the Pomodoro: the block ID, the
/// `[[<stem>#^<id>]]` link, the task text, and the rendered `[*]`/`[?]` line.
/// `bob capture --format json` reports these in source order inside
/// `project_note.task_links`; older Bob binaries omit the whole object.
public struct CaptureProjectTaskLink: Codable, Equatable, Sendable {
    public let blockID: String
    public let blockLink: String
    public let text: String
    public let taskLine: String

    public init(blockID: String, blockLink: String, text: String, taskLine: String) {
        self.blockID = blockID
        self.blockLink = blockLink
        self.text = text
        self.taskLine = taskLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        taskLine = try container.decodeIfPresent(String.self, forKey: .taskLine) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case blockLink = "block_link"
        case text
        case taskLine = "task_line"
    }
}

/// The additive `project_note` object on a `project_note` capture result:
/// the new note's identity plus the Task Links written into the Pomodoro.
/// `task_links` is always present on newer Bob and may be empty; older Bob
/// binaries omit the whole object and decode as nil.
public struct CaptureProjectNoteSummary: Codable, Equatable, Sendable {
    public let basename: String
    public let parentRoute: String
    public let parentLink: String
    public let tasks: Int
    public let sections: [String]
    public let taskLinks: [CaptureProjectTaskLink]

    public init(
        basename: String,
        parentRoute: String = "",
        parentLink: String = "",
        tasks: Int = 0,
        sections: [String] = [],
        taskLinks: [CaptureProjectTaskLink] = []
    ) {
        self.basename = basename
        self.parentRoute = parentRoute
        self.parentLink = parentLink
        self.tasks = tasks
        self.sections = sections
        self.taskLinks = taskLinks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basename = try container.decodeIfPresent(String.self, forKey: .basename) ?? ""
        parentRoute = try container.decodeIfPresent(String.self, forKey: .parentRoute) ?? ""
        parentLink = try container.decodeIfPresent(String.self, forKey: .parentLink) ?? ""
        tasks = try container.decodeIfPresent(Int.self, forKey: .tasks) ?? 0
        sections = try container.decodeIfPresent([String].self, forKey: .sections) ?? []
        taskLinks = try container.decodeIfPresent(
            [CaptureProjectTaskLink].self,
            forKey: .taskLinks
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case basename
        case parentRoute = "parent_route"
        case parentLink = "parent_link"
        case tasks
        case sections
        case taskLinks = "task_links"
    }
}

/// The offline library verdict on a reference item: one of `not_found`,
/// `in_library`, `in_intake`, `clipping`, `duplicate`, `legacy`, or `unknown`.
/// Every field decodes tolerantly so a malformed verdict degrades to defaults
/// instead of failing the capture decode.
public struct CaptureRefLibrary: Codable, Equatable, Sendable {
    public let verdict: String
    public let path: String?
    public let title: String?
    public let readingState: String?
    public let message: String?

    public init(
        verdict: String = "",
        path: String? = nil,
        title: String? = nil,
        readingState: String? = nil,
        message: String? = nil
    ) {
        self.verdict = verdict
        self.path = path
        self.title = title
        self.readingState = readingState
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try container.decodeIfPresent(String.self, forKey: .verdict) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        readingState = try container.decodeIfPresent(String.self, forKey: .readingState)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case verdict
        case path
        case title
        case readingState = "reading_state"
        case message
    }
}

/// The staged ref job on a real run that queued the link. Present only when
/// the run queued a job; dry runs and unchanged items omit it.
public struct CaptureRefJob: Codable, Equatable, Sendable {
    public let id: String
    public let state: String

    public init(id: String = "", state: String = "") {
        self.id = id
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case state
    }
}

/// The inbox fallback on a queued reference item: where the task goes when the
/// background clip fails. Present only on queued items.
public struct CaptureRefFallback: Codable, Equatable, Sendable {
    public let relativeTarget: String
    public let taskLine: String

    public init(relativeTarget: String = "", taskLine: String = "") {
        self.relativeTarget = relativeTarget
        self.taskLine = taskLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        taskLine = try container.decodeIfPresent(String.self, forKey: .taskLine) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case relativeTarget = "relative_target"
        case taskLine = "task_line"
    }
}

/// The additive `ref` object on a reference (`kind == "ref"`) capture result:
/// the classified URL, its offline library verdict, the staged job (real runs
/// that queued only), and the inbox fallback (queued items only). Older Bob
/// binaries omit it entirely; decode as nil, and a malformed value decodes as
/// nil so it can never fail the capture decode.
public struct CaptureRef: Codable, Equatable, Sendable {
    public let url: String
    public let cleanedURL: String
    public let dedupeKey: String
    public let display: String
    public let routeHint: String
    public let library: CaptureRefLibrary
    public let job: CaptureRefJob?
    public let fallback: CaptureRefFallback?

    public init(
        url: String = "",
        cleanedURL: String = "",
        dedupeKey: String = "",
        display: String = "",
        routeHint: String = "",
        library: CaptureRefLibrary = CaptureRefLibrary(),
        job: CaptureRefJob? = nil,
        fallback: CaptureRefFallback? = nil
    ) {
        self.url = url
        self.cleanedURL = cleanedURL
        self.dedupeKey = dedupeKey
        self.display = display
        self.routeHint = routeHint
        self.library = library
        self.job = job
        self.fallback = fallback
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        cleanedURL = try container.decodeIfPresent(String.self, forKey: .cleanedURL) ?? ""
        dedupeKey = try container.decodeIfPresent(String.self, forKey: .dedupeKey) ?? ""
        display = try container.decodeIfPresent(String.self, forKey: .display) ?? ""
        routeHint = try container.decodeIfPresent(String.self, forKey: .routeHint) ?? ""
        library = try container.decodeIfPresent(CaptureRefLibrary.self, forKey: .library)
            ?? CaptureRefLibrary()
        job = try container.decodeIfPresent(CaptureRefJob.self, forKey: .job)
        fallback = try container.decodeIfPresent(CaptureRefFallback.self, forKey: .fallback)
    }

    /// Whether the object carries no identity at all: every field defaulted,
    /// as from `{"ref": {"raw": 42}}`. Such an object presents as nothing.
    public var isEmpty: Bool {
        url.isEmpty && display.isEmpty && dedupeKey.isEmpty && library.verdict.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case cleanedURL = "cleaned_url"
        case dedupeKey = "dedupe_key"
        case display
        case routeHint = "route_hint"
        case library
        case job
        case fallback
    }
}

public struct CaptureCommandSuccess: Codable, Equatable {
    public let ok: Bool
    public let dryRun: Bool
    public let routed: Bool
    public let route: String?
    public let routeLabel: String
    public let relativeTarget: String
    public let target: String
    public let text: String
    public let taskLine: String
    public let kind: String
    public let created: String
    public let scheduled: String?
    public let priority: String?
    public let priorityLabel: String?
    public let placement: String
    // Additive: `bob capture` omits this key entirely when a draft has no authored
    // sub-bullets, so decoding must tolerate its absence. These are the exact rendered
    // Markdown child lines (including target-selected indentation), unlike
    // `CaptureParseResponse.subBullets`'s normalized semantic bodies.
    public let subBullets: [String]
    public let clip: CaptureClipOutput?
    public let scheduleLog: CaptureScheduleLog?
    public let blockID: String?
    public let dayFile: String?
    public let blockLink: String?
    public let pomodoroLinkPlacement: String?
    public let parentLine: Int?
    public let parentText: String?
    public let parentSection: String?
    public let parentStatusSymbol: String?
    public let parentStatusName: String?
    // Additive: only present when `kind == "task_toggle"`. Bob always populates every
    // one of these together, so a decoded toggle response either has all of them or
    // none; `removedScheduled`, `scheduleLog`, and `pomodoroName` stay legitimately
    // optional per-toggle depending on what the toggle actually did.
    public let toggleDirection: String?
    public let previousTaskLine: String?
    public let statusSymbol: String?
    public let statusName: String?
    public let previousStatusSymbol: String?
    public let previousStatusName: String?
    public let pomodoroName: String?
    public let createsPomodoro: Bool?
    public let pomodoroAlreadyLinked: Bool?
    public let removedPomodoroLinks: Int?
    public let removedScheduled: String?
    public let pomodoroSelectorUnused: Bool?
    // Additive to schema version 1 for Bob's ensure-Next task-toggle behavior. Older
    // Bob binaries and two-way toggles omit these keys; missing values preserve
    // compatibility.
    public let toggleBehavior: String?
    public let statusChanged: Bool?
    public let pomodoroLinkAction: String?
    public let pomodoroLinkSource: PomodoroLinkEndpoint?
    public let pomodoroLinkDestination: PomodoroLinkEndpoint?
    // Additive atomic-start summary for `@<route>:<block-id>[#<name>]=<X>`
    // and whole-item `=`/`=<X>` starts. Older bob binaries omit it entirely;
    // decode as nil.
    public let pomodoroStart: PomodoroStartSummary?
    // Additive adjustment summary for whole-item `+N`/`-N`.
    // Older bob binaries omit it entirely; decode as nil.
    public let pomodoroAdjust: PomodoroAdjustSummary?
    // Additive shift summary for whole-item `++N`/`--N`.
    // Older bob binaries omit it entirely; decode as nil.
    public let pomodoroShift: PomodoroShiftSummary?
    // Additive session-close result for `=x` and task-link closes. Older Bob
    // binaries omit it entirely; decode as nil.
    public let pomodoroClose: PomodoroCloseSummary?
    // Additive note-free `=x0` reset result. Mutually exclusive with
    // `pomodoroClose`. Older Bob binaries omit it entirely; decode as nil.
    public let pomodoroReset: PomodoroResetSummary?
    // Additive dependency summary for captures that add prerequisites:
    // dependent identity and text, added/already-present counts,
    // prerequisite summaries, open prerequisite count, and resulting
    // dependent status. Older Bob omits it entirely; decode as nil.
    public let dependencyUpdate: DependencyUpdateSummary?
    // Additive `task_complete` object on a whole-item `!note:block-id`
    // completion. Older Bob binaries omit it entirely; decode as nil, and a
    // malformed value decodes as nil so it can never fail the capture decode.
    public let taskComplete: CaptureTaskComplete?
    // Additive `project_note` object (including `task_links`) on a
    // `project_note` capture. Older Bob binaries omit it entirely; decode
    // as nil.
    public let projectNote: CaptureProjectNoteSummary?
    // Additive `ref` object on a `ref` capture. Older Bob binaries omit it
    // entirely; decode as nil, and a malformed value decodes as nil so it
    // can never fail the capture decode.
    public let ref: CaptureRef?
    // Additive top-level `plan_budget`: present only when the batch changed
    // today's Pomodoros section. It is not per item. Older Bob omits it
    // entirely; decode as nil.
    public let planBudget: CapturePlanBudget?
    // Additive batch-level `pomodoro_blocks`: every Pomodoro the capture
    // touches, creates, or reports, in its final after-state. Older Bob
    // omits it entirely, and a malformed value decodes as empty so it can
    // never fail the capture decode.
    public let pomodoroBlocks: [CapturePomodoroBlock]
    // Additive batch-level `task_blocks`: every parent task a sub-bullet
    // capture wrote under, in its final after-state. Older Bob omits it
    // entirely, and a malformed value decodes as empty so it can never
    // fail the capture decode.
    public let taskBlocks: [CaptureTaskBlock]
    public let captures: [CaptureCommandSuccess]
    public let globalDestination: CaptureGlobalDestination?
    public let warnings: [String]

    public init(
        ok: Bool,
        dryRun: Bool,
        routed: Bool,
        route: String? = nil,
        routeLabel: String,
        relativeTarget: String,
        target: String,
        text: String,
        taskLine: String,
        kind: String,
        created: String,
        scheduled: String? = nil,
        priority: String? = nil,
        priorityLabel: String? = nil,
        placement: String,
        subBullets: [String] = [],
        clip: CaptureClipOutput? = nil,
        scheduleLog: CaptureScheduleLog? = nil,
        blockID: String? = nil,
        dayFile: String? = nil,
        blockLink: String? = nil,
        pomodoroLinkPlacement: String? = nil,
        parentLine: Int? = nil,
        parentText: String? = nil,
        parentSection: String? = nil,
        parentStatusSymbol: String? = nil,
        parentStatusName: String? = nil,
        toggleDirection: String? = nil,
        previousTaskLine: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        previousStatusSymbol: String? = nil,
        previousStatusName: String? = nil,
        pomodoroName: String? = nil,
        createsPomodoro: Bool? = nil,
        pomodoroAlreadyLinked: Bool? = nil,
        removedPomodoroLinks: Int? = nil,
        removedScheduled: String? = nil,
        pomodoroSelectorUnused: Bool? = nil,
        toggleBehavior: String? = nil,
        statusChanged: Bool? = nil,
        pomodoroLinkAction: String? = nil,
        pomodoroLinkSource: PomodoroLinkEndpoint? = nil,
        pomodoroLinkDestination: PomodoroLinkEndpoint? = nil,
        pomodoroStart: PomodoroStartSummary? = nil,
        pomodoroAdjust: PomodoroAdjustSummary? = nil,
        pomodoroShift: PomodoroShiftSummary? = nil,
        pomodoroClose: PomodoroCloseSummary? = nil,
        pomodoroReset: PomodoroResetSummary? = nil,
        dependencyUpdate: DependencyUpdateSummary? = nil,
        taskComplete: CaptureTaskComplete? = nil,
        projectNote: CaptureProjectNoteSummary? = nil,
        ref: CaptureRef? = nil,
        planBudget: CapturePlanBudget? = nil,
        captures: [CaptureCommandSuccess] = [],
        globalDestination: CaptureGlobalDestination? = nil,
        warnings: [String] = [],
        pomodoroBlocks: [CapturePomodoroBlock] = [],
        taskBlocks: [CaptureTaskBlock] = []
    ) {
        self.ok = ok
        self.dryRun = dryRun
        self.routed = routed
        self.route = route
        self.routeLabel = routeLabel
        self.relativeTarget = relativeTarget
        self.target = target
        self.text = text
        self.taskLine = taskLine
        self.kind = kind
        self.created = created
        self.scheduled = scheduled
        self.priority = priority
        self.priorityLabel = priorityLabel
        self.placement = placement
        self.subBullets = subBullets
        self.clip = clip
        self.scheduleLog = scheduleLog
        self.blockID = blockID
        self.dayFile = dayFile
        self.blockLink = blockLink
        self.pomodoroLinkPlacement = pomodoroLinkPlacement
        self.parentLine = parentLine
        self.parentText = parentText
        self.parentSection = parentSection
        self.parentStatusSymbol = parentStatusSymbol
        self.parentStatusName = parentStatusName
        self.toggleDirection = toggleDirection
        self.previousTaskLine = previousTaskLine
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.pomodoroName = pomodoroName
        self.createsPomodoro = createsPomodoro
        self.pomodoroAlreadyLinked = pomodoroAlreadyLinked
        self.removedPomodoroLinks = removedPomodoroLinks
        self.removedScheduled = removedScheduled
        self.pomodoroSelectorUnused = pomodoroSelectorUnused
        self.toggleBehavior = toggleBehavior
        self.statusChanged = statusChanged
        self.pomodoroLinkAction = pomodoroLinkAction
        self.pomodoroLinkSource = pomodoroLinkSource
        self.pomodoroLinkDestination = pomodoroLinkDestination
        self.pomodoroStart = pomodoroStart
        self.pomodoroAdjust = pomodoroAdjust
        self.pomodoroShift = pomodoroShift
        self.pomodoroClose = pomodoroClose
        self.pomodoroReset = pomodoroReset
        self.dependencyUpdate = dependencyUpdate
        self.taskComplete = taskComplete
        self.projectNote = projectNote
        self.ref = ref
        self.planBudget = planBudget
        self.pomodoroBlocks = pomodoroBlocks
        self.taskBlocks = taskBlocks
        self.captures = captures
        self.globalDestination = globalDestination
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        dryRun = try container.decode(Bool.self, forKey: .dryRun)
        routed = try container.decode(Bool.self, forKey: .routed)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        routeLabel = try container.decode(String.self, forKey: .routeLabel)
        relativeTarget = try container.decode(String.self, forKey: .relativeTarget)
        target = try container.decode(String.self, forKey: .target)
        text = try container.decode(String.self, forKey: .text)
        taskLine = try container.decode(String.self, forKey: .taskLine)
        kind = try container.decode(String.self, forKey: .kind)
        created = try container.decode(String.self, forKey: .created)
        scheduled = try container.decodeIfPresent(String.self, forKey: .scheduled)
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        priorityLabel = try container.decodeIfPresent(String.self, forKey: .priorityLabel)
        placement = try container.decode(String.self, forKey: .placement)
        subBullets = try container.decodeIfPresent([String].self, forKey: .subBullets) ?? []
        clip = try container.decodeIfPresent(CaptureClipOutput.self, forKey: .clip)
        scheduleLog = try container.decodeIfPresent(CaptureScheduleLog.self, forKey: .scheduleLog)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        dayFile = try container.decodeIfPresent(String.self, forKey: .dayFile)
        blockLink = try container.decodeIfPresent(String.self, forKey: .blockLink)
        pomodoroLinkPlacement = try container.decodeIfPresent(String.self, forKey: .pomodoroLinkPlacement)
        parentLine = try container.decodeIfPresent(Int.self, forKey: .parentLine)
        parentText = try container.decodeIfPresent(String.self, forKey: .parentText)
        parentSection = try container.decodeIfPresent(String.self, forKey: .parentSection)
        parentStatusSymbol = try container.decodeIfPresent(String.self, forKey: .parentStatusSymbol)
        parentStatusName = try container.decodeIfPresent(String.self, forKey: .parentStatusName)
        toggleDirection = try container.decodeIfPresent(String.self, forKey: .toggleDirection)
        previousTaskLine = try container.decodeIfPresent(String.self, forKey: .previousTaskLine)
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        previousStatusSymbol = try container.decodeIfPresent(String.self, forKey: .previousStatusSymbol)
        previousStatusName = try container.decodeIfPresent(String.self, forKey: .previousStatusName)
        pomodoroName = try container.decodeIfPresent(String.self, forKey: .pomodoroName)
        createsPomodoro = try container.decodeIfPresent(Bool.self, forKey: .createsPomodoro)
        pomodoroAlreadyLinked = try container.decodeIfPresent(Bool.self, forKey: .pomodoroAlreadyLinked)
        removedPomodoroLinks = try container.decodeIfPresent(Int.self, forKey: .removedPomodoroLinks)
        removedScheduled = try container.decodeIfPresent(String.self, forKey: .removedScheduled)
        pomodoroSelectorUnused = try container.decodeIfPresent(Bool.self, forKey: .pomodoroSelectorUnused)
        toggleBehavior = try container.decodeIfPresent(String.self, forKey: .toggleBehavior)
        statusChanged = try container.decodeIfPresent(Bool.self, forKey: .statusChanged)
        pomodoroLinkAction = try container.decodeIfPresent(String.self, forKey: .pomodoroLinkAction)
        pomodoroLinkSource = try container.decodeIfPresent(
            PomodoroLinkEndpoint.self,
            forKey: .pomodoroLinkSource
        )
        pomodoroLinkDestination = try container.decodeIfPresent(
            PomodoroLinkEndpoint.self,
            forKey: .pomodoroLinkDestination
        )
        pomodoroStart = try container.decodeIfPresent(
            PomodoroStartSummary.self,
            forKey: .pomodoroStart
        )
        pomodoroAdjust = try container.decodeIfPresent(
            PomodoroAdjustSummary.self,
            forKey: .pomodoroAdjust
        )
        pomodoroShift = try container.decodeIfPresent(
            PomodoroShiftSummary.self,
            forKey: .pomodoroShift
        )
        pomodoroClose = try container.decodeIfPresent(
            PomodoroCloseSummary.self,
            forKey: .pomodoroClose
        )
        pomodoroReset = try container.decodeIfPresent(
            PomodoroResetSummary.self,
            forKey: .pomodoroReset
        )
        dependencyUpdate = try container.decodeIfPresent(
            DependencyUpdateSummary.self,
            forKey: .dependencyUpdate
        )
        taskComplete =
            (try? container.decodeIfPresent(
                CaptureTaskComplete.self,
                forKey: .taskComplete
            )) ?? nil
        projectNote = try container.decodeIfPresent(
            CaptureProjectNoteSummary.self,
            forKey: .projectNote
        )
        ref = (try? container.decodeIfPresent(CaptureRef.self, forKey: .ref)) ?? nil
        planBudget = try container.decodeIfPresent(
            CapturePlanBudget.self,
            forKey: .planBudget
        )
        pomodoroBlocks =
            (try? container.decodeIfPresent(
                [CapturePomodoroBlock].self,
                forKey: .pomodoroBlocks
            )) ?? []
        taskBlocks =
            (try? container.decodeIfPresent(
                [CaptureTaskBlock].self,
                forKey: .taskBlocks
            )) ?? []
        captures = try container.decodeIfPresent([CaptureCommandSuccess].self, forKey: .captures) ?? []
        globalDestination = try container.decodeIfPresent(
            CaptureGlobalDestination.self,
            forKey: .globalDestination
        )
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case dryRun = "dry_run"
        case routed
        case route
        case routeLabel = "route_label"
        case relativeTarget = "relative_target"
        case target
        case text
        case taskLine = "task_line"
        case kind
        case created
        case scheduled
        case priority
        case priorityLabel = "priority_label"
        case placement
        case subBullets = "sub_bullets"
        case clip
        case scheduleLog = "schedule_log"
        case blockID = "block_id"
        case dayFile = "day_file"
        case blockLink = "block_link"
        case pomodoroLinkPlacement = "pomodoro_link_placement"
        case parentLine = "parent_line"
        case parentText = "parent_text"
        case parentSection = "parent_section"
        case parentStatusSymbol = "parent_status_symbol"
        case parentStatusName = "parent_status_name"
        case toggleDirection = "toggle_direction"
        case previousTaskLine = "previous_task_line"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case pomodoroName = "pomodoro_name"
        case createsPomodoro = "creates_pomodoro"
        case pomodoroAlreadyLinked = "pomodoro_already_linked"
        case removedPomodoroLinks = "removed_pomodoro_links"
        case removedScheduled = "removed_scheduled"
        case pomodoroSelectorUnused = "pomodoro_selector_unused"
        case toggleBehavior = "toggle_behavior"
        case statusChanged = "status_changed"
        case pomodoroLinkAction = "pomodoro_link_action"
        case pomodoroLinkSource = "pomodoro_link_source"
        case pomodoroLinkDestination = "pomodoro_link_destination"
        case pomodoroStart = "pomodoro_start"
        case pomodoroAdjust = "pomodoro_adjust"
        case pomodoroShift = "pomodoro_shift"
        case pomodoroClose = "pomodoro_close"
        case pomodoroReset = "pomodoro_reset"
        case dependencyUpdate = "dependency_update"
        case taskComplete = "task_complete"
        case projectNote = "project_note"
        case ref
        case planBudget = "plan_budget"
        case pomodoroBlocks = "pomodoro_blocks"
        case taskBlocks = "task_blocks"
        case captures
        case globalDestination = "global_destination"
        case warnings
    }

    /// The exact Markdown block `bob capture` writes beneath the destination, in the
    /// same order the CLI renders and prints it: the captured parent line, the authored
    /// children, the clipboard children, then the priority-roll schedule log. Every line
    /// already carries the target note's own child indentation, so preview must render
    /// them verbatim rather than re-deriving nesting.
    ///
    /// Continuous live preview runs with `--no-clip`, so `clip` is absent there and the
    /// block is just the parent plus authored children; the explicit Preview and Capture
    /// paths resolve the clipboard and therefore mirror the full block.
    public var previewBlockLines: [String] {
        var lines = [taskLine]
        lines.append(contentsOf: subBullets)
        if let clip {
            lines.append(contentsOf: clip.lines)
        }
        if let scheduleLog {
            lines.append(contentsOf: scheduleLog.lines)
        }
        return lines
    }

    /// Bob preserves the legacy top-level success fields for one capture and for the
    /// first item of a multi-capture response. New callers should use this normalized
    /// collection so single and batch presentation share one code path.
    public var normalizedCaptures: [CaptureCommandSuccess] {
        captures.isEmpty ? [self] : captures
    }
}

public func captureUsesGlobalDestination(
    _ capture: CaptureCommandSuccess,
    _ globalDestination: CaptureGlobalDestination
) -> Bool {
    guard let globalRoute = globalDestination.route, !globalRoute.isEmpty else {
        return false
    }

    let routeMatches = capture.route == globalRoute
        || capture.routeLabel == "\(globalRoute).md"
        || capture.relativeTarget == "\(globalRoute).md"
    guard routeMatches else {
        return false
    }
    guard capture.blockID == globalDestination.blockID else {
        return false
    }

    switch normalizedCaptureKind(globalDestination.mode) {
    case "task":
        return normalizedCaptureKind(capture.kind) == "task"
    case "sub_bullet":
        return normalizedCaptureKind(capture.kind) == "sub_bullet"
    default:
        return true
    }
}

private func normalizedCaptureKind(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
}

/// One prerequisite in Bob's `dependency_update` preview detail: the exact
/// note identity, block ID, canonical `[[note#^id]]` link, status, text,
/// and whether it still blocks the dependent. Closed prerequisites do not
/// block. Older Bob omits the whole object; decode tolerantly.
public struct DependencyPrerequisite: Codable, Equatable, Sendable {
    public let note: String
    public let blockID: String
    public let link: String
    public let statusSymbol: String
    public let statusName: String
    public let text: String
    public let isOpen: Bool

    public init(
        note: String,
        blockID: String,
        link: String,
        statusSymbol: String,
        statusName: String,
        text: String,
        isOpen: Bool
    ) {
        self.note = note
        self.blockID = blockID
        self.link = link
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.text = text
        self.isOpen = isOpen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        isOpen = try container.decodeIfPresent(Bool.self, forKey: .isOpen) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case note
        case blockID = "block_id"
        case link
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case text
        case isOpen = "open"
    }
}

/// Optional `dependency_update` execution/preview detail on a capture that
/// adds prerequisites: dependent identity and text, added/already-present
/// counts, prerequisite summaries, open prerequisite count, resulting
/// dependent status, and whether the capture created the dependent.
public struct DependencyUpdateSummary: Codable, Equatable, Sendable {
    public let dependentNote: String
    public let dependentText: String
    public let isNewTask: Bool
    public let added: Int
    public let alreadyPresent: Int
    public let openPrerequisites: Int
    public let prerequisites: [DependencyPrerequisite]
    public let dependentStatus: String
    public let dependentStatusName: String
    public let statusChanged: Bool

    public init(
        dependentNote: String,
        dependentText: String,
        isNewTask: Bool,
        added: Int,
        alreadyPresent: Int,
        openPrerequisites: Int,
        prerequisites: [DependencyPrerequisite] = [],
        dependentStatus: String,
        dependentStatusName: String,
        statusChanged: Bool
    ) {
        self.dependentNote = dependentNote
        self.dependentText = dependentText
        self.isNewTask = isNewTask
        self.added = added
        self.alreadyPresent = alreadyPresent
        self.openPrerequisites = openPrerequisites
        self.prerequisites = prerequisites
        self.dependentStatus = dependentStatus
        self.dependentStatusName = dependentStatusName
        self.statusChanged = statusChanged
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dependentNote = try container.decodeIfPresent(String.self, forKey: .dependentNote) ?? ""
        dependentText = try container.decodeIfPresent(String.self, forKey: .dependentText) ?? ""
        isNewTask = try container.decodeIfPresent(Bool.self, forKey: .isNewTask) ?? false
        added = try container.decodeIfPresent(Int.self, forKey: .added) ?? 0
        alreadyPresent = try container.decodeIfPresent(Int.self, forKey: .alreadyPresent) ?? 0
        openPrerequisites = try container.decodeIfPresent(Int.self, forKey: .openPrerequisites) ?? 0
        prerequisites = try container.decodeIfPresent(
            [DependencyPrerequisite].self,
            forKey: .prerequisites
        ) ?? []
        dependentStatus = try container.decodeIfPresent(String.self, forKey: .dependentStatus) ?? ""
        dependentStatusName = try container.decodeIfPresent(String.self, forKey: .dependentStatusName) ?? ""
        statusChanged = try container.decodeIfPresent(Bool.self, forKey: .statusChanged) ?? false
    }

    /// Preview headline: `New task · depends on …` for created dependents,
    /// `Add dependency to "…"` for existing ones. Never "Create task" for a
    /// dependency-only action.
    public var headline: String {
        if isNewTask {
            return "New task · depends on \(prerequisites.count == 1 ? "1 task" : "\(prerequisites.count) tasks")"
        }
        return "Add dependency to \u{201C}\(dependentText)\u{201D}"
    }

    /// The resulting managed child line, from Bob's canonical prerequisite
    /// links in typed order.
    public var managedLineText: String {
        let links = prerequisites.map { $0.link }.joined(separator: " ")
        return "**DEPENDS ON:** \(links)"
    }

    /// Waiting count plus the Blocked/closed distinction, straight from Bob:
    /// open prerequisites block, closed ones do not.
    public var waitingText: String {
        if openPrerequisites == 0 {
            return "No open prerequisites · \(dependentStatusName)"
        }
        let waiting = openPrerequisites == 1 ? "Waiting on 1 open prerequisite" : "Waiting on \(openPrerequisites) open prerequisites"
        return "\(waiting) · \(dependentStatusName)"
    }

    /// VoiceOver summary for the dependency preview section.
    public var previewAccessibilitySummary: String {
        var parts = [headline, managedLineText, waitingText]
        if alreadyPresent > 0 {
            parts.append(alreadyPresent == 1 ? "1 already present" : "\(alreadyPresent) already present")
        }
        return parts.joined(separator: ". ") + "."
    }

    private enum CodingKeys: String, CodingKey {
        case dependentNote = "dependent_note"
        case dependentText = "dependent_text"
        case isNewTask = "new_task"
        case added
        case alreadyPresent = "already_present"
        case openPrerequisites = "open_prerequisites"
        case prerequisites
        case dependentStatus = "dependent_status"
        case dependentStatusName = "dependent_status_name"
        case statusChanged = "status_changed"
    }
}

/// One embedded subtask closed by a whole-item `!note:block-id` completion.
/// Every field decodes tolerantly so a partial object still yields a row
/// instead of failing the whole capture.
public struct TaskCompleteSubtask: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let line: Int
    public let text: String
    public let previousStatusSymbol: String
    public let previousStatusName: String
    public let statusSymbol: String
    public let statusName: String

    public init(
        notePath: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = "",
        previousStatusSymbol: String = "",
        previousStatusName: String = "",
        statusSymbol: String = "",
        statusName: String = ""
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.line = line
        self.text = text
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.statusSymbol = statusSymbol
        self.statusName = statusName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        previousStatusSymbol = try container.decodeIfPresent(String.self, forKey: .previousStatusSymbol) ?? ""
        previousStatusName = try container.decodeIfPresent(String.self, forKey: .previousStatusName) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case line
        case text
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
    }
}

/// One descendant left open by a whole-item `!note:block-id` completion.
/// `reason` is `blocked`, `recurring`, `unknown_status`, or `cap`.
public struct TaskCompleteLeftOpen: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let line: Int
    public let text: String
    public let statusSymbol: String
    public let statusName: String
    public let reason: String

    public init(
        notePath: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        reason: String = ""
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.line = line
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case line
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case reason
    }
}

/// One ledger endpoint for a `task_complete` move: 1-based line, short
/// entry name, and entry status.
public struct TaskCompleteLedgerEndpoint: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String
    public let status: String

    public init(line: Int = 0, name: String = "", status: String = "") {
        self.line = line
        self.name = name
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case status
    }
}

/// One moved bullet's source and destination ledger entries.
public struct TaskCompleteLedgerMove: Codable, Equatable, Sendable {
    public let from: TaskCompleteLedgerEndpoint
    public let to: TaskCompleteLedgerEndpoint

    public init(
        from: TaskCompleteLedgerEndpoint = TaskCompleteLedgerEndpoint(),
        to: TaskCompleteLedgerEndpoint = TaskCompleteLedgerEndpoint()
    ) {
        self.from = from
        self.to = to
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decodeIfPresent(
            TaskCompleteLedgerEndpoint.self,
            forKey: .from
        ) ?? TaskCompleteLedgerEndpoint()
        to = try container.decodeIfPresent(
            TaskCompleteLedgerEndpoint.self,
            forKey: .to
        ) ?? TaskCompleteLedgerEndpoint()
    }

    private enum CodingKeys: String, CodingKey {
        case from
        case to
    }
}

/// One placeholder removed by a `task_complete` item.
public struct TaskCompleteRemovedPlaceholder: Codable, Equatable, Sendable {
    public let name: String

    public init(name: String = "") {
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case name
    }
}

/// Ledger retirement for a `task_complete` item, omitted when today's
/// ledger was untouched. `struckIn` and `dropped` are nil on older Bob
/// payloads that predate them, so the presentation can keep the
/// count-based wording as a fallback; new Bob always sends both arrays
/// (possibly empty) whenever `ledger` is present.
public struct TaskCompleteLedger: Codable, Equatable, Sendable {
    public let dayFile: String
    public let struck: Int
    public let struckIn: [TaskCompleteLedgerEndpoint]?
    public let moved: [TaskCompleteLedgerMove]
    public let deduplicated: Int
    public let dropped: [TaskCompleteLedgerMove]?
    public let removedPlaceholders: [TaskCompleteRemovedPlaceholder]

    public init(
        dayFile: String = "",
        struck: Int = 0,
        struckIn: [TaskCompleteLedgerEndpoint]? = nil,
        moved: [TaskCompleteLedgerMove] = [],
        deduplicated: Int = 0,
        dropped: [TaskCompleteLedgerMove]? = nil,
        removedPlaceholders: [TaskCompleteRemovedPlaceholder] = []
    ) {
        self.dayFile = dayFile
        self.struck = struck
        self.struckIn = struckIn
        self.moved = moved
        self.deduplicated = deduplicated
        self.dropped = dropped
        self.removedPlaceholders = removedPlaceholders
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayFile = try container.decodeIfPresent(String.self, forKey: .dayFile) ?? ""
        struck = try container.decodeIfPresent(Int.self, forKey: .struck) ?? 0
        struckIn = try container.decodeIfPresent(
            [TaskCompleteLedgerEndpoint].self,
            forKey: .struckIn
        )
        moved = try container.decodeIfPresent(
            [TaskCompleteLedgerMove].self,
            forKey: .moved
        ) ?? []
        deduplicated = try container.decodeIfPresent(Int.self, forKey: .deduplicated) ?? 0
        dropped = try container.decodeIfPresent(
            [TaskCompleteLedgerMove].self,
            forKey: .dropped
        )
        removedPlaceholders = try container.decodeIfPresent(
            [TaskCompleteRemovedPlaceholder].self,
            forKey: .removedPlaceholders
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case dayFile = "day_file"
        case struck
        case struckIn = "struck_in"
        case moved
        case deduplicated
        case dropped
        case removedPlaceholders = "removed_placeholders"
    }
}

/// One dependent recovered by a `task_complete` item.
public struct TaskCompleteUnblocked: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let line: Int
    public let text: String
    public let previousStatusSymbol: String
    public let previousStatusName: String
    public let statusSymbol: String
    public let statusName: String

    public init(
        notePath: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = "",
        previousStatusSymbol: String = "",
        previousStatusName: String = "",
        statusSymbol: String = "",
        statusName: String = ""
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.line = line
        self.text = text
        self.previousStatusSymbol = previousStatusSymbol
        self.previousStatusName = previousStatusName
        self.statusSymbol = statusSymbol
        self.statusName = statusName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        previousStatusSymbol = try container.decodeIfPresent(String.self, forKey: .previousStatusSymbol) ?? ""
        previousStatusName = try container.decodeIfPresent(String.self, forKey: .previousStatusName) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol) ?? ""
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case line
        case text
        case previousStatusSymbol = "previous_status_symbol"
        case previousStatusName = "previous_status_name"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
    }
}

/// Bob's resolved preview for a whole-item `!note:block-id` completion.
/// Additive to capture schema v1 and absent on older Bob binaries. Every
/// field decodes tolerantly so a partial object still previews instead of
/// failing the whole capture. `subtasks`, `subtasks_left_open`, and
/// `unblocked` are always present (possibly empty) on a real Bob response;
/// `ledger` is omitted when today's ledger was untouched and
/// `completion_date` is omitted when `action` is `already_done`.
public struct CaptureTaskComplete: Codable, Equatable, Sendable {
    public let raw: String
    public let note: String
    public let notePath: String
    public let blockID: String
    public let action: String
    public let completionDate: String?
    /// Clean display text for the root task from Bob (configured global
    /// filter, inline fields, and trailing block ID stripped). Empty on
    /// older Bob payloads, which omit the key.
    public let text: String
    public let subtasks: [TaskCompleteSubtask]
    public let subtasksLeftOpen: [TaskCompleteLeftOpen]
    public let ledger: TaskCompleteLedger?
    public let unblocked: [TaskCompleteUnblocked]

    public init(
        raw: String = "",
        note: String = "",
        notePath: String = "",
        blockID: String = "",
        action: String = "",
        completionDate: String? = nil,
        text: String = "",
        subtasks: [TaskCompleteSubtask] = [],
        subtasksLeftOpen: [TaskCompleteLeftOpen] = [],
        ledger: TaskCompleteLedger? = nil,
        unblocked: [TaskCompleteUnblocked] = []
    ) {
        self.raw = raw
        self.note = note
        self.notePath = notePath
        self.blockID = blockID
        self.action = action
        self.completionDate = completionDate
        self.text = text
        self.subtasks = subtasks
        self.subtasksLeftOpen = subtasksLeftOpen
        self.ledger = ledger
        self.unblocked = unblocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        completionDate = try container.decodeIfPresent(String.self, forKey: .completionDate)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        subtasks = try container.decodeIfPresent(
            [TaskCompleteSubtask].self,
            forKey: .subtasks
        ) ?? []
        subtasksLeftOpen = try container.decodeIfPresent(
            [TaskCompleteLeftOpen].self,
            forKey: .subtasksLeftOpen
        ) ?? []
        ledger = try container.decodeIfPresent(TaskCompleteLedger.self, forKey: .ledger)
        unblocked = try container.decodeIfPresent(
            [TaskCompleteUnblocked].self,
            forKey: .unblocked
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case note
        case notePath = "note_path"
        case blockID = "block_id"
        case action
        case completionDate = "completion_date"
        case text
        case subtasks
        case subtasksLeftOpen = "subtasks_left_open"
        case ledger
        case unblocked
    }
}

public struct CaptureCommandFailure: Codable, Equatable {
    public let ok: Bool
    public let error: String
    // Additive machine-readable failure code, emitted only for the strict
    // plan-budget refusal (`plan_theme_cap_exceeded`). Older Bob omits it
    // and it decodes as nil.
    public let code: String?

    public init(ok: Bool = false, error: String, code: String? = nil) {
        self.ok = ok
        self.error = error
        self.code = code
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case error
        case code
    }
}

public enum CaptureTaskIDResponse: Equatable, Decodable {
    case success(CaptureTaskIDSuccess)
    case failure(CaptureCommandFailure)

    public var ok: Bool {
        switch self {
        case .success(let value):
            return value.ok
        case .failure(let value):
            return value.ok
        }
    }

    private enum DiscriminatorKeys: String, CodingKey {
        case ok
    }

    public init(from decoder: Decoder) throws {
        let discriminator = try decoder.container(keyedBy: DiscriminatorKeys.self)
        if try discriminator.decode(Bool.self, forKey: .ok) {
            self = .success(try CaptureTaskIDSuccess(from: decoder))
        } else {
            self = .failure(try CaptureCommandFailure(from: decoder))
        }
    }
}

public struct CaptureTaskIDSuccess: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let dryRun: Bool
    public let route: String
    public let relativeTarget: String
    public let blockID: String
    public let line: Int
    public let taskRef: String
    public let task: CaptureTaskIDTask
    /// Exact vault-relative note path including extension, present in
    /// `--note-path` mode so the app can resume the picker without losing
    /// quoting or case. Older Bob omits it; decode as nil.
    public let notePath: String?
    /// Backend-formatted `&note:id` (quoted when the locator needs it) to
    /// splice on a successful explicit ID assignment. Older Bob omits it;
    /// decode as nil.
    public let dependencyReplacement: String?
    /// Backend-formatted `@route+id` to splice on a successful vault-wide
    /// parent-task ID assignment. Older Bob omits it; decode as nil.
    public let parentReplacement: String?
    /// Backend-formatted `!note:id` (quoted when the locator needs it) to
    /// splice on a successful Complete picker ID assignment. Older Bob
    /// omits it; decode as nil.
    public let completeReplacement: String?

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        dryRun: Bool,
        route: String,
        relativeTarget: String,
        blockID: String,
        line: Int,
        taskRef: String,
        task: CaptureTaskIDTask,
        notePath: String? = nil,
        dependencyReplacement: String? = nil,
        parentReplacement: String? = nil,
        completeReplacement: String? = nil
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.dryRun = dryRun
        self.route = route
        self.relativeTarget = relativeTarget
        self.blockID = blockID
        self.line = line
        self.taskRef = taskRef
        self.task = task
        self.notePath = notePath
        self.dependencyReplacement = dependencyReplacement
        self.parentReplacement = parentReplacement
        self.completeReplacement = completeReplacement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        // `--note-path` responses omit `route`; the exact path is the
        // identity there, so a missing route decodes as empty.
        route = try container.decodeIfPresent(String.self, forKey: .route) ?? ""
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        taskRef = try container.decodeIfPresent(String.self, forKey: .taskRef) ?? ""
        task = try container.decode(CaptureTaskIDTask.self, forKey: .task)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath)
        dependencyReplacement = try container.decodeIfPresent(String.self, forKey: .dependencyReplacement)
        parentReplacement = try container.decodeIfPresent(String.self, forKey: .parentReplacement)
        completeReplacement = try container.decodeIfPresent(String.self, forKey: .completeReplacement)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case dryRun = "dry_run"
        case route
        case relativeTarget = "relative_target"
        case blockID = "block_id"
        case line
        case taskRef = "ref"
        case task
        case notePath = "note_path"
        case dependencyReplacement = "dependency_replacement"
        case parentReplacement = "parent_replacement"
        case completeReplacement = "complete_replacement"
    }
}

public struct CaptureTaskIDTask: Codable, Equatable {
    public let taskRef: String
    public let line: Int
    public let blockID: String
    public let statusSymbol: String
    public let statusName: String
    public let statusType: String
    public let text: String
    public let section: String?
    public let depth: Int
    public let childCount: Int

    public init(
        taskRef: String,
        line: Int,
        blockID: String,
        statusSymbol: String,
        statusName: String,
        statusType: String,
        text: String,
        section: String? = nil,
        depth: Int,
        childCount: Int
    ) {
        self.taskRef = taskRef
        self.line = line
        self.blockID = blockID
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.statusType = statusType
        self.text = text
        self.section = section
        self.depth = depth
        self.childCount = childCount
    }

    private enum CodingKeys: String, CodingKey {
        case taskRef = "ref"
        case line
        case blockID = "block_id"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case statusType = "status_type"
        case text
        case section
        case depth
        case childCount = "child_count"
    }
}

public enum CapturePomodoroNameResponse: Equatable, Decodable {
    case success(CapturePomodoroNameSuccess)
    case failure(CaptureCommandFailure)

    public var ok: Bool {
        switch self {
        case .success(let value):
            return value.ok
        case .failure(let value):
            return value.ok
        }
    }

    private enum DiscriminatorKeys: String, CodingKey {
        case ok
    }

    public init(from decoder: Decoder) throws {
        let discriminator = try decoder.container(keyedBy: DiscriminatorKeys.self)
        if try discriminator.decode(Bool.self, forKey: .ok) {
            self = .success(try CapturePomodoroNameSuccess(from: decoder))
        } else {
            self = .failure(try CaptureCommandFailure(from: decoder))
        }
    }
}

public struct CapturePomodoroNameSuccess: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let dryRun: Bool
    public let dayFile: String
    public let relativeDayFile: String
    public let name: String
    public let slug: String
    public let line: Int
    public let pomodoroRef: String
    public let pomodoro: CapturePomodoroEntry

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        dryRun: Bool,
        dayFile: String,
        relativeDayFile: String,
        name: String,
        slug: String,
        line: Int,
        pomodoroRef: String,
        pomodoro: CapturePomodoroEntry
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.dryRun = dryRun
        self.dayFile = dayFile
        self.relativeDayFile = relativeDayFile
        self.name = name
        self.slug = slug
        self.line = line
        self.pomodoroRef = pomodoroRef
        self.pomodoro = pomodoro
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case dryRun = "dry_run"
        case dayFile = "day_file"
        case relativeDayFile = "relative_day_file"
        case name
        case slug
        case line
        case pomodoroRef = "ref"
        case pomodoro
    }
}

public struct CapturePomodoroEntry: Codable, Equatable {
    public let pomodoroRef: String
    public let line: Int
    public let state: String
    public let statusSymbol: String
    public let name: String?
    public let slug: String
    public let selectable: Bool
    public let timeRange: String?
    public let placeholder: Bool
    public let isCurrent: Bool
    public let childCount: Int

    public init(
        pomodoroRef: String,
        line: Int,
        state: String,
        statusSymbol: String,
        name: String? = nil,
        slug: String,
        selectable: Bool,
        timeRange: String? = nil,
        placeholder: Bool,
        isCurrent: Bool,
        childCount: Int
    ) {
        self.pomodoroRef = pomodoroRef
        self.line = line
        self.state = state
        self.statusSymbol = statusSymbol
        self.name = name
        self.slug = slug
        self.selectable = selectable
        self.timeRange = timeRange
        self.placeholder = placeholder
        self.isCurrent = isCurrent
        self.childCount = childCount
    }

    private enum CodingKeys: String, CodingKey {
        case pomodoroRef = "ref"
        case line
        case state
        case statusSymbol = "status_symbol"
        case name
        case slug
        case selectable
        case timeRange = "time_range"
        case placeholder
        case isCurrent = "is_current"
        case childCount = "child_count"
    }
}

// Keep callers on non-optional collection fields while tolerating older bob binaries
// that omitted empty arrays from clip JSON.
public struct CaptureClipOutput: Codable, Equatable {
    public let header: String?
    public let mode: String
    public let lines: [String]
    public let attachments: [CaptureAttachmentOutput]
    public let snippet: String?
    public let entries: [CaptureClipOutput]

    public init(
        header: String? = nil,
        mode: String,
        lines: [String] = [],
        attachments: [CaptureAttachmentOutput] = [],
        snippet: String? = nil,
        entries: [CaptureClipOutput] = []
    ) {
        self.header = header
        self.mode = mode
        self.lines = lines
        self.attachments = attachments
        self.snippet = snippet
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        mode = try container.decode(String.self, forKey: .mode)
        lines = try container.decodeIfPresent([String].self, forKey: .lines) ?? []
        attachments = try container.decodeIfPresent([CaptureAttachmentOutput].self, forKey: .attachments) ?? []
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        entries = try container.decodeIfPresent([CaptureClipOutput].self, forKey: .entries) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case header
        case mode
        case lines
        case attachments
        case snippet
        case entries
    }
}

public struct CaptureAttachmentOutput: Codable, Equatable {
    public let source: String
    public let saved: String
    public let kind: String
    public let reused: Bool

    public init(source: String, saved: String, kind: String, reused: Bool) {
        self.source = source
        self.saved = saved
        self.kind = kind
        self.reused = reused
    }
}

public struct CaptureScheduleLog: Codable, Equatable {
    public let reason: String
    public let lines: [String]

    public init(reason: String, lines: [String]) {
        self.reason = reason
        self.lines = lines
    }
}

public struct CaptureTargetsResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let bobDirectory: String?
    public let count: Int?
    public let targets: [CaptureTarget]

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        bobDirectory: String? = nil,
        count: Int? = nil,
        targets: [CaptureTarget]
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.bobDirectory = bobDirectory
        self.count = count
        self.targets = targets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        bobDirectory = try container.decodeIfPresent(String.self, forKey: .bobDirectory)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        targets = try container.decodeIfPresent([CaptureTarget].self, forKey: .targets) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case bobDirectory = "bob_dir"
        case count
        case targets
    }
}

public struct CaptureTarget: Codable, Equatable, Identifiable {
    public let route: String
    public let name: String
    public let label: String
    public let kind: String
    public let isDefault: Bool
    public let status: String?
    public let relativePath: String

    public var id: String { route }

    public init(
        route: String,
        name: String,
        label: String,
        kind: String,
        isDefault: Bool = false,
        status: String? = nil,
        relativePath: String
    ) {
        self.route = route
        self.name = name
        self.label = label
        self.kind = kind
        self.isDefault = isDefault
        self.status = status
        self.relativePath = relativePath
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case name
        case label
        case kind
        case isDefault = "is_default"
        case status
        case relativePath = "relative_path"
    }
}

public struct CaptureTargetSection: Codable, Equatable, Identifiable {
    public let name: String
    public let anchor: String?

    public var id: String { anchor ?? name }

    public init(name: String, anchor: String? = nil) {
        self.name = name
        self.anchor = anchor
    }
}

public struct CaptureCompletionResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let cursor: Int
    public let replacement: CaptureRange
    public let context: String?
    public let candidates: [CaptureCompletionCandidate]
    public let warnings: [String]
    /// Additive top-level `block_id` object, present exactly when the context
    /// is `pomodoro_block_id` or `task_block_id`. Older Bob binaries omit it;
    /// the Block ID picker treats that as Link intent without New ID rows.
    public let blockID: CaptureBlockIDField?
    /// Decoded `task_dependency` query (sigil stripped, one opening quote
    /// stripped, `\"`/`\\` resolved), so the app never parses quoted note
    /// components itself. Set only for that context; omitted elsewhere so
    /// every older payload stays byte-identical.
    public let query: String?
    /// Lexical owner of the `task_dependency` modifier under the cursor
    /// (the capture-parse `dependency_target` for the cursor's item), so the
    /// app never derives the dependent itself. Set only for that context.
    public let owner: DependencyOwner?
    /// Additive parent-task picker descriptor on `task` and `task_parent`
    /// responses. Older Bob omits it; scoped `task` without one keeps the
    /// inline parent-task list.
    public let picker: CapturePickerDescriptor?

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        cursor: Int,
        replacement: CaptureRange,
        context: String?,
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = [],
        blockID: CaptureBlockIDField? = nil,
        query: String? = nil,
        owner: DependencyOwner? = nil,
        picker: CapturePickerDescriptor? = nil
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.cursor = cursor
        self.replacement = replacement
        self.context = context
        self.candidates = candidates
        self.warnings = warnings
        self.blockID = blockID
        self.query = query
        self.owner = owner
        self.picker = picker
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        cursor = try container.decode(Int.self, forKey: .cursor)
        replacement = try container.decode(CaptureRange.self, forKey: .replacement)
        context = try container.decodeIfPresent(String.self, forKey: .context)
        candidates = try container.decodeIfPresent([CaptureCompletionCandidate].self, forKey: .candidates) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        blockID = try container.decodeIfPresent(CaptureBlockIDField.self, forKey: .blockID)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        owner = try container.decodeIfPresent(DependencyOwner.self, forKey: .owner)
        picker = try container.decodeIfPresent(CapturePickerDescriptor.self, forKey: .picker)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case cursor
        case replacement
        case context
        case candidates
        case warnings
        case blockID = "block_id"
        case query
        case owner
        case picker
    }

}

/// Additive server-authored picker lifecycle metadata for parent-task
/// completion. All ranges are half-open UTF-8 byte offsets into the draft.
/// Older Bob omits the whole object, so missing decodes as nil.
public struct CapturePickerDescriptor: Codable, Equatable, Sendable {
    public let kind: String
    public let scope: String
    public let scopeToken: String
    public let noteTarget: String?
    public let markerRange: CaptureRange
    public let triggerRemovalRange: CaptureRange
    public let actionContinuationKeys: [String]

    public init(
        kind: String,
        scope: String,
        scopeToken: String,
        noteTarget: String? = nil,
        markerRange: CaptureRange,
        triggerRemovalRange: CaptureRange,
        actionContinuationKeys: [String] = []
    ) {
        self.kind = kind
        self.scope = scope
        self.scopeToken = scopeToken
        self.noteTarget = noteTarget
        self.markerRange = markerRange
        self.triggerRemovalRange = triggerRemovalRange
        self.actionContinuationKeys = actionContinuationKeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? ""
        scopeToken = try container.decodeIfPresent(String.self, forKey: .scopeToken) ?? ""
        noteTarget = try container.decodeIfPresent(String.self, forKey: .noteTarget)
        markerRange = try container.decodeIfPresent(CaptureRange.self, forKey: .markerRange)
            ?? CaptureRange(start: 0, end: 0)
        triggerRemovalRange = try container.decodeIfPresent(
            CaptureRange.self,
            forKey: .triggerRemovalRange
        ) ?? markerRange
        actionContinuationKeys = try container.decodeIfPresent(
            [String].self,
            forKey: .actionContinuationKeys
        ) ?? []
    }

    /// True when this descriptor is the parent-task picker contract.
    public var isParentTask: Bool {
        kind == "parent_task"
    }

    /// True when this descriptor is the Complete (`!`) picker contract.
    public var isTaskComplete: Bool {
        kind == "task_complete"
    }

    public var parentTaskContext: ParentTaskPickerContext? {
        guard isParentTask, let scope = ParentTaskPickerScope(rawValue: scope) else {
            return nil
        }
        return ParentTaskPickerContext(
            scope: scope,
            scopeToken: scopeToken,
            noteTarget: noteTarget,
            markerRange: markerRange,
            triggerRemovalRange: triggerRemovalRange,
            actionContinuationKeys: actionContinuationKeys
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case scope
        case scopeToken = "scope_token"
        case noteTarget = "note_target"
        case markerRange = "marker_range"
        case triggerRemovalRange = "trigger_removal_range"
        case actionContinuationKeys = "action_continuation_keys"
    }
}

/// Lexical owner of the `task_dependency` modifier under the cursor: the
/// capture-parse `dependency_target` for the cursor's item. `new_task` means
/// the capture will create the dependent; `existing_task` carries the exact
/// `@route+block-id` parent the dependency belongs to. Absent when the draft
/// names no dependent yet. Unknown kinds keep their raw value and the header
/// falls back to the ownerless prompt, so a newer Bob never breaks the picker.
public struct DependencyOwner: Codable, Equatable, Sendable {
    public let kind: String
    public let route: String?
    public let blockID: String?

    public init(kind: String, route: String? = nil, blockID: String? = nil) {
        self.kind = kind
        self.route = route
        self.blockID = blockID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        route = try container.decodeIfPresent(String.self, forKey: .route)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
    }

    /// True for an explicitly selected existing parent task.
    public var isExistingTask: Bool {
        kind == "existing_task"
    }

    /// Short owner description for the picker header (`@route+id`,
    /// `new task`, or nil when ownerless).
    public var headerText: String? {
        if isExistingTask, let route, let blockID {
            return "@\(route)+\(blockID)"
        }
        if kind == "new_task" {
            return nil
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case route
        case blockID = "block_id"
    }
}

/// Queued-task annotation on an `active_task` completion candidate: the first open
/// Pomodoro entry holding the task's dedicated `[[route#^id]]` link, or `nil` when
/// the task is not queued. Older `bob` binaries predate `active_task` completion
/// and omit the whole object, so candidates decode it tolerantly.
public struct ActiveTaskPomodoro: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let timeRange: String?
    public let isCurrent: Bool

    public init(
        line: Int,
        name: String? = nil,
        timeRange: String? = nil,
        isCurrent: Bool = false
    ) {
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.isCurrent = isCurrent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(Int.self, forKey: .line)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case timeRange = "time_range"
        case isCurrent = "is_current"
    }
}

/// Today's Task Link placement for a `task_complete` candidate: the winning
/// role, its entry, and how many distinct Pomodoros link the task today.
/// `noted` rows carry no entry. Older Bob omits the whole object, so
/// missing decodes as nil.
public struct TaskCompleteTodayPomodoro: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String?
    public let timeRange: String?
    public let status: String

    public init(line: Int, name: String? = nil, timeRange: String? = nil, status: String = "queued") {
        self.line = line
        self.name = name
        self.timeRange = timeRange
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(Int.self, forKey: .line)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "queued"
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case timeRange = "time_range"
        case status
    }
}

public struct TaskCompleteToday: Codable, Equatable, Sendable {
    public let role: String
    public let pomodoro: TaskCompleteTodayPomodoro?
    public let sessions: Int

    public init(role: String, pomodoro: TaskCompleteTodayPomodoro? = nil, sessions: Int = 0) {
        self.role = role
        self.pomodoro = pomodoro
        self.sessions = sessions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "noted"
        pomodoro = try container.decodeIfPresent(TaskCompleteTodayPomodoro.self, forKey: .pomodoro)
        sessions = try container.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case pomodoro
        case sessions
    }
}

public struct CaptureCompletionCandidate: Codable, Equatable, Identifiable {
    public let replacement: String
    public let route: String?
    public let label: String?
    public let kind: String?
    public let status: String?
    public let title: String?
    public let level: Int?
    public let taskRef: String?
    public let blockID: String?
    public let requiresBlockID: Bool
    public let statusSymbol: String?
    public let statusName: String?
    public let statusType: String?
    public let text: String?
    public let section: String?
    public let depth: Int?
    public let childCount: Int?
    public let cursorAfter: Int?
    public let path: String?
    public let name: String?
    public let alias: String?
    public let matchKind: String?
    public let heading: String?
    public let preview: String?
    public let requiresName: Bool
    public let line: Int?
    public let state: String?
    public let timeRange: String?
    public let placeholder: Bool
    public let isCurrent: Bool
    public let matchCount: Int?
    public let createsPomodoro: Bool
    // Additive `next_up` marker on `pomodoro_start_name` rows: true for the
    // entry a bare `=` would start. Omitted when false, and older Bob never
    // sends it, so missing decodes as false.
    public let nextUp: Bool
    // Additive plan-budget preview on `pomodoro_name` create rows: the
    // resulting theme count and cap when the row is accepted. Only on
    // `creates_pomodoro` rows; omitted when the daily note or the plan
    // config is unavailable, so older Bob decodes as nil.
    public let planThemesAfter: Int?
    public let planThemesCap: Int?
    public let pomodoro: ActiveTaskPomodoro?
    // Additive `task_link` fields from Bob's linkable-task scanner: the
    // note kind (`inbox`/`area`/`project`), ID suggestions for ID-less
    // tasks, the group (`queued`/`in_progress`/`next`/`note`), the
    // raw `YYYY-MM-DD` schedule, and whether linking pulls it forward.
    // Older Bob never sends them, so missing decodes to nil/empty/false.
    public let noteKind: String?
    public let blockIDSuggestions: [String]
    public let group: String?
    public let scheduled: String?
    public let pullsForward: Bool
    // Additive `task_dependency` fields from Bob's vault-wide prerequisite
    // scanner: the exact vault-relative note path including extension (never
    // the lowercased display route), the short human locator, whether the
    // row is already on the dependent's managed line, why a guarded row
    // cannot be used directly, and whether a `#hide` task renders subdued.
    // Older Bob and every other context omit them, so missing decodes to
    // nil/nil/false/nil/false.
    public let notePath: String?
    public let locator: String?
    public let alreadyDependency: Bool
    public let disabledReason: String?
    public let hidden: Bool
    // Additive `task_complete` fields from Bob's completable-task scanner:
    // whether capture refuses the row as recurring, whether another `!`
    // item in the draft already names it, and today's Task Link placement.
    // Older Bob and every other context omit them, so missing decodes to
    // false/false/nil.
    public let recurring: Bool
    public let alreadySelected: Bool
    public let today: TaskCompleteToday?

    public var id: String {
        [
            replacement,
            route,
            notePath,
            locator,
            title,
            taskRef,
            blockID,
            text,
            path,
            alias,
            heading,
            preview,
            line.map(String.init),
            timeRange,
            createsPomodoro ? "create" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: "\u{1f}")
    }

    public init(
        replacement: String,
        route: String? = nil,
        label: String? = nil,
        kind: String? = nil,
        status: String? = nil,
        title: String? = nil,
        level: Int? = nil,
        taskRef: String? = nil,
        blockID: String? = nil,
        requiresBlockID: Bool = false,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        statusType: String? = nil,
        text: String? = nil,
        section: String? = nil,
        depth: Int? = nil,
        childCount: Int? = nil,
        cursorAfter: Int? = nil,
        path: String? = nil,
        name: String? = nil,
        alias: String? = nil,
        matchKind: String? = nil,
        heading: String? = nil,
        preview: String? = nil,
        requiresName: Bool = false,
        line: Int? = nil,
        state: String? = nil,
        timeRange: String? = nil,
        placeholder: Bool = false,
        isCurrent: Bool = false,
        matchCount: Int? = nil,
        createsPomodoro: Bool = false,
        nextUp: Bool = false,
        planThemesAfter: Int? = nil,
        planThemesCap: Int? = nil,
        pomodoro: ActiveTaskPomodoro? = nil,
        noteKind: String? = nil,
        blockIDSuggestions: [String] = [],
        group: String? = nil,
        scheduled: String? = nil,
        pullsForward: Bool = false,
        notePath: String? = nil,
        locator: String? = nil,
        alreadyDependency: Bool = false,
        disabledReason: String? = nil,
        hidden: Bool = false,
        recurring: Bool = false,
        alreadySelected: Bool = false,
        today: TaskCompleteToday? = nil
    ) {
        self.replacement = replacement
        self.route = route
        self.label = label
        self.kind = kind
        self.status = status
        self.title = title
        self.level = level
        self.taskRef = taskRef
        self.blockID = blockID
        self.requiresBlockID = requiresBlockID
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.statusType = statusType
        self.text = text
        self.section = section
        self.depth = depth
        self.childCount = childCount
        self.cursorAfter = cursorAfter
        self.path = path
        self.name = name
        self.alias = alias
        self.matchKind = matchKind
        self.heading = heading
        self.preview = preview
        self.requiresName = requiresName
        self.line = line
        self.state = state
        self.timeRange = timeRange
        self.placeholder = placeholder
        self.isCurrent = isCurrent
        self.matchCount = matchCount
        self.createsPomodoro = createsPomodoro
        self.nextUp = nextUp
        self.planThemesAfter = planThemesAfter
        self.planThemesCap = planThemesCap
        self.pomodoro = pomodoro
        self.noteKind = noteKind
        self.blockIDSuggestions = blockIDSuggestions
        self.group = group
        self.scheduled = scheduled
        self.pullsForward = pullsForward
        self.notePath = notePath
        self.locator = locator
        self.alreadyDependency = alreadyDependency
        self.disabledReason = disabledReason
        self.hidden = hidden
        self.recurring = recurring
        self.alreadySelected = alreadySelected
        self.today = today
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replacement = try container.decode(String.self, forKey: .replacement)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        level = try container.decodeIfPresent(Int.self, forKey: .level)
        taskRef = try container.decodeIfPresent(String.self, forKey: .taskRef)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        requiresBlockID = try container.decodeIfPresent(Bool.self, forKey: .requiresBlockID) ?? false
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        statusType = try container.decodeIfPresent(String.self, forKey: .statusType)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        depth = try container.decodeIfPresent(Int.self, forKey: .depth)
        childCount = try container.decodeIfPresent(Int.self, forKey: .childCount)
        cursorAfter = try container.decodeIfPresent(Int.self, forKey: .cursorAfter)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        matchKind = try container.decodeIfPresent(String.self, forKey: .matchKind)
        heading = try container.decodeIfPresent(String.self, forKey: .heading)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        requiresName = try container.decodeIfPresent(Bool.self, forKey: .requiresName) ?? false
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        placeholder = try container.decodeIfPresent(Bool.self, forKey: .placeholder) ?? false
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        matchCount = try container.decodeIfPresent(Int.self, forKey: .matchCount)
        createsPomodoro = try container.decodeIfPresent(Bool.self, forKey: .createsPomodoro) ?? false
        nextUp = try container.decodeIfPresent(Bool.self, forKey: .nextUp) ?? false
        planThemesAfter = try container.decodeIfPresent(Int.self, forKey: .planThemesAfter)
        planThemesCap = try container.decodeIfPresent(Int.self, forKey: .planThemesCap)
        pomodoro = try container.decodeIfPresent(ActiveTaskPomodoro.self, forKey: .pomodoro)
        noteKind = try container.decodeIfPresent(String.self, forKey: .noteKind)
        blockIDSuggestions = try container.decodeIfPresent([String].self, forKey: .blockIDSuggestions) ?? []
        group = try container.decodeIfPresent(String.self, forKey: .group)
        scheduled = try container.decodeIfPresent(String.self, forKey: .scheduled)
        pullsForward = try container.decodeIfPresent(Bool.self, forKey: .pullsForward) ?? false
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath)
        locator = try container.decodeIfPresent(String.self, forKey: .locator)
        alreadyDependency = try container.decodeIfPresent(Bool.self, forKey: .alreadyDependency) ?? false
        disabledReason = try container.decodeIfPresent(String.self, forKey: .disabledReason)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        recurring = try container.decodeIfPresent(Bool.self, forKey: .recurring) ?? false
        alreadySelected = try container.decodeIfPresent(Bool.self, forKey: .alreadySelected) ?? false
        today = try container.decodeIfPresent(TaskCompleteToday.self, forKey: .today)
    }

    private enum CodingKeys: String, CodingKey {
        case replacement
        case route
        case label
        case kind
        case status
        case title
        case level
        case taskRef = "ref"
        case blockID = "block_id"
        case requiresBlockID = "requires_block_id"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case statusType = "status_type"
        case text
        case section
        case depth
        case childCount = "child_count"
        case cursorAfter = "cursor_after"
        case path
        case name
        case alias
        case matchKind = "match_kind"
        case heading
        case preview
        case requiresName = "requires_name"
        case line
        case state
        case timeRange = "time_range"
        case placeholder
        case isCurrent = "is_current"
        case matchCount = "match_count"
        case createsPomodoro = "creates_pomodoro"
        case nextUp = "next_up"
        case planThemesAfter = "plan_themes_after"
        case planThemesCap = "plan_themes_cap"
        case pomodoro
        case noteKind = "note_kind"
        case blockIDSuggestions = "block_id_suggestions"
        case group
        case scheduled
        case pullsForward = "pulls_forward"
        case notePath = "note_path"
        case locator
        case alreadyDependency = "already_dependency"
        case disabledReason = "disabled_reason"
        case hidden
        case recurring
        case alreadySelected = "already_selected"
        case today
    }
}

/// What the person can mean on the right-hand side of `@route:`/`@route^`:
/// `link` references an existing task, `new` mints an unused ID, and
/// `project_note` names a new project note. Unknown values decode to `link`
/// so a newer Bob never breaks the picker.
public enum CaptureBlockIDIntent: String, Equatable, Sendable {
    case link
    case new
    case projectNote = "project_note"

    public init(wireValue: String?) {
        self = (wireValue.flatMap(CaptureBlockIDIntent.init(rawValue:)) ?? .link)
    }
}

extension CaptureBlockIDIntent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self.init(wireValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One ID already in the routed note, found by the exact scanner Bob's
/// duplicate check uses. Task lines carry their status and description;
/// other lines carry the trimmed line as text with null status fields.
public struct CaptureUsedBlockID: Codable, Equatable, Sendable {
    public let id: String
    public let line: Int
    public let isTask: Bool
    public let statusSymbol: String?
    public let statusName: String?
    public let text: String

    public init(
        id: String,
        line: Int,
        isTask: Bool,
        statusSymbol: String? = nil,
        statusName: String? = nil,
        text: String
    ) {
        self.id = id
        self.line = line
        self.isTask = isTask
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        isTask = try container.decodeIfPresent(Bool.self, forKey: .isTask) ?? false
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case line
        case isTask = "task"
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case text
    }
}

/// The additive top-level `block_id` object Bob sends exactly for
/// `pomodoro_block_id` and `task_block_id` contexts. Every field decodes
/// tolerantly: missing arrays are empty, strings are "", booleans are
/// false, the marker range is nil, and the intent falls back to `link`.
public struct CaptureBlockIDField: Codable, Equatable, Sendable {
    public let route: String
    public let relativeTarget: String
    public let noteExists: Bool
    public let marker: String
    public let markerRange: CaptureRange?
    public let intent: CaptureBlockIDIntent
    public let body: String
    public let allowedCharacter: String
    public let allowedDescription: String
    public let suggestions: [String]
    public let used: [CaptureUsedBlockID]

    public init(
        route: String,
        relativeTarget: String,
        noteExists: Bool = true,
        marker: String,
        markerRange: CaptureRange? = nil,
        intent: CaptureBlockIDIntent,
        body: String = "",
        allowedCharacter: String,
        allowedDescription: String,
        suggestions: [String] = [],
        used: [CaptureUsedBlockID] = []
    ) {
        self.route = route
        self.relativeTarget = relativeTarget
        self.noteExists = noteExists
        self.marker = marker
        self.markerRange = markerRange
        self.intent = intent
        self.body = body
        self.allowedCharacter = allowedCharacter
        self.allowedDescription = allowedDescription
        self.suggestions = suggestions
        self.used = used
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = try container.decodeIfPresent(String.self, forKey: .route) ?? ""
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget) ?? ""
        noteExists = try container.decodeIfPresent(Bool.self, forKey: .noteExists) ?? false
        marker = try container.decodeIfPresent(String.self, forKey: .marker) ?? ""
        markerRange = try container.decodeIfPresent(CaptureRange.self, forKey: .markerRange)
        intent = try container.decodeIfPresent(CaptureBlockIDIntent.self, forKey: .intent) ?? .link
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        allowedCharacter = try container.decodeIfPresent(String.self, forKey: .allowedCharacter) ?? ""
        allowedDescription = try container.decodeIfPresent(String.self, forKey: .allowedDescription) ?? ""
        suggestions = try container.decodeIfPresent([String].self, forKey: .suggestions) ?? []
        used = try container.decodeIfPresent([CaptureUsedBlockID].self, forKey: .used) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case relativeTarget = "relative_target"
        case noteExists = "note_exists"
        case marker
        case markerRange = "marker_range"
        case intent
        case body
        case allowedCharacter = "allowed_character"
        case allowedDescription = "allowed_description"
        case suggestions
        case used
    }
}

/// Versioned `bob capture-pomodoros --format json` response. Only the
/// current entry's numbered Task Link count matters to the editor; every
/// other field decodes tolerantly so an older bob without
/// `task_link_count` still decodes with a nil count.
public struct CapturePomodorosResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let pomodoros: [CapturePomodoroEntry]

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        pomodoros: [CapturePomodoroEntry] = []
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.pomodoros = pomodoros
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        pomodoros = try container.decodeIfPresent(
            [CapturePomodoroEntry].self,
            forKey: .pomodoros
        ) ?? []
    }

    /// The `isCurrent` entry's `taskLinkCount`, or nil when there is no
    /// current entry or the field is absent (older bob).
    public var currentTaskLinkCount: Int? {
        pomodoros.first(where: { $0.isCurrent })?.taskLinkCount
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case pomodoros
    }
}

/// Minimal `capture-pomodoros` entry: only the fields the close-comma
/// assist needs. `taskLinkCount` is the size of the numbered Task Link
/// lineup a plain `=x` close indexes; it is an integer only on the
/// `isCurrent` entry and null elsewhere. Older bob binaries omit the key.
public struct CapturePomodoroEntry: Codable, Equatable {
    public let line: Int
    public let name: String?
    public let isCurrent: Bool
    public let taskLinkCount: Int?

    public init(
        line: Int = 0,
        name: String? = nil,
        isCurrent: Bool = false,
        taskLinkCount: Int? = nil
    ) {
        self.line = line
        self.name = name
        self.isCurrent = isCurrent
        self.taskLinkCount = taskLinkCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        taskLinkCount = try container.decodeIfPresent(Int.self, forKey: .taskLinkCount)
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case name
        case isCurrent = "is_current"
        case taskLinkCount = "task_link_count"
    }
}
