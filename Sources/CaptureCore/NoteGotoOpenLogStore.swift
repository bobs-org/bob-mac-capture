import Foundation

/// One successful `//` open: the vault hash plus the vault-relative note
/// path and the open time. The log never stores the vault path.
public struct NoteGotoOpenEvent: Codable, Equatable, Sendable {
    public let vault: String
    public let notePath: String
    public let at: Date

    public init(vault: String, notePath: String, at: Date) {
        self.vault = vault
        self.notePath = notePath
        self.at = at
    }

    private enum CodingKeys: String, CodingKey {
        case vault
        case notePath = "note_path"
        case at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vault = try container.decode(String.self, forKey: .vault)
        notePath = try container.decode(String.self, forKey: .notePath)
        let raw = try container.decode(String.self, forKey: .at)
        guard let date = Self.date(from: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .at,
                in: container,
                debugDescription: "Invalid ISO-8601 date"
            )
        }
        at = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vault, forKey: .vault)
        try container.encode(notePath, forKey: .notePath)
        try container.encode(Self.string(from: at), forKey: .at)
    }

    static func string(from date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    static func date(from raw: String) -> Date? {
        if let date = fractionalFormatter.date(from: raw) {
            return date
        }
        return plainFormatter.date(from: raw)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

public struct NoteGotoOpenLogFile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var opens: [NoteGotoOpenEvent]

    public init(
        schemaVersion: Int = NoteGotoOpenLogFile.currentSchemaVersion,
        opens: [NoteGotoOpenEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.opens = opens
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case opens
    }
}

/// The app-local `//` open history. Mirrors `RefsOpenLogStore` and
/// `FileCanceledDraftStashStore`: `load()` never creates the directory, a
/// corrupt file or schema mismatch is quarantined, and saves are atomic
/// with a 0600 file in a 0700 directory.
public struct NoteGotoOpenLogStore: Sendable {
    public static let bundleIdentifier = "org.bobs.bob-mac-capture"
    public static let fileName = "note-goto-open-log.json"
    public static let quarantineFileName = "note-goto-open-log.corrupt.json"
    public static let maxEvents = 500
    public static let maxAgeDays = 365

    public static let unreadableQuarantinedMessage =
        "Note Go To history unreadable; quarantined and started empty"
    public static let unreadableStartedEmptyMessage =
        "Note Go To history unreadable; started empty"

    private let fileURL: URL
    private let fileManager: FileManager
    private let onError: @Sendable (String) -> Void
    private let now: @Sendable () -> Date

    public init(
        fileURL: URL,
        fileManager: FileManager = .default,
        onError: @escaping @Sendable (String) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.onError = onError
        self.now = now
    }

    public static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return
            support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func saveFailureMessage(for error: Error) -> String {
        "Note Go To history not saved: \(error.localizedDescription)"
    }

    /// FNV-1a 64-bit hex of the vault root, the same scheme as the inbox
    /// route key, so the log never stores the vault path.
    public static func vaultHash(for vaultRoot: String) -> String {
        let hash = vaultRoot.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    // Load never creates the Application Support directory or the log
    // file. AppDelegate construction under `swift test` must not litter
    // the developer's real support directory.
    public func load() -> [NoteGotoOpenEvent] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let file = try Self.makeDecoder().decode(NoteGotoOpenLogFile.self, from: data)
            guard file.schemaVersion == NoteGotoOpenLogFile.currentSchemaVersion else {
                quarantineUnreadableFile()
                return []
            }
            return file.opens
        } catch {
            quarantineUnreadableFile()
            return []
        }
    }

    /// Loads, appends, prunes, and saves, so concurrent panels cannot lose
    /// each other's opens.
    public func append(_ event: NoteGotoOpenEvent) {
        var opens = load()
        opens.append(event)
        save(pruned(opens))
    }

    public func reset() {
        do {
            try removeItemIfExists(at: fileURL)
            try removeItemIfExists(at: quarantineURL)
        } catch {
            onError(Self.saveFailureMessage(for: error))
        }
    }

    func pruned(_ opens: [NoteGotoOpenEvent]) -> [NoteGotoOpenEvent] {
        let cutoff = now().addingTimeInterval(TimeInterval(-Self.maxAgeDays * 24 * 3_600))
        let fresh = opens.filter { $0.at >= cutoff }
        guard fresh.count > Self.maxEvents else {
            return fresh
        }
        return Array(fresh.sorted { $0.at < $1.at }.suffix(Self.maxEvents))
    }

    private func save(_ opens: [NoteGotoOpenEvent]) {
        do {
            try ensureParentDirectory()
            let file = NoteGotoOpenLogFile(opens: opens)
            let data = try Self.makeEncoder().encode(file)
            try data.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: parentDirectoryURL.path
            )
        } catch {
            onError(Self.saveFailureMessage(for: error))
        }
    }

    private var parentDirectoryURL: URL {
        fileURL.deletingLastPathComponent()
    }

    private var quarantineURL: URL {
        parentDirectoryURL.appendingPathComponent(
            Self.quarantineFileName,
            isDirectory: false
        )
    }

    private func ensureParentDirectory() throws {
        try fileManager.createDirectory(
            at: parentDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func removeItemIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func quarantineUnreadableFile() {
        do {
            try removeItemIfExists(at: quarantineURL)
            try fileManager.moveItem(at: fileURL, to: quarantineURL)
            onError(Self.unreadableQuarantinedMessage)
        } catch {
            onError(Self.unreadableStartedEmptyMessage)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
