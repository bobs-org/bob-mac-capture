import Foundation

/// The notification owner Bob selected before writing the receipt.
/// Missing or unknown ownership is never permission to announce.
public enum SnoozeWakeNotificationChannel: Equatable, Sendable, Hashable {
    case macCapture
    case desktop
    case off
    case unknown(String)

    public init(rawValue: String?) {
        switch rawValue {
        case "mac_capture":
            self = .macCapture
        case "desktop":
            self = .desktop
        case "off":
            self = .off
        case .none:
            self = .unknown("")
        case .some(let other):
            self = .unknown(other)
        }
    }

    public var rawValue: String? {
        switch self {
        case .macCapture:
            return "mac_capture"
        case .desktop:
            return "desktop"
        case .off:
            return "off"
        case .unknown(let other):
            return other.isEmpty ? nil : other
        }
    }

    /// Only an explicit `mac_capture` receipt may drive app notice surfaces.
    public var permitsMacNotice: Bool {
        self == .macCapture
    }
}

/// One task entry inside a wake receipt. Every field decodes tolerantly:
/// older or hand-edited receipts may carry nulls, and unknown keys are ignored.
public struct SnoozeWakeReceiptTask: Decodable, Equatable, Sendable {
    public let title: String?
    public let route: String?
    public let blockID: String?
    public let target: String?
    public let wokeAt: String?
    public let destination: String?
    public let line: Int?

    public init(
        title: String? = nil,
        route: String? = nil,
        blockID: String? = nil,
        target: String? = nil,
        wokeAt: String? = nil,
        destination: String? = nil,
        line: Int? = nil
    ) {
        self.title = title
        self.route = route
        self.blockID = blockID
        self.target = target
        self.wokeAt = wokeAt
        self.destination = destination
        self.line = line
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case route
        case blockID = "block_id"
        case target
        case wokeAt = "woke_at"
        case destination
        case line
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        wokeAt = try container.decodeIfPresent(String.self, forKey: .wokeAt)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
    }

    /// Stable task identity for filtering and acknowledgement.
    /// Nil when the receipt omits the locator, so callers can drop it.
    public var identityKey: String? {
        guard let route, !route.isEmpty, let blockID, !blockID.isEmpty else {
            return nil
        }
        return "\(route)#\(blockID)"
    }
}

/// Bob's small passthrough plan object on the receipt. Unknown shapes
/// decode as empty so a newer bob never breaks an older client.
public struct SnoozeWakeReceiptPlan: Decodable, Equatable, Sendable {
    public let count: Int?
    public let cap: Int?
    public let over: Bool?

    public init(count: Int? = nil, cap: Int? = nil, over: Bool? = nil) {
        self.count = count
        self.cap = cap
        self.over = over
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case cap
        case over
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        cap = try container.decodeIfPresent(Int.self, forKey: .cap)
        over = try container.decodeIfPresent(Bool.self, forKey: .over)
    }
}

/// Portable decoding of `bob-cli/snooze/last-wake.json` (schema 1).
/// Additive Rust fields decode untouched; unknown keys are ignored.
public struct SnoozeWakeReceipt: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let wakeID: String
    public let date: String
    public let wokenAt: String
    public let host: String
    public let notificationChannel: SnoozeWakeNotificationChannel
    public let vaultRoot: String?
    public let dailyFile: String
    public let tasks: [SnoozeWakeReceiptTask]
    public let plan: SnoozeWakeReceiptPlan

    public init(
        schemaVersion: Int = 1,
        wakeID: String,
        date: String,
        wokenAt: String,
        host: String = "",
        notificationChannel: SnoozeWakeNotificationChannel = .unknown(""),
        vaultRoot: String? = nil,
        dailyFile: String,
        tasks: [SnoozeWakeReceiptTask] = [],
        plan: SnoozeWakeReceiptPlan = SnoozeWakeReceiptPlan()
    ) {
        self.schemaVersion = schemaVersion
        self.wakeID = wakeID
        self.date = date
        self.wokenAt = wokenAt
        self.host = host
        self.notificationChannel = notificationChannel
        self.vaultRoot = vaultRoot
        self.dailyFile = dailyFile
        self.tasks = tasks
        self.plan = plan
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case wakeID = "wake_id"
        case date
        case wokenAt = "woken_at"
        case host
        case notificationChannel = "notification_channel"
        case vaultRoot = "vault_root"
        case dailyFile = "daily_file"
        case tasks
        case plan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        wakeID = try container.decodeIfPresent(String.self, forKey: .wakeID) ?? ""
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        wokenAt = try container.decodeIfPresent(String.self, forKey: .wokenAt) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        let rawChannel = try container.decodeIfPresent(String.self, forKey: .notificationChannel)
        notificationChannel = SnoozeWakeNotificationChannel(rawValue: rawChannel)
        vaultRoot = try container.decodeIfPresent(String.self, forKey: .vaultRoot)
        dailyFile = try container.decodeIfPresent(String.self, forKey: .dailyFile) ?? ""
        tasks = try container.decodeIfPresent(
            [SnoozeWakeReceiptTask].self, forKey: .tasks) ?? []
        plan = try container.decodeIfPresent(
            SnoozeWakeReceiptPlan.self, forKey: .plan) ?? SnoozeWakeReceiptPlan()
    }
}

public enum SnoozeWakeReceiptError: Error, Equatable, Sendable {
    case tooLarge(maximumBytes: Int)
    case unreadable(reason: String)
    case malformed(reason: String)
}

/// Bounded reader for the wake receipt, mirroring
/// `RefsScanReceiptReader` without importing RefsCore into CaptureCore.
/// Unsupported schema versions are ignored (nil). Malformed, oversized,
/// or unreadable input throws a nonfatal `SnoozeWakeReceiptError` the
/// caller reports as a diagnostic without disturbing the scheduler.
public struct SnoozeWakeReceiptReader: Sendable {
    public static let maximumBytes = 4 * 1024 * 1024

    /// Darwin notification posted after a writing `bob snooze wake`
    /// rewrites the receipt for the `mac_capture` owner only.
    public static let darwinNotificationName = "org.bobs.bob.snooze.woken"

    public init() {}

    /// Resolves the same state root as bob: `XDG_STATE_HOME`, otherwise
    /// `$HOME/.local/state`, then `bob-cli/snooze/last-wake.json`.
    public static func receiptURL(
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
            .appendingPathComponent("last-wake.json", isDirectory: false)
    }

    public func read(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> SnoozeWakeReceipt? {
        try read(at: Self.receiptURL(environment: environment, homeDirectoryURL: homeDirectoryURL))
    }

    public func read(at url: URL) throws -> SnoozeWakeReceipt? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw SnoozeWakeReceiptError.unreadable(reason: error.localizedDescription)
        }
        defer { try? handle.close() }

        var data = Data()
        do {
            while data.count <= Self.maximumBytes {
                let remaining = Self.maximumBytes + 1 - data.count
                guard remaining > 0,
                    let chunk = try handle.read(upToCount: min(64 * 1024, remaining)),
                    !chunk.isEmpty
                else {
                    break
                }
                data.append(chunk)
            }
        } catch {
            throw SnoozeWakeReceiptError.unreadable(reason: error.localizedDescription)
        }

        guard data.count <= Self.maximumBytes else {
            throw SnoozeWakeReceiptError.tooLarge(maximumBytes: Self.maximumBytes)
        }

        let receipt: SnoozeWakeReceipt
        do {
            receipt = try JSONDecoder().decode(SnoozeWakeReceipt.self, from: data)
        } catch {
            throw SnoozeWakeReceiptError.malformed(reason: error.localizedDescription)
        }
        guard receipt.schemaVersion == 1 else {
            return nil
        }
        return receipt
    }
}
