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
        diagnostics: [CaptureDiagnostic] = []
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

public struct CaptureCommandResponse: Codable, Equatable {
    public let ok: Bool
    public let schemaVersion: Int
    public let dryRun: Bool?
    public let routed: Bool?
    public let route: String?
    public let routeLabel: String?
    public let relativeTarget: String?
    public let target: String?
    public let text: String?
    public let taskLine: String?
    public let kind: String?
    public let created: String?
    public let scheduled: String?
    public let priority: String?
    public let priorityLabel: String?
    public let placement: String?
    public let error: String?
    public let opened: Bool?
    public let message: String?
    public let diagnostics: [CaptureDiagnostic]

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        dryRun: Bool? = nil,
        routed: Bool? = nil,
        route: String? = nil,
        routeLabel: String? = nil,
        relativeTarget: String? = nil,
        target: String? = nil,
        text: String? = nil,
        taskLine: String? = nil,
        kind: String? = nil,
        created: String? = nil,
        scheduled: String? = nil,
        priority: String? = nil,
        priorityLabel: String? = nil,
        placement: String? = nil,
        error: String? = nil,
        opened: Bool? = nil,
        message: String? = nil,
        diagnostics: [CaptureDiagnostic] = []
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
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
        self.error = error
        self.opened = opened
        self.message = message
        self.diagnostics = diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun)
        routed = try container.decodeIfPresent(Bool.self, forKey: .routed)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        routeLabel = try container.decodeIfPresent(String.self, forKey: .routeLabel)
        relativeTarget = try container.decodeIfPresent(String.self, forKey: .relativeTarget)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        taskLine = try container.decodeIfPresent(String.self, forKey: .taskLine)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        created = try container.decodeIfPresent(String.self, forKey: .created)
        scheduled = try container.decodeIfPresent(String.self, forKey: .scheduled)
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        priorityLabel = try container.decodeIfPresent(String.self, forKey: .priorityLabel)
        placement = try container.decodeIfPresent(String.self, forKey: .placement)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        opened = try container.decodeIfPresent(Bool.self, forKey: .opened)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        diagnostics = try container.decodeIfPresent([CaptureDiagnostic].self, forKey: .diagnostics) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
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
        case error
        case opened
        case message
        case diagnostics
    }
}

public struct CaptureDestination: Codable, Equatable {
    public let vaultPath: String?
    public let notePath: String?
    public let heading: String?
    public let blockID: String?
    public let url: String?

    public init(
        vaultPath: String? = nil,
        notePath: String? = nil,
        heading: String? = nil,
        blockID: String? = nil,
        url: String? = nil
    ) {
        self.vaultPath = vaultPath
        self.notePath = notePath
        self.heading = heading
        self.blockID = blockID
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
        case notePath = "note_path"
        case heading
        case blockID = "block_id"
        case url
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

    public init(
        ok: Bool,
        schemaVersion: Int = 1,
        cursor: Int,
        replacement: CaptureRange,
        context: String?,
        candidates: [CaptureCompletionCandidate]
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.cursor = cursor
        self.replacement = replacement
        self.context = context
        self.candidates = candidates
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case cursor
        case replacement
        case context
        case candidates
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

    public var id: String {
        [
            replacement,
            route,
            title,
            taskRef,
            blockID,
            text,
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
        childCount: Int? = nil
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
    }
}
