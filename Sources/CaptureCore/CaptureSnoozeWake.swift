import Foundation

/// The settled outcome of `bob snooze wake -q -f json`.
public enum CaptureSnoozeWakeStatus: Equatable, Sendable, Decodable {
    case woke
    case nothingDue
    case deferred
    case skipped
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "woke":
            self = .woke
        case "nothing_due":
            self = .nothingDue
        case "deferred":
            self = .deferred
        case "skipped":
            self = .skipped
        default:
            self = .other(raw)
        }
    }
}

/// The small schema-1 portion the scheduler needs from Bob's wake envelope.
/// Other fields remain Bob-owned and additive fields decode untouched.
public struct CaptureSnoozeWakeResponse: Decodable, Equatable, Sendable, SchemaVersioned {
    public let schemaVersion: Int
    public let status: CaptureSnoozeWakeStatus
    /// Bob's next advertised wake instant, including its UTC offset.
    public let nextWakeAt: String?

    public init(
        schemaVersion: Int = 1,
        status: CaptureSnoozeWakeStatus,
        nextWakeAt: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.nextWakeAt = nextWakeAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case status
        case nextWakeAt = "next_wake_at"
    }
}

/// Parses Bob's RFC 3339 instants without interpreting them in the process's
/// local time zone. ISO 8601 accepts both `Z` and explicit UTC offsets.
public enum CaptureRFC3339Date {
    public static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// Pure scheduling policy for Bob's advertised wake instant. The caller
/// supplies `now`, so retries and clock changes are deterministic in tests.
public struct CaptureSnoozeWakePolicy: Sendable {
    public static let wakeGraceSeconds: TimeInterval = 5
    public static let minimumRetryInterval: TimeInterval = 60

    private var day: String?
    private var target: Date?
    private var retryDeadline: Date?
    private var disabled = false
    /// The last authoritative snoozed facts applied by `update`: Bob's
    /// `snoozed` block (rows plus advertised target). Timer, lifecycle,
    /// and failed-refresh callbacks re-apply the retained snapshot, so a
    /// re-applied block that still equals these facts must not overwrite
    /// a settled outcome or a reserved retry deadline. Only a changed
    /// block — retimed, dropped, added, or re-advertised work — is new
    /// authority. Changes outside `snoozed` (ledger rows, headline,
    /// budget) never touch the retry state.
    private var appliedSnoozed: CaptureAgendaSnoozed?

    public init() {}

    public var isDisabled: Bool {
        disabled
    }

    public var advertisedTarget: Date? {
        target
    }

    /// Applies Bob's snapshot facts. Old-day, missing, null, or malformed
    /// instants disarm scheduling; the app never infers a time from `target`.
    /// A re-applied snapshot whose `snoozed` block still equals the last
    /// applied facts (timer/lifecycle callbacks, unchanged or failed
    /// refreshes) preserves the settled outcome and any reserved retry
    /// deadline instead of re-arming a retired target. A changed block is
    /// new authority: it retimes, drops, or adds work, including a new
    /// task at an already-settled clock target. The per-target retry floor
    /// survives same-target block changes, so unrelated agenda edits and
    /// mid-retry row changes never buy an immediate second attempt.
    @discardableResult
    public mutating func update(
        snapshot: CaptureAgendaSnapshot?,
        today: String,
        now: Date
    ) -> Date? {
        if day != today {
            day = today
            target = nil
            retryDeadline = nil
            appliedSnoozed = nil
        }
        guard !disabled,
            let snapshot,
            snapshot.date == today
        else {
            target = nil
            retryDeadline = nil
            appliedSnoozed = nil
            return nil
        }
        let incoming = snapshot.snoozed
        if incoming == appliedSnoozed {
            return nextAttemptDate(now: now)
        }
        appliedSnoozed = incoming
        guard let rawTarget = incoming?.nextWakeAt,
            let newTarget = CaptureRFC3339Date.date(from: rawTarget)
        else {
            target = nil
            retryDeadline = nil
            return nil
        }
        if target != newTarget {
            target = newTarget
            retryDeadline = nil
        }
        return nextAttemptDate(now: now)
    }

    /// The next timer instant, including the five-second grace after Bob's
    /// target and the per-target retry deadline after an attempt.
    public func nextAttemptDate(now: Date) -> Date? {
        guard !disabled, let target else {
            return nil
        }
        let dueAt = target.addingTimeInterval(Self.wakeGraceSeconds)
        return max(dueAt, retryDeadline ?? dueAt)
    }

    /// Reserves the per-target retry window before starting a subprocess.
    /// Repeated publications or timer callbacks cannot start an immediate
    /// second write for an unchanged past target.
    @discardableResult
    public mutating func beginAttempt(at now: Date) -> Bool {
        guard let deadline = nextAttemptDate(now: now), deadline <= now else {
            return false
        }
        retryDeadline = now.addingTimeInterval(Self.minimumRetryInterval)
        return true
    }

    /// Uses Bob's settled response as authoritative next-wake evidence. A
    /// null/invalid value retires pending work until a changed agenda snapshot
    /// advertises another target. Call only for writing outcomes (`woke`,
    /// `nothingDue`): `deferred`/`skipped`/unknown replies carry a
    /// prospective postimage that proves no write, so the scheduler must
    /// preserve the due target and its retry deadline instead of settling.
    @discardableResult
    public mutating func settle(nextWakeAt: String?, now: Date) -> Date? {
        guard !disabled,
            let nextWakeAt,
            let newTarget = CaptureRFC3339Date.date(from: nextWakeAt)
        else {
            target = nil
            retryDeadline = nil
            return nil
        }
        if target != newTarget {
            target = newTarget
            retryDeadline = nil
        }
        return nextAttemptDate(now: now)
    }

    /// A confirmed old-Bob command rejection disables only this client
    /// session. The owner resets the policy on Recheck Bob or reconfiguration.
    public mutating func markUnsupported() {
        disabled = true
        target = nil
        retryDeadline = nil
    }

    public mutating func reset() {
        day = nil
        target = nil
        retryDeadline = nil
        disabled = false
        appliedSnoozed = nil
    }
}
