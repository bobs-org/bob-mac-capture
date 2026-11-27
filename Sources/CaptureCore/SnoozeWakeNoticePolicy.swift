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
    /// The agenda has no usable same-day snapshot for bob's day, so a
    /// meeting may be running unseen. Holding is the safe default; the
    /// coordinator requests a refresh with bounded backoff.
    case agendaUnavailable(until: Date)
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
    /// The original receipt facts stay attached so presentation can show
    /// wake provenance without trusting stale row copy.
    public let receiptTasks: [SnoozeWakeReceiptTask]

    public init(
        wakeID: String,
        wokenAt: Date,
        date: String,
        rows: [SnoozeWakeListRow],
        vaultRoot: String?,
        receiptTasks: [SnoozeWakeReceiptTask] = []
    ) {
        self.wakeID = wakeID
        self.wokenAt = wokenAt
        self.date = date
        self.rows = rows
        self.vaultRoot = vaultRoot
        self.receiptTasks = receiptTasks
    }

    public var identityKeys: [String] {
        rows.compactMap { $0.identityKey }
    }
}

/// Pure, clock-injected wake-notice policy. Every timestamp comparison
/// uses the caller-supplied `now`, so tests never sleep. Bob's fresh
/// `today`/`bobNow` is the task-day authority; a stale receipt date is
/// never combined with a new local clock.
public struct SnoozeWakeNoticePolicy: Sendable {
    public static let awayThresholdSeconds: TimeInterval = 180
    public static let receiptMaxAgeSeconds: TimeInterval = 4 * 60 * 60
    /// Bounded backoff for agenda-unavailable holds: the coordinator
    /// requests a refresh and re-evaluates no sooner than this.
    public static let agendaRetrySeconds: TimeInterval = 15

    private var handledWakeIDs: Set<String> = []
    private var handledDay: String?

    public init() {}

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
    ///
    /// `today` and `bobNow` are bob's day authorities from the latest
    /// `bob snooze -f json` read made for this batch, never the Mac clock
    /// or `CaptureAgendaStore.localToday()`. `listVaultRoot` is that same
    /// read's `vault_root`; bob canonicalizes both sides. A receipt is
    /// checked against bob's date and vault only after a fresh read: when
    /// `verification` is `.unverified` the day, vault, and duplicate
    /// checks are deferred and the caller fetches first.
    public mutating func decide(
        receipt: SnoozeWakeReceipt?,
        today: String,
        bobNow: String?,
        configuredVaultRoot: String?,
        listVaultRoot: String? = nil,
        presence: SnoozeWakePresence,
        events: CaptureAgendaEvents?,
        agendaHasSameDayData: Bool = true,
        settings: SnoozeWakeNoticeSettings,
        verification: SnoozeWakeVerification,
        handledIDs: Set<String> = [],
        handledIDsDay: String? = nil,
        now: Date
    ) -> SnoozeWakeNoticeDecision {
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
        guard receipt.notificationChannel.permitsMacNotice else {
            return .drop(reason: .wrongChannel)
        }
        guard !receipt.wakeID.isEmpty, !receipt.date.isEmpty else {
            return .drop(reason: .invalidTimestamp)
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

        if settings.holdWhileAway, presence.isAway {
            let nextCheck = now.addingTimeInterval(2)
            return .hold(
                reason: .away(signals: presence.awaySignals), nextCheck: nextCheck)
        }

        if settings.holdDuringMeetings {
            if !agendaHasSameDayData {
                let until = now.addingTimeInterval(Self.agendaRetrySeconds)
                return .hold(reason: .agendaUnavailable(until: until), nextCheck: until)
            }
            if let until = Self.runningMeetingEnd(events: events, now: now, bobNow: bobNow) {
                return .hold(reason: .meeting(until: until), nextCheck: until)
            }
        }

        // Day, vault, and duplicate need bob's fresh read. Defer them
        // until verification carries that read; never pair a stale receipt
        // date with a new local clock.
        switch verification {
        case .unverified:
            return .verify(recheckAt: now)
        case .failed(let reason):
            return .drop(reason: .verificationFailed(reason: reason))
        case .empty:
            // An empty verification still proves bob's day: a receipt for
            // another day is a day mismatch, not an empty batch.
            guard receipt.date == today else {
                return .drop(reason: .dayMismatch)
            }
            return .drop(reason: .emptyVerification)
        case .verified(let eligible):
            guard receipt.date == today else {
                return .drop(reason: .dayMismatch)
            }
            // Vault identity comes from bob on both sides: the receipt's
            // vault_root against the current list read's vault_root, which
            // bob canonicalized in the same environment. Missing on either
            // side is never permission to announce.
            guard let receiptVault = receipt.vaultRoot, !receiptVault.isEmpty else {
                return .drop(reason: .vaultMismatch)
            }
            if let listVault = listVaultRoot, !listVault.isEmpty {
                guard Self.standardizedPath(receiptVault) == Self.standardizedPath(listVault)
                else {
                    return .drop(reason: .vaultMismatch)
                }
            } else if let configured = configuredVaultRoot, !configured.isEmpty {
                // Legacy path (no list vault): compare against Settings
                // symlink-safe. The coordinator always supplies listVault.
                guard
                    Self.symlinkResolvedPath(receiptVault)
                        == Self.symlinkResolvedPath(configured)
                else {
                    return .drop(reason: .vaultMismatch)
                }
            } else {
                return .drop(reason: .vaultMismatch)
            }
            // The Settings comparison is symlink-safe: ~/bob or /tmp
            // (/private/tmp) must not drop every receipt.
            if let configured = configuredVaultRoot, !configured.isEmpty,
                let listVault = listVaultRoot, !listVault.isEmpty
            {
                guard
                    Self.symlinkResolvedPath(receiptVault)
                        == Self.symlinkResolvedPath(configured)
                else {
                    return .drop(reason: .vaultMismatch)
                }
            }
            if knownHandled.contains(receipt.wakeID) {
                return .drop(reason: .duplicate)
            }
            let rowsByIdentity = Dictionary(
                eligible.compactMap { row in row.identityKey.map { ($0, row) } },
                uniquingKeysWith: { first, _ in first }
            )
            let usable = receipt.tasks.compactMap { task -> SnoozeWakeListRow? in
                guard let key = task.identityKey,
                    let row = rowsByIdentity[key],
                    let target = task.target,
                    let wokeAt = task.wokeAt,
                    row.target == target,
                    row.wokeAt == wokeAt
                else {
                    return nil
                }
                return row
            }
            guard !usable.isEmpty else {
                return .drop(reason: .noEligibleTasks)
            }
            return .show(
                batch: SnoozeWakeNoticeBatch(
                    wakeID: receipt.wakeID,
                    wokenAt: wokenAt,
                    date: receipt.date,
                    rows: usable,
                    vaultRoot: receipt.vaultRoot,
                    receiptTasks: receipt.tasks
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

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Symlink-resolving comparison for the Settings vault root: a
    /// symlinked ~/bob or /tmp (/private/tmp) vault must not drop every
    /// receipt as vaultMismatch.
    static func symlinkResolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
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

    /// The next qualifying meeting start after now, for mid-display
    /// re-evaluation. A meeting that begins while a notice is on screen
    /// hides the HUD immediately. Cancelled rows, non-task rows, and rows
    /// without spans never qualify; buffered spans are ignored.
    public static func nextMeetingStart(
        events: CaptureAgendaEvents?, now: Date, bobNow: String?
    ) -> Date? {
        guard let rows = events?.rows, !rows.isEmpty else { return nil }
        let offset = Self.offsetSuffix(from: bobNow)
        var earliestStart: Date?
        for row in rows {
            guard row.kind == .task else { continue }
            if let statusType = row.statusType, statusType.lowercased() == "cancelled" {
                continue
            }
            if row.statusSymbol == "-" { continue }
            guard let startsRaw = row.startsAt,
                let starts = Self.meetingDate(from: startsRaw, offsetSuffix: offset)
            else { continue }
            guard starts > now else { continue }
            if let current = earliestStart {
                earliestStart = min(current, starts)
            } else {
                earliestStart = starts
            }
        }
        return earliestStart
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
