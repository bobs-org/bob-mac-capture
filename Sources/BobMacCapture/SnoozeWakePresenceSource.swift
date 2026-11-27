import AppKit
import CaptureCore
import CoreGraphics
import Foundation

/// macOS presence adapter sampling the four away signals. Ordinary app
/// deactivation is not away and is deliberately absent here. Lock, sleep,
/// session, and clock events arrive through injected centers; idle time
/// is sampled live on every read, and a 2-second poll runs only while
/// work is held.
///
/// Initial state assumes a present session: launch itself implies an
/// interactive user with awake displays and an unlocked screen, and the
/// first lock/sleep/resign event corrects it. Idle is sampled
/// immediately at start, not merely on subsequent ticks.
@MainActor
final class SnoozeWakePresenceSource {
    static let idlePollInterval: TimeInterval = 2

    /// Fired on every presence-relevant signal: lock/unlock, display
    /// sleep/wake, session resign/active, day/clock change, and each
    /// idle-poll tick while held.
    var onChange: () -> Void = {}
    /// Lifecycle and clock signals clear a bounded retry delay before
    /// `onChange` asks the coordinator to reevaluate.
    var onLifecycleChange: () -> Void = {}

    private let workspaceCenter: NotificationCenter
    private let defaultCenter: NotificationCenter
    private let distributedCenter: DistributedNotificationCenter
    private let idleSampler: () -> TimeInterval
    private var observers: [NSObjectProtocol] = []
    private var idleTimer: Timer?
    private var idlePolling = false

    private var screenLocked = false
    private var displaysAsleep = false
    private var sessionInactive = false

    init(
        workspaceCenter: NotificationCenter? = nil,
        defaultCenter: NotificationCenter = .default,
        distributedCenter: DistributedNotificationCenter? = nil,
        idleSampler: (() -> TimeInterval)? = nil
    ) {
        self.workspaceCenter = workspaceCenter ?? NSWorkspace.shared.notificationCenter
        self.defaultCenter = defaultCenter
        self.distributedCenter = distributedCenter ?? DistributedNotificationCenter.default()
        if let idleSampler {
            self.idleSampler = idleSampler
        } else {
            self.idleSampler = {
                CGEventSource.secondsSinceLastEventType(
                    .combinedSessionState, eventType: .null)
            }
        }
    }

    func start() {
        stopObservers()
        let workspace = workspaceCenter
        let center = defaultCenter
        let distributed = distributedCenter

        func observe(
            _ notificationCenter: NotificationCenter, _ name: Notification.Name,
            _ update: @escaping () -> Void
        ) {
            observers.append(
                notificationCenter.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    update()
                    self?.onLifecycleChange()
                    self?.onChange()
                })
        }

        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.displaysAsleep = true
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.displaysAsleep = false
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.sessionInactive = true
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.sessionInactive = false
        }
        observe(center, .NSCalendarDayChanged) {}
        observe(center, .NSSystemClockDidChange) {}

        observers.append(
            distributed.addObserver(
                forName: .screenIsLocked, object: nil, queue: .main
            ) { [weak self] _ in
                self?.screenLocked = true
                self?.onLifecycleChange()
                self?.onChange()
            })
        observers.append(
            distributed.addObserver(
                forName: .screenIsUnlocked, object: nil, queue: .main
            ) { [weak self] _ in
                self?.screenLocked = false
                self?.onLifecycleChange()
                self?.onChange()
            })
    }

    func stop() {
        stopObservers()
        setIdlePollingActive(false)
        screenLocked = false
        displaysAsleep = false
        sessionInactive = false
    }

    /// Starts or stops the 2-second idle poll. The coordinator enables
    /// it only while work is held and disables it when the queue
    /// empties; every tick re-samples idle and fires `onChange`.
    func setIdlePollingActive(_ active: Bool) {
        if active == idlePolling {
            return
        }
        idlePolling = active
        idleTimer?.invalidate()
        idleTimer = nil
        if active {
            let timer = Timer.scheduledTimer(
                withTimeInterval: Self.idlePollInterval, repeats: true
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onChange()
                }
            }
            idleTimer = timer
        }
    }

    var isIdlePolling: Bool {
        idlePolling
    }

    /// The current presence: stored lock/sleep/session flags plus a
    /// live idle sample.
    func currentPresence() -> SnoozeWakePresence {
        SnoozeWakePresence(
            screenLocked: screenLocked,
            displaysAsleep: displaysAsleep,
            sessionInactive: sessionInactive,
            idleSeconds: max(0, idleSampler())
        )
    }

    /// Test seam: drive one signal without posting a notification.
    func simulateSignalForTests(_ update: (SnoozeWakePresenceSource) -> Void) {
        update(self)
    }

    func setScreenLockedForTests(_ locked: Bool) {
        screenLocked = locked
    }

    func setDisplaysAsleepForTests(_ asleep: Bool) {
        displaysAsleep = asleep
    }

    func setSessionInactiveForTests(_ inactive: Bool) {
        sessionInactive = inactive
    }

    private func stopObservers() {
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            defaultCenter.removeObserver(observer)
            distributedCenter.removeObserver(observer)
        }
        observers = []
    }
}

extension Notification.Name {
    fileprivate static let screenIsLocked = Notification.Name("com.apple.screenIsLocked")
    fileprivate static let screenIsUnlocked = Notification.Name("com.apple.screenIsUnlocked")
}
