import Foundation

/// Pure presentation model for a Pomodoro duration adjustment (`pomodoro_adjust`
/// present on a `bob capture --format json` success), built once from
/// `CaptureCommandSuccess` so the SwiftUI layer never branches on
/// adjustment-specific JSON fields or recomputes clock math.
/// The preview's only source of truth is Bob's resolved `pomodoro_adjust`
/// object — which itself comes from `bob capture --dry-run --no-clip --format
/// json` for live preview and the same command without `--dry-run`/`--no-clip`
/// for submission — so there is no Swift-side clock or ledger logic here, only
/// wording.
///
/// Wording mirrors `print_human_pomodoro_adjust_success` in
/// `src/native/capture.rs` (`would adjust` / `adjusted`, before/after timing,
/// signed minute effect, `(requested … clamped)` note, `at line N`) so the
/// panel and the CLI describe the same adjustment the same way. Works for
/// dry-run previews and committed captures alike; `isDryRun` is the only thing
/// that changes the verb.
public struct CapturePomodoroAdjustPresentation: Equatable, Sendable {
    public let isDryRun: Bool
    public let pomodoroName: String
    public let beforeStart: String
    public let beforeEnd: String
    public let beforeDurationMinutes: Int
    public let afterStart: String
    public let afterEnd: String
    public let afterDurationMinutes: Int
    public let deltaMinutes: Int
    public let requestedUnits: Int
    public let requestedMinutes: Int
    public let pomodoroLine: Int
    public let clamped: Bool
    public let timeRange: String

    /// `"Would adjust FOCUS 0900-0930 (30m) to 0900-0955 (55m), +25m at line 3"`
    /// (dry run) or `"Adjusted … at line 3"` (committed), with a
    /// `"(requested -45m in 9 units clamped)"` suffix when clamping changed the
    /// delta.
    public let statusText: String
    /// `"0900-0930 (30m) → 0900-0955 (55m), +25m"` — the calm, legible
    /// before-to-after line shown in preview.
    public let sessionText: String
    /// `"FOCUS · line 3"`.
    public let destinationText: String
    public let accessibilitySummary: String
    public let notificationDetail: String

    public init?(capture: CaptureCommandSuccess) {
        guard let summary = capture.pomodoroAdjust else {
            return nil
        }
        self.init(summary: summary, dryRun: capture.dryRun)
    }

    public init(summary: PomodoroAdjustSummary, dryRun: Bool) {
        isDryRun = dryRun
        pomodoroName = summary.pomodoroName ?? "current session"
        beforeStart = summary.beforeStart
        beforeEnd = summary.beforeEnd
        beforeDurationMinutes = summary.beforeDurationMinutes
        afterStart = summary.afterStart
        afterEnd = summary.afterEnd
        afterDurationMinutes = summary.afterDurationMinutes
        deltaMinutes = summary.deltaMinutes
        requestedUnits = summary.requestedUnits
        requestedMinutes = summary.requestedMinutes
        pomodoroLine = summary.pomodoroLine
        clamped = summary.clamped
        timeRange = summary.timeRange

        let verb = dryRun ? "Would adjust" : "Adjusted"
        let effect = Self.signedMinutes(summary.deltaMinutes)
        let before = "\(summary.beforeStart)-\(summary.beforeEnd) (\(summary.beforeDurationMinutes)m)"
        let after =
            "\(summary.afterStart)-\(summary.afterEnd) (\(summary.afterDurationMinutes)m)"
        var status =
            "\(verb) \(pomodoroName) \(before) to \(after), \(effect) at line \(summary.pomodoroLine)"
        if summary.clamped {
            let requestedSign = summary.direction == "plus" ? "+" : "-"
            status +=
                " (requested \(requestedSign)\(abs(summary.requestedMinutes))m in \(summary.requestedUnits) units clamped)"
        }
        statusText = status
        sessionText = "\(before) → \(after), \(effect)"
        destinationText = "\(pomodoroName) · line \(summary.pomodoroLine)"
        let effectPhrase = Self.spokenMinutes(summary.deltaMinutes)
        var accessibility =
            "Adjusts \(pomodoroName), \(summary.beforeStart)-\(summary.beforeEnd), \(summary.beforeDurationMinutes) minutes, to \(summary.afterStart)-\(summary.afterEnd), \(summary.afterDurationMinutes) minutes, \(effectPhrase), line \(summary.pomodoroLine)"
        if summary.clamped {
            let requestedDirection = summary.direction == "plus" ? "plus" : "minus"
            accessibility +=
                ", requested \(requestedDirection) \(abs(summary.requestedMinutes)) minutes in \(summary.requestedUnits) units, clamped to \(Self.spokenMinutes(summary.deltaMinutes))"
        }
        accessibilitySummary = accessibility
        notificationDetail = statusText
    }

    private static func signedMinutes(_ minutes: Int) -> String {
        minutes >= 0 ? "+\(minutes)m" : "-\(abs(minutes))m"
    }

    private static func spokenMinutes(_ minutes: Int) -> String {
        minutes >= 0 ? "plus \(minutes) minutes" : "minus \(abs(minutes)) minutes"
    }
}
