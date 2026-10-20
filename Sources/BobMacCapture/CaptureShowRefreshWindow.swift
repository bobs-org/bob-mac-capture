import Foundation

/// Why `AppDelegate` refreshes the capture-targets cache.
enum CaptureTargetsRefreshReason: Equatable, Sendable {
    case launch
    case show
    case watcher
    case recheck
    case failureRecovery
}

/// Shared 5 s window for show-triggered Capture refreshes, named after
/// `RefsLibrary.pullThrottleInterval` so Capture and Refs use one constant.
enum CaptureShowRefreshWindow {
    static let pullThrottleInterval = RefsLibrary.pullThrottleInterval

    /// Show-triggered refreshes skip when the last spawn started inside
    /// the window. Launch, watcher, Recheck Bob, submit, mutation, and
    /// failure-recovery calls always run.
    static func shouldSkipShowTriggeredRefresh(lastStartedAt: Date?, now: Date) -> Bool {
        guard let lastStartedAt else {
            return false
        }
        return now.timeIntervalSince(lastStartedAt) < pullThrottleInterval
    }
}
