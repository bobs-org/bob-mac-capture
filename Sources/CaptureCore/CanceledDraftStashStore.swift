import Foundation

public struct PersistedCanceledDraft: Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let createdAt: Date

    public init(id: UUID, text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

public struct CanceledDraftStashFile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let drafts: [PersistedCanceledDraft]

    public init(
        schemaVersion: Int = CanceledDraftStashFile.currentSchemaVersion,
        drafts: [PersistedCanceledDraft]
    ) {
        self.schemaVersion = schemaVersion
        self.drafts = drafts
    }
}

public protocol CanceledDraftStashStoring: Sendable {
    func load() -> [PersistedCanceledDraft]
    func save(_ drafts: [PersistedCanceledDraft])
}

public struct FileCanceledDraftStashStore: CanceledDraftStashStoring {
    public static let bundleIdentifier = "org.bobs.bob-mac-capture"
    public static let fileName = "canceled-draft-stash.json"
    public static let quarantineFileName = "canceled-draft-stash.corrupt.json"

    public static let unreadableQuarantinedMessage =
        "Canceled draft stash unreadable; quarantined and started empty"
    public static let unreadableStartedEmptyMessage =
        "Canceled draft stash unreadable; started empty"

    private let fileURL: URL
    private let fileManager: FileManager
    private let onError: @Sendable (String) -> Void

    public init(
        fileURL: URL,
        fileManager: FileManager = .default,
        onError: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.onError = onError
    }

    public static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func saveFailureMessage(for error: Error) -> String {
        "Canceled draft stash not saved: \(error.localizedDescription)"
    }

    // Load never creates the Application Support directory or the stash file. AppDelegate
    // construction under `swift test` must not litter the developer's real support directory.
    public func load() -> [PersistedCanceledDraft] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let file = try Self.makeDecoder().decode(CanceledDraftStashFile.self, from: data)
            guard file.schemaVersion == CanceledDraftStashFile.currentSchemaVersion else {
                quarantineUnreadableFile()
                return []
            }
            return file.drafts
        } catch {
            quarantineUnreadableFile()
            return []
        }
    }

    // An empty stash deletes both the stash file and the quarantine file rather than
    // writing `{"schemaVersion":1,"drafts":[]}`. Capacity 0 and Clear Stash then leave
    // no captured text on disk.
    public func save(_ drafts: [PersistedCanceledDraft]) {
        guard !drafts.isEmpty else {
            removePersistedFiles()
            return
        }

        do {
            try ensureParentDirectory()
            let file = CanceledDraftStashFile(drafts: drafts)
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
        parentDirectoryURL.appendingPathComponent(Self.quarantineFileName, isDirectory: false)
    }

    private func ensureParentDirectory() throws {
        try fileManager.createDirectory(
            at: parentDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
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

    private func removePersistedFiles() {
        do {
            try removeItemIfExists(at: fileURL)
            try removeItemIfExists(at: quarantineURL)
        } catch {
            onError(Self.saveFailureMessage(for: error))
        }
    }

    private func removeItemIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
