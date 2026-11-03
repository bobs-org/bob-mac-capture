import Foundation

/// One relation target Bob identifies by note path and block ID.
public struct CaptureRelationTarget: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let text: String

    public init(notePath: String = "", blockID: String = "", text: String = "") {
        self.notePath = notePath
        self.blockID = blockID
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case text
    }
}

/// Bob's winning or secondary reason for a relation successor row.
public struct CaptureRelationMetadata: Codable, Equatable, Sendable {
    public let label: String
    public let key: String
    public let event: String
    public let after: [CaptureRelationTarget]

    public init(label: String = "", key: String = "", event: String = "", after: [CaptureRelationTarget] = []) {
        self.label = label
        self.key = key
        self.event = event
        self.after = after
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        event = (try? container.decodeIfPresent(String.self, forKey: .event)) ?? ""
        after = (try? container.decodeIfPresent([CaptureRelationTarget].self, forKey: .after)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case key
        case event
        case after
    }
}

/// A relation source Bob checked but did not offer.
public struct CaptureRelationHeld: Codable, Equatable, Sendable {
    public let notePath: String
    public let blockID: String
    public let line: Int
    public let text: String
    public let statusSymbol: String
    public let statusName: String
    public let reason: String
    public let waitsOn: [CaptureRelationTarget]?
    public let scheduled: String?
    public let project: String?
    public let waitsFor: [CaptureRelationTarget]?
    public let relation: CaptureRelationMetadata?

    public init(
        notePath: String = "",
        blockID: String = "",
        line: Int = 0,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = "",
        reason: String = "",
        waitsOn: [CaptureRelationTarget]? = nil,
        scheduled: String? = nil,
        project: String? = nil,
        waitsFor: [CaptureRelationTarget]? = nil,
        relation: CaptureRelationMetadata? = nil
    ) {
        self.notePath = notePath
        self.blockID = blockID
        self.line = line
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
        self.reason = reason
        self.waitsOn = waitsOn
        self.scheduled = scheduled
        self.project = project
        self.waitsFor = waitsFor
        self.relation = relation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        line = (try? container.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        statusSymbol = (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        waitsOn = try? container.decodeIfPresent([CaptureRelationTarget].self, forKey: .waitsOn)
        scheduled = try? container.decodeIfPresent(String.self, forKey: .scheduled)
        project = try? container.decodeIfPresent(String.self, forKey: .project)
        waitsFor = try? container.decodeIfPresent([CaptureRelationTarget].self, forKey: .waitsFor)
        relation = try? container.decodeIfPresent(CaptureRelationMetadata.self, forKey: .relation)
    }

    private enum CodingKeys: String, CodingKey {
        case notePath = "note_path"
        case blockID = "block_id"
        case line
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
        case reason
        case waitsOn = "waits_on"
        case scheduled
        case project
        case waitsFor = "waits_for"
        case relation
    }
}

/// Bob-authored title, capsule, and SF Symbols key for the pull-in chooser.
public struct CapturePullInCopy: Codable, Equatable, Sendable {
    public let title: String
    public let capsule: String
    public let glyph: String

    public init(title: String = "", capsule: String = "", glyph: String = "") {
        self.title = title
        self.capsule = capsule
        self.glyph = glyph
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        capsule = (try? container.decodeIfPresent(String.self, forKey: .capsule)) ?? ""
        glyph = (try? container.decodeIfPresent(String.self, forKey: .glyph)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case capsule
        case glyph
    }
}

/// Bob-issued relation group identity attached to a pull-in section.
public struct CapturePullInAfter: Codable, Equatable, Sendable {
    public let key: String
    public let notePath: String
    public let blockID: String
    public let text: String

    public init(key: String = "", notePath: String = "", blockID: String = "", text: String = "") {
        self.key = key
        self.notePath = notePath
        self.blockID = blockID
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? ""
        notePath = (try? container.decodeIfPresent(String.self, forKey: .notePath)) ?? ""
        blockID = (try? container.decodeIfPresent(String.self, forKey: .blockID)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case notePath = "note_path"
        case blockID = "block_id"
        case text
    }
}

/// Bob-authored copy for one pull-in group. Missing optional strings stay nil.
public struct CapturePullInGroupCopy: Codable, Equatable, Sendable {
    public let title: String
    public let why: String?
    public let tag: String?
    public let fold: String?
    public let glyph: String

    public init(
        title: String = "",
        why: String? = nil,
        tag: String? = nil,
        fold: String? = nil,
        glyph: String = ""
    ) {
        self.title = title
        self.why = why
        self.tag = tag
        self.fold = fold
        self.glyph = glyph
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        why = try? container.decodeIfPresent(String.self, forKey: .why)
        tag = try? container.decodeIfPresent(String.self, forKey: .tag)
        fold = try? container.decodeIfPresent(String.self, forKey: .fold)
        glyph = (try? container.decodeIfPresent(String.self, forKey: .glyph)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case why
        case tag
        case fold
        case glyph
    }
}

/// One endpoint in Bob's capture-complete successor authoring consequence.
public struct CaptureCompletionRelationSuccessorTask: Codable, Equatable, Sendable {
    public let path: String
    public let blockID: String?
    public let text: String
    public let statusSymbol: String
    public let statusName: String

    public init(
        path: String = "",
        blockID: String? = nil,
        text: String = "",
        statusSymbol: String = "",
        statusName: String = ""
    ) {
        self.path = path
        self.blockID = blockID
        self.text = text
        self.statusSymbol = statusSymbol
        self.statusName = statusName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decodeIfPresent(String.self, forKey: .path)) ?? ""
        blockID = try? container.decodeIfPresent(String.self, forKey: .blockID)
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        statusSymbol = (try? container.decodeIfPresent(String.self, forKey: .statusSymbol)) ?? ""
        statusName = (try? container.decodeIfPresent(String.self, forKey: .statusName)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case blockID = "block_id"
        case text
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
    }
}

/// Bob-authored relation successor verdict or inverse spelling hint.
public struct CaptureCompletionRelationSuccessor: Codable, Equatable, Sendable {
    public let source: CaptureCompletionRelationSuccessorTask
    public let target: CaptureCompletionRelationSuccessorTask
    public let verdict: String?
    public let message: String?
    public let hint: String?

    public init(
        source: CaptureCompletionRelationSuccessorTask = CaptureCompletionRelationSuccessorTask(),
        target: CaptureCompletionRelationSuccessorTask = CaptureCompletionRelationSuccessorTask(),
        verdict: String? = nil,
        message: String? = nil,
        hint: String? = nil
    ) {
        self.source = source
        self.target = target
        self.verdict = verdict
        self.message = message
        self.hint = hint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? container.decode(CaptureCompletionRelationSuccessorTask.self, forKey: .source))
            ?? CaptureCompletionRelationSuccessorTask()
        target = (try? container.decode(CaptureCompletionRelationSuccessorTask.self, forKey: .target))
            ?? CaptureCompletionRelationSuccessorTask()
        verdict = try? container.decodeIfPresent(String.self, forKey: .verdict)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        hint = try? container.decodeIfPresent(String.self, forKey: .hint)
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case target
        case verdict
        case message
        case hint
    }
}
