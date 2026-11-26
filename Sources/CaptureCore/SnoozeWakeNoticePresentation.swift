import Foundation

/// How the notice should announce when it is shown.
public enum SnoozeWakeAnnouncement: Equatable, Sendable {
    case hud
    case silentRecordOnly
}

/// Pure notice presentation and acknowledgement state. The receipt
/// supplies wake-time provenance; the verified list rows supply today's
/// actionable identities and the current list budget for TODAY. Stale
/// receipt totals are never shown.
public struct SnoozeWakeNoticePresentation: Equatable, Sendable {
    /// At most three task titles are shown; the remainder folds into a count.
    public static let maxVisibleTitles = 3
    /// The transient HUD dismisses after 12 seconds of unhovered display.
    public static let hudDisplaySeconds: TimeInterval = 12
    /// The shared acknowledgement clears the beacon and records 60
    /// minutes after delivery.
    public static let beaconLifetimeSeconds: TimeInterval = 60 * 60

    public let batch: SnoozeWakeNoticeBatch
    public let listBudget: SnoozeWakeLinkPlan
    public let announcement: SnoozeWakeAnnouncement

    public init(
        batch: SnoozeWakeNoticeBatch,
        listBudget: SnoozeWakeLinkPlan = SnoozeWakeLinkPlan(),
        announcement: SnoozeWakeAnnouncement = .hud
    ) {
        self.batch = batch
        self.listBudget = listBudget
        self.announcement = announcement
    }

    /// Rows with a usable identity, in receipt order. Identity-less rows
    /// never produce an action target.
    public var actionableRows: [SnoozeWakeListRow] {
        batch.rows.filter { $0.identityKey != nil }
    }

    /// The action targets for Open and +15m, in receipt order.
    public var actionTargets: [SnoozeWakeActionTarget] {
        actionableRows.compactMap { row in
            guard let key = row.identityKey else { return nil }
            return SnoozeWakeActionTarget(
                identityKey: key,
                route: row.route ?? "",
                blockID: row.blockID ?? "",
                title: row.title ?? "")
        }
    }

    public var taskCount: Int {
        actionableRows.count
    }

    /// Single-task copy reads `Ready now · <title>` with the wake-time
    /// provenance below. Batch copy names the count and the visible titles.
    public var headline: String {
        switch taskCount {
        case 0:
            return "Snoozed tasks are ready"
        case 1:
            return "Ready now · \(actionableRows[0].title ?? "Snoozed task")"
        default:
            return "\(taskCount) snoozed tasks are ready"
        }
    }

    public var visibleTitles: [String] {
        Array(actionableRows.prefix(Self.maxVisibleTitles).map { $0.title ?? "Snoozed task" })
    }

    public var remainingCount: Int {
        max(0, taskCount - visibleTitles.count)
    }

    /// Over-cap text renders amber; color stays supplementary to the text.
    public var isOverCap: Bool {
        listBudget.over
    }

    /// Stable Notification Center record ID for this wake.
    public var recordID: String {
        "snooze-woken-\(batch.wakeID)"
    }

    public static func recordID(wakeID: String) -> String {
        "snooze-woken-\(wakeID)"
    }

    /// The record thread shared by every notice in the batch.
    public static let recordThread = "snooze"

    /// Per-batch expiry: the receipt's wake instant plus four hours.
    /// Nil when the wake instant is unparseable, so callers drop instead.
    public func expiresAt() -> Date? {
        batch.wokenAt.addingTimeInterval(SnoozeWakeNoticePolicy.receiptMaxAgeSeconds)
    }

    /// The beacon clears 60 minutes after delivery.
    public func beaconClearsAt(deliveredAt: Date) -> Date {
        deliveredAt.addingTimeInterval(Self.beaconLifetimeSeconds)
    }

    /// The transient HUD dismisses after 12 unhovered seconds.
    public func hudDismissesAt(presentedAt: Date) -> Date {
        presentedAt.addingTimeInterval(Self.hudDisplaySeconds)
    }
}

/// One validated Open/+15m target. Routes are bob's resolved
/// vault-relative values, never shell-composed URLs.
public struct SnoozeWakeActionTarget: Equatable, Sendable {
    public let identityKey: String
    public let route: String
    public let blockID: String
    public let title: String

    public init(identityKey: String, route: String, blockID: String, title: String) {
        self.identityKey = identityKey
        self.route = route
        self.blockID = blockID
        self.title = title
    }

    /// The `route:block-id` locator for `bob snooze add`.
    public var locator: String {
        "\(route):\(blockID)"
    }
}

/// Every trigger that acknowledges the shared beacon/record lifecycle.
/// The HUD's x/timeout ends only the transient nudge, never this state.
public enum SnoozeWakeAcknowledgement: Equatable, Sendable {
    case panelOpened
    case openAction
    case addSucceeded(removedKeys: [String])
    case sixtyMinutesElapsed
    case dayRollover
}

/// Bounded acknowledgement store: terminally handled wake IDs scoped to
/// one day. A held batch is never marked delivered merely because the
/// observer read it; only acknowledgement, expiry, or day purge adds an ID.
public struct SnoozeWakeAcknowledgementStore: Equatable, Sendable {
    public static let maxEntries = 256

    public private(set) var day: String?
    public private(set) var handledWakeIDs: Set<String> = []

    public init(day: String? = nil, handledWakeIDs: Set<String> = []) {
        self.day = day
        self.handledWakeIDs = handledWakeIDs
    }

    public var count: Int {
        handledWakeIDs.count
    }

    public func contains(_ wakeID: String, day: String) -> Bool {
        guard self.day == day else { return false }
        return handledWakeIDs.contains(wakeID)
    }

    public mutating func acknowledge(_ wakeID: String, day: String) {
        if self.day != day {
            self.day = day
            handledWakeIDs = []
        }
        handledWakeIDs.insert(wakeID)
        while handledWakeIDs.count > Self.maxEntries {
            handledWakeIDs.removeFirst()
        }
    }

    public mutating func purge(day: String) {
        if self.day != day {
            self.day = day
            handledWakeIDs = []
        }
    }

    /// Applies one acknowledgement trigger to the visible task keys.
    /// Returns the keys that remain unacknowledged.
    public static func remainingKeys(
        visibleKeys: [String],
        trigger: SnoozeWakeAcknowledgement,
        removedKeys: [String] = []
    ) -> [String] {
        switch trigger {
        case .panelOpened, .openAction, .sixtyMinutesElapsed, .dayRollover:
            return []
        case .addSucceeded(let removed):
            let gone = Set(removed.isEmpty ? removedKeys : removed)
            return visibleKeys.filter { !gone.contains($0) }
        }
    }
}
