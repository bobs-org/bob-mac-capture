import Foundation

/// On-disk cache for the decoded snapshot plus the last Today value, so a
/// cold launch paints immediately. Follows `FileCanceledDraftStashStore`:
/// the load never creates the directory, a corrupt file or schema mismatch
/// is renamed to `*.corrupt.json` and reported through `onError`, and saves
/// are atomic with a 0600 file in a 0700 directory.
public struct RefsSnapshotFile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var snapshot: RefsSnapshot?
    public var today: RefsToday?

    public init(
        schemaVersion: Int = RefsSnapshotFile.currentSchemaVersion,
        snapshot: RefsSnapshot? = nil,
        today: RefsToday? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.snapshot = snapshot
        self.today = today
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case snapshot
        case today
    }
}

public struct RefsSnapshotStore: Sendable {
    public static let bundleIdentifier = "org.bobs.bob-mac-capture"
    public static let fileName = "refs-snapshot.json"
    public static let quarantineFileName = "refs-snapshot.corrupt.json"

    public static let unreadableQuarantinedMessage =
        "Refs snapshot unreadable; quarantined and started empty"
    public static let unreadableStartedEmptyMessage =
        "Refs snapshot unreadable; started empty"

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
        "Refs snapshot not saved: \(error.localizedDescription)"
    }

    // Load never creates the Application Support directory or the cache
    // file. AppDelegate construction under `swift test` must not litter
    // the developer's real support directory.
    public func load() -> RefsSnapshotFile {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return RefsSnapshotFile()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let file = try RefsStoreCodecs.decoder().decode(RefsSnapshotFile.self, from: data)
            guard file.schemaVersion == RefsSnapshotFile.currentSchemaVersion else {
                quarantineUnreadableFile()
                return RefsSnapshotFile()
            }
            return file
        } catch {
            quarantineUnreadableFile()
            return RefsSnapshotFile()
        }
    }

    public func save(snapshot: RefsSnapshot, today: RefsToday?) {
        do {
            try RefsStoreCodecs.ensureParentDirectory(for: fileURL, fileManager: fileManager)
            let file = RefsSnapshotFile(snapshot: snapshot, today: today)
            let data = try RefsStoreCodecs.encoder().encode(file)
            try RefsStoreCodecs.writeAtomically(
                data,
                to: fileURL,
                fileManager: fileManager
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

    private func quarantineUnreadableFile() {
        do {
            try RefsStoreCodecs.removeItemIfExists(at: quarantineURL, fileManager: fileManager)
            try fileManager.moveItem(at: fileURL, to: quarantineURL)
            onError(Self.unreadableQuarantinedMessage)
        } catch {
            onError(Self.unreadableStartedEmptyMessage)
        }
    }
}

/// One successful open of a reference PDF in Highlights or the default app.
/// Note opens, reveals, selections, and previews are never recorded.
public struct RefsOpenEvent: Codable, Equatable, Sendable {
    public let path: String
    public let at: Date

    public init(path: String, at: Date) {
        self.path = path
        self.at = at
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case at
    }
}

public struct RefsOpenLogFile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var opens: [RefsOpenEvent]

    public init(
        schemaVersion: Int = RefsOpenLogFile.currentSchemaVersion,
        opens: [RefsOpenEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.opens = opens
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case opens
    }
}

/// The append-only open history: note paths and timestamps only. Pruning
/// drops events older than 365 days, then keeps the newest 2000.
public struct RefsOpenLogStore: Sendable {
    public static let bundleIdentifier = "org.bobs.bob-mac-capture"
    public static let fileName = "refs-open-log.json"
    public static let quarantineFileName = "refs-open-log.corrupt.json"
    public static let maxEvents = 2000
    public static let maxAgeDays = 365

    public static let unreadableQuarantinedMessage =
        "Refs open log unreadable; quarantined and started empty"
    public static let unreadableStartedEmptyMessage =
        "Refs open log unreadable; started empty"

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
        return support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func saveFailureMessage(for error: Error) -> String {
        "Refs open log not saved: \(error.localizedDescription)"
    }

    public func load() -> [RefsOpenEvent] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let file = try RefsStoreCodecs.decoder().decode(RefsOpenLogFile.self, from: data)
            guard file.schemaVersion == RefsOpenLogFile.currentSchemaVersion else {
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
    public func append(_ event: RefsOpenEvent) {
        var opens = load()
        opens.append(event)
        save(pruned(opens))
    }

    public func reset() {
        do {
            try RefsStoreCodecs.removeItemIfExists(at: fileURL, fileManager: fileManager)
            try RefsStoreCodecs.removeItemIfExists(
                at: quarantineURL,
                fileManager: fileManager
            )
        } catch {
            onError(Self.saveFailureMessage(for: error))
        }
    }

    func pruned(_ opens: [RefsOpenEvent]) -> [RefsOpenEvent] {
        let cutoff = now().addingTimeInterval(TimeInterval(-Self.maxAgeDays * 24 * 3_600))
        let fresh = opens.filter { $0.at >= cutoff }
        guard fresh.count > Self.maxEvents else {
            return fresh
        }
        return Array(fresh.sorted { $0.at < $1.at }.suffix(Self.maxEvents))
    }

    private func save(_ opens: [RefsOpenEvent]) {
        do {
            try RefsStoreCodecs.ensureParentDirectory(for: fileURL, fileManager: fileManager)
            let file = RefsOpenLogFile(opens: opens)
            let data = try RefsStoreCodecs.encoder().encode(file)
            try RefsStoreCodecs.writeAtomically(
                data,
                to: fileURL,
                fileManager: fileManager
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

    private func quarantineUnreadableFile() {
        do {
            try RefsStoreCodecs.removeItemIfExists(at: quarantineURL, fileManager: fileManager)
            try fileManager.moveItem(at: fileURL, to: quarantineURL)
            onError(Self.unreadableQuarantinedMessage)
        } catch {
            onError(Self.unreadableStartedEmptyMessage)
        }
    }
}

/// Read model over the open log: last-opened dates, open counts, and the
/// frecency decay `Σ 0.5^(ageDays / frecencyHalfLifeDays)` the ranker
/// weights.
public struct RefsOpenStats: Equatable, Sendable {
    private let lastOpenedByPath: [String: Date]
    private let countByPath: [String: Int]
    private let frecencyByPath: [String: Double]
    public let maxFrecency: Double

    public init(events: [RefsOpenEvent], now: Date) {
        var lastOpened: [String: Date] = [:]
        var counts: [String: Int] = [:]
        var frecency: [String: Double] = [:]
        for event in events {
            counts[event.path, default: 0] += 1
            if let known = lastOpened[event.path] {
                lastOpened[event.path] = max(known, event.at)
            } else {
                lastOpened[event.path] = event.at
            }
            let ageDays = max(0, now.timeIntervalSince(event.at) / 86_400)
            frecency[event.path, default: 0] += pow(
                0.5, ageDays / RefsRankingConstants.frecencyHalfLifeDays
            )
        }
        lastOpenedByPath = lastOpened
        countByPath = counts
        frecencyByPath = frecency
        maxFrecency = frecency.values.max() ?? 0
    }

    public func lastOpened(_ path: String) -> Date? {
        lastOpenedByPath[path]
    }

    public func count(_ path: String) -> Int {
        countByPath[path] ?? 0
    }

    public func frecency(_ path: String) -> Double {
        frecencyByPath[path] ?? 0
    }
}

enum RefsStoreCodecs {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static func ensureParentDirectory(for fileURL: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    static func writeAtomically(
        _ data: Data,
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fileURL.deletingLastPathComponent().path
        )
    }

    static func removeItemIfExists(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }
}
