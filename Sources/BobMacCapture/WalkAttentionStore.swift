import AppKit
import CaptureCore
import Combine
import Foundation

/// Why the independent walks attention lane refreshed.
public enum WalkAttentionRefreshReason: Equatable, Sendable {
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

/// Health of the last good same-day walks report.
public enum WalkAttentionStoreStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case stale(String)
    case failed(String)
    case unsupported
}

/// In-memory, date-guarded `bob walks` snapshot. The command runs on the
/// client's own `walks` lane; it never shares or delays the agenda request.
@MainActor
public final class WalkAttentionStore: ObservableObject {
    @Published public private(set) var snapshot: WalkAttentionSnapshot?
    @Published public private(set) var status: WalkAttentionStoreStatus = .idle
    @Published public private(set) var lastRefreshedAt: Date?

    /// The client refreshes run against. Replacing it invalidates in-flight
    /// results; callers use `reset()` for Recheck Bob and executable changes.
    public var processClient: BobProcessClient? {
        didSet {
            guard processClient !== oldValue else {
                return
            }
            state.invalidateInFlight()
        }
    }

    /// Absolute vault root used by the same filtered event contract as agenda.
    public var vaultRootPath: String

    private var state = CaptureAgendaRefreshState()
    private var lastGoodSnapshot: WalkAttentionSnapshot?
    private var lastSuccessAt: Date?
    private var isPanelVisible = false
    private var dirty = true
    private var debounceTask: Task<Void, Never>?
    private let today: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let debounceInterval: @Sendable (Bool) -> TimeInterval
    private let workspaceCenter: NotificationCenter
    private let defaultCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    public init(
        processClient: BobProcessClient? = nil,
        vaultRootPath: String = "",
        today: @Sendable @escaping () -> String = CaptureAgendaStore.localToday,
        now: @Sendable @escaping () -> Date = { Date() },
        debounceInterval: @Sendable @escaping (Bool) -> TimeInterval = {
            WalkAttentionRefreshPolicy.debounceInterval(visible: $0)
        },
        workspaceCenter: NotificationCenter? = nil,
        defaultCenter: NotificationCenter = .default
    ) {
        self.processClient = processClient
        self.vaultRootPath = vaultRootPath
        self.today = today
        self.now = now
        self.debounceInterval = debounceInterval
        self.workspaceCenter = workspaceCenter ?? NSWorkspace.shared.notificationCenter
        self.defaultCenter = defaultCenter
        state.today = today
        startObservers()
    }

    deinit {
        debounceTask?.cancel()
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            defaultCenter.removeObserver(observer)
        }
    }

    /// The panel reports visibility through CapturePanelModel. On show,
    /// reuse a fresh cache; dirty, missing, or 60-second-old data refreshes.
    public func panelVisibilityDidChange(_ visible: Bool) {
        guard visible != isPanelVisible else {
            return
        }
        isPanelVisible = visible
        if visible {
            cancelDebounce()
            refresh(reason: .show)
        } else if dirty, debounceTask != nil {
            // A pending event is now hidden; use the hidden trailing delay.
            scheduleVaultRefresh()
        }
    }

    /// Feeds a watcher batch to the agenda's exact relevance filter, then
    /// applies the visible/hidden trailing debounce for this whole-vault scan.
    public func vaultDidChange(_ batch: VaultChangeBatch) {
        guard CaptureAgendaRefreshFilter.isRelevant(batch, vaultRoot: vaultRootPath) else {
            return
        }
        dirty = true
        scheduleVaultRefresh()
    }

    /// Refreshes immediately for lifecycle and mutation triggers. A show is
    /// conditional on the cache age/dirty flag; a trigger in flight queues at
    /// most one follow-up through CaptureAgendaRefreshState.
    public func refresh(reason: WalkAttentionRefreshReason) {
        guard let client = processClient else {
            return
        }
        if reason == .show {
            guard state.capability != .unsupported,
                WalkAttentionRefreshPolicy.shouldRefreshOnShow(
                    dirty: dirty || !hasCurrentSnapshot,
                    lastSuccess: lastSuccessAt,
                    now: now()
                )
            else {
                return
            }
        } else {
            guard reason == .recheck || state.capability != .unsupported else {
                return
            }
            dirty = true
        }
        cancelDebounce()
        guard let generation = state.begin() else {
            return
        }
        if !hasCurrentSnapshot {
            status = .loading
        }
        let previous = state.lastBytes
        Task { [weak self] in
            do {
                let fetch = try await client.walkAttention(previous: previous)
                await MainActor.run {
                    self?.finish(fetch, generation: generation)
                }
            } catch let error as BobClientError {
                await MainActor.run {
                    self?.finish(error, generation: generation)
                }
            } catch {
                await MainActor.run {
                    self?.finishFailure(String(describing: error), generation: generation)
                }
            }
        }
    }

    /// Clears the cached report and capability verdict before Recheck Bob.
    public func reset() {
        cancelDebounce()
        state.reset()
        snapshot = nil
        lastGoodSnapshot = nil
        lastSuccessAt = nil
        lastRefreshedAt = nil
        dirty = true
        status = .idle
        refresh(reason: .recheck)
    }

    /// One-line Settings diagnostic. It contains status and the latest
    /// successful refresh time, or the actionable error/upgrade hint.
    public func diagnosticLine() -> String {
        Self.diagnosticLine(status: status, lastRefreshedAt: lastRefreshedAt)
    }

    public static func diagnosticLine(
        status: WalkAttentionStoreStatus,
        lastRefreshedAt: Date?
    ) -> String {
        switch status {
        case .unsupported:
            return "Upgrade bob for walk marks"
        case .stale(let message), .failed(let message):
            return "Walk marks couldn't refresh: \(message)"
        case .loading:
            if let lastRefreshedAt {
                let timestamp = clockFormatter.string(from: lastRefreshedAt)
                return "Refreshing walk marks · last refreshed \(timestamp)"
            }
            return "Loading walk marks…"
        case .idle:
            return "Walk marks haven't refreshed yet"
        case .ready:
            if let lastRefreshedAt {
                return "Walk marks refreshed \(clockFormatter.string(from: lastRefreshedAt))"
            }
            return "Walk marks are ready"
        }
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var hasCurrentSnapshot: Bool {
        guard let lastGoodSnapshot else {
            return false
        }
        return state.isCurrent(lastGoodSnapshot)
    }

    private func scheduleVaultRefresh() {
        cancelDebounce()
        let delay = max(0, debounceInterval(isPanelVisible))
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self else {
                return
            }
            self.debounceTask = nil
            self.refresh(reason: .watcher)
        }
    }

    private func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func finish(_ fetch: WalkAttentionFetch, generation: UInt64) {
        let completion = state.end(generation: generation)
        guard completion != .discarded else {
            return
        }
        state.capability = .supported
        switch fetch {
        case .unchanged:
            lastSuccessAt = now()
            lastRefreshedAt = lastSuccessAt
            if hasCurrentSnapshot, let lastGoodSnapshot {
                snapshot = lastGoodSnapshot
                status = .ready
            }
        case .changed(let fetched, let bytes):
            state.lastBytes = bytes
            lastGoodSnapshot = fetched
            lastSuccessAt = now()
            lastRefreshedAt = lastSuccessAt
            if state.isCurrent(fetched) {
                if snapshot != fetched {
                    snapshot = fetched
                }
                status = .ready
            } else {
                snapshot = nil
                status = .loading
            }
        }
        dirty = completion == .followUp || !hasCurrentSnapshot
        if completion == .followUp {
            refresh(reason: .followUp)
        }
    }

    private func finish(_ error: BobClientError, generation: UInt64) {
        guard state.isCurrentGeneration(generation) else {
            return
        }
        if case .unsupportedCommand("walks") = error {
            let completion = state.end(generation: generation)
            guard completion != .discarded else {
                return
            }
            state.capability = .unsupported
            snapshot = nil
            status = .unsupported
            dirty = false
            if completion == .followUp {
                // An unsupported executable cannot satisfy a queued scan;
                // keep it dirty for Recheck Bob instead of spinning.
                dirty = true
            }
            return
        }
        finishFailure(String(describing: error), generation: generation)
    }

    private func finishFailure(_ message: String, generation: UInt64) {
        let completion = state.end(generation: generation)
        guard completion != .discarded else {
            return
        }
        dirty = true
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

    private func startObservers() {
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh(reason: .wake)
                }
            }
        )
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh(reason: .unlock)
                }
            }
        )
        observers.append(
            defaultCenter.addObserver(
                forName: .NSCalendarDayChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh(reason: .dayChanged)
                }
            }
        )
        observers.append(
            defaultCenter.addObserver(
                forName: .NSSystemClockDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh(reason: .clockChanged)
                }
            }
        )
    }
}
