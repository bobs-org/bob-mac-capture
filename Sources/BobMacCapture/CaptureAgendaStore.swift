import AppKit
import CaptureCore
import Combine
import Foundation

/// Why the agenda refreshed. Every trigger shares the one `agenda` lane.
public enum CaptureAgendaRefreshReason: String, Equatable, Sendable {
    case launch
    case watcher
    case show
    case submit
    case wake
    case unlock
    case dayChanged
    case clockChanged
    case recheck
    case followUp
}

/// Health of the published agenda snapshot.
public enum CaptureAgendaStoreStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    /// The last refresh failed, but the previous snapshot is still today.
    case stale(String)
    /// The last refresh failed with nothing current to show.
    case failed(String)
    /// bob predates `--tasks`: the agenda stays hidden and the
    /// close-comma count comes from the plain `capture-pomodoros` lane.
    case unsupported
}

/// In-memory agenda: the last good decoded snapshot plus the raw stdout
/// bytes it came from. One refresh is in flight at a time on the shared
/// `agenda` lane; byte-identical output is a no-op that publishes
/// nothing. A snapshot whose `date` is not today is never published.
///
/// The close-comma assist reads `currentTaskLinkCount`, which follows the
/// snapshot while bob supports `--tasks` and the plain lane while it does
/// not. It is nil when the snapshot is not today's, or when the latest
/// refresh failed, exactly as the old per-show spawn cleared it.
@MainActor
public final class CaptureAgendaStore: ObservableObject {
    @Published public private(set) var snapshot: CaptureAgendaSnapshot?
    @Published public private(set) var status: CaptureAgendaStoreStatus = .idle
    @Published public private(set) var lastRefreshedAt: Date?
    @Published public private(set) var currentTaskLinkCount: Int?

    /// The client refreshes run against. Replacing it invalidates
    /// in-flight results and clears the count; callers then `reset()`
    /// (Recheck Bob, executable change) or `refresh(reason:)` explicitly.
    public var processClient: BobProcessClient? {
        didSet {
            guard processClient !== oldValue else {
                return
            }
            state.invalidateInFlight()
            currentTaskLinkCount = nil
        }
    }

    /// Absolute vault root the relevance filter resolves batches against.
    public var vaultRootPath: String

    private var state = CaptureAgendaRefreshState()
    private var lastGoodSnapshot: CaptureAgendaSnapshot?
    private let today: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let workspaceCenter: NotificationCenter
    private let defaultCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    public init(
        processClient: BobProcessClient? = nil,
        vaultRootPath: String = "",
        today: @Sendable @escaping () -> String = CaptureAgendaStore.localToday,
        now: @Sendable @escaping () -> Date = { Date() },
        workspaceCenter: NotificationCenter? = nil,
        defaultCenter: NotificationCenter = .default
    ) {
        self.processClient = processClient
        self.vaultRootPath = vaultRootPath
        self.today = today
        self.now = now
        self.workspaceCenter = workspaceCenter ?? NSWorkspace.shared.notificationCenter
        self.defaultCenter = defaultCenter
        state.today = today
        startObservers()
    }

    deinit {
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            defaultCenter.removeObserver(observer)
        }
    }

    /// The app's local `yyyy-MM-dd` for the snapshot date guard.
    public nonisolated static func localToday() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Refreshes on every trigger in §2: launch, filtered vault events,
    /// show (stale-while-revalidate), submit, wake, unlock, day and clock
    /// changes, and Recheck Bob. A trigger during a refresh schedules
    /// exactly one follow-up.
    public func refresh(reason: CaptureAgendaRefreshReason) {
        guard let client = processClient else {
            return
        }
        guard let generation = state.begin() else {
            return
        }
        if state.capability == .unsupported {
            refreshPlainCount(generation: generation, client: client)
            return
        }
        if !hasCurrentSnapshot {
            status = .loading
        }
        let previous = state.lastBytes
        Task { [weak self] in
            do {
                let fetch = try await client.captureAgenda(previous: previous)
                await MainActor.run {
                    self?.finishAgenda(fetch, generation: generation)
                }
            } catch let clientError as BobClientError {
                await MainActor.run {
                    self?.finishClientError(
                        clientError,
                        generation: generation,
                        client: client
                    )
                }
            } catch {
                await MainActor.run {
                    self?.finishFailure(
                        String(describing: error),
                        generation: generation
                    )
                }
            }
        }
    }

    /// Feeds one watcher batch to the relevance filter; only accepted
    /// batches refresh, whether or not the panel is visible.
    public func vaultDidChange(_ batch: VaultChangeBatch) {
        guard CaptureAgendaRefreshFilter.isRelevant(
            batch,
            vaultRoot: vaultRootPath
        ) else {
            return
        }
        refresh(reason: .watcher)
    }

    /// Clears the snapshot, bytes, and capability verdict, then refreshes,
    /// so `--tasks` is retried fresh after Recheck Bob or a settings
    /// change. In-flight results are discarded by the generation bump.
    public func reset() {
        state.reset()
        snapshot = nil
        lastGoodSnapshot = nil
        currentTaskLinkCount = nil
        status = .idle
        lastRefreshedAt = nil
        refresh(reason: .recheck)
    }

    private var hasCurrentSnapshot: Bool {
        guard let lastGoodSnapshot else {
            return false
        }
        return state.isCurrent(lastGoodSnapshot)
    }

    private func finishAgenda(
        _ fetch: CaptureAgendaFetch,
        generation: UInt64
    ) {
        let completion = state.end(generation: generation)
        guard completion != .discarded else {
            return
        }
        state.capability = .supported
        switch fetch {
        case .unchanged:
            lastRefreshedAt = now()
            if hasCurrentSnapshot {
                status = .ready
            }
        case .changed(let fetched, let bytes):
            state.lastBytes = bytes
            lastGoodSnapshot = fetched
            lastRefreshedAt = now()
            if state.isCurrent(fetched) {
                publish(fetched)
                status = .ready
            } else {
                snapshot = nil
                currentTaskLinkCount = nil
                status = .loading
            }
        }
        if completion == .followUp {
            refresh(reason: .followUp)
        }
    }

    private func publish(_ fetched: CaptureAgendaSnapshot) {
        if snapshot != fetched {
            snapshot = fetched
        }
        let count = fetched.currentTaskLinkCount
        if currentTaskLinkCount != count {
            currentTaskLinkCount = count
        }
    }

    private func finishClientError(
        _ error: BobClientError,
        generation: UInt64,
        client: BobProcessClient
    ) {
        switch error {
        case .unsupportedOption:
            // An old bob without `--tasks`: hide the agenda, remember not
            // to retry it, and keep the count on the plain lane only. The
            // generation stays open across the plain call, so one `end`
            // still covers the whole refresh unit.
            state.capability = .unsupported
            snapshot = nil
            status = .unsupported
            refreshPlainCount(generation: generation, client: client)
        default:
            finishFailure(String(describing: error), generation: generation)
        }
    }

    private func finishFailure(
        _ message: String,
        generation: UInt64
    ) {
        let completion = state.end(generation: generation)
        guard completion != .discarded else {
            return
        }
        // A failed refresh keeps the last good agenda but clears the
        // count, exactly as the old failed spawn cleared it.
        currentTaskLinkCount = nil
        if hasCurrentSnapshot {
            status = .stale(message)
        } else {
            snapshot = nil
            status = .failed(message)
        }
        if completion == .followUp {
            refresh(reason: .followUp)
        }
    }

    /// Old-bob fallback: the plain call serves the close-comma count
    /// only, and `--tasks` is not retried until `reset()`.
    private func refreshPlainCount(
        generation: UInt64,
        client: BobProcessClient
    ) {
        Task { [weak self] in
            let count = try? await client.capturePomodoros()
            await MainActor.run {
                self?.finishPlainCount(
                    count?.currentTaskLinkCount,
                    generation: generation
                )
            }
        }
    }

    private func finishPlainCount(
        _ count: Int?,
        generation: UInt64
    ) {
        let completion = state.end(generation: generation)
        guard completion != .discarded else {
            return
        }
        // A reset in between clears the capability and the stale end
        // discards us, so only a still-unsupported store takes the count.
        if state.capability == .unsupported {
            currentTaskLinkCount = count
        }
        if completion == .followUp {
            refresh(reason: .followUp)
        }
    }

    private func startObservers() {
        let workspace = workspaceCenter
        let center = defaultCenter
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { [weak self] in
                    await MainActor.run {
                        self?.refresh(reason: .wake)
                    }
                }
            }
        )
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { [weak self] in
                    await MainActor.run {
                        self?.refresh(reason: .unlock)
                    }
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: .NSCalendarDayChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { [weak self] in
                    await MainActor.run {
                        self?.refresh(reason: .dayChanged)
                    }
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: .NSSystemClockDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { [weak self] in
                    await MainActor.run {
                        self?.refresh(reason: .clockChanged)
                    }
                }
            }
        )
    }
}
