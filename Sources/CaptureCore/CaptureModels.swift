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
        items: [CaptureParseItem] = []
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
        subBulletDepths: [Int] = []
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
    }
}

public struct CaptureSpan: Codable, Equatable {
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
}

public struct CaptureRange: Codable, Equatable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
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
    public let parentStatusSymbol: String?
    public let parentStatusName: String?
    public let captures: [CaptureCommandSuccess]
    public let globalDestination: CaptureGlobalDestination?

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
        parentStatusSymbol: String? = nil,
        parentStatusName: String? = nil,
        captures: [CaptureCommandSuccess] = [],
        globalDestination: CaptureGlobalDestination? = nil
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
        self.parentStatusSymbol = parentStatusSymbol
        self.parentStatusName = parentStatusName
        self.captures = captures
        self.globalDestination = globalDestination
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
        parentStatusSymbol = try container.decodeIfPresent(String.self, forKey: .parentStatusSymbol)
        parentStatusName = try container.decodeIfPresent(String.self, forKey: .parentStatusName)
        captures = try container.decodeIfPresent([CaptureCommandSuccess].self, forKey: .captures) ?? []
        globalDestination = try container.decodeIfPresent(
            CaptureGlobalDestination.self,
            forKey: .globalDestination
        )
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
        case parentStatusSymbol = "parent_status_symbol"
        case parentStatusName = "parent_status_name"
        case captures
        case globalDestination = "global_destination"
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

public struct CaptureCommandFailure: Codable, Equatable {
    public let ok: Bool
    public let error: String

    public init(ok: Bool = false, error: String) {
        self.ok = ok
        self.error = error
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

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        dryRun: Bool,
        route: String,
        relativeTarget: String,
        blockID: String,
        line: Int,
        taskRef: String,
        task: CaptureTaskIDTask
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

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        cursor: Int,
        replacement: CaptureRange,
        context: String?,
        candidates: [CaptureCompletionCandidate],
        warnings: [String] = []
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.cursor = cursor
        self.replacement = replacement
        self.context = context
        self.candidates = candidates
        self.warnings = warnings
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
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case cursor
        case replacement
        case context
        case candidates
        case warnings
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

    public var id: String {
        [
            replacement,
            route,
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
        matchCount: Int? = nil
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
    }
}
