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
    // Additive to schema version 1: `bob capture-parse` omits these keys entirely when
    // a draft has no authored sub-bullets, and older bob versions omit depths even when
    // they provide bodies. Decode both tolerantly and synthesize depth 1 for older bob
    // responses rather than letting clients index mismatched arrays.
    public let subBullets: [String]
    public let subBulletDepths: [Int]

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
        subBullets: [String] = [],
        subBulletDepths: [Int]? = nil
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
        self.subBullets = subBullets
        self.subBulletDepths = Self.normalizedSubBulletDepths(
            subBulletDepths,
            bodyCount: subBullets.count
        )
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
        subBullets = try container.decodeIfPresent([String].self, forKey: .subBullets) ?? []
        let decodedDepths = try container.decodeIfPresent(
            [Int].self,
            forKey: .subBulletDepths
        )
        subBulletDepths = Self.normalizedSubBulletDepths(
            decodedDepths,
            bodyCount: subBullets.count
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
        parentStatusName: String? = nil
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
}

public struct CaptureCommandFailure: Codable, Equatable {
    public let ok: Bool
    public let error: String

    public init(ok: Bool = false, error: String) {
        self.ok = ok
        self.error = error
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
        preview: String? = nil
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
    }
}
