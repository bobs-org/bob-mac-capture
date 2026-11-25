import Foundation

public enum MeetingNotesStatus: String, CaseIterable, Equatable, Sendable {
    case next
    case ready
    case wip
    case read
}

/// Options Bob used to resolve and preview one clipboard filing. An absent
/// status leaves the vault's configured status in force.
public struct MeetingNotesOptions: Equatable, Sendable {
    public let eventToken: String?
    public let parent: String?
    public let status: MeetingNotesStatus?
    public let overwrite: Bool

    public init(
        eventToken: String? = nil,
        parent: String? = nil,
        status: MeetingNotesStatus? = nil,
        overwrite: Bool = false
    ) {
        self.eventToken = eventToken
        self.parent = parent
        self.status = status
        self.overwrite = overwrite
    }
}

public struct MeetingNotesFileRequest: Equatable, Sendable {
    public let options: MeetingNotesOptions
    public let sha256: String

    public init(options: MeetingNotesOptions, sha256: String) {
        self.options = options
        self.sha256 = sha256
    }
}

public enum MeetingNotesOutcome: Equatable, Sendable {
    case wouldFile
    case filed
    case queued
    case unknown(String)

    public init(_ value: String) {
        switch value {
        case "would_file": self = .wouldFile
        case "filed": self = .filed
        case "queued": self = .queued
        default: self = .unknown(value)
        }
    }

    public var wireValue: String {
        switch self {
        case .wouldFile: "would_file"
        case .filed: "filed"
        case .queued: "queued"
        case .unknown(let value): value
        }
    }
}

extension MeetingNotesOutcome: Decodable {
    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }
}

public struct MeetingNotesListResponse: Decodable, Equatable, SchemaVersioned, Sendable {
    public let schemaVersion: Int
    public let ok: Bool
    public let meetings: [MeetingNotesMeeting]
    public let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case meetings
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        ok = try container.decode(Bool.self, forKey: .ok)
        meetings =
            try container.decodeIfPresent([MeetingNotesMeeting].self, forKey: .meetings) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

/// A Bob-owned event identity. `ref`, `block_id`, and `root` can be null;
/// clients must never synthesize an event token from the title or path.
public struct MeetingNotesMeeting: Decodable, Equatable, Sendable {
    public let eventRef: String?
    public let path: String
    public let blockID: String?
    public let date: String
    public let start: String
    public let end: String
    public let title: String
    public let root: String?
    public let rootIsInbox: Bool
    public let status: String
    public let eventID: String?
    public let notes: MeetingNotesLink?

    private enum CodingKeys: String, CodingKey {
        case eventRef = "ref"
        case path
        case blockID = "block_id"
        case date
        case start
        case end
        case title
        case root
        case rootIsInbox = "root_is_inbox"
        case status
        case eventID = "event_id"
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventRef = try container.decodeIfPresent(String.self, forKey: .eventRef)
        path = try container.decode(String.self, forKey: .path)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        date = try container.decode(String.self, forKey: .date)
        start = try container.decode(String.self, forKey: .start)
        end = try container.decode(String.self, forKey: .end)
        title = try container.decode(String.self, forKey: .title)
        root = try container.decodeIfPresent(String.self, forKey: .root)
        rootIsInbox = try container.decodeIfPresent(Bool.self, forKey: .rootIsInbox) ?? false
        status = try container.decode(String.self, forKey: .status)
        eventID = try container.decodeIfPresent(String.self, forKey: .eventID)
        notes = try container.decodeIfPresent(MeetingNotesLink.self, forKey: .notes)
    }
}

public struct MeetingNotesLink: Decodable, Equatable, Sendable {
    public let note: String
    public let task: String
    public let status: String
}

public struct MeetingNotesCandidate: Decodable, Equatable, Sendable {
    public let meeting: MeetingNotesMeeting
    public let detail: String
    public let evidence: [String]
}

/// This is the shipped ParentChoice shape. In particular, parent choices are
/// under `parent_candidates`, never the meeting `candidates` field.
public struct MeetingNotesParentChoice: Decodable, Equatable, Sendable {
    public let route: String
    public let kind: String
    public let label: String
    public let aliases: [String]
    public let status: String?
}

public struct MeetingNotesExisting: Decodable, Equatable, Sendable {
    public let note: String
    public let task: String
    public let status: String
}

public struct MeetingNotesError: Decodable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let hint: String?
}

public struct MeetingNotesMatch: Decodable, Equatable, Sendable {
    public let method: String
    public let evidence: [String]
}

public struct MeetingNotesFiling: Decodable, Equatable, Sendable {
    public let parent: String
    public let parentKind: String
    public let reroot: MeetingNotesReroot?
    public let title: String
    public let stem: String
    public let note: String
    public let pdf: String
    public let task: MeetingNotesTaskPlan
    public let relation: MeetingNotesRelation

    private enum CodingKeys: String, CodingKey {
        case parent
        case parentKind = "parent_kind"
        case reroot
        case title
        case stem
        case note
        case pdf
        case task
        case relation
    }
}

public struct MeetingNotesReroot: Decodable, Equatable, Sendable {
    public let from: String?
    public let to: String
}

public struct MeetingNotesTaskPlan: Decodable, Equatable, Sendable {
    public let destination: String
    public let blockID: String
    public let status: String

    private enum CodingKeys: String, CodingKey {
        case destination
        case blockID = "block_id"
        case status
    }
}

public struct MeetingNotesRelation: Decodable, Equatable, Sendable {
    public let label: String
    public let target: String
}

public struct MeetingNotesNotes: Decodable, Equatable, Sendable {
    public let sha256: String?
    public let shape: String?
    public let producer: String?
    public let outline: MeetingNotesOutline?
    public let transcript: String?
}

public struct MeetingNotesOutline: Decodable, Equatable, Sendable {
    public let tldr: String
    public let nextSteps: [MeetingNotesNextStep]
    public let sections: [MeetingNotesSection]

    private enum CodingKeys: String, CodingKey {
        case tldr
        case nextSteps = "next_steps"
        case sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tldr = try container.decodeIfPresent(String.self, forKey: .tldr) ?? ""
        nextSteps =
            try container.decodeIfPresent([MeetingNotesNextStep].self, forKey: .nextSteps) ?? []
        sections =
            try container.decodeIfPresent([MeetingNotesSection].self, forKey: .sections) ?? []
    }
}

public struct MeetingNotesNextStep: Decodable, Equatable, Sendable {
    public let owner: String?
    public let action: String
}

public struct MeetingNotesSection: Decodable, Equatable, Sendable {
    public let heading: String?
    public let items: Int
}

public struct MeetingNotesQueued: Decodable, Equatable, Sendable {
    public let path: String
    public let reason: String
    public let detail: String
}

/// One schema-1 `ref meet` success or structured refusal. Decoding is
/// additive: unknown fields are ignored and absent optional receipt fields
/// remain nil, while Bob's schema version is checked by `decodeReport`.
public struct MeetingNotesResponse: Decodable, Equatable, SchemaVersioned, Sendable {
    public let schemaVersion: Int
    public let ok: Bool
    public let outcome: MeetingNotesOutcome?
    public let meeting: MeetingNotesMeeting?
    public let match: MeetingNotesMatch?
    public let filing: MeetingNotesFiling?
    public let notes: MeetingNotesNotes?
    public let warnings: [String]
    public let commit: String?
    public let commitWarning: String?
    public let syncStatus: String?
    public let pushPending: Bool?
    public let queued: MeetingNotesQueued?
    public let pages: Int?
    public let sourcePointer: String?
    public let replaced: Bool?
    public let root: String?
    public let candidates: [MeetingNotesCandidate]
    public let parentCandidates: [MeetingNotesParentChoice]
    public let existing: MeetingNotesExisting?
    public let error: MeetingNotesError?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case outcome
        case meeting
        case match
        case filing
        case notes
        case warnings
        case commit
        case commitWarning = "commit_warning"
        case syncStatus = "sync_status"
        case pushPending = "push_pending"
        case queued
        case pages
        case sourcePointer = "source_pointer"
        case replaced
        case root
        case candidates
        case parentCandidates = "parent_candidates"
        case existing
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        ok = try container.decode(Bool.self, forKey: .ok)
        outcome = try container.decodeIfPresent(MeetingNotesOutcome.self, forKey: .outcome)
        meeting = try container.decodeIfPresent(MeetingNotesMeeting.self, forKey: .meeting)
        match = try container.decodeIfPresent(MeetingNotesMatch.self, forKey: .match)
        filing = try container.decodeIfPresent(MeetingNotesFiling.self, forKey: .filing)
        notes = try container.decodeIfPresent(MeetingNotesNotes.self, forKey: .notes)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        commit = try container.decodeIfPresent(String.self, forKey: .commit)
        commitWarning = try container.decodeIfPresent(String.self, forKey: .commitWarning)
        syncStatus = try container.decodeIfPresent(String.self, forKey: .syncStatus)
        pushPending = try container.decodeIfPresent(Bool.self, forKey: .pushPending)
        queued = try container.decodeIfPresent(MeetingNotesQueued.self, forKey: .queued)
        pages = try container.decodeIfPresent(Int.self, forKey: .pages)
        sourcePointer = try container.decodeIfPresent(String.self, forKey: .sourcePointer)
        replaced = try container.decodeIfPresent(Bool.self, forKey: .replaced)
        root = try container.decodeIfPresent(String.self, forKey: .root)
        candidates =
            try container.decodeIfPresent([MeetingNotesCandidate].self, forKey: .candidates) ?? []
        parentCandidates =
            try container.decodeIfPresent(
                [MeetingNotesParentChoice].self, forKey: .parentCandidates) ?? []
        existing = try container.decodeIfPresent(MeetingNotesExisting.self, forKey: .existing)
        error = try container.decodeIfPresent(MeetingNotesError.self, forKey: .error)
    }
}

public protocol MeetingNotesProcess: Sendable {
    var meetingNotesKnownUnsupported: Bool { get }
    func meetingNotesList() async throws -> MeetingNotesListResponse
    func meetingNotesPreview(_ options: MeetingNotesOptions) async throws -> MeetingNotesResponse
    func meetingNotesFile(_ request: MeetingNotesFileRequest) async throws -> MeetingNotesResponse
    func cancelMeetingNotesReads()
    func recheckMeetingNotesCapability()
}
