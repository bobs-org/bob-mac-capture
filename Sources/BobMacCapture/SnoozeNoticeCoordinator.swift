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
///   batch and configuration via the generation token.
/// - Terminally handled IDs (acknowledged, expired, day-purged, or
///   consumed while disabled) persist in the bounded day-scoped store;
///   a held batch is never marked delivered merely because the
///   observer read it.
@MainActor
final class SnoozeNoticeCoordinator {
    /// One queued receipt awaiting hold clearance and verification.
    struct PendingEntry: Sendable {
        let receipt: SnoozeWakeReceipt
        let firstSeenAt: Date
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
    var onQueueChanged: (Int, Int) -> Void = { _, _ in }
    var onDiagnostic: (String) -> Void = { _ in }
    var isPanelOpen: () -> Bool = { false }

    private let observer: SnoozeWakeObserver
    private let presenceSource: SnoozeWakePresenceSource
    private let claim: SnoozeWakeNotifierClaim
    private let handledStore: SnoozeWakeHandledStore
    private var processClient: BobProcessClient?
    private var configuredVaultRoot: String
    private let todayProvider: () -> String
    private let nowProvider: () -> Date
    private let settingsProvider: () -> SnoozeWakeNoticeSettings
    private let agendaEventsProvider: () -> CaptureAgendaEvents?
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
    private var deliveredSettleDeadline: Date?
    private var verification: SnoozeWakeVerification = .unverified
    private var verifyAfter: Date?
    private var fetchInFlight = false
    private var fetchRetryAfter: Date?
    private var lastListPlan = SnoozeWakeLinkPlan()
    private var lastListNow: String?
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

    init(
        observer: SnoozeWakeObserver? = nil,
        presenceSource: SnoozeWakePresenceSource? = nil,
        claim: SnoozeWakeNotifierClaim,
        handledStore: SnoozeWakeHandledStore = SnoozeWakeHandledStore(),
        processClient: BobProcessClient? = nil,
        configuredVaultRoot: String = "",
        today: (() -> String)? = nil,
        now: (() -> Date)? = nil,
        settings: (() -> SnoozeWakeNoticeSettings)? = nil,
        agendaEvents: (() -> CaptureAgendaEvents?)? = nil,
        requestAgendaRefresh: (() -> Void)? = nil,
        settleDelaySeconds: TimeInterval = defaultSettleDelaySeconds,
        retryIntervalSeconds: TimeInterval = defaultRetryIntervalSeconds
    ) {
        self.claim = claim
        self.handledStore = handledStore
        self.processClient = processClient
        self.configuredVaultRoot = configuredVaultRoot
        self.todayProvider = today ?? { CaptureAgendaStore.localToday() }
        self.nowProvider = now ?? { Date() }
        self.settingsProvider = settings ?? { SnoozeWakeNoticeSettings() }
        self.agendaEventsProvider = agendaEvents ?? { nil }
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
        presenceSource.start()
        observer.start()
        probeCapabilityIfNeeded()
        updateClaim()
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
        deliveredSettleDeadline = nil
        verification = .unverified
        fetchInFlight = false
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
    /// async work is invalidated, capability is re-probed, and the
    /// claim follows the new configuration.
    func reconfigure(processClient: BobProcessClient?, vaultRoot: String) {
        let identityChanged = processClient?.identityToken != self.processClient?.identityToken
        self.processClient = processClient
        configuredVaultRoot = vaultRoot
        generation &+= 1
        fetchTask?.cancel()
        fetchTask = nil
        fetchInFlight = false
        fetchID &+= 1
        if identityChanged {
            isCapable = nil
            policy.invalidate()
        }
        updateClaim()
        probeCapabilityIfNeeded()
        evaluate(reason: "reconfigure")
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

    /// The capture panel opened: delivered beacons/records count as
    /// acknowledged. Pending notices still follow the announcement path.
    func acknowledgePanelOpen() {
        guard !delivered.isEmpty else {
            return
        }
        let today = todayProvider()
        for entry in delivered {
            handledStore.acknowledge(entry.batch.wakeID, day: today)
            policy.markHandled(entry.batch.wakeID, day: today)
            onDismiss(entry.batch.wakeID)
        }
        delivered = []
        suppressedDeliveredWakeIDs = []
        deliveredSettleDeadline = nil
        emitQueueChanged()
    }

    /// One delivered batch was acted on (Open or +15m). Marks it handled
    /// so it never replays, and withdraws its transient UI.
    func acknowledgeDelivered(wakeID: String) {
        guard let index = delivered.firstIndex(where: { $0.batch.wakeID == wakeID }) else {
            return
        }
        let entry = delivered.remove(at: index)
        suppressedDeliveredWakeIDs.remove(entry.batch.wakeID)
        handledStore.acknowledge(entry.batch.wakeID, day: todayProvider())
        policy.markHandled(entry.batch.wakeID, day: todayProvider())
        onDismiss(entry.batch.wakeID)
        onTransientDismiss(entry.batch.wakeID)
        emitQueueChanged()
    }

    /// Removes tasks Bob confirmed as re-snoozed (or which no longer
    /// match the verified wake). A partially remaining batch stays live.
    func removeDeliveredTasks(wakeID: String, keys: [String]) {
        guard let index = delivered.firstIndex(where: { $0.batch.wakeID == wakeID }),
            !keys.isEmpty
        else {
            return
        }
        let removed = Set(keys)
        let entry = delivered[index]
        let rows = entry.batch.rows.filter { row in
            guard let key = row.identityKey else { return false }
            return !removed.contains(key)
        }
        if rows.isEmpty {
            delivered.remove(at: index)
            suppressedDeliveredWakeIDs.remove(wakeID)
            handledStore.acknowledge(wakeID, day: todayProvider())
            policy.markHandled(wakeID, day: todayProvider())
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
            if !suppressedDeliveredWakeIDs.contains(wakeID) {
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
        let today = todayProvider()
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
        pending.append(PendingEntry(receipt: receipt, firstSeenAt: nowProvider()))
        requestAgendaRefresh()
        evaluate(reason: "receipt")
    }

    // MARK: - Evaluation

    private func evaluate(reason: String) {
        guard isStarted else {
            return
        }
        _ = reason
        let today = todayProvider()
        let now = nowProvider()
        if lastEvaluatedDay != today {
            purgeDay(today: today)
        }
        let settings = settingsProvider()
        let configIdentity = SnoozeWakeNoticePolicy.configIdentity(
            today: today, vaultRoot: configuredVaultRoot, settings: settings)
        if lastConfigIdentity != configIdentity {
            lastConfigIdentity = configIdentity
            generation &+= 1
            fetchInFlight = false
        }
        if !settings.announceWakes {
            consumeWhileDisabled(today: today)
            return
        }
        expireDelivered(today: today, now: now)
        let presence = presenceSource.currentPresence()
        let events = agendaEventsProvider()
        presenceSource.setIdlePollingActive(!pending.isEmpty)
        var earliestRecheck: Date?
        let deliveryHeld = currentDeliveryIsHeld(
            presence: presence,
            events: events,
            settings: settings,
            now: now,
            bobNow: lastListNow
        )
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
                    settings: settings,
                    now: now,
                    bobNow: lastListNow
                )
            }
        }
        var dropping: [PendingEntry] = []
        var isHeld = false
        for entry in Array(pending) {
            let decision = policy.decide(
                receipt: entry.receipt,
                today: today,
                bobNow: lastListNow,
                configuredVaultRoot: configuredVaultRoot,
                presence: presence,
                events: events,
                settings: settings,
                verification: verification,
                handledIDs: handledStore.handledIDs(for: today),
                handledIDsDay: today,
                now: now
            )
            switch decision {
            case .show(let batch):
                present(batch: batch)
            case .hold(let holdReason, let nextCheck):
                isHeld = true
                heldReasonText = holdDescription(holdReason)
                verification = .unverified
                verifyAfter = nil
                fetchTask?.cancel()
                fetchTask = nil
                fetchInFlight = false
                fetchID &+= 1
                if nextCheck > now {
                    earliestRecheck = min(earliestRecheck ?? nextCheck, nextCheck)
                }
            case .verify(let recheckAt):
                heldReasonText = nil
                if let retryAfter = fetchRetryAfter, now < retryAfter {
                    earliestRecheck = min(earliestRecheck ?? retryAfter, retryAfter)
                } else if verificationNeedsFetch {
                    if let verifyAfter {
                        if now < verifyAfter {
                            earliestRecheck = min(earliestRecheck ?? verifyAfter, verifyAfter)
                        } else {
                            self.verifyAfter = nil
                            fetchVerification()
                        }
                    } else if recheckAt > now {
                        verifyAfter = recheckAt
                        earliestRecheck = min(earliestRecheck ?? recheckAt, recheckAt)
                    } else {
                        fetchVerification()
                    }
                }
                if let verifyAfter, verifyAfter > now {
                    earliestRecheck = min(earliestRecheck ?? verifyAfter, verifyAfter)
                }
            case .drop(let dropReason):
                dropping.append(entry)
                handleDrop(entry: entry, reason: dropReason, today: today)
            }
        }
        for entry in dropping {
            pending.removeAll(where: { $0.receipt.wakeID == entry.receipt.wakeID })
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
        pending.removeAll(where: { $0.receipt.wakeID == batch.wakeID })
        let presentation = SnoozeWakeNoticePresentation(
            batch: batch, listBudget: lastListPlan, announcement: .hud)
        delivered.append(
            DeliveredEntry(batch: batch, presentation: presentation, deliveredAt: nowProvider()))
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
        if case .verificationFailed(let message) = reason {
            lastFailure = message
        }
    }

    private func expireDelivered(today: String, now: Date) {
        var expired: [DeliveredEntry] = []
        for entry in delivered {
            let age = now.timeIntervalSince(entry.batch.wokenAt)
            let expiredByAge = age > SnoozeWakeNoticePolicy.receiptMaxAgeSeconds
            if entry.batch.date != today || expiredByAge {
                expired.append(entry)
            }
        }
        for entry in expired {
            delivered.removeAll(where: { $0.batch.wakeID == entry.batch.wakeID })
            suppressedDeliveredWakeIDs.remove(entry.batch.wakeID)
            handledStore.acknowledge(entry.batch.wakeID, day: today)
            policy.markHandled(entry.batch.wakeID, day: today)
            onDismiss(entry.batch.wakeID)
            onTransientDismiss(entry.batch.wakeID)
        }
        if suppressedDeliveredWakeIDs.isEmpty {
            deliveredSettleDeadline = nil
        }
        if !expired.isEmpty {
            emitQueueChanged()
        }
    }

    private func consumeWhileDisabled(today: String) {
        for entry in pending {
            handledStore.acknowledge(entry.receipt.wakeID, day: today)
            policy.markHandled(entry.receipt.wakeID, day: today)
        }
        for entry in delivered {
            handledStore.acknowledge(entry.batch.wakeID, day: today)
            policy.markHandled(entry.batch.wakeID, day: today)
            onDismiss(entry.batch.wakeID)
            onTransientDismiss(entry.batch.wakeID)
        }
        let hadWork = !pending.isEmpty || !delivered.isEmpty
        pending = []
        delivered = []
        suppressedDeliveredWakeIDs = []
        deliveredSettleDeadline = nil
        verification = .unverified
        verifyAfter = nil
        wasHeld = false
        presenceSource.setIdlePollingActive(false)
        if hadWork {
            emitQueueChanged()
        }
    }

    private func purgeDay(today: String) {
        lastEvaluatedDay = today
        handledStore.purge(day: today)
        policy.invalidate()
        for entry in delivered {
            onDismiss(entry.batch.wakeID)
            onTransientDismiss(entry.batch.wakeID)
        }
        pending = []
        delivered = []
        suppressedDeliveredWakeIDs = []
        deliveredSettleDeadline = nil
        verification = .unverified
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
        let today = todayProvider()
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            let result: Result<SnoozeWakeListResponse, Error>
            do {
                result = .success(try await client.snoozeList())
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                self?.finishFetch(
                    result, generation: expectedGeneration, fetch: expectedFetch, today: today)
            }
        }
    }

    private func finishFetch(
        _ result: Result<SnoozeWakeListResponse, Error>,
        generation expected: UInt64,
        fetch expectedFetch: UInt64,
        today: String
    ) {
        fetchInFlight = false
        fetchTask = nil
        guard expected == generation, expectedFetch == fetchID,
            today == todayProvider(), isStarted
        else {
            return
        }
        switch result {
        case .success(let response):
            fetchRetryAfter = nil
            lastFailure = nil
            isCapable = response.supportsWakeNotice
            lastListPlan = response.plan
            lastListNow = response.now
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
                lastFailure = String(describing: error)
                diagnose("snooze list failed: \(error)")
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
        guard isStarted, presenterAttached, isCapable == true, processClient != nil else {
            if claim.isOwned {
                claim.relinquish()
            }
            return
        }
        if !claim.isOwned {
            do {
                try claim.publish()
            } catch {
                diagnose("claim publish failed: \(error)")
            }
        }
    }

    // MARK: - Helpers

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
        settings: SnoozeWakeNoticeSettings,
        now: Date,
        bobNow: String?
    ) -> Bool {
        (settings.holdWhileAway && presence.isAway)
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
        settings: SnoozeWakeNoticeSettings,
        now: Date,
        bobNow: String?
    ) {
        guard
            !currentDeliveryIsHeld(
                presence: presence,
                events: events,
                settings: settings,
                now: now,
                bobNow: bobNow
            )
        else {
            return
        }
        let entries = delivered.filter { suppressedDeliveredWakeIDs.contains($0.batch.wakeID) }
        for entry in entries {
            onPresent(entry.batch, entry.presentation)
            suppressedDeliveredWakeIDs.remove(entry.batch.wakeID)
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
        case .verificationFailed(let message): return "verificationFailed(\(message))"
        case .noEligibleTasks: return "noEligibleTasks"
        }
    }
}
