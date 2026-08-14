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
    public let destination: CaptureDestination?
    public let markdown: String?
    public let opened: Bool?
    public let message: String?
    public let diagnostics: [CaptureDiagnostic]

    public init(
        ok: Bool,
        schemaVersion: Int,
        destination: CaptureDestination? = nil,
        markdown: String? = nil,
        opened: Bool? = nil,
        message: String? = nil,
        diagnostics: [CaptureDiagnostic] = []
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.destination = destination
        self.markdown = markdown
        self.opened = opened
        self.message = message
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case destination
        case markdown
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
    public let targets: [CaptureTarget]

    public init(ok: Bool, schemaVersion: Int, targets: [CaptureTarget]) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.targets = targets
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case targets
    }
}

public struct CaptureTarget: Codable, Equatable, Identifiable {
    public let route: String
    public let title: String
    public let sections: [CaptureTargetSection]
    public let aliases: [String]

    public var id: String { route }

    public init(
        route: String,
        title: String,
        sections: [CaptureTargetSection] = [],
        aliases: [String] = []
    ) {
        self.route = route
        self.title = title
        self.sections = sections
        self.aliases = aliases
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
