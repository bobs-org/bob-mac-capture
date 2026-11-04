import Foundation

/// Pure five-minute boundary math for past-work preview refresh. Bob drops
/// seconds before ceiling to the next five-minute anchor (`T = ceil5(now)`),
/// so the app sleeps until the next strict multiple of 300 seconds since the
/// Unix epoch and then asks Bob again. Local clock arithmetic only decides
/// *when* to request; every displayed window comes from Bob's new response.
public enum CapturePastBoundary {
    public static let intervalSeconds: TimeInterval = 300

    /// The next strict five-minute boundary after `date`.
    public static func nextBoundary(after date: Date) -> Date {
        let epoch = date.timeIntervalSince1970
        let floored = floor(epoch / intervalSeconds) * intervalSeconds
        // Strictly after: an exact boundary sleeps a full interval.
        let next = (floored >= epoch ? floored : floored + intervalSeconds)
        let adjusted = next <= epoch ? next + intervalSeconds : next
        return Date(timeIntervalSince1970: adjusted)
    }

    /// Nanoseconds to sleep from `now` until the next boundary.
    public static func sleepNanoseconds(
        now: Date,
        calendar _: Calendar = .current
    ) -> UInt64 {
        let next = nextBoundary(after: now)
        let delay = max(0, next.timeIntervalSince(now))
        return UInt64(delay * 1_000_000_000)
    }

    /// True when a past refresh should be armed: the panel is visible, the
    /// preview is a current past preview, and Bob's client is still current.
    public static func shouldArm(
        panelVisible: Bool,
        hasPastGroups: Bool
    ) -> Bool {
        panelVisible && hasPastGroups
    }
}
