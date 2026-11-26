import Foundation

/// One row in `bob snooze list -f json`. `wake_notice_eligible` is the
/// read-only capability Bob computed: true only for today's valid woken
/// history that still resolves to an actionable open task. A missing field
/// (older bob) or an unknown ownership value is never permission to announce.
public struct SnoozeWakeListRow: Decodable, Equatable, Sendable {
    public let line: Int?
    public let route: String?
    public let blockID: String?
    public let title: String?
    public let target: String?
    public let state: String
    public let reason: String?
    public let wokeAt: String?
    public let wakeNoticeEligible: Bool?

    public init(
        line: Int? = nil,
        route: String? = nil,
        blockID: String? = nil,
        title: String? = nil,
        target: String? = nil,
        state: String = "",
        reason: String? = nil,
        wokeAt: String? = nil,
        wakeNoticeEligible: Bool? = nil
    ) {
        self.line = line
        self.route = route
        self.blockID = blockID
        self.title = title
        self.target = target
        self.state = state
        self.reason = reason
        self.wokeAt = wokeAt
        self.wakeNoticeEligible = wakeNoticeEligible
    }

    private enum CodingKeys: String, CodingKey {
        case line
        case route
        case blockID = "block_id"
        case title
        case target
        case state
        case reason
        case wokeAt = "woke_at"
        case wakeNoticeEligible = "wake_notice_eligible"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        wokeAt = try container.decodeIfPresent(String.self, forKey: .wokeAt)
        wakeNoticeEligible = try container.decodeIfPresent(Bool.self, forKey: .wakeNoticeEligible)
    }

    /// True only when Bob explicitly marked this row eligible.
    /// Nil (older bob) and false both mean "not permission".
    public var isEligible: Bool {
        wakeNoticeEligible == true
    }

    public var identityKey: String? {
        guard let route, !route.isEmpty, let blockID, !blockID.isEmpty else {
            return nil
        }
        return "\(route)#\(blockID)"
    }
}

/// The link-count plan on list and add responses. Older payloads may
/// omit it; it decodes as zeros with `over == false`.
public struct SnoozeWakeLinkPlan: Decodable, Equatable, Sendable {
    public let count: Int
    public let cap: Int
    public let over: Bool

    public init(count: Int = 0, cap: Int = 0, over: Bool = false) {
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
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        cap = try container.decodeIfPresent(Int.self, forKey: .cap) ?? 0
        over = try container.decodeIfPresent(Bool.self, forKey: .over) ?? false
    }
}

/// Schema-1 `bob snooze list -f json` (also `bob snooze -f json`).
/// `wake_notice_version` is the feature probe: only a value of 1 proves
/// the running bob understands ownership and eligibility fields.
/// A missing version disables only the wake-notice feature, never the
/// already-landed wake scheduler.
public struct SnoozeWakeListResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public let schemaVersion: Int
    public let wakeNoticeVersion: Int?
    public let vaultRoot: String?
    public let date: String?
    public let now: String?
    public let rows: [SnoozeWakeListRow]
    public let nextWakeAt: String?
    public let plan: SnoozeWakeLinkPlan

    public init(
        schemaVersion: Int = 1,
        wakeNoticeVersion: Int? = nil,
        vaultRoot: String? = nil,
        date: String? = nil,
        now: String? = nil,
        rows: [SnoozeWakeListRow] = [],
        nextWakeAt: String? = nil,
        plan: SnoozeWakeLinkPlan = SnoozeWakeLinkPlan()
    ) {
        self.schemaVersion = schemaVersion
        self.wakeNoticeVersion = wakeNoticeVersion
        self.vaultRoot = vaultRoot
        self.date = date
        self.now = now
        self.rows = rows
        self.nextWakeAt = nextWakeAt
        self.plan = plan
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case wakeNoticeVersion = "wake_notice_version"
        case vaultRoot = "vault_root"
        case date
        case now
        case rows
        case nextWakeAt = "next_wake_at"
        case plan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        wakeNoticeVersion = try container.decodeIfPresent(Int.self, forKey: .wakeNoticeVersion)
        vaultRoot = try container.decodeIfPresent(String.self, forKey: .vaultRoot)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        now = try container.decodeIfPresent(String.self, forKey: .now)
        rows = try container.decodeIfPresent([SnoozeWakeListRow].self, forKey: .rows) ?? []
        nextWakeAt = try container.decodeIfPresent(String.self, forKey: .nextWakeAt)
        plan = try container.decodeIfPresent(SnoozeWakeLinkPlan.self, forKey: .plan)
            ?? SnoozeWakeLinkPlan()
    }

    /// Whether this bob speaks the wake-notice contract.
    public var supportsWakeNotice: Bool {
        wakeNoticeVersion == 1
    }

    /// Rows Bob marked eligible. Empty on older bob, never synthesized here.
    public var eligibleRows: [SnoozeWakeListRow] {
        rows.filter { $0.isEligible }
    }
}

/// The settled outcome of `bob snooze add <route:block-id> +15m -f json`.
public enum SnoozeWakeAddStatus: Equatable, Sendable {
    case added
    case planned
    case deferred
    case dropped
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "added":
            self = .added
        case "planned":
            self = .planned
        case "deferred":
            self = .deferred
        case "dropped":
            self = .dropped
        default:
            self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .added:
            return "added"
        case .planned:
            return "planned"
        case .deferred:
            return "deferred"
        case .dropped:
            return "dropped"
        case .other(let raw):
            return raw
        }
    }
}

/// Schema-1 `bob snooze add -f json`. Dry runs report `planned`;
/// lock contention and day rollover report `deferred`; only `added`
/// proves a vault write. Unknown keys are ignored.
public struct SnoozeWakeAddResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public let schemaVersion: Int
    public let date: String?
    public let now: String?
    public let status: SnoozeWakeAddStatus
    public let route: String?
    public let blockID: String?
    public let title: String?
    public let targetTime: String?
    public let targetAt: String?
    public let lane: String?
    public let dailyFile: String?
    public let plan: SnoozeWakeLinkPlan
    public let dryRun: Bool?

    public init(
        schemaVersion: Int = 1,
        date: String? = nil,
        now: String? = nil,
        status: SnoozeWakeAddStatus = .other(""),
        route: String? = nil,
        blockID: String? = nil,
        title: String? = nil,
        targetTime: String? = nil,
        targetAt: String? = nil,
        lane: String? = nil,
        dailyFile: String? = nil,
        plan: SnoozeWakeLinkPlan = SnoozeWakeLinkPlan(),
        dryRun: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.date = date
        self.now = now
        self.status = status
        self.route = route
        self.blockID = blockID
        self.title = title
        self.targetTime = targetTime
        self.targetAt = targetAt
        self.lane = lane
        self.dailyFile = dailyFile
        self.plan = plan
        self.dryRun = dryRun
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case date
        case now
        case status
        case task
        case target
        case lane
        case dailyFile = "daily_file"
        case plan
        case dryRun = "dry_run"
    }

    private enum TaskKeys: String, CodingKey {
        case route
        case blockID = "block_id"
        case title
    }

    private enum TargetKeys: String, CodingKey {
        case time
        case at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        date = try container.decodeIfPresent(String.self, forKey: .date)
        now = try container.decodeIfPresent(String.self, forKey: .now)
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        status = SnoozeWakeAddStatus(rawValue: rawStatus)
        if let task = try? container.nestedContainer(keyedBy: TaskKeys.self, forKey: .task) {
            route = try task.decodeIfPresent(String.self, forKey: .route)
            blockID = try task.decodeIfPresent(String.self, forKey: .blockID)
            title = try task.decodeIfPresent(String.self, forKey: .title)
        } else {
            route = nil
            blockID = nil
            title = nil
        }
        if let target = try? container.nestedContainer(keyedBy: TargetKeys.self, forKey: .target) {
            targetTime = try target.decodeIfPresent(String.self, forKey: .time)
            targetAt = try target.decodeIfPresent(String.self, forKey: .at)
        } else {
            targetTime = nil
            targetAt = nil
        }
        lane = try container.decodeIfPresent(String.self, forKey: .lane)
        dailyFile = try container.decodeIfPresent(String.self, forKey: .dailyFile)
        plan = try container.decodeIfPresent(SnoozeWakeLinkPlan.self, forKey: .plan)
            ?? SnoozeWakeLinkPlan()
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun)
    }

    /// Only `added` proves a write. Confirm only bob's `added` outcome.
    public var didWrite: Bool {
        status == .added
    }

    /// Bob's returned target for the `Snoozed until HH:MM` label.
    /// Never computed client-side from an exact 15-minute offset.
    public var snoozedUntilLabel: String? {
        targetTime
    }
}
