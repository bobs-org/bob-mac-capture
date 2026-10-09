import Foundation

/// Pure single-flight refresh orchestration for the agenda store: one
/// refresh in flight at a time, a trigger during a refresh schedules
/// exactly one follow-up, and a generation counter discards results that
/// started before a reset (Recheck Bob, vault or executable change).
public struct CaptureAgendaRefreshState: Sendable {
    /// Whether this executable is known to support `--tasks`.
    public enum Capability: Equatable, Sendable {
        case unknown
        case supported
        case unsupported
    }

    /// How a finished refresh resolves against the current generation.
    public enum Completion: Equatable, Sendable {
        /// The result is current; the store may publish it.
        case done
        /// The result is current and a trigger arrived mid-flight, so
        /// the store must refresh once more.
        case followUp
        /// The result started before a reset; the store must drop it.
        case discarded
    }

    public var capability: Capability = .unknown
    public var lastBytes: Data?
    public private(set) var generation: UInt64 = 0
    public private(set) var isRefreshing = false
    public private(set) var followUpQueued = false
    /// The app's local `yyyy-MM-dd`, injected so tests pin the date.
    public var today: @Sendable () -> String = { "" }

    public init() {}

    /// Starts a refresh. Returns the generation the completion must
    /// present to `end`, or nil when a refresh is already in flight
    /// (exactly one follow-up is then queued). Queued triggers never bump
    /// the generation: only a started refresh owns one, so the in-flight
    /// result still completes instead of discarding itself as stale.
    public mutating func begin() -> UInt64? {
        if isRefreshing {
            followUpQueued = true
            return nil
        }
        generation &+= 1
        isRefreshing = true
        return generation
    }

    /// Finishes the refresh started by `begin`. A stale generation is
    /// discarded without touching the in-flight flags, so a reset
    /// followed by a new refresh is never cancelled by the old result.
    public mutating func end(generation: UInt64) -> Completion {
        guard generation == self.generation else {
            return .discarded
        }
        let followUp = followUpQueued
        isRefreshing = false
        followUpQueued = false
        return followUp ? .followUp : .done
    }

    /// Drops in-flight results, queued follow-ups, cached bytes, and the
    /// capability verdict, so the next refresh retries `--tasks` fresh.
    public mutating func reset() {
        generation &+= 1
        isRefreshing = false
        followUpQueued = false
        lastBytes = nil
        capability = .unknown
    }

    /// Invalidates in-flight results without clearing the cached bytes
    /// or the capability verdict (the executable did not change).
    public mutating func invalidateInFlight() {
        generation &+= 1
        isRefreshing = false
        followUpQueued = false
    }

    /// The date guard: a snapshot whose `date` is not today is never
    /// shown. A missing date never counts as today.
    public func isCurrent(_ snapshot: CaptureAgendaSnapshot) -> Bool {
        guard let date = snapshot.date else {
            return false
        }
        return date == today()
    }
}
