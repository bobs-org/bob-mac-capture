import CaptureCore
import Foundation

/// Additive fields are optional; bob owns identity, destination selection, and link semantics.
public struct RefsTodayLinkReference: Decodable, Equatable, Sendable {
    public let path: String?
    public let link: String?
    public let title: String?
    public let markerID: String?

    public init(
        path: String? = nil,
        link: String? = nil,
        title: String? = nil,
        markerID: String? = nil
    ) {
        self.path = path
        self.link = link
        self.title = title
        self.markerID = markerID
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case link
        case title
        case markerID = "marker_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        markerID = try container.decodeIfPresent(String.self, forKey: .markerID)
    }
}

/// Additive fields are optional; bob owns identity, destination selection, and link semantics.
public struct RefsTodayLinkTask: Decodable, Equatable, Sendable {
    public let path: String?
    public let blockID: String?
    public let link: String?
    public let statusSymbol: String?
    public let statusName: String?

    public init(
        path: String? = nil,
        blockID: String? = nil,
        link: String? = nil,
        statusSymbol: String? = nil,
        statusName: String? = nil
    ) {
        self.path = path
        self.blockID = blockID
        self.link = link
        self.statusSymbol = statusSymbol
        self.statusName = statusName
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case blockID = "block_id"
        case link
        case statusSymbol = "status_symbol"
        case statusName = "status_name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        statusSymbol = try container.decodeIfPresent(String.self, forKey: .statusSymbol)
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName)
    }
}

/// Additive fields are optional; bob owns identity, destination selection, and link semantics.
public struct RefsTodayLinkPomodoro: Decodable, Equatable, Sendable {
    public let ref: String
    public let line: Int?
    public let name: String?
    public let slug: String?
    public let timeRange: String?
    public let placeholder: Bool
    public let startsAt: String?
    public let endsAt: String?
    public let running: Bool
    public let isDefault: Bool
    public let linked: Bool
    public let taskLinkCount: Int
    public let homes: CaptureAgendaHomes?
    /// Theme refs for the row name. Bob omits them on older binaries;
    /// they decode as empty and the row renders the plain name.
    public let themes: [CapturePomodoroThemeRef]

    public init(
        ref: String,
        line: Int? = nil,
        name: String? = nil,
        slug: String? = nil,
        timeRange: String? = nil,
        placeholder: Bool = false,
        startsAt: String? = nil,
        endsAt: String? = nil,
        running: Bool = false,
        isDefault: Bool = false,
        linked: Bool = false,
        taskLinkCount: Int = 0,
        homes: CaptureAgendaHomes? = nil,
        themes: [CapturePomodoroThemeRef] = []
    ) {
        self.ref = ref
        self.line = line
        self.name = name
        self.slug = slug
        self.timeRange = timeRange
        self.placeholder = placeholder
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.running = running
        self.isDefault = isDefault
        self.linked = linked
        self.taskLinkCount = taskLinkCount
        self.homes = homes
        self.themes = themes
    }

    private enum CodingKeys: String, CodingKey {
        case ref
        case line
        case name
        case slug
        case timeRange = "time_range"
        case placeholder
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case running
        case isDefault = "default"
        case linked
        case taskLinkCount = "task_link_count"
        case homes
        case themes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ref = try container.decode(String.self, forKey: .ref)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
        placeholder = try container.decodeIfPresent(Bool.self, forKey: .placeholder) ?? false
        startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(String.self, forKey: .endsAt)
        running = try container.decodeIfPresent(Bool.self, forKey: .running) ?? false
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        linked = try container.decodeIfPresent(Bool.self, forKey: .linked) ?? false
        taskLinkCount = try container.decodeIfPresent(Int.self, forKey: .taskLinkCount) ?? 0
        homes = try container.decodeIfPresent(CaptureAgendaHomes.self, forKey: .homes)
        themes =
            (try? container.decodeIfPresent(
                [CapturePomodoroThemeRef].self,
                forKey: .themes
            )) ?? []
    }
}

/// Additive fields are optional; bob owns identity, destination selection, and link semantics.
public struct RefsTodayLinkFailure: Decodable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let hint: String?

    public init(
        code: String,
        message: String,
        hint: String? = nil
    ) {
        self.code = code
        self.message = message
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case hint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
    }
}

/// Additive fields are optional; bob owns identity, destination selection, and link semantics.
public struct RefsTodayLinkResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public let schemaVersion: Int
    public let ok: Bool?
    public let mode: String?
    public let changed: Bool?
    public let ref: RefsTodayLinkReference?
    public let task: RefsTodayLinkTask?
    public let pomodoros: [RefsTodayLinkPomodoro]
    public let capture: CaptureCommandSuccess?
    public let error: RefsTodayLinkFailure?
    public let candidates: [RefsTodayLinkReference]

    public init(
        schemaVersion: Int = 1,
        ok: Bool? = nil,
        mode: String? = nil,
        changed: Bool? = nil,
        ref: RefsTodayLinkReference? = nil,
        task: RefsTodayLinkTask? = nil,
        pomodoros: [RefsTodayLinkPomodoro] = [],
        capture: CaptureCommandSuccess? = nil,
        error: RefsTodayLinkFailure? = nil,
        candidates: [RefsTodayLinkReference] = []
    ) {
        self.schemaVersion = schemaVersion
        self.ok = ok
        self.mode = mode
        self.changed = changed
        self.ref = ref
        self.task = task
        self.pomodoros = pomodoros
        self.capture = capture
        self.error = error
        self.candidates = candidates
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case mode
        case changed
        case ref
        case task
        case pomodoros
        case capture
        case error
        case candidates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        changed = try container.decodeIfPresent(Bool.self, forKey: .changed)
        ref = try container.decodeIfPresent(RefsTodayLinkReference.self, forKey: .ref)
        task = try container.decodeIfPresent(RefsTodayLinkTask.self, forKey: .task)
        pomodoros =
            try container.decodeIfPresent([RefsTodayLinkPomodoro].self, forKey: .pomodoros) ?? []
        capture = try container.decodeIfPresent(CaptureCommandSuccess.self, forKey: .capture)
        error = try container.decodeIfPresent(RefsTodayLinkFailure.self, forKey: .error)
        candidates =
            try container.decodeIfPresent([RefsTodayLinkReference].self, forKey: .candidates) ?? []
    }
}

public enum RefsTodayLinkSelector: Equatable, Sendable {
    case automatic
    case entry(ref: String)
    case exactName(String)

    public var arguments: [String] {
        switch self {
        case .automatic: return []
        case .entry(let ref): return ["-P", ref]
        case .exactName(let name): return ["-p", name, "-e"]
        }
    }
}

public enum RefsTodayLinkProblemMapping {
    public static func responseProblem(_ response: RefsTodayLinkResponse) -> RefsTodayLinkFailure? {
        response.error
    }

    public static func transportProblem(for error: Error) -> RefsTodayLinkFailure {
        if let clientError = error as? BobClientError {
            if case .timedOut = clientError {
                return RefsTodayLinkFailure(
                    code: "timed_out", message: RefsTodayLinkPresentation.timeoutMessage,
                    hint: RefsTodayLinkPresentation.timeoutHint)
            }
            if case .processFailed(_, let status, _) = clientError, status == 2 {
                return RefsTodayLinkFailure(
                    code: "bob_too_old",
                    message: RefsTodayLinkPresentation.bobTooOldMessage)
            }
        }
        return RefsTodayLinkFailure(
            code: "transport", message: boundedProcessText(String(describing: error)))
    }
}
