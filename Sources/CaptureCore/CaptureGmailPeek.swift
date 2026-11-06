import Foundation

/// The schema-v1 metadata preview from `bob gmail peek <url> -f json`.
/// Bob owns resolution and the ready-made `message` line; the Mac client
/// only decodes it and paints the line in place of the offline preview.
/// `verdict` is `resolved` on a hit, or `unresolvable` / `refused` when
/// the URL cannot become a thread. Unknown verdicts still decode so a
/// newer Bob never breaks the panel.
public struct CaptureGmailPeekResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public let ok: Bool
    public let schemaVersion: Int
    public let verdict: String
    public let threadID: String?
    public let subject: String?
    public let who: String?
    public let messages: Int?
    public let lastDate: String?
    public let savedNote: String?
    public let label: String?
    public let message: String

    public init(
        ok: Bool = false,
        schemaVersion: Int = 1,
        verdict: String = "",
        threadID: String? = nil,
        subject: String? = nil,
        who: String? = nil,
        messages: Int? = nil,
        lastDate: String? = nil,
        savedNote: String? = nil,
        label: String? = nil,
        message: String = ""
    ) {
        self.ok = ok
        self.schemaVersion = schemaVersion
        self.verdict = verdict
        self.threadID = threadID
        self.subject = subject
        self.who = who
        self.messages = messages
        self.lastDate = lastDate
        self.savedNote = savedNote
        self.label = label
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
        schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 0
        verdict = (try? container.decodeIfPresent(String.self, forKey: .verdict)) ?? ""
        threadID = (try? container.decodeIfPresent(String.self, forKey: .threadID)) ?? nil
        subject = (try? container.decodeIfPresent(String.self, forKey: .subject)) ?? nil
        who = (try? container.decodeIfPresent(String.self, forKey: .who)) ?? nil
        messages = (try? container.decodeIfPresent(Int.self, forKey: .messages)) ?? nil
        lastDate = (try? container.decodeIfPresent(String.self, forKey: .lastDate)) ?? nil
        savedNote = (try? container.decodeIfPresent(String.self, forKey: .savedNote)) ?? nil
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? nil
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case schemaVersion = "schema_version"
        case verdict
        case threadID = "thread_id"
        case subject
        case who
        case messages
        case lastDate = "last_date"
        case savedNote = "saved_note"
        case label
        case message
    }
}
