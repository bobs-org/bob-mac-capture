import Foundation

/// Scope names accepted by `bob gcal note`. Unknown schema-v1 display values
/// remain available to the caller without gaining invented behavior.
public enum GcalNoteScope: Equatable, Sendable {
    case event
    case series
    case unknown(String)

    public init(_ wireValue: String) {
        switch wireValue {
        case "event": self = .event
        case "series": self = .series
        default: self = .unknown(wireValue)
        }
    }

    public var wireValue: String {
        switch self {
        case .event: "event"
        case .series: "series"
        case .unknown(let value): value
        }
    }
}

extension GcalNoteScope: Decodable {
    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }
}

public struct GcalNoteWindow: Decodable, Equatable, Sendable {
    public let from: String?
    public let to: String?
    public let start: String?
    public let end: String?
}

/// Identity is always the opaque calendar/event pair returned by Bob. The
/// client never decodes Google `eid` values from URLs.
public struct GcalNoteEvent: Decodable, Equatable, Sendable {
    public let calendarID: String
    public let eventID: String
    public let calendarName: String?
    public let seriesID: String?
    public let recurring: Bool?
    public let title: String?
    public let day: String?
    public let start: String?
    public let end: String?
    public let time: String?
    public let answer: String?
    public let organizer: GcalNoteOrganizer?
    public let url: String?
    public let lands: String?
    public let note: GcalNoteShowNote?

    private enum CodingKeys: String, CodingKey {
        case calendarID = "calendar_id"
        case eventID = "event_id"
        case calendarName = "calendar_name"
        case seriesID = "series_id"
        case recurring
        case title
        case day
        case start
        case end
        case time
        case answer
        case organizer
        case url
        case lands
        case note
    }
}

public struct GcalNoteOrganizer: Decodable, Equatable, Sendable {
    public let name: String?
    public let selfOrganized: Bool?

    private enum CodingKeys: String, CodingKey {
        case name
        case selfOrganized = "self"
    }
}

/// The show/list event note shape. Its `lines` are plain strings and its
/// summary fields describe the currently layered note.
public struct GcalNoteShowNote: Decodable, Equatable, Sendable {
    public let scope: GcalNoteScope?
    public let root: GcalNoteRoot?
    public let buffer: GcalNoteBufferSummary?
    public let clock: String?
    public let bulletLines: Int?
    public let text: String?
    public let lines: [String]

    private enum CodingKeys: String, CodingKey {
        case scope
        case root
        case buffer
        case clock
        case bulletLines = "bullet_lines"
        case text
        case lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try? container.decodeIfPresent(GcalNoteScope.self, forKey: .scope)
        root = try? container.decodeIfPresent(GcalNoteRoot.self, forKey: .root)
        buffer = try? container.decodeIfPresent(GcalNoteBufferSummary.self, forKey: .buffer)
        clock = try? container.decodeIfPresent(String.self, forKey: .clock)
        bulletLines = try? container.decodeIfPresent(Int.self, forKey: .bulletLines)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        lines = try container.decodeIfPresent([String].self, forKey: .lines) ?? []
    }
}

public struct GcalNoteRoot: Decodable, Equatable, Sendable {
    public let value: String?
    public let hue: String?
}

public struct GcalNoteBufferSummary: Decodable, Equatable, Sendable {
    public let beforeMinutes: Int?
    public let afterMinutes: Int?
    public let beforeReason: String?
    public let afterReason: String?

    private enum CodingKeys: String, CodingKey {
        case beforeMinutes = "before_minutes"
        case afterMinutes = "after_minutes"
        case beforeReason = "before_reason"
        case afterReason = "after_reason"
    }
}

public struct GcalNoteListResponse: Decodable, Equatable, SchemaVersioned, Sendable {
    public let schemaVersion: Int
    public let ok: Bool
    public let window: GcalNoteWindow?
    public let notes: [GcalNoteEvent]
    public let events: [GcalNoteEvent]
    public let orphans: [GcalNoteOrphan]
    public let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case window
        case notes
        case events
        case orphans
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        ok = try container.decode(Bool.self, forKey: .ok)
        window = try? container.decodeIfPresent(GcalNoteWindow.self, forKey: .window)
        notes = try container.decodeIfPresent([GcalNoteEvent].self, forKey: .notes) ?? []
        events = try container.decodeIfPresent([GcalNoteEvent].self, forKey: .events) ?? []
        orphans = try container.decodeIfPresent([GcalNoteOrphan].self, forKey: .orphans) ?? []
        warnings = (try? container.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    }
}

public struct GcalNoteOrphan: Decodable, Equatable, Sendable {
    public let calendarID: String
    public let eventID: String
    public let seriesID: String?
    public let scope: GcalNoteScope?
    public let title: String?
    public let reason: String?

    private enum CodingKeys: String, CodingKey {
        case calendarID = "calendar_id"
        case eventID = "event_id"
        case seriesID = "series_id"
        case scope
        case title
        case reason
    }
}

/// Show and URL selection share the same envelope. An ambiguous URL selection
/// has candidates and an error but no `event`; it still arrives on exit 2.
public struct GcalNoteShowResponse: Decodable, Equatable, SchemaVersioned, Sendable {
    public let schemaVersion: Int
    public let ok: Bool
    public let action: String?
    public let event: GcalNoteEvent?
    public let scope: GcalNoteScope?
    public let candidates: [GcalNoteEvent]
    public let effective: GcalNoteEffective?
    public let preview: GcalNotePreview?
    public let warnings: [String]
    public let error: GcalNoteError?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case action
        case event
        case scope
        case candidates
        case effective
        case preview
        case warnings
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        ok = try container.decode(Bool.self, forKey: .ok)
        action = try? container.decodeIfPresent(String.self, forKey: .action)
        event = try container.decodeIfPresent(GcalNoteEvent.self, forKey: .event)
        scope = try? container.decodeIfPresent(GcalNoteScope.self, forKey: .scope)
        candidates = try container.decodeIfPresent([GcalNoteEvent].self, forKey: .candidates) ?? []
        effective = try? container.decodeIfPresent(GcalNoteEffective.self, forKey: .effective)
        preview = try? container.decodeIfPresent(GcalNotePreview.self, forKey: .preview)
        warnings = (try? container.decodeIfPresent([String].self, forKey: .warnings)) ?? []
        error = try? container.decodeIfPresent(GcalNoteError.self, forKey: .error)
    }
}

/// Preview/write representation: typed line objects are intentionally
/// separate from `GcalNoteShowNote.lines`, which Bob returns as strings.
public struct GcalNoteWriteResponse: Decodable, Equatable, SchemaVersioned, Sendable {
    public let schemaVersion: Int
    public let ok: Bool
    public let action: String?
    public let event: GcalNoteEvent?
    public let scope: GcalNoteScope?
    public let input: GcalNoteInput?
    public let spans: [GcalNoteSpan]
    public let note: GcalNoteWriteNote?
    public let effective: GcalNoteEffective?
    public let preview: GcalNotePreview?
    public let status: GcalNoteStatus?
    public let errors: [GcalNoteIssue]
    public let warnings: [String]
    public let error: GcalNoteError?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case action
        case event
        case scope
        case input
        case spans
        case note
        case effective
        case preview
        case status
        case errors
        case warnings
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        ok = try container.decode(Bool.self, forKey: .ok)
        action = try? container.decodeIfPresent(String.self, forKey: .action)
        event = try container.decodeIfPresent(GcalNoteEvent.self, forKey: .event)
        scope = try? container.decodeIfPresent(GcalNoteScope.self, forKey: .scope)
        input = try? container.decodeIfPresent(GcalNoteInput.self, forKey: .input)
        spans = try container.decodeIfPresent([GcalNoteSpan].self, forKey: .spans) ?? []
        note = try? container.decodeIfPresent(GcalNoteWriteNote.self, forKey: .note)
        effective = try? container.decodeIfPresent(GcalNoteEffective.self, forKey: .effective)
        preview = try? container.decodeIfPresent(GcalNotePreview.self, forKey: .preview)
        status = try? container.decodeIfPresent(GcalNoteStatus.self, forKey: .status)
        errors = try container.decodeIfPresent([GcalNoteIssue].self, forKey: .errors) ?? []
        warnings = (try? container.decodeIfPresent([String].self, forKey: .warnings)) ?? []
        error = try? container.decodeIfPresent(GcalNoteError.self, forKey: .error)
    }
}

public struct GcalNoteInput: Decodable, Equatable, Sendable {
    public let text: String?
}

public struct GcalNoteWriteNote: Decodable, Equatable, Sendable {
    public let text: String?
    public let lines: [GcalNoteTypedLine]

    private enum CodingKeys: String, CodingKey {
        case text
        case lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        lines = try container.decodeIfPresent([GcalNoteTypedLine].self, forKey: .lines) ?? []
    }
}

public struct GcalNoteTypedLine: Decodable, Equatable, Sendable {
    public let kind: String
    public let text: String
    public let side: String?
    public let minutes: Int?
}

public struct GcalNoteSpan: Decodable, Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let kind: String
}

public struct GcalNoteIssue: Decodable, Equatable, Sendable {
    public let start: Int?
    public let end: Int?
    public let kind: String
    public let message: String?
    public let suggestions: [String]

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case kind
        case message
        case suggestions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try? container.decodeIfPresent(Int.self, forKey: .start)
        end = try? container.decodeIfPresent(Int.self, forKey: .end)
        kind = try container.decode(String.self, forKey: .kind)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        suggestions = try container.decodeIfPresent([String].self, forKey: .suggestions) ?? []
    }
}

public struct GcalNoteError: Decodable, Equatable, Sendable {
    public let kind: String
    public let message: String?
    public let hint: String?
}

public struct GcalNoteEffective: Decodable, Equatable, Sendable {
    public let root: GcalNoteEffectiveRoot?
    public let clock: String?
    public let buffer: GcalNoteBufferSummary?
    public let meeting: GcalNoteTimeBounds?
    public let occupied: GcalNoteOccupiedBounds?
    public let fields: [String]

    private enum CodingKeys: String, CodingKey {
        case root
        case clock
        case buffer
        case meeting
        case occupied
        case fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        root = try? container.decodeIfPresent(GcalNoteEffectiveRoot.self, forKey: .root)
        clock = try? container.decodeIfPresent(String.self, forKey: .clock)
        buffer = try? container.decodeIfPresent(GcalNoteBufferSummary.self, forKey: .buffer)
        meeting = try? container.decodeIfPresent(GcalNoteTimeBounds.self, forKey: .meeting)
        occupied = try? container.decodeIfPresent(GcalNoteOccupiedBounds.self, forKey: .occupied)
        fields = try container.decodeIfPresent([String].self, forKey: .fields) ?? []
    }
}

public struct GcalNoteEffectiveRoot: Decodable, Equatable, Sendable {
    public let value: String?
    public let source: String?
    public let kind: String?
    public let hue: String?
}

public struct GcalNoteTimeBounds: Decodable, Equatable, Sendable {
    public let start: String?
    public let end: String?
}

public struct GcalNoteOccupiedBounds: Decodable, Equatable, Sendable {
    public let start: String?
    public let end: String?
    public let clipped: Bool?
}

public struct GcalNotePreview: Decodable, Equatable, Sendable {
    public let path: String?
    public let row: String?
    public let bullets: [String]
    public let rail: String?
    public let meeting: GcalNoteTimeBounds?
    public let occupied: GcalNoteOccupiedBounds?

    private enum CodingKeys: String, CodingKey {
        case path
        case row
        case bullets
        case rail
        case meeting
        case occupied
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        row = try? container.decodeIfPresent(String.self, forKey: .row)
        bullets = try container.decodeIfPresent([String].self, forKey: .bullets) ?? []
        rail = try? container.decodeIfPresent(String.self, forKey: .rail)
        meeting = try? container.decodeIfPresent(GcalNoteTimeBounds.self, forKey: .meeting)
        occupied = try? container.decodeIfPresent(GcalNoteOccupiedBounds.self, forKey: .occupied)
    }
}

public struct GcalNoteStatus: Decodable, Equatable, Sendable {
    public let state: String
    public let detail: String?
    public let path: String?
}

/// Bob can return nested spans (for example `buffer` and `reason_sign`).
/// Validate each UTF-8 range independently, then order broad styles before
/// nested signs and error overlays. Unsafe offsets are ignored safely.
public enum GcalNoteSpanAdapter {
    public static func validatedRanges(in text: String, spans: [GcalNoteSpan])
        -> [ValidatedCaptureSpan]
    {
        let validated = spans.compactMap { span -> (Int, Int, ValidatedCaptureSpan)? in
            let captureSpan = CaptureSpan(start: span.start, end: span.end, kind: span.kind)
            guard let value = validatedSpanRanges(in: text, spans: [captureSpan])?.first else {
                return nil
            }
            let overlay = ["reason_sign", "error", "warning"].contains(span.kind)
            return (overlay ? 1 : 0, -(span.end - span.start), value)
        }
        return validated.sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2.span.start < $1.2.span.start
        }.map(\.2)
    }
}
