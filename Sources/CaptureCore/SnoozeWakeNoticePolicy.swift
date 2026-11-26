import Foundation

/// Current device presence sampled by the app services. Ordinary app
/// deactivation is not away and is deliberately absent here.
public struct SnoozeWakePresence: Equatable, Sendable {
    public let screenLocked: Bool
    public let displaysAsleep: Bool
    public let sessionInactive: Bool
    public let idleSeconds: TimeInterval

    public init(
        screenLocked: Bool = false,
        displaysAsleep: Bool = false,
        sessionInactive: Bool = false,
        idleSeconds: TimeInterval = 0
    ) {
        self.screenLocked = screenLocked
        self.displaysAsleep = displaysAsleep
        self.sessionInactive = sessionInactive
        self.idleSeconds = idleSeconds
    }

    /// Away means screen locked, displays asleep, user session inactive,
    /// or idle for at least 180 seconds. Each signal holds independently.
    public var isAway: Bool {
        screenLocked || displaysAsleep || sessionInactive || idleSeconds >= 180
    }

    /// The individual away signals that are currently set, for diagnostics.
    /// Empty when present.
    public var awaySignals: [SnoozeWakeAwaySignal] {
        var signals: [SnoozeWakeAwaySignal] = []
        if screenLocked { signals.append(.screenLocked) }
        if displaysAsleep { signals.append(.displaysAsleep) }
        if sessionInactive { signals.append(.sessionInactive) }
        if idleSeconds >= 180 { signals.append(.idleTimeout) }
        return signals
    }
}

public enum SnoozeWakeAwaySignal: String, Equatable, Sendable {
    case screenLocked
    case displaysAsleep
    case sessionInactive
    case idleTimeout
}

/// Persisted user settings that gate notice delivery. The wake scheduler
/// keeps running independently of these toggles.
public struct SnoozeWakeNoticeSettings: Equatable, Sendable {
    public let announceWakes: Bool
    public let holdWhileAway: Bool
    public let holdDuringMeetings: Bool

    public init(
        announceWakes: Bool = true,
        holdWhileAway: Bool = true,
        holdDuringMeetings: Bool = true
    ) {
        self.announceWakes = announceWakes
        self.holdWhileAway = holdWhileAway
        self.holdDuringMeetings = holdDuringMeetings
    }
}

/// The outcome of re-reading bob (`snooze list`) during the settle delay.
/// Only rows Bob still marks eligible may be shown; anything else is
/// filtered before presentation. Unknown fields are ignored by decoding.
public enum SnoozeWakeVerification: Equatable, Sendable {
    case unverified
    case verified(eligible: [SnoozeWakeListRow])
    case empty
    case failed(reason: String)

    public var verifiedRows: [SnoozeWakeListRow] {
        guard case .verified(let eligible) = self else { return [] }
        return eligible
    }
}

public enum SnoozeWakeHoldReason: Equatable, Sendable {
    case away(signals: [SnoozeWakeAwaySignal])
    case meeting(until: Date)
    case settling(until: Date)
}

public enum SnoozeWakeDropReason: Equatable, Sendable {
    case announcementsDisabled
    case unsupportedBob
    case wrongChannel
    case dayMismatch
    case vaultMismatch
    case invalidTimestamp
    case futureDated
    case expired
    case duplicate
    case emptyVerification
    case verificationFailed(reason: String)
    case noEligibleTasks
}

public enum SnoozeWakeNoticeDecision: Equatable, Sendable {
    case show(batch: SnoozeWakeNoticeBatch)
    case hold(reason: SnoozeWakeHoldReason, nextCheck: Date)
    case verify(recheckAt: Date)
    case drop(reason: SnoozeWakeDropReason)
}

/// One deliverable batch: the receipt plus the verified rows to present.
/// The receipt supplies wake-time provenance; the verified rows supply
/// today's actionable identities and copy.
public struct SnoozeWakeNoticeBatch: Equatable, Sendable {
    public let wakeID: String
    public let wokenAt: Date
    public let date: String
    public let rows: [SnoozeWakeListRow]
    public let vaultRoot: String?

    public init(
        wakeID: String,
        wokenAt: Date,
        date: String,
        rows: [SnoozeWakeListRow],
        vaultRoot: String?
    ) {
        self.wakeID = wakeID
        self.wokenAt = wokenAt
        self.date = date
        self.rows = rows
        self.vaultRoot = vaultRoot
    }

    public var identityKeys: [String] {
        rows.compactMap { $0.identityKey }
    }
}

/// A completion token proving a settle-delay or subprocess result still
/// belongs to the current batch and configuration. Settings changes,
/// executable/vault replacement, day rollover, and shutdown invalidate
/// obsolete callbacks by bumping the generation.
public struct SnoozeWakeCompletionToken: Equatable, Sendable {
    public let generation: UInt64
    public let wakeID: String
    public let configIdentity: String
}

/// Pure, clock-injected wake-notice policy. Every timestamp comparison
/// uses the caller-supplied `now`, so tests never sleep. Bob's fresh
/// `today`/`bobNow` is the task-day authority; a stale receipt date is
/// never combined with a new local clock.
public struct SnoozeWakeNoticePolicy: Sendable {
    public static let awayThresholdSeconds: TimeInterval = 180
    public static let returnSettleSeconds: TimeInterval = 1.5
    public static let receiptMaxAgeSeconds: TimeInterval = 4 * 60 * 60

    private var generation: UInt64 = 0
    private var currentWakeID: String?
    private var currentConfigIdentity: String?
    private var handledWakeIDs: Set<String> = []
    private var handledDay: String?

    public init() {}

    public func token(
        generation: UInt64, wakeID: String, configIdentity: String
    ) -> SnoozeWakeCompletionToken {
        SnoozeWakeCompletionToken(
            generation: generation, wakeID: wakeID, configIdentity: configIdentity)
    }

    public func currentToken(
        wakeID: String, configIdentity: String
    ) -> SnoozeWakeCompletionToken {
        SnoozeWakeCompletionToken(
            generation: generation, wakeID: wakeID, configIdentity: configIdentity)
    }

    public func isCurrent(_ token: SnoozeWakeCompletionToken) -> Bool {
        token.generation == generation
            && token.wakeID == currentWakeID
            && token.configIdentity == currentConfigIdentity
    }

    /// Canonical config identity: today plus the configured vault plus the
    /// hold toggles. Any of these changing invalidates pending work.
    public static func configIdentity(
        today: String, vaultRoot: String?, settings: SnoozeWakeNoticeSettings
    ) -> String {
        "today=\(today)|vault=\(vaultRoot ?? "")"
            + "|announce=\(settings.announceWakes)"
            + "|away=\(settings.holdWhileAway)|meet=\(settings.holdDuringMeetings)"
    }

    /// The one decision for this instant. Callers re-invoke on every
    /// signal change (presence, agenda refresh, settings, clock) with the
    /// same receipt and fresh inputs.
    public mutating func decide(
        receipt: SnoozeWakeReceipt?,
        today: String,
        bobNow: String?,
        configuredVaultRoot: String?,
        presence: SnoozeWakePresence,
        events: CaptureAgendaEvents?,
        settings: SnoozeWakeNoticeSettings,
        verification: SnoozeWakeVerification,
        handledIDs: Set<String> = [],
        handledIDsDay: String? = nil,
        now: Date
    ) -> SnoozeWakeNoticeDecision {
        let configIdentity = Self.configIdentity(
            today: today, vaultRoot: configuredVaultRoot, settings: settings)

        if handledDay != today {
            handledWakeIDs = []
            handledDay = today
        }
        let knownHandled = handledIDs.union(handledWakeIDs)

        guard settings.announceWakes else {
            return .drop(reason: .announcementsDisabled)
        }
        guard let receipt else {
            return .drop(reason: .invalidTimestamp)
        }
        guard receipt.schemaVersion == 1 else {
            return .drop(reason: .unsupportedBob)
        }
        if currentConfigIdentity != configIdentity {
            generation &+= 1
            currentWakeID = nil
            currentConfigIdentity = configIdentity
        }
        guard receipt.notificationChannel.permitsMacNotice else {
            return .drop(reason: .wrongChannel)
        }
        guard !receipt.wakeID.isEmpty, !receipt.date.isEmpty else {
            return .drop(reason: .invalidTimestamp)
        }
        guard receipt.date == today else {
            return .drop(reason: .dayMismatch)
        }
        if let receiptVault = receipt.vaultRoot, !receiptVault.isEmpty,
            let configured = configuredVaultRoot, !configured.isEmpty
        {
            guard
                Self.standardizedPath(receiptVault) == Self.standardizedPath(configured)
            else {
                return .drop(reason: .vaultMismatch)
            }
        } else if receipt.vaultRoot == nil || receipt.vaultRoot?.isEmpty == true {
            return .drop(reason: .vaultMismatch)
        }
        guard let wokenAt = CaptureRFC3339Date.date(from: receipt.wokenAt) else {
            return .drop(reason: .invalidTimestamp)
        }
        if wokenAt > now {
            return .drop(reason: .futureDated)
        }
        if now.timeIntervalSince(wokenAt) > Self.receiptMaxAgeSeconds {
            return .drop(reason: .expired)
        }
        if knownHandled.contains(receipt.wakeID) {
            return .drop(reason: .duplicate)
        }

        if currentWakeID != receipt.wakeID {
            generation &+= 1
            currentWakeID = receipt.wakeID
        }

        if settings.holdWhileAway, presence.isAway {
            let nextCheck = now.addingTimeInterval(2)
            return .hold(
                reason: .away(signals: presence.awaySignals), nextCheck: nextCheck)
        }

        if settings.holdDuringMeetings,
            let until = Self.runningMeetingEnd(events: events, now: now, bobNow: bobNow)
        {
            return .hold(reason: .meeting(until: until), nextCheck: until)
        }

        switch verification {
        case .unverified:
            let recheckAt = now.addingTimeInterval(Self.returnSettleSeconds)
            return .verify(recheckAt: recheckAt)
        case .failed(let reason):
            return .drop(reason: .verificationFailed(reason: reason))
        case .empty:
            return .drop(reason: .emptyVerification)
        case .verified(let eligible):
            let matching = eligible.filter { row in
                row.identityKey.flatMap { key in
                    receipt.tasks.contains { $0.identityKey == key } ? key : nil
                } != nil
            }
            let usable = matching.isEmpty ? eligible : matching
            guard !usable.isEmpty else {
                return .drop(reason: .noEligibleTasks)
            }
            let verifiedDate = eligible.first?.wokeAt.flatMap { _ in today }
            _ = verifiedDate
            return .show(
                batch: SnoozeWakeNoticeBatch(
                    wakeID: receipt.wakeID,
                    wokenAt: wokenAt,
                    date: receipt.date,
                    rows: usable,
                    vaultRoot: receipt.vaultRoot
                ))
        }
    }

    /// Records a terminally handled wake ID. Held batches are never
    /// marked delivered merely because the observer read them: only
    /// call this for acknowledged, expired, or day-purged batches.
    public mutating func markHandled(_ wakeID: String, day: String) {
        if handledDay != day {
            handledWakeIDs = []
            handledDay = day
        }
        handledWakeIDs.insert(wakeID)
    }

    /// Invalidates every pending callback after a settings change,
    /// executable/vault replacement, or shutdown.
    public mutating func invalidate() {
        generation &+= 1
        currentWakeID = nil
        currentConfigIdentity = nil
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// The earliest end of a currently running qualifying meeting, or nil
    /// when none is running. Recomputes every span against `now`; the
    /// stored `phase` label is never trusted. Cancelled rows and
    /// non-task rows never qualify. Buffered spans are ignored: only the
    /// actual `starts_at <= now < ends_at` span holds.
    public static func runningMeetingEnd(
        events: CaptureAgendaEvents?, now: Date, bobNow: String?
    ) -> Date? {
        guard let rows = events?.rows, !rows.isEmpty else { return nil }
        let offset = Self.offsetSuffix(from: bobNow)
        var earliestEnd: Date?
        for row in rows {
            guard row.kind == .task else { continue }
            if let statusType = row.statusType, statusType.lowercased() == "cancelled" {
                continue
            }
            if row.statusSymbol == "-" { continue }
            guard let startsRaw = row.startsAt, let endsRaw = row.endsAt,
                let starts = Self.meetingDate(from: startsRaw, offsetSuffix: offset),
                let ends = Self.meetingDate(from: endsRaw, offsetSuffix: offset)
            else { continue }
            guard starts <= now, now < ends else { continue }
            if let current = earliestEnd {
                earliestEnd = min(current, ends)
            } else {
                earliestEnd = ends
            }
        }
        return earliestEnd
    }

    static func meetingDate(from raw: String, offsetSuffix: String?) -> Date? {
        if let date = CaptureRFC3339Date.date(from: raw) { return date }
        let wall = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wall.isEmpty else { return nil }
        var candidate = wall
        if candidate.count == 16 {
            candidate += ":00"
        }
        if let offset = offsetSuffix {
            candidate += offset
        } else {
            candidate += "Z"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: candidate)
    }

    static func offsetSuffix(from bobNow: String?) -> String? {
        guard let bobNow, !bobNow.isEmpty else { return nil }
        if bobNow.hasSuffix("Z") { return "Z" }
        let tail = bobNow.suffix(6)
        guard tail.count == 6 else { return nil }
        let sign = tail.prefix(1)
        guard sign == "+" || sign == "-" else { return nil }
        let rest = tail.dropFirst()
        guard rest.count == 5, rest.contains(":") else { return nil }
        return String(tail)
    }
}
