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
    private enum ClaimError: Error {
        case system(operation: String, code: Int32)
    }

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
                candidate > 0 && (kill(candidate, 0) == 0 || errno == EPERM)
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

    /// Atomically publishes only when the path is unclaimed or its owner
    /// is dead. A stable lock serializes competing launches so an active
    /// claim cannot be displaced by an evaluate-loop race.
    func publish() throws {
        let dir = claimURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try withClaimLock {
            if let existing = Self.readRecord(at: claimURL),
                Self.isLive(existing, pidIsAlive: pidIsAlive)
            {
                guard existing.pid == pid, existing.startedAt == startedAt else {
                    return
                }
                return
            }
            try publishAtomically(in: dir)
        }
    }

    /// Removes the claim only when the file still holds this instance's
    /// pid plus start token. A rival claim, an empty path, or an
    /// unreadable file is left untouched.
    func relinquish() {
        try? withClaimLock {
            guard let current = Self.readRecord(at: claimURL),
                current.pid == pid, current.startedAt == startedAt
            else {
                return
            }
            try FileManager.default.removeItem(at: claimURL)
        }
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
        return Self.isLive(current, pidIsAlive: pidIsAlive)
    }

    private static func isLive(
        _ current: SnoozeWakeClaimRecord, pidIsAlive: @Sendable (Int32) -> Bool
    ) -> Bool {
        current.schemaVersion == 1
            && current.pid > 0
            && !current.app.isEmpty
            && !current.version.isEmpty
            && !current.startedAt.isEmpty
            && pidIsAlive(current.pid)
    }

    private func withClaimLock(_ body: () throws -> Void) throws {
        let lockURL = claimURL.deletingLastPathComponent()
            .appendingPathComponent(".notifier.lock", isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else {
            throw ClaimError.system(operation: "open claim lock", code: errno)
        }
        defer { _ = close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw ClaimError.system(operation: "lock notifier claim", code: errno)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        try body()
    }

    private func publishAtomically(in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(record)
        let temp = directory.appendingPathComponent(
            ".notifier.\(pid).\(UUID().uuidString).tmp")
        let descriptor = open(
            temp.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else {
            throw ClaimError.system(operation: "create temporary notifier claim", code: errno)
        }
        var closed = false
        defer {
            if !closed {
                _ = close(descriptor)
            }
            _ = unlink(temp.path)
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw ClaimError.system(operation: "protect temporary notifier claim", code: errno)
        }
        try bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var offset = 0
            while offset < rawBuffer.count {
                let written = write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0 && errno == EINTR {
                    continue
                }
                guard written > 0 else {
                    throw ClaimError.system(operation: "write notifier claim", code: errno)
                }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else {
            throw ClaimError.system(operation: "sync notifier claim", code: errno)
        }
        guard close(descriptor) == 0 else {
            closed = true
            throw ClaimError.system(operation: "close notifier claim", code: errno)
        }
        closed = true
        guard rename(temp.path, claimURL.path) == 0 else {
            throw ClaimError.system(operation: "publish notifier claim", code: errno)
        }
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
