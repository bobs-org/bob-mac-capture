import Foundation

/// Pure presentation model for a Pomodoro whole-session shift (`pomodoro_shift`
/// present on a `bob capture --format json` success), built once from
/// `CaptureCommandSuccess` so the SwiftUI layer never branches on
/// shift-specific JSON fields or recomputes clock math.
/// The preview's only source of truth is Bob's resolved `pomodoro_shift`
/// object — which itself comes from `bob capture --dry-run --no-clip --format
/// json` for live preview and the same command without `--dry-run`/`--no-clip`
/// for submission — so there is no Swift-side clock or ledger logic here, only
/// wording.
///
/// Wording mirrors `print_human_pomodoro_shift_success` in
/// `src/native/capture.rs` (`would shift` / `shifted`, before/after timing,
/// minute effect with later/earlier, `at line N`) so the panel and the CLI
/// describe the same shift the same way. Works for dry-run previews and
/// committed captures alike; `isDryRun` is the only thing that changes the
/// verb.
public struct CapturePomodoroShiftPresentation: Equatable, Sendable {
    public let isDryRun: Bool
    public let pomodoroName: String
    public let beforeStart: String
    public let beforeEnd: String
    public let afterStart: String
    public let afterEnd: String
    public let durationMinutes: Int
    public let deltaMinutes: Int
    public let requestedUnits: Int
    public let later: Bool
    public let pomodoroLine: Int
    public let timeRange: String

    /// `"Would shift FOCUS 0900-0925 to 0915-0940 (25m), 15m later at line 5"`
    /// (dry run) or `"Shifted … at line 5"` (committed).
    public let statusText: String
    /// `"0900-0925 → 0915-0940 (25m), 15m later"` — the calm, legible
    /// before-to-after line shown in preview.
    public let sessionText: String
    /// `"FOCUS · line 5"`.
    public let destinationText: String
    /// Doubled chevron echoing the doubled sign: `chevron.forward.2` for
    /// later, `chevron.backward.2` for earlier.
    public let symbolName: String
    public let accessibilitySummary: String
    public let notificationDetail: String

    public init?(capture: CaptureCommandSuccess) {
        guard let summary = capture.pomodoroShift else {
            return nil
        }
        self.init(summary: summary, dryRun: capture.dryRun)
    }

    public init(summary: PomodoroShiftSummary, dryRun: Bool) {
        isDryRun = dryRun
        pomodoroName = summary.pomodoroName ?? "current session"
        beforeStart = summary.beforeStart
        beforeEnd = summary.beforeEnd
        afterStart = summary.afterStart
        afterEnd = summary.afterEnd
        durationMinutes = summary.durationMinutes
        deltaMinutes = summary.deltaMinutes
        requestedUnits = summary.requestedUnits
        later = summary.direction == "later"
        pomodoroLine = summary.pomodoroLine
        timeRange = summary.timeRange

        let verb = dryRun ? "Would shift" : "Shifted"
        let directionWord = later ? "later" : "earlier"
        let magnitude = abs(summary.deltaMinutes)
        let before = "\(summary.beforeStart)-\(summary.beforeEnd)"
        let after = "\(summary.afterStart)-\(summary.afterEnd)"
        statusText =
            "\(verb) \(pomodoroName) \(before) to \(after) (\(summary.durationMinutes)m), \(magnitude)m \(directionWord) at line \(summary.pomodoroLine)"
        sessionText = "\(before) → \(after) (\(summary.durationMinutes)m), \(magnitude)m \(directionWord)"
        destinationText = "\(pomodoroName) · line \(summary.pomodoroLine)"
        symbolName = later ? "chevron.forward.2" : "chevron.backward.2"
        let spokenDirection = later ? "later" : "earlier"
        accessibilitySummary =
            "Shifts \(pomodoroName), \(summary.beforeStart)-\(summary.beforeEnd), to \(summary.afterStart)-\(summary.afterEnd), \(summary.durationMinutes) minutes, \(magnitude) minutes \(spokenDirection), line \(summary.pomodoroLine)"
        notificationDetail = statusText
    }
}
