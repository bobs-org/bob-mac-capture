import CaptureCore
import Foundation

/// App-lifetime delivery coordinator behind injected presentation
/// callbacks. It owns the queue, hold, settle delay, bounded
/// revalidation retry, day purge, and stale callback suppression for
/// wake receipts. Only `mac_capture` receipts ever enter the queue;
/// other channels are ignored for all app notice surfaces.
///
/// Behavior contract:
/// - Distinct batches queue without replacing a held predecessor;
///   duplicate IDs never replay.
/// - A failed list read never shows stale tasks and never marks them
///   delivered. Retries run no more often than every 30 seconds, or on
///   a real lifecycle/configuration change, while pending work is
///   retained.
/// - Every async completion proves it still belongs to the current
///   configuration and fetch; each receipt is verified only by a read
///   started after that receipt was accepted.
/// - Terminally handled IDs (acknowledged, expired, day-purged, or
///   consumed while disabled) persist in the bounded day-scoped store;
///   a held batch is never marked delivered merely because the
///   observer read it.
/// Usable agenda snapshot for one evaluation: the store's date, health,
/// and events. The coordinator holds unless the snapshot is ready/stale
/// for bob's day.
struct SnoozeAgendaSnapshot: Sendable {
    var date: String?
    var status: CaptureAgendaStoreStatus
    var events: CaptureAgendaEvents?
}

@MainActor
final class SnoozeNoticeCoordinator {
    /// One queued receipt awaiting hold clearance and verification.
    struct PendingEntry: Sendable {
        let receipt: SnoozeWakeReceipt
        let firstSeenAt: Date
        let verificationAfterFetchID: UInt64
    }

    /// One delivered batch awaiting acknowledgement or expiry.
    struct DeliveredEntry: Sendable {
        let batch: SnoozeWakeNoticeBatch
        let presentation: SnoozeWakeNoticePresentation
        let deliveredAt: Date
    }

    /// Metadata-only diagnostic snapshot for future Settings UI.
    /// No task text, only IDs, counts, and reasons.
    struct DiagnosticSnapshot: Equatable, Sendable {
        var lastReceiptID: String?
        var lastChannel: String?
        var heldReason: String?
        var lastVerification: String?
        var pendingCount: Int
        var deliveredCount: Int
        var isClaimed: Bool
        var isCapable: Bool?
        var lastFailure: String?
    }

    static let defaultSettleDelaySeconds: TimeInterval = 1.5
    static let defaultRetryIntervalSeconds: TimeInterval = 30

    var onPresent: (SnoozeWakeNoticeBatch, SnoozeWakeNoticePresentation) -> Void = { _, _ in }
    var onDismiss: (String) -> Void = { _ in }
    var onTransientDismiss: (String) -> Void = { _ in }
    var onRestore: (SnoozeWakeNoticeBatch, SnoozeWakeNoticePresentation) -> Void = { _, _ in }
    var onQueueChanged: (Int, Int) -> Void = { _, _ in }
    var onDiagnostic: (String) -> Void = { _ in }
    var isPanelOpen: () -> Bool = { false }

    private let observer: SnoozeWakeObserver
    private let presenceSource: SnoozeWakePresenceSource
    private let claim: SnoozeWakeNotifierClaim
    private let handledStore: SnoozeWakeHandledStore
    private let beaconStore: SnoozeWakeBeaconStore
    private var processClient: BobProcessClient?
    private var configuredVaultRoot: String
    private let todayProvider: () -> String
    private let nowProvider: () -> Date
    private let settingsProvider: () -> SnoozeWakeNoticeSettings
    private let agendaEventsProvider: () -> CaptureAgendaEvents?
    private let agendaSnapshotProvider: (() -> SnoozeAgendaSnapshot?)?
    private let requestAgendaRefresh: () -> Void
    private let settleDelaySeconds: TimeInterval
    private let retryIntervalSeconds: TimeInterval

    private var policy = SnoozeWakeNoticePolicy()
    private var isStarted = false
    private var presenterAttached = false
    private var isCapable: Bool?
    private var pending: [PendingEntry] = []
    private var delivered: [DeliveredEntry] = []
    private var suppressedDeliveredWakeIDs: Set<String> = []
    // Wake IDs whose transient HUD nudge already ended (x or timeout),
    // keyed by wake ID. A ended nudge is never re-presented, re-chimed,
    // re-announced, or re-posted after a later hold.
    private var nudgeEndedWakeIDs: Set<String> = []
    private var deliveredSettleDeadline: Date?
    private var verification: SnoozeWakeVerification = .unverified
    private var verificationFetchID: UInt64?
    private var verifyAfter: Date?
    private var fetchInFlight = false
    private var fetchRetryAfter: Date?
    private var lastListPlan = SnoozeWakeLinkPlan()
    private var lastListNow: String?
    private var lastListDate: String?
    private var lastListVaultRoot: String?
    private var lastAgendaRefreshRequestAt: Date?
    private var lastEvaluatedDay: String?
    private var lastConfigIdentity: String?
    private var generation: UInt64 = 0
    private var reevaluateTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var fetchID: UInt64 = 0
    private var lastReceiptID: String?
    private var lastChannel: String?
    private var wasHeld = false
    private var heldReasonText: String?
    private var lastVerificationText: String?
    private var lastFailure: String?
    /// Beacon metadata restored at launch without re-announcing. Cleared
    /// through the same acknowledgement path as live batches.
    private var restoredBeacon: [SnoozeWakeBeaconStore.Entry] = []

    init(
        observer: SnoozeWakeObserver? = nil,
        presenceSource: SnoozeWakePresenceSource? = nil,
        claim: SnoozeWakeNotifierClaim,
        handledStore: SnoozeWakeHandledStore = SnoozeWakeHandledStore(),
        beaconStore: SnoozeWakeBeaconStore = SnoozeWakeBeaconStore(),
        processClient: BobProcessClient? = nil,
        configuredVaultRoot: String = "",
        today: (() -> String)? = nil,
        now: (() -> Date)? = nil,
        settings: (() -> SnoozeWakeNoticeSettings)? = nil,
        agendaEvents: (() -> CaptureAgendaEvents?)? = nil,
        agendaSnapshot: (() -> SnoozeAgendaSnapshot?)? = nil,
        requestAgendaRefresh: (() -> Void)? = nil,
        settleDelaySeconds: TimeInterval = defaultSettleDelaySeconds,
        retryIntervalSeconds: TimeInterval = defaultRetryIntervalSeconds
    ) {
        self.claim = claim
        self.handledStore = handledStore
        self.beaconStore = beaconStore
        self.processClient = processClient
        self.configuredVaultRoot = configuredVaultRoot
        self.todayProvider = today ?? { CaptureAgendaStore.localToday() }
        self.nowProvider = now ?? { Date() }
        self.settingsProvider = settings ?? { SnoozeWakeNoticeSettings() }
        self.agendaEventsProvider = agendaEvents ?? { nil }
        self.agendaSnapshotProvider = agendaSnapshot
        self.requestAgendaRefresh = requestAgendaRefresh ?? {}
        self.settleDelaySeconds = settleDelaySeconds
        self.retryIntervalSeconds = retryIntervalSeconds
        if let observer {
            self.observer = observer
        } else {
            self.observer = SnoozeWakeObserver()
        }
        if let presenceSource {
            self.presenceSource = presenceSource
        } else {
            self.presenceSource = SnoozeWakePresenceSource()
        }
    }

    // MARK: - Lifecycle

    /// Registers the observer, attaches presence, probes capability,
    /// and claims only when a compatible client and live presenter are
    /// attached. Without a presenter this stays dormant: no claim, so
    /// desktop fallback remains available.
    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        generation &+= 1
        let today = todayProvider()
        lastEvaluatedDay = today
        // Restore the unexpired beacon without re-announcing: the HUD stays
        // hidden, but the menu-bar count and its clearing rules survive a
        // restart even when notification permission denied the record.
        restoredBeacon = beaconStore.activeEntries(
            today: today, vaultRoot: configuredVaultRoot, now: nowProvider())
        // Establish the initial identity before starting the capability read.
        // The presenter is normally attached immediately afterward, and its
        // first evaluation must not invalidate that in-flight probe.
        lastConfigIdentity = SnoozeWakeNoticePolicy.configIdentity(
            today: today, vaultRoot: configuredVaultRoot, settings: settingsProvider())
        observer.onReceipt = { [weak self] receipt in
            self?.handleReceipt(receipt)
        }
        observer.onDiagnostic = { [weak self] message in
            self?.diagnose(message)
        }
        presenceSource.onChange = { [weak self] in
            self?.evaluate(reason: "presence")
        }
        presenceSource.onLifecycleChange = { [weak self] in
            self?.fetchRetryAfter = nil
        }
        presenceSource.start()
        observer.start()
        probeCapabilityIfNeeded()
        updateClaim()
        if !restoredBeacon.isEmpty {
            emitQueueChanged()
        }
    }

    func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        generation &+= 1
        reevaluateTask?.cancel()
        reevaluateTask = nil
        fetchTask?.cancel()
        fetchTask = nil
        observer.stop()
        presenceSource.stop()
        claim.relinquish()
        for entry in delivered {
            onTransientDismiss(entry.batch.wakeID)
        }
        pending = []
        delivered = []
        suppressedDeliveredWakeIDs = []
        nudgeEndedWakeIDs = []
        deliveredSettleDeadline = nil
        verification = .unverified
        verificationFetchID = nil
        fetchInFlight = false
        fetchRetryAfter = nil
        wasHeld = false
    }

    /// Attaches the live presenter (the HUD, owned by the next phase).
    /// Claiming requires this: the app never claims before presentation
    /// exists, so no placeholder can suppress desktop fallback.
    func attachPresenter() {
        presenterAttached = true
        probeCapabilityIfNeeded()
        updateClaim()
        evaluate(reason: "presenter")
    }

    func detachPresenter() {
        presenterAttached = false
        updateClaim()
    }

    /// Re-points the coordinator at a new executable or vault. Pending
    /// async work and wake records for the previous configuration are
    /// withdrawn, capability is re-probed, and the claim follows the new
    /// configuration.
    func reconfigure(processClient: BobProcessClient?, vaultRoot: String) {
        let identityChanged = processClient?.identityToken != self.processClient?.identityToken
        let oldVaultRoot = configuredVaultRoot
        let vaultChanged = canonicalVaultRoot(oldVaultRoot) != canonicalVaultRoot(vaultRoot)
        if identityChanged || vaultChanged {
            withdrawForConfigurationChange(oldVaultRoot: oldVaultRoot)
        }
        self.processClient = processClient
        configuredVaultRoot = vaultRoot
        generation &+= 1
        fetchTask?.cancel()
        fetchTask = nil
        fetchInFlight = false
        fetchID &+= 1
        fetchRetryAfter = nil
        verification = .unverified
        verificationFetchID = nil
        lastListDate = nil
        lastListNow = nil
        lastListVaultRoot = nil
        if identityChanged {
            isCapable = nil
        }
        updateClaim()
        probeCapabilityIfNeeded()
        evaluate(reason: "reconfigure")
    }

    private func withdrawForConfigurationChange(oldVaultRoot: String) {
        for entry in pending {
            handledStore.acknowledge(entry.receipt.wakeID, day: entry.receipt.date)
            policy.markHandled(entry.receipt.wakeID, day: entry.receipt.date)
        }
        for entry in delivered {
            handledStore.acknowledge(entry.batch.wakeID, day: entry.batch.date)
            policy.markHandled(entry.batch.wakeID, day: entry.batch.date)
            onDismiss(entry.batch.wakeID)
            onTransientDismiss(entry.batch.wakeID)
        }
        for restored in restoredBeacon {
            handledStore.acknowledge(restored.wakeID, day: restored.date)
            policy.markHandled(restored.wakeID, day: restored.date)
            onDismiss(restored.wakeID)
            onTransientDismiss(restored.wakeID)
        }
        beaconStore.removeAll(vaultRoot: oldVaultRoot)
        pending = []
        delivered = []
        restoredBeacon = []
        suppressedDeliveredWakeIDs = []
        nudgeEndedWakeIDs = []
        deliveredSettleDeadline = nil
        verification = .unverified
        verificationFetchID = nil
        verifyAfter = nil
        wasHeld = false
        heldReasonText = nil
        lastFailure = nil
        lastVerificationText = nil
        presenceSource.setIdlePollingActive(false)
        emitQueueChanged()
    }

    private func canonicalVaultRoot(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The agenda store published a new snapshot or status.
    func notifyAgendaChanged() {
        evaluate(reason: "agenda")
    }

    /// Settings changed: hold toggles apply live, and turning Announce
    /// wakes off discards pending notices and clears UI/records while
    /// keeping a healthy claim.
    func notifySettingsChanged() {
        evaluate(reason: "settings")
    }

    // MARK: - Acknowledgements

    /// The transient HUD nudge ended (x or timeout), keyed by wake ID. The
    /// batch stays delivered so its beacon and record keep their lifecycle,
    /// but it is never re-presented, re-chimed, re-announced, or re-posted
    /// after a later hold. Hold hides call `onTransientDismiss` directly
    /// and never land here.
    func noteTransientEnded(wakeID: String) {
        guard delivered.contains(where: { $0.batch.wakeID == wakeID }) else {
            return
        }
        nudgeEndedWakeIDs.insert(wakeID)
        suppressedDeliveredWakeIDs.remove(wakeID)
        if suppressedDeliveredWakeIDs.isEmpty {
            deliveredSettleDeadline = nil
        }
        emitQueueChanged()
    }

    /// The capture panel opened: delivered beacons/records count as
    /// acknowledged. Pending notices still follow the announcement path.
    /// Restored beacons clear through the same shared path.
    func acknowledgePanelOpen() {
        guard !delivered.isEmpty || !restoredBeacon.isEmpty else {
            return
        }
        CaptureSignpost.event(CaptureSignpost.snoozeAction)
        let today = effectiveToday()
        for entry in delivered {
            handledStore.acknowledge(entry.batch.wakeID, day: today)
            policy.markHandled(entry.batch.wakeID, day: today)
            beaconStore.remove(wakeID: entry.batch.wakeID)
            onDismiss(entry.batch.wakeID)
        }
        for restored in restoredBeacon {
            handledStore.acknowledge(restored.wakeID, day: today)
            policy.markHandled(restored.wakeID, day: today)
            beaconStore.remove(wakeID: restored.wakeID)
            onDismiss(restored.wakeID)
        }
        delivered = []
        restoredBeacon = []
        suppressedDeliveredWakeIDs = []
        nudgeEndedWakeIDs = []
        deliveredSettleDeadline = nil
        emitQueueChanged()
    }

    /// One delivered batch was acted on (Open or +15m). Marks it handled
    /// so it never replays, and withdraws its transient UI. Restored beacons
    /// clear through the same path when the record action fires after a
    /// restart.
    func acknowledgeDelivered(wakeID: String) {
        if let index = restoredBeacon.firstIndex(where: { $0.wakeID == wakeID }) {
            CaptureSignpost.event(CaptureSignpost.snoozeAction)
            restoredBeacon.remove(at: index)
            beaconStore.remove(wakeID: wakeID)
            handledStore.acknowledge(wakeID, day: effectiveToday())
            policy.markHandled(wakeID, day: effectiveToday())
            onDismiss(wakeID)
            onTransientDismiss(wakeID)
            emitQueueChanged()
            return
        }
        guard let index = delivered.firstIndex(where: { $0.batch.wakeID == wakeID }) else {
            return
        }
        CaptureSignpost.event(CaptureSignpost.snoozeAction)
        let entry = delivered.remove(at: index)
        suppressedDeliveredWakeIDs.remove(entry.batch.wakeID)
        nudgeEndedWakeIDs.remove(entry.batch.wakeID)
        handledStore.acknowledge(entry.batch.wakeID, day: effectiveToday())
        policy.markHandled(entry.batch.wakeID, day: effectiveToday())
        beaconStore.remove(wakeID: entry.batch.wakeID)
        onDismiss(entry.batch.wakeID)
        onTransientDismiss(entry.batch.wakeID)
        emitQueueChanged()
    }

    /// Removes tasks Bob confirmed as re-snoozed (or which no longer
    /// match the verified wake). A partially remaining batch stays live.
    /// An empty remainder clears the beacon/record; a partial remainder
    /// refreshes the persisted beacon metadata.
    func removeDeliveredTasks(wakeID: String, keys: [String]) {
        guard !keys.isEmpty else {
            return
        }
        if restoredBeacon.contains(where: { $0.wakeID == wakeID }) {
            // A restored beacon has no live rows to filter: a successful
            // +15m clears it, since Bob confirmed the tasks moved.
            CaptureSignpost.event(CaptureSignpost.snoozeAction)
            restoredBeacon.removeAll(where: { $0.wakeID == wakeID })
            beaconStore.remove(wakeID: wakeID)
            handledStore.acknowledge(wakeID, day: effectiveToday())
            policy.markHandled(wakeID, day: effectiveToday())
            onDismiss(wakeID)
            emitQueueChanged()
            return
        }
        guard let index = delivered.firstIndex(where: { $0.batch.wakeID == wakeID }) else {
            return
        }
        let removed = Set(keys)
        let entry = delivered[index]
        let rows = entry.batch.rows.filter { row in
            guard let key = row.identityKey else { return false }
            return !removed.contains(key)
        }
        if rows.isEmpty {
            CaptureSignpost.event(CaptureSignpost.snoozeAction)
            delivered.remove(at: index)
            suppressedDeliveredWakeIDs.remove(wakeID)
            nudgeEndedWakeIDs.remove(wakeID)
            handledStore.acknowledge(wakeID, day: effectiveToday())
            policy.markHandled(wakeID, day: effectiveToday())
            beaconStore.remove(wakeID: wakeID)
            onDismiss(wakeID)
        } else {
            let batch = SnoozeWakeNoticeBatch(
                wakeID: entry.batch.wakeID,
                wokenAt: entry.batch.wokenAt,
                date: entry.batch.date,
                rows: rows,
                vaultRoot: entry.batch.vaultRoot,
                receiptTasks: entry.batch.receiptTasks
            )
            let presentation = SnoozeWakeNoticePresentation(
                batch: batch,
                listBudget: entry.presentation.listBudget,
                announcement: entry.presentation.announcement
            )
            delivered[index] = DeliveredEntry(
                batch: batch,
                presentation: presentation,
                deliveredAt: entry.deliveredAt
            )
            beaconStore.save(
                wakeID: batch.wakeID,
                taskKeys: batch.identityKeys,
                taskCount: presentation.taskCount,
                deliveredAt: entry.deliveredAt,
                wokenAt: batch.wokenAt,
                date: batch.date,
                vaultRoot: batch.vaultRoot ?? configuredVaultRoot
            )
            if !suppressedDeliveredWakeIDs.contains(wakeID) {
                CaptureSignpost.event(CaptureSignpost.snoozePresent)
                onPresent(batch, presentation)
            }
        }
        emitQueueChanged()
    }

    // MARK: - Test seams

    func receiveForTests(_ receipt: SnoozeWakeReceipt) {
        handleReceipt(receipt)
    }

    var pendingCountForTests: Int { pending.count }
    var deliveredCountForTests: Int { delivered.count }
    var isClaimedForTests: Bool { claim.isOwned }
    var isCapableForTests: Bool? { isCapable }
    var isStartedForTests: Bool { isStarted }
    var isObserverRegisteredForTests: Bool { observer.isRegistered }

    /// Total unacknowledged delivered tasks across live batches plus restored
    /// beacon metadata. Drives the menu-bar beacon count.
    func unacknowledgedTaskCount() -> Int {
        let live = delivered.reduce(0) { $0 + $1.presentation.taskCount }
        let restored = restoredBeacon.reduce(0) { $0 + $1.taskCount }
        return live + restored
    }

    /// Wake IDs with an unexpired beacon or record, for launch reconciliation.
    func activeWakeIDs() -> Set<String> {
        Set(delivered.map(\.batch.wakeID)).union(restoredBeacon.map(\.wakeID))
    }

    /// Restored beacon metadata for diagnostics and launch restore.
    func restoredBeaconEntries() -> [SnoozeWakeBeaconStore.Entry] {
        restoredBeacon
    }

    func saveBeaconForTests(_ entry: SnoozeWakeBeaconStore.Entry) {
        beaconStore.save(
            wakeID: entry.wakeID,
            taskKeys: entry.taskKeys,
            taskCount: entry.taskCount,
            deliveredAt: entry.deliveredAt,
            wokenAt: entry.wokenAt,
            date: entry.date,
            vaultRoot: entry.vaultRoot
        )
    }

    func diagnosticSnapshot() -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            lastReceiptID: lastReceiptID,
            lastChannel: lastChannel,
            heldReason: heldReasonText,
            lastVerification: lastVerificationText,
            pendingCount: pending.count,
            deliveredCount: delivered.count,
            isClaimed: claim.isOwned,
            isCapable: isCapable,
            lastFailure: lastFailure
        )
    }

    // MARK: - Receipt intake

    private func handleReceipt(_ receipt: SnoozeWakeReceipt) {
        guard isStarted else {
            return
        }
        CaptureSignpost.event(CaptureSignpost.snoozeReceiptRead)
        lastReceiptID = receipt.wakeID
        lastChannel = receipt.notificationChannel.rawValue
        guard receipt.notificationChannel.permitsMacNotice else {
            let channel = receipt.notificationChannel.rawValue ?? "?"
            diagnose("ignoring \(receipt.wakeID): channel \(channel)")
            return
        }
        guard isCapable != false else {
            diagnose("ignoring \(receipt.wakeID): Bob does not support wake notices")
            return
        }
        let today = effectiveToday()
        if handledStore.contains(receipt.wakeID, day: today) {
            diagnose("ignoring duplicate \(receipt.wakeID)")
            return
        }
        if pending.contains(where: { $0.receipt.wakeID == receipt.wakeID }) {
            return
        }
        if delivered.contains(where: { $0.batch.wakeID == receipt.wakeID }) {
            return
        }
        if restoredBeacon.contains(where: { $0.wakeID == receipt.wakeID }) {
            diagnose("ignoring duplicate \(receipt.wakeID)")
            return
        }
        pending.append(
            PendingEntry(
                receipt: receipt,
                firstSeenAt: nowProvider(),
                verificationAfterFetchID: fetchID
            ))
        requestAgendaRefresh()
        evaluate(reason: "receipt")
    }

    // MARK: - Evaluation

    private func evaluate(reason: String) {
        guard isStarted else {
            return
        }
        _ = reason
        // Bob's day is the authority. Before the first list read there is
        // no bob date yet; pending receipts wait for verification instead
        // of being judged against the local clock.
        let today = effectiveToday()
        let now = nowProvider()
        // A local day/clock change never pairs a stale receipt with a new
        // clock: it forces a fresh bob read first.
        if reason == "presence" || reason == "timer" || reason == "agenda" {
            let localDay = todayProvider()
            if lastListDate == nil || localDay != lastListDate {
                // No bob date yet, or the local calendar moved past bob's
                // date: refresh bob facts before judging any receipt.
                if !pending.isEmpty || !delivered.isEmpty, !fetchInFlight,
                    fetchRetryAfter.map({ now < $0 }) != true
                {
                    fetchVerification()
                }
            }
        }
        if lastEvaluatedDay != today {
            purgeDay(today: today)
        }
        let settings = settingsProvider()
        let configIdentity = SnoozeWakeNoticePolicy.configIdentity(
            today: today, vaultRoot: configuredVaultRoot, settings: settings)
        if lastConfigIdentity != configIdentity {
            lastConfigIdentity = configIdentity
            generation &+= 1
            fetchRetryAfter = nil
            fetchTask?.cancel()
            fetchTask = nil
            fetchInFlight = false
            fetchID &+= 1
            verification = .unverified
            verificationFetchID = nil
        }
        if !settings.announceWakes {
            consumeWhileDisabled(today: today)
            return
        }
        if isCapable == nil {
            probeCapabilityIfNeeded()
        }
        expireDelivered(today: today, now: now)
        // The 60-minute beacon and four-hour receipt expiries need a timer
        // even when no hold or verification is pending.
        if let nextExpiry = nextDeliveredExpiry(now: now) {
            scheduleReevaluate(after: max(0.05, nextExpiry.timeIntervalSince(now)))
        }
        let presence = presenceSource.currentPresence()
        let events = effectiveEvents(bobDay: today)
        let hasSameDayAgenda = agendaHasSameDayData(bobDay: today)
        presenceSource.setIdlePollingActive(!pending.isEmpty)
        var earliestRecheck: Date?
        let deliveryHeld = currentDeliveryIsHeld(
            presence: presence,
            events: events,
            hasSameDayData: hasSameDayAgenda,
            settings: settings,
            now: now,
            bobNow: lastListNow
        )
        // While a notice is on screen, re-evaluate at the next meeting
        // start: a meeting that begins mid-display hides the HUD.
        if !delivered.isEmpty, settings.holdDuringMeetings, hasSameDayAgenda {
            if let nextStart = SnoozeWakeNoticePolicy.nextMeetingStart(
                events: events, now: now, bobNow: lastListNow),
                nextStart > now
            {
                earliestRecheck = min(earliestRecheck ?? nextStart, nextStart)
            }
        }
        if deliveryHeld {
            for entry in delivered
            where suppressedDeliveredWakeIDs.insert(entry.batch.wakeID).inserted {
                onTransientDismiss(entry.batch.wakeID)
            }
            deliveredSettleDeadline = nil
        } else if !suppressedDeliveredWakeIDs.isEmpty {
            if deliveredSettleDeadline == nil {
                deliveredSettleDeadline = now.addingTimeInterval(settleDelaySeconds)
                verification = .unverified
                requestAgendaRefresh()
            }
            if let deadline = deliveredSettleDeadline, now < deadline {
                earliestRecheck = min(earliestRecheck ?? deadline, deadline)
            } else if let retryAfter = fetchRetryAfter, now < retryAfter {
                earliestRecheck = min(earliestRecheck ?? retryAfter, retryAfter)
            } else if verificationNeedsFetch {
                fetchVerification()
            } else if case .verified = verification {
                restoreSuppressedDeliveries(
                    presence: presence,
                    events: events,
                    hasSameDayData: hasSameDayAgenda,
                    settings: settings,
                    now: now,
                    bobNow: lastListNow
                )
            }
        }
        var dropping: [PendingEntry] = []
        var isHeld = false
        let cycleVerification = verification
        let cycleVerificationFetchID = verificationFetchID
        var consumedVerification = false
        for entry in Array(pending) {
            let entryVerification: SnoozeWakeVerification
            if let cycleVerificationFetchID,
                cycleVerificationFetchID > entry.verificationAfterFetchID
            {
                entryVerification = cycleVerification
            } else {
                entryVerification = .unverified
            }
            let decision = policy.decide(
                receipt: entry.receipt,
                today: today,
                bobNow: lastListNow,
                configuredVaultRoot: configuredVaultRoot,
                listVaultRoot: lastListVaultRoot,
                presence: presence,
                events: events,
                agendaHasSameDayData: hasSameDayAgenda,
                settings: settings,
                verification: entryVerification,
                handledIDs: handledStore.handledIDs(for: today),
                handledIDsDay: today,
                now: now
            )
            switch decision {
            case .show(let batch):
                present(batch: batch)
                consumedVerification = true
            case .hold(let holdReason, let nextCheck):
                if !isHeld {
                    CaptureSignpost.event(CaptureSignpost.snoozeHold)
                }
                isHeld = true
                heldReasonText = holdDescription(holdReason)
                if case .agendaUnavailable = holdReason {
                    // No usable agenda: hold visibly, refresh with bounded
                    // backoff, retain until expiry. Do not cancel the
                    // verification read; bob facts are still needed.
                    requestAgendaRefreshIfNeeded(now: now)
                } else {
                    verification = .unverified
                    verifyAfter = nil
                    fetchTask?.cancel()
                    fetchTask = nil
                    fetchInFlight = false
                    fetchID &+= 1
                }
                if nextCheck > now {
                    earliestRecheck = min(earliestRecheck ?? nextCheck, nextCheck)
                }
            case .verify(let recheckAt):
                heldReasonText = nil
                if case .unverified = entryVerification {
                    if let retryAfter = fetchRetryAfter, now < retryAfter {
                        earliestRecheck = min(earliestRecheck ?? retryAfter, retryAfter)
                    } else if let verifyAfter {
                        if now < verifyAfter {
                            earliestRecheck = min(earliestRecheck ?? verifyAfter, verifyAfter)
                        } else {
                            self.verifyAfter = nil
                            fetchVerification()
                        }
                    } else {
                        let requiredRecheckAt =
                            wasHeld && !deliveryHeld
                            ? max(recheckAt, now.addingTimeInterval(settleDelaySeconds))
                            : recheckAt
                        if requiredRecheckAt > now {
                            verifyAfter = requiredRecheckAt
                            earliestRecheck = min(
                                earliestRecheck ?? requiredRecheckAt, requiredRecheckAt)
                        } else {
                            fetchVerification()
                        }
                    }
                }
                if let verifyAfter, verifyAfter > now {
                    earliestRecheck = min(earliestRecheck ?? verifyAfter, verifyAfter)
                }
            case .drop(let dropReason):
                dropping.append(entry)
                handleDrop(entry: entry, reason: dropReason, today: today)
                consumedVerification = true
            }
        }
        for entry in dropping {
            pending.removeAll(where: { $0.receipt.wakeID == entry.receipt.wakeID })
        }
        if consumedVerification {
            verification = .unverified
        }
        if !dropping.isEmpty || !pending.isEmpty {
            emitQueueChanged()
        }
        if let earliestRecheck, earliestRecheck > now {
            scheduleReevaluate(after: earliestRecheck.timeIntervalSince(now))
        }
        // A hold that just cleared gets a fresh agenda read before
        // delivery: meeting facts may have changed while held.
        if wasHeld, !isHeld, !pending.isEmpty {
            CaptureSignpost.event(CaptureSignpost.snoozeReturn)
            requestAgendaRefresh()
        }
        wasHeld = isHeld
        updateClaim()
    }

    private var verificationNeedsFetch: Bool {
        if case .unverified = verification {
            return !fetchInFlight
        }
        return false
    }

    private func present(batch: SnoozeWakeNoticeBatch) {
        guard !delivered.contains(where: { $0.batch.wakeID == batch.wakeID }) else {
            return
        }
        CaptureSignpost.event(CaptureSignpost.snoozePresent)
        pending.removeAll(where: { $0.receipt.wakeID == batch.wakeID })
        // A restored beacon for the same ID is superseded by the live batch.
        restoredBeacon.removeAll(where: { $0.wakeID == batch.wakeID })
        let presentation = SnoozeWakeNoticePresentation(
            batch: batch, listBudget: lastListPlan, announcement: .hud)
        let deliveredAt = nowProvider()
        delivered.append(
            DeliveredEntry(batch: batch, presentation: presentation, deliveredAt: deliveredAt))
        beaconStore.save(
            wakeID: batch.wakeID,
            taskKeys: batch.identityKeys,
            taskCount: presentation.taskCount,
            deliveredAt: deliveredAt,
            wokenAt: batch.wokenAt,
            date: batch.date,
            vaultRoot: batch.vaultRoot ?? configuredVaultRoot
        )
        heldReasonText = nil
        lastVerificationText = "verified(\(batch.rows.count))"
        onPresent(batch, presentation)
        if isPanelOpen() {
            acknowledgePanelOpen()
        }
        emitQueueChanged()
    }

    private func handleDrop(
        entry: PendingEntry, reason: SnoozeWakeDropReason, today: String
    ) {
        switch reason {
        case .wrongChannel:
            diagnose("ignoring \(entry.receipt.wakeID): wrong channel")
        case .duplicate:
            break
        default:
            handledStore.acknowledge(entry.receipt.wakeID, day: today)
            policy.markHandled(entry.receipt.wakeID, day: today)
            diagnose("dropping \(entry.receipt.wakeID): \(dropDescription(reason))")
        }
        if case .verificationFailed = reason {
            lastFailure = "verification failed"
        }
    }

    private func expireDelivered(today: String, now: Date) {
        var expired: [DeliveredEntry] = []
        for entry in delivered {
            let receiptAge = now.timeIntervalSince(entry.batch.wokenAt)
            let expiredByReceiptAge = receiptAge > SnoozeWakeNoticePolicy.receiptMaxAgeSeconds
            let beaconAge = now.timeIntervalSince(entry.deliveredAt)
            let expiredByBeaconAge = beaconAge >= SnoozeWakeNoticePresentation.beaconLifetimeSeconds
            if entry.batch.date != today || expiredByReceiptAge || expiredByBeaconAge {
                expired.append(entry)
            }
        }
        // Restored beacons expire through the same 60-minute, four-hour, and
        // day-boundary rules without a live batch.
        let expiredRestored = restoredBeacon.filter { restored in
            if restored.date != today {
                return true
            }
            let beaconAge = now.timeIntervalSince(restored.deliveredAt)
            let receiptAge = now.timeIntervalSince(restored.wokenAt)
            return beaconAge >= SnoozeWakeNoticePresentation.beaconLifetimeSeconds
                || receiptAge > SnoozeWakeNoticePolicy.receiptMaxAgeSeconds
        }
        if !expired.isEmpty || !expiredRestored.isEmpty {
            CaptureSignpost.event(CaptureSignpost.snoozeWithdraw)
        }
        for entry in expired {
            delivered.removeAll(where: { $0.batch.wakeID == entry.batch.wakeID })
            suppressedDeliveredWakeIDs.remove(entry.batch.wakeID)
            nudgeEndedWakeIDs.remove(entry.batch.wakeID)
            handledStore.acknowledge(entry.batch.wakeID, day: today)
            policy.markHandled(entry.batch.wakeID, day: today)
            beaconStore.remove(wakeID: entry.batch.wakeID)
            onDismiss(entry.batch.wakeID)
            onTransientDismiss(entry.batch.wakeID)
        }
        for restored in expiredRestored {
            restoredBeacon.removeAll(where: { $0.wakeID == restored.wakeID })
            beaconStore.remove(wakeID: restored.wakeID)
            handledStore.acknowledge(restored.wakeID, day: today)
            policy.markHandled(restored.wakeID, day: today)
            onDismiss(restored.wakeID)
            onTransientDismiss(restored.wakeID)
        }
        if suppressedDeliveredWakeIDs.isEmpty {
            deliveredSettleDeadline = nil
        }
        if !expired.isEmpty || !expiredRestored.isEmpty {
            emitQueueChanged()
        }
        // A 60-minute expiry that just fired may leave no pending work but
        // still needs its recheck timer cleared; the queue change above
        // covers the beacon refresh.
    }

    /// Next beacon or receipt expiry across live and restored beacons, for the
    /// 60-minute clearing timer. Nil when nothing is delivered.
    private func nextDeliveredExpiry(now: Date) -> Date? {
        var candidates: [Date] = []
        for entry in delivered {
            candidates.append(entry.deliveredAt.addingTimeInterval(
                SnoozeWakeNoticePresentation.beaconLifetimeSeconds))
            candidates.append(entry.batch.wokenAt.addingTimeInterval(
                SnoozeWakeNoticePolicy.receiptMaxAgeSeconds))
        }
        for restored in restoredBeacon {
            candidates.append(restored.deliveredAt.addingTimeInterval(
                SnoozeWakeNoticePresentation.beaconLifetimeSeconds))
            candidates.append(restored.wokenAt.addingTimeInterval(
                SnoozeWakeNoticePolicy.receiptMaxAgeSeconds))
        }
        return candidates.filter { $0 > now }.min()
    }

    private func consumeWhileDisabled(today: String) {
        let hadRestored = !restoredBeacon.isEmpty
        for entry in pending {
            handledStore.acknowledge(entry.receipt.wakeID, day: today)
            policy.markHandled(entry.receipt.wakeID, day: today)
        }
        for entry in delivered {
            handledStore.acknowledge(entry.batch.wakeID, day: today)
            policy.markHandled(entry.batch.wakeID, day: today)
            beaconStore.remove(wakeID: entry.batch.wakeID)
            onDismiss(entry.batch.wakeID)
            onTransientDismiss(entry.batch.wakeID)
        }
        for restored in restoredBeacon {
            handledStore.acknowledge(restored.wakeID, day: today)
            policy.markHandled(restored.wakeID, day: today)
            beaconStore.remove(wakeID: restored.wakeID)
            onDismiss(restored.wakeID)
            onTransientDismiss(restored.wakeID)
        }
        let hadWork = !pending.isEmpty || !delivered.isEmpty || hadRestored
        pending = []
        delivered = []
        restoredBeacon = []
        suppressedDeliveredWakeIDs = []
        nudgeEndedWakeIDs = []
        deliveredSettleDeadline = nil
        verification = .unverified
        verificationFetchID = nil
        verifyAfter = nil
        wasHeld = false
        presenceSource.setIdlePollingActive(false)
        if hadWork {
            emitQueueChanged()
        }
    }

    private func purgeDay(today: String) {
        CaptureSignpost.event(CaptureSignpost.snoozeWithdraw)
        lastEvaluatedDay = today
        handledStore.purge(day: today)
        for entry in pending {
            handledStore.acknowledge(entry.receipt.wakeID, day: today)
            policy.markHandled(entry.receipt.wakeID, day: today)
        }
        generation &+= 1
        fetchTask?.cancel()
        fetchTask = nil
        fetchInFlight = false
        fetchID &+= 1
        for entry in delivered {
            handledStore.acknowledge(entry.batch.wakeID, day: today)
            policy.markHandled(entry.batch.wakeID, day: today)
            beaconStore.remove(wakeID: entry.batch.wakeID)
            onDismiss(entry.batch.wakeID)
            onTransientDismiss(entry.batch.wakeID)
        }
        for restored in restoredBeacon {
            handledStore.acknowledge(restored.wakeID, day: today)
            policy.markHandled(restored.wakeID, day: today)
            beaconStore.remove(wakeID: restored.wakeID)
            onDismiss(restored.wakeID)
            onTransientDismiss(restored.wakeID)
        }
        pending = []
        delivered = []
        restoredBeacon = []
        suppressedDeliveredWakeIDs = []
        nudgeEndedWakeIDs = []
        deliveredSettleDeadline = nil
        verification = .unverified
        verificationFetchID = nil
        verifyAfter = nil
        fetchRetryAfter = nil
        wasHeld = false
        presenceSource.setIdlePollingActive(false)
        emitQueueChanged()
    }

    // MARK: - Verification fetch

    private func probeCapabilityIfNeeded() {
        guard isStarted, isCapable != true, !fetchInFlight, processClient != nil else {
            return
        }
        if let fetchRetryAfter, nowProvider() < fetchRetryAfter {
            return
        }
        fetchVerification()
    }

    private func fetchVerification() {
        CaptureSignpost.event(CaptureSignpost.snoozeVerify)
        guard let client = processClient, !fetchInFlight else {
            return
        }
        if let fetchRetryAfter, nowProvider() < fetchRetryAfter {
            return
        }
        fetchInFlight = true
        fetchID &+= 1
        let expectedFetch = fetchID
        let expectedGeneration = generation
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            let result: Result<SnoozeWakeListResponse, Error>
            do {
                result = .success(try await client.snoozeListForWakeVerification())
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                self?.finishFetch(
                    result, generation: expectedGeneration, fetch: expectedFetch)
            }
        }
    }

    private func finishFetch(
        _ result: Result<SnoozeWakeListResponse, Error>,
        generation expected: UInt64,
        fetch expectedFetch: UInt64
    ) {
        guard expected == generation, expectedFetch == fetchID, isStarted
        else {
            return
        }
        fetchInFlight = false
        fetchTask = nil
        verificationFetchID = expectedFetch
        let today = effectiveToday()
        switch result {
        case .success(let response):
            fetchRetryAfter = nil
            lastFailure = nil
            isCapable = response.supportsWakeNotice
            lastListPlan = response.plan
            lastListNow = response.now
            lastListDate = response.date
            lastListVaultRoot = response.vaultRoot
            lastVerificationText = "verified(\(response.eligibleRows.count))"
            if response.supportsWakeNotice {
                if response.eligibleRows.isEmpty {
                    verification = .empty
                } else {
                    verification = .verified(eligible: response.eligibleRows)
                }
            } else {
                verification = .failed(reason: "unsupported")
                dropAllPendingUnsupported(today: today)
            }
            revalidateSuppressedDeliveries(response: response, today: today)
        case .failure(let error):
            if let clientError = error as? BobClientError,
                case .unsupportedCommand = clientError
            {
                isCapable = false
                verification = .failed(reason: "unsupported")
                lastFailure = "unsupported"
                dropAllPendingUnsupported(today: today)
            } else {
                fetchRetryAfter = nowProvider().addingTimeInterval(retryIntervalSeconds)
                let failure = error is BobClientError ? "Bob command failed" : "read failed"
                lastFailure = failure
                diagnose("snooze list failed: \(failure)")
                requestAgendaRefresh()
                scheduleReevaluate(after: retryIntervalSeconds)
            }
        }
        updateClaim()
        evaluate(reason: "verification")
    }

    private func dropAllPendingUnsupported(today: String) {
        for entry in pending {
            handledStore.acknowledge(entry.receipt.wakeID, day: today)
            policy.markHandled(entry.receipt.wakeID, day: today)
        }
        pending = []
        verification = .unverified
        presenceSource.setIdlePollingActive(false)
        emitQueueChanged()
    }

    // MARK: - Claim

    private func updateClaim() {
        guard isStarted, observer.isRegistered, presenterAttached,
            isCapable == true, processClient != nil
        else {
            if claim.isOwned {
                claim.relinquish()
            }
            return
        }
        if !claim.isOwned {
            do {
                try claim.publish()
            } catch {
                diagnose("claim publish failed")
            }
        }
    }

    // MARK: - Helpers

    /// Bob's day authority: the latest list read's date, falling back to
    /// the local calendar only before the first read. Every receipt-day,
    /// handled-ID, purge, and meeting check uses this, never
    /// `CaptureAgendaStore.localToday()` or a fresh Mac clock alone.
    func effectiveToday() -> String {
        lastListDate ?? todayProvider()
    }

    /// Usable agenda events for bob's day. When a snapshot provider is
    /// present (production), only ready/stale same-day snapshots supply
    /// events; loading, failed with no same-day data, and other-day
    /// snapshots supply nil so the coordinator holds instead of
    /// delivering. Without a snapshot provider (older tests), the legacy
    /// events provider is used directly.
    private func effectiveEvents(bobDay: String) -> CaptureAgendaEvents? {
        guard let snapshotProvider = agendaSnapshotProvider else {
            return agendaEventsProvider()
        }
        guard let snapshot = snapshotProvider() else {
            return nil
        }
        guard snapshot.date == bobDay else {
            return nil
        }
        switch snapshot.status {
        case .ready, .stale:
            return snapshot.events
        case .idle, .loading, .failed, .unsupported:
            return nil
        }
    }

    /// Whether the agenda has usable same-day data for bob's day. Without
    /// a snapshot provider (older tests) this is true so nil events keep
    /// meaning "no meetings". With a provider, missing/loading/failed/
    /// other-day snapshots are unavailable and hold.
    private func agendaHasSameDayData(bobDay: String) -> Bool {
        guard let snapshotProvider = agendaSnapshotProvider else {
            return true
        }
        guard let snapshot = snapshotProvider() else {
            return false
        }
        guard snapshot.date == bobDay else {
            return false
        }
        switch snapshot.status {
        case .ready, .stale:
            return true
        case .idle, .loading, .failed, .unsupported:
            return false
        }
    }

    /// Bounded agenda refresh: no more often than the agenda retry
    /// interval, so an unavailable agenda does not spin the refresh lane.
    private func requestAgendaRefreshIfNeeded(now: Date) {
        let interval = SnoozeWakeNoticePolicy.agendaRetrySeconds
        if let last = lastAgendaRefreshRequestAt,
            now.timeIntervalSince(last) < interval
        {
            return
        }
        lastAgendaRefreshRequestAt = now
        requestAgendaRefresh()
    }

    private func scheduleReevaluate(after delay: TimeInterval) {
        reevaluateTask?.cancel()
        let expectedGeneration = generation
        reevaluateTask = Task { [weak self] in
            do {
                let clamped = min(max(delay, 0), 86_400)
                try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
            } catch {
                return
            }
            await MainActor.run { [weak self] in
                guard let self, self.generation == expectedGeneration, self.isStarted else {
                    return
                }
                self.evaluate(reason: "timer")
            }
        }
    }

    private func emitQueueChanged() {
        onQueueChanged(pending.count, delivered.count)
    }

    private func currentDeliveryIsHeld(
        presence: SnoozeWakePresence,
        events: CaptureAgendaEvents?,
        hasSameDayData: Bool = true,
        settings: SnoozeWakeNoticeSettings,
        now: Date,
        bobNow: String?
    ) -> Bool {
        (settings.holdWhileAway && presence.isAway)
            || (settings.holdDuringMeetings && !hasSameDayData)
            || (settings.holdDuringMeetings
                && SnoozeWakeNoticePolicy.runningMeetingEnd(
                    events: events,
                    now: now,
                    bobNow: bobNow
                ) != nil)
    }

    private func revalidateSuppressedDeliveries(
        response: SnoozeWakeListResponse, today: String
    ) {
        guard !suppressedDeliveredWakeIDs.isEmpty else { return }
        let configuredRoot = URL(fileURLWithPath: configuredVaultRoot, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath().path
        guard response.supportsWakeNotice, response.date == today,
            let responseRoot = response.vaultRoot,
            URL(fileURLWithPath: responseRoot, isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath().path == configuredRoot
        else {
            let staleIDs = Array(suppressedDeliveredWakeIDs)
            for wakeID in staleIDs {
                acknowledgeDelivered(wakeID: wakeID)
            }
            return
        }
        let eligible = Dictionary(
            response.eligibleRows.compactMap { row in row.identityKey.map { ($0, row) } },
            uniquingKeysWith: { first, _ in first }
        )
        for entry in delivered where suppressedDeliveredWakeIDs.contains(entry.batch.wakeID) {
            let rows = entry.batch.rows.filter { old in
                guard let key = old.identityKey, let fresh = eligible[key] else { return false }
                return old.target == fresh.target && old.wokeAt == fresh.wokeAt
                    && old.route == fresh.route && old.blockID == fresh.blockID
            }
            if rows.isEmpty {
                acknowledgeDelivered(wakeID: entry.batch.wakeID)
                continue
            }
            guard rows != entry.batch.rows,
                let index = delivered.firstIndex(where: { $0.batch.wakeID == entry.batch.wakeID })
            else {
                continue
            }
            let batch = SnoozeWakeNoticeBatch(
                wakeID: entry.batch.wakeID,
                wokenAt: entry.batch.wokenAt,
                date: entry.batch.date,
                rows: rows,
                vaultRoot: entry.batch.vaultRoot,
                receiptTasks: entry.batch.receiptTasks
            )
            let presentation = SnoozeWakeNoticePresentation(
                batch: batch,
                listBudget: entry.presentation.listBudget,
                announcement: entry.presentation.announcement
            )
            delivered[index] = DeliveredEntry(
                batch: batch,
                presentation: presentation,
                deliveredAt: entry.deliveredAt
            )
        }
    }

    private func restoreSuppressedDeliveries(
        presence: SnoozeWakePresence,
        events: CaptureAgendaEvents?,
        hasSameDayData: Bool = true,
        settings: SnoozeWakeNoticeSettings,
        now: Date,
        bobNow: String?
    ) {
        guard
            !currentDeliveryIsHeld(
                presence: presence,
                events: events,
                hasSameDayData: hasSameDayData,
                settings: settings,
                now: now,
                bobNow: bobNow
            )
        else {
            return
        }
        // Only a HUD the hold hid while still on screen is restored, without
        // a chime, announcement, or record re-post. An ended nudge stays
        // ended; its beacon and record keep their own lifecycle.
        let entries = delivered.filter { suppressedDeliveredWakeIDs.contains($0.batch.wakeID) }
        for entry in entries {
            suppressedDeliveredWakeIDs.remove(entry.batch.wakeID)
            guard !nudgeEndedWakeIDs.contains(entry.batch.wakeID) else {
                continue
            }
            onRestore(entry.batch, entry.presentation)
        }
        if suppressedDeliveredWakeIDs.isEmpty {
            deliveredSettleDeadline = nil
        }
    }

    private func diagnose(_ message: String) {
        lastFailure = message
        onDiagnostic(message)
    }

    private func holdDescription(_ reason: SnoozeWakeHoldReason) -> String {
        switch reason {
        case .away(let signals):
            return "away(\(signals.map(\.rawValue).joined(separator: ",")))"
        case .meeting(let until):
            return "meeting(until:\(until))"
        case .settling(let until):
            return "settling(until:\(until))"
        case .agendaUnavailable(let until):
            return "agendaUnavailable(until:\(until))"
        }
    }

    private func dropDescription(_ reason: SnoozeWakeDropReason) -> String {
        switch reason {
        case .announcementsDisabled: return "announcementsDisabled"
        case .unsupportedBob: return "unsupportedBob"
        case .wrongChannel: return "wrongChannel"
        case .dayMismatch: return "dayMismatch"
        case .vaultMismatch: return "vaultMismatch"
        case .invalidTimestamp: return "invalidTimestamp"
        case .futureDated: return "futureDated"
        case .expired: return "expired"
        case .duplicate: return "duplicate"
        case .emptyVerification: return "emptyVerification"
        case .verificationFailed: return "verificationFailed"
        case .noEligibleTasks: return "noEligibleTasks"
        }
    }
}
