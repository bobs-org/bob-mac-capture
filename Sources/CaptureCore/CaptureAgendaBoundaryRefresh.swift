import Foundation

/// Whether a calendar boundary refresh should fire now or after a sleep.
public enum CaptureAgendaBoundaryRefreshDecision: Equatable, Sendable {
    case none
    case immediate
    case sleep(TimeInterval)
}

/// Keeps an already-fired calendar boundary from immediately refreshing again.
public enum CaptureAgendaBoundaryRefresh {
    public static func decision(
        refreshAt: Date?,
        lastFiredBoundary: Date?,
        now: Date
    ) -> CaptureAgendaBoundaryRefreshDecision {
        guard let refreshAt, refreshAt != lastFiredBoundary else {
            return .none
        }
        let delay = refreshAt.timeIntervalSince(now)
        return delay <= 0 ? .immediate : .sleep(delay)
    }
}
