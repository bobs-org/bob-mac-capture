import Darwin
import Foundation

/// The live-claim record Bob's auto route reads before choosing the
/// `mac_capture` notification channel. Well-formed with a live pid, it
/// keeps Bob's wake on the app path; corrupt, stale, or absent claims
/// leave the desktop fallback available.
struct SnoozeWakeClaimRecord: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var pid: Int32
    var app: String
    var version: String
    var startedAt: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case pid
        case app
        case version
        case startedAt = "started_at"
    }
}

/// Atomic writer for the sibling `notifier.json` claim. The claim is
/// written with 0600 through a temp file plus rename, and only a claim
/// this instance still owns (pid plus start token) is ever removed, so
/// overlapping instances never delete each other's ownership.
final class SnoozeWakeNotifierClaim: Sendable {
    private let pid: Int32
    private let app: String
    private let version: String
    private let startedAt: String
    private let claimURL: URL
    private let pidIsAlive: @Sendable (Int32) -> Bool

    init(
        claimURL: URL,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        app: String = Bundle.main.bundleIdentifier ?? "org.bobs.bob-mac-capture",
        version: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0",
        startedAt: String? = nil,
        pidIsAlive: (@Sendable (Int32) -> Bool)? = nil
    ) {
        self.claimURL = claimURL
        self.pid = pid
        self.app = app
        self.version = version
        if let startedAt {
            self.startedAt = startedAt
        } else {
            self.startedAt = Self.iso8601Now()
        }
        if let pidIsAlive {
            self.pidIsAlive = pidIsAlive
        } else {
            self.pidIsAlive = { candidate in
                candidate > 0 && kill(candidate, 0) == 0
            }
        }
    }

    /// Resolves the sibling claim path from the same state root as the
    /// wake receipt: `XDG_STATE_HOME`, otherwise `$HOME/.local/state`,
    /// then `bob-cli/snooze/notifier.json`.
    static func defaultClaimURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let stateRoot: URL
        if let xdgStateHome = environment["XDG_STATE_HOME"], !xdgStateHome.isEmpty {
            stateRoot = URL(fileURLWithPath: xdgStateHome, isDirectory: true)
        } else {
            let home =
                environment["HOME"].flatMap { value in
                    value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
                } ?? homeDirectoryURL
            stateRoot = home.appendingPathComponent(".local/state", isDirectory: true)
        }
        return
            stateRoot
            .appendingPathComponent("bob-cli", isDirectory: true)
            .appendingPathComponent("snooze", isDirectory: true)
            .appendingPathComponent("notifier.json", isDirectory: false)
    }

    /// The record this instance writes and later compares for ownership.
    var record: SnoozeWakeClaimRecord {
        SnoozeWakeClaimRecord(
            schemaVersion: 1,
            pid: pid,
            app: app,
            version: version,
            startedAt: startedAt
        )
    }

    /// Atomically publishes the claim. Overwrites any stale claim; a
    /// live rival claim is replaced by rename, and ownership of the new
    /// file belongs to this instance by pid plus start token.
    func publish() throws {
        let dir = claimURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(record)
        let temp = dir.appendingPathComponent(
            ".notifier.\(pid).\(UUID().uuidString).tmp")
        try bytes.write(to: temp, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: temp.path)
        if FileManager.default.fileExists(atPath: claimURL.path) {
            try FileManager.default.removeItem(at: claimURL)
        }
        try FileManager.default.moveItem(at: temp, to: claimURL)
    }

    /// Removes the claim only when the file still holds this instance's
    /// pid plus start token. A rival claim, an empty path, or an
    /// unreadable file is left untouched.
    func relinquish() {
        guard let current = Self.readRecord(at: claimURL) else {
            return
        }
        guard current.pid == pid, current.startedAt == startedAt else {
            return
        }
        try? FileManager.default.removeItem(at: claimURL)
    }

    /// Whether the file currently holds this instance's claim.
    var isOwned: Bool {
        guard let current = Self.readRecord(at: claimURL) else {
            return false
        }
        return current.pid == pid && current.startedAt == startedAt
    }

    /// Whether any well-formed claim with a live pid exists at the URL.
    /// Corrupt or unsupported claims never suppress desktop fallback.
    func isLiveClaim() -> Bool {
        guard let current = Self.readRecord(at: claimURL) else {
            return false
        }
        guard current.schemaVersion == 1, !current.app.isEmpty,
            !current.version.isEmpty, !current.startedAt.isEmpty
        else {
            return false
        }
        return pidIsAlive(current.pid)
    }

    static func readRecord(at url: URL) -> SnoozeWakeClaimRecord? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SnoozeWakeClaimRecord.self, from: data)
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
