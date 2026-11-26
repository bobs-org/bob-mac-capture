import AppKit
import CaptureCore
import Combine
import Foundation

/// App-lifetime adapter for Bob's snooze wake writer. Timer invalidation is
/// independent from a started Bob process: ordinary publications, lifecycle
/// events, and reconfiguration never terminate a write already in progress.
@MainActor
final class SnoozeWakeScheduler {
    private let agendaStore: CaptureAgendaStore
    private let now: () -> Date
    private let today: () -> String
    private let workspaceCenter: NotificationCenter
    private let defaultCenter: NotificationCenter
    private var processClient: BobProcessClient?
    private var processIdentity: String?
    private var policy = CaptureSnoozeWakePolicy()
    private var snapshot: CaptureAgendaSnapshot?
    private var snapshotRevision: UInt64 = 0
    private var generation: UInt64 = 0
    private var timerGeneration: UInt64 = 0
    private var timerTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var wakeInFlight = false
    private var followUpPending = false
    private var isStopped = false
    private var snapshotCancellable: AnyCancellable?
    private var observers: [NSObjectProtocol] = []

    private(set) var scheduledFireDateForTesting: Date?
    private(set) var wakeInFlightForTesting = false

    init(
        agendaStore: CaptureAgendaStore,
        processClient: BobProcessClient?,
        now: @escaping () -> Date = { Date() },
        today: @escaping () -> String = CaptureAgendaStore.localToday,
        workspaceCenter: NotificationCenter? = nil,
        defaultCenter: NotificationCenter = .default
    ) {
        self.agendaStore = agendaStore
        self.processClient = processClient
        self.processIdentity = processClient?.identityToken
        self.now = now
        self.today = today
        self.workspaceCenter = workspaceCenter ?? NSWorkspace.shared.notificationCenter
        self.defaultCenter = defaultCenter
        observeSnapshots()
        observeLifecycle()
    }

    deinit {
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            defaultCenter.removeObserver(observer)
        }
    }

    /// Reconfiguration retires old timers and callbacks but leaves an
    /// already-started writer alone. The agenda store publishes its reset
    /// snapshot immediately after this call.
    func reconfigure(processClient: BobProcessClient?) {
        generation &+= 1
        cancelPendingTimer()
        self.processClient = processClient
        processIdentity = processClient?.identityToken
        snapshot = nil
        snapshotRevision &+= 1
        policy.reset()
        followUpPending = false
    }

    func stop() {
        isStopped = true
        generation &+= 1
        cancelPendingTimer()
    }

    /// Test hook: simulates the armed instant after advancing the injected
    /// clock, without waiting on wall-clock time.
    func fireDueWakeForTesting() {
        cancelPendingTimer()
        refreshScheduleFromSnapshot()
    }

    private func observeSnapshots() {
        snapshotCancellable = agendaStore.$snapshot.sink { [weak self] emittedSnapshot in
            guard let self else {
                return
            }
            self.snapshot = emittedSnapshot
            self.snapshotRevision &+= 1
            if self.wakeInFlight {
                self.followUpPending = true
            }
            self.refreshScheduleFromSnapshot()
        }
    }

    private func observeLifecycle() {
        let workspace = workspaceCenter
        let center = defaultCenter
        let names: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification),
            (center, .NSCalendarDayChanged),
            (center, .NSSystemClockDidChange),
        ]
        for (notificationCenter, name) in names {
            observers.append(
                notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshScheduleFromSnapshot()
                    }
                }
            )
        }
    }

    private func refreshScheduleFromSnapshot() {
        guard !isStopped else {
            return
        }
        refreshForExecutableReplacementIfNeeded()
        _ = policy.update(snapshot: snapshot, today: today(), now: now())
        scheduleNextAttempt()
    }

    private func refreshForExecutableReplacementIfNeeded() {
        let currentIdentity = processClient?.identityToken
        guard currentIdentity != processIdentity else {
            return
        }
        generation &+= 1
        cancelPendingTimer()
        processIdentity = currentIdentity
        policy.reset()
        if wakeInFlight {
            followUpPending = true
        }
    }

    private func scheduleNextAttempt() {
        cancelPendingTimer()
        guard !isStopped, processClient != nil,
            let fireAt = policy.nextAttemptDate(now: now())
        else {
            return
        }
        let delay = fireAt.timeIntervalSince(now())
        guard delay > 0 else {
            if wakeInFlight {
                followUpPending = true
            } else {
                startWakeAttempt()
            }
            return
        }

        timerGeneration &+= 1
        let expectedTimerGeneration = timerGeneration
        scheduledFireDateForTesting = fireAt
        let nanoseconds = UInt64(min(delay, 86_400 * 365) * 1_000_000_000)
        timerTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self,
                self.timerGeneration == expectedTimerGeneration,
                !self.isStopped
            else {
                return
            }
            self.timerTask = nil
            self.scheduledFireDateForTesting = nil
            self.refreshScheduleFromSnapshot()
        }
    }

    private func startWakeAttempt() {
        guard !isStopped, !wakeInFlight,
            let client = processClient,
            policy.beginAttempt(at: now())
        else {
            scheduleNextAttempt()
            return
        }

        let attemptGeneration = generation
        let attemptRevision = snapshotRevision
        let attemptDay = today()
        wakeInFlight = true
        wakeInFlightForTesting = true
        followUpPending = false
        wakeTask = Task { [weak self] in
            do {
                let response = try await client.snoozeWake()
                self?.finishWakeAttempt(
                    response: response,
                    error: nil,
                    generation: attemptGeneration,
                    snapshotRevision: attemptRevision,
                    day: attemptDay
                )
            } catch {
                self?.finishWakeAttempt(
                    response: nil,
                    error: error,
                    generation: attemptGeneration,
                    snapshotRevision: attemptRevision,
                    day: attemptDay
                )
            }
        }
    }

    private func finishWakeAttempt(
        response: CaptureSnoozeWakeResponse?,
        error: Error?,
        generation attemptGeneration: UInt64,
        snapshotRevision attemptRevision: UInt64,
        day attemptDay: String
    ) {
        wakeTask = nil
        wakeInFlight = false
        wakeInFlightForTesting = false

        // Day rollover invalidates the old day's result authority: an old
        // callback never settles (and so never re-arms) yesterday's timer.
        // Reconfiguration already invalidates via the generation check, and
        // a mid-write snapshot publication invalidates via the revision
        // check, so only an outcome for this generation, this day, and the
        // facts it attempted settles the policy.
        if generation == attemptGeneration, today() == attemptDay {
            if let response, snapshotRevision == attemptRevision {
                switch response.status {
                case .woke, .nothingDue:
                    _ = policy.settle(nextWakeAt: response.nextWakeAt, now: now())
                case .deferred, .skipped, .other:
                    // Non-writing outcomes prove no write happened: Bob's
                    // `deferred`/`skipped` replies carry the prospective
                    // postimage `next_wake_at`, and unknown statuses assert
                    // no successful write. Preserve the previously due
                    // target and its reserved retry deadline until fresh
                    // agenda facts retire or retime it. Never bypass the
                    // writer pin or turn a skip into an explicit request.
                    break
                }
            } else if let clientError = error as? BobClientError,
                case .unsupportedCommand("snooze wake") = clientError
            {
                policy.markUnsupported()
            }
        }

        // Bob owns every wake decision. Refresh even after an error or a
        // valid no-op so the agenda can retire completed work or show a
        // changed pending target.
        agendaStore.refresh(reason: .snoozeWake)

        let hadFollowUp = followUpPending
        followUpPending = false
        if today() != attemptDay {
            // Day rolled over mid-write: drop the old day's facts and any
            // reserved deadline instead of scheduling from them. The update
            // disarms against the new day; an old callback never re-arms
            // yesterday's timer.
            refreshScheduleFromSnapshot()
        } else if hadFollowUp {
            refreshScheduleFromSnapshot()
        } else {
            scheduleNextAttempt()
        }
    }

    private func cancelPendingTimer() {
        timerGeneration &+= 1
        timerTask?.cancel()
        timerTask = nil
        scheduledFireDateForTesting = nil
    }
}
