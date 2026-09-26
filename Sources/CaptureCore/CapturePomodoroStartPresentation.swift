import Foundation

/// Pure presentation model for an atomic Pomodoro start (`pomodoro_start` present on a
/// `bob capture --format json` success), built once from `CaptureCommandSuccess` so the
/// SwiftUI layer never branches on start-specific JSON fields or recomputes clock math.
/// The preview's only source of truth is Bob's resolved `pomodoro_start` object — which
/// itself comes from `bob capture --dry-run --no-clip --format json` for live preview
/// and the same command without `--dry-run`/`--no-clip` for submission — so there is no
/// Swift-side clock or ledger logic here, only wording.
///
/// Wording mirrors `print_human_success` in `src/native/capture.rs` (`would start` /
/// `started`, `(created)`, `at line N`) so the panel and the CLI describe the same
/// session the same way. Works for dry-run previews and committed captures alike;
/// `isDryRun` is the only thing that changes the verb.
public struct CapturePomodoroStartPresentation: Equatable, Sendable {
    public let isDryRun: Bool
    public let pomodoroName: String
    public let start: String
    public let end: String
    public let durationMinutes: Int
    public let offsetUnits: Int
    public let pomodoroLine: Int
    public let createdPomodoro: Bool
    public let timeRange: String

    /// `"Would start deep 0930-0955 (25m) at line 12"` (dry run) or
    /// `"Started deep 0930-0955 (25m) (created) at line 12"`.
    public let statusText: String
    /// `"0930-0955 (25m)"` — the calm, legible session line shown in preview.
    public let sessionText: String
    /// `"deep · line 12"` or `"deep · line 12 · created entry"`.
    public let destinationText: String
    public let accessibilitySummary: String
    public let notificationDetail: String

    public init?(capture: CaptureCommandSuccess) {
        guard let summary = capture.pomodoroStart else {
            return nil
        }
        self.init(summary: summary, dryRun: capture.dryRun)
    }

    public init(summary: PomodoroStartSummary, dryRun: Bool) {
        isDryRun = dryRun
        pomodoroName = summary.pomodoroName ?? "next session"
        start = summary.start
        end = summary.end
        durationMinutes = summary.durationMinutes
        offsetUnits = summary.offsetUnits
        pomodoroLine = summary.pomodoroLine
        createdPomodoro = summary.createdPomodoro
        timeRange = summary.timeRange

        let verb = dryRun ? "Would start" : "Started"
        let created = summary.createdPomodoro ? " (created)" : ""
        statusText =
            "\(verb) \(pomodoroName) \(start)-\(end) (\(durationMinutes)m)\(created) at line \(pomodoroLine)"
        sessionText = "\(start)-\(end) (\(durationMinutes)m)"
        destinationText = summary.createdPomodoro
            ? "\(pomodoroName) · line \(pomodoroLine) · created entry"
            : "\(pomodoroName) · line \(pomodoroLine)"
        let createdPhrase = summary.createdPomodoro ? ", created new entry" : ", uses existing entry"
        accessibilitySummary =
            "Starts \(pomodoroName), \(start) to \(end), \(durationMinutes) minutes, line \(pomodoroLine)\(createdPhrase)"
        notificationDetail = statusText
    }
}
