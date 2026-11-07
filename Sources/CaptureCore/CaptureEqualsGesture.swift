import Foundation

/// Shared key-to-key window for a fast second `=` that types one literal `=`.
/// The card arms it after an `=` flip; later phases reuse it on the editor
/// and picker.
public enum CaptureEqualsGesture {
    /// Maximum delay from the first `=` key-down to the second, measured
    /// from `NSEvent.timestamp`.
    public static let window: TimeInterval = 0.350

    /// Whether `second` is a fast follow-up of `first`. Synthesized events
    /// (`timestamp == 0`) never qualify, and neither do auto-repeats.
    public static func isFastSecond(
        first: TimeInterval,
        second: TimeInterval,
        isRepeat: Bool = false
    ) -> Bool {
        guard !isRepeat, first > 0, second > 0, second >= first else {
            return false
        }
        // NSEvent timestamps are binary TimeIntervals; 0.350 is not exact,
        // so a one-nanosecond slack keeps the named 350 ms boundary inside.
        return second - first <= window + 1e-9
    }
}
