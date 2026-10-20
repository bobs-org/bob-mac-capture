import Foundation

/// Small testable orchestration for `AppDelegate.refreshTargetsWhenPossible`:
/// one injected instant decides the show-window skip and records the start,
/// so a show inside the five-second window skips while launch, watcher,
/// recheck, and failure-recovery always run.
struct CaptureTargetsRefreshGate: Sendable {
    var lastStartedAt: Date?
    var now: @Sendable () -> Date = Date.init

    /// Returns true when the refresh should run, recording the start.
    /// Uses a single `now()` for both the skip decision and the record.
    mutating func shouldRefresh(reason: CaptureTargetsRefreshReason) -> Bool {
        let current = now()
        if reason == .show,
           CaptureShowRefreshWindow.shouldSkipShowTriggeredRefresh(
               lastStartedAt: lastStartedAt,
               now: current
           )
        {
            return false
        }
        lastStartedAt = current
        return true
    }
}
