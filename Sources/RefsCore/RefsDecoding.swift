import CaptureCore
import Foundation

/// Lossy decoding of the `bob ref list` and `bob plan` JSON envelopes.
///
/// Every optional field uses `decodeIfPresent`, so an older `bob` still
/// decodes: a row without `blocked` reads as not blocked, and unknown fields
/// are ignored. `ref list` rows decode element by element — a row missing
/// `path` or `title` is skipped and counted in `skippedRowCount` instead of
/// failing the whole snapshot.
public struct RefsListResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public let schemaVersion: Int
    public let generatedAt: String?
    public let refs: [RefRecord]
    public let skippedRowCount: Int

    public init(
        schemaVersion: Int,
        generatedAt: String? = nil,
        refs: [RefRecord] = [],
        skippedRowCount: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.refs = refs
        self.skippedRowCount = skippedRowCount
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case refs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        let rows = try container.decodeIfPresent([LossyRefRecord].self, forKey: .refs) ?? []
        refs = rows.compactMap(\.record)
        skippedRowCount = rows.count - refs.count
    }
}

/// One `bob ref list` row. Only `path`, `link`, and `title` are required;
/// everything else tolerates absence so older `bob` output still decodes.
/// Encodes with the same snake_case keys so the snapshot cache round-trips.
public struct RefRecord: Codable, Equatable, Sendable {
    public let path: String
    public let link: String
    public let title: String
    public let refType: String?
    public let origin: String?
    public let status: String?
    public let readingState: String?
    public let blocked: Bool
    public let parent: String?
    public let author: String?
    public let published: String?
    public let added: String?
    public let addedSource: String?
    public let finished: String?
    public let finishedSource: String?
    public let sourcePDF: String?
    public let audio: String?
    public let snapshotSyncedAt: String?
    public let urls: [String]
    public let arxiv: String?
    public let doi: String?
    public let annotationCount: Int
    public let commentCount: Int

    public init(
        path: String,
        link: String,
        title: String,
        refType: String? = nil,
        origin: String? = nil,
        status: String? = nil,
        readingState: String? = nil,
        blocked: Bool = false,
        parent: String? = nil,
        author: String? = nil,
        published: String? = nil,
        added: String? = nil,
        addedSource: String? = nil,
        finished: String? = nil,
        finishedSource: String? = nil,
        sourcePDF: String? = nil,
        audio: String? = nil,
        snapshotSyncedAt: String? = nil,
        urls: [String] = [],
        arxiv: String? = nil,
        doi: String? = nil,
        annotationCount: Int = 0,
        commentCount: Int = 0
    ) {
        self.path = path
        self.link = link
        self.title = title
        self.refType = refType
        self.origin = origin
        self.status = status
        self.readingState = readingState
        self.blocked = blocked
        self.parent = parent
        self.author = author
        self.published = published
        self.added = added
        self.addedSource = addedSource
        self.finished = finished
        self.finishedSource = finishedSource
        self.sourcePDF = sourcePDF
        self.audio = audio
        self.snapshotSyncedAt = snapshotSyncedAt
        self.urls = urls
        self.arxiv = arxiv
        self.doi = doi
        self.annotationCount = annotationCount
        self.commentCount = commentCount
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case link
        case title
        case refType = "ref_type"
        case origin
        case status
        case readingState = "reading_state"
        case blocked
        case parent
        case author
        case published
        case added
        case addedSource = "added_source"
        case finished
        case finishedSource = "finished_source"
        case sourcePDF = "source_pdf"
        case audio
        case snapshot
        case urls
        case identity
        case annotationCount = "annotation_count"
        case commentCount = "comment_count"
    }

    private enum SnapshotKeys: String, CodingKey {
        case syncedAt = "synced_at"
    }

    private struct SnapshotPayload: Decodable {
        let syncedAt: String?

        private enum CodingKeys: String, CodingKey {
            case syncedAt = "synced_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            syncedAt = try container.decodeIfPresent(String.self, forKey: .syncedAt)
        }
    }

    private struct IdentityPayload: Decodable {
        let arxiv: String?
        let doi: String?

        private enum CodingKeys: String, CodingKey {
            case arxiv
            case doi
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            arxiv = try container.decodeIfPresent(String.self, forKey: .arxiv)
            doi = try container.decodeIfPresent(String.self, forKey: .doi)
        }
    }

    private enum IdentityKeys: String, CodingKey {
        case arxiv
        case doi
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        link = try container.decode(String.self, forKey: .link)
        title = try container.decode(String.self, forKey: .title)
        refType = try container.decodeIfPresent(String.self, forKey: .refType)
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        readingState = try container.decodeIfPresent(String.self, forKey: .readingState)
        blocked = try container.decodeIfPresent(Bool.self, forKey: .blocked) ?? false
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        published = try container.decodeIfPresent(String.self, forKey: .published)
        added = try container.decodeIfPresent(String.self, forKey: .added)
        addedSource = try container.decodeIfPresent(String.self, forKey: .addedSource)
        finished = try container.decodeIfPresent(String.self, forKey: .finished)
        finishedSource = try container.decodeIfPresent(String.self, forKey: .finishedSource)
        sourcePDF = try container.decodeIfPresent(String.self, forKey: .sourcePDF)
        audio = try container.decodeIfPresent(String.self, forKey: .audio)
        snapshotSyncedAt = try container.decodeIfPresent(
            SnapshotPayload.self,
            forKey: .snapshot
        )?.syncedAt
        urls = try container.decodeIfPresent([String].self, forKey: .urls) ?? []
        let identity = try container.decodeIfPresent(IdentityPayload.self, forKey: .identity)
        arxiv = identity?.arxiv
        doi = identity?.doi
        annotationCount = try container.decodeIfPresent(Int.self, forKey: .annotationCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(link, forKey: .link)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(refType, forKey: .refType)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(readingState, forKey: .readingState)
        try container.encode(blocked, forKey: .blocked)
        try container.encodeIfPresent(parent, forKey: .parent)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(published, forKey: .published)
        try container.encodeIfPresent(added, forKey: .added)
        try container.encodeIfPresent(addedSource, forKey: .addedSource)
        try container.encodeIfPresent(finished, forKey: .finished)
        try container.encodeIfPresent(finishedSource, forKey: .finishedSource)
        try container.encodeIfPresent(sourcePDF, forKey: .sourcePDF)
        try container.encodeIfPresent(audio, forKey: .audio)
        if let snapshotSyncedAt {
            var snapshot = container.nestedContainer(
                keyedBy: SnapshotKeys.self,
                forKey: .snapshot
            )
            try snapshot.encode(snapshotSyncedAt, forKey: .syncedAt)
        }
        try container.encode(urls, forKey: .urls)
        var identity = container.nestedContainer(keyedBy: IdentityKeys.self, forKey: .identity)
        try identity.encodeIfPresent(arxiv, forKey: .arxiv)
        try identity.encodeIfPresent(doi, forKey: .doi)
        try container.encode(annotationCount, forKey: .annotationCount)
        try container.encode(commentCount, forKey: .commentCount)
    }
}

/// One `refs` array element that never fails: an undecodable row becomes nil
/// and is counted, so a single bad row cannot empty the library.
private struct LossyRefRecord: Decodable {
    let record: RefRecord?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        record = try? container.decode(RefRecord.self)
    }
}

/// The `bob plan` envelope the panel reads Today from. Only `today_tasks`
/// matters here; every other key is ignored.
public struct RefsPlanResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public let schemaVersion: Int
    public let todayTasks: [RefsPlanTodayTask]

    public init(schemaVersion: Int, todayTasks: [RefsPlanTodayTask] = []) {
        self.schemaVersion = schemaVersion
        self.todayTasks = todayTasks
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case todayTasks = "today_tasks"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        todayTasks = try container.decodeIfPresent(
            [RefsPlanTodayTask].self,
            forKey: .todayTasks
        ) ?? []
    }
}

/// One `today_tasks[]` entry: the note `path` it links, the Pomodoro
/// `entry_name`, and the task `status_symbol`. All other keys are ignored.
public struct RefsPlanTodayTask: Codable, Equatable, Sendable {
    public let path: String
    public let entryName: String
    public let statusSymbol: String?

    public init(path: String, entryName: String = "", statusSymbol: String? = nil) {
        self.path = path
        self.entryName = entryName
        self.statusSymbol = statusSymbol
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case entryName = "entry_name"
        case statusSymbol = "status_symbol"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        entryName = try container.decodeIfPresent(String.self, forKey: .entryName) ?? ""
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
    }
}
