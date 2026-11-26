import Foundation

/// Whether a calendar boundary refresh should fire now or after a sleep.
public enum CaptureAgendaBoundaryRefreshDecision: Equatable, Sendable {
    case none
    case immediate
    case sleep(TimeInterval)
}

/// Keeps an already-fired calendar boundary from immediately refreshing again.
public enum CaptureAgendaBoundaryRefresh {
    /// Chooses the earliest unfired boundary from independent calendar and
    /// snooze facts. The caller owns parsing because Calendar's date strings
    /// are local while Bob's wake instants carry an explicit UTC offset.
    public static func earliestUnfired(
        calendarBoundary: Date?,
        snoozeBoundary: Date?,
        firedBoundaries: Set<Date>
    ) -> Date? {
        [calendarBoundary, snoozeBoundary]
            .compactMap { $0 }
            .filter { !firedBoundaries.contains($0) }
            .min()
    }

    public static func decision(
        refreshAt: Date?,
        lastFiredBoundary: Date?,
        now: Date
    ) -> CaptureAgendaBoundaryRefreshDecision {
        decision(
            refreshAt: refreshAt,
            firedBoundaries: lastFiredBoundary.map { Set([$0]) } ?? [],
            now: now
        )
    }

    public static func decision(
        refreshAt: Date?,
        firedBoundaries: Set<Date>,
        now: Date
    ) -> CaptureAgendaBoundaryRefreshDecision {
        guard let refreshAt, !firedBoundaries.contains(refreshAt) else {
            return .none
        }
        let delay = refreshAt.timeIntervalSince(now)
        return delay <= 0 ? .immediate : .sleep(delay)
    }
}
