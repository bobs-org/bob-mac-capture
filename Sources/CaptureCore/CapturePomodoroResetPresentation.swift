import Foundation

/// Pure presentation model for a note-free `=x0` reset (`pomodoro_reset`
/// present on a `bob capture --format json` success), built once from
/// `CaptureCommandSuccess` so the SwiftUI layer never branches on
/// reset-specific JSON fields. The preview's only source of truth is Bob's
/// resolved `pomodoro_reset` object — which itself comes from
/// `bob capture --dry-run --no-clip --format json` for live preview and the
/// same command without `--dry-run`/`--no-clip` for submission — so there is
/// no Swift-side ledger logic here, only wording.
///
/// Wording mirrors `print_human_pomodoro_reset_success` in
/// `src/native/capture/output.rs` (`reset`/`would reset`, the session and
/// day/line, first-future destination with contents kept) so the panel and
/// the CLI describe the same reset the same way. Works for dry-run previews
/// and committed captures alike; `isDryRun` is the only thing that changes
/// the verb. No completed/started-task counts or early/overrun badge appear
/// on a reset card.
public struct CapturePomodoroResetPresentation: Equatable, Sendable {
    public enum Variant: Equatable, Sendable {
        case session
        case linkedTask
        case newTask
    }

    public let variant: Variant
    public let isDryRun: Bool
    public let pomodoroName: String
    /// `"Reset CAPTURE"`, or `"Reset session"` when Bob named no session.
    public let title: String
    /// `"2026/20261009.md · line 4"` — the day file and `pomodoro_line`.
    public let destinationText: String
    /// The reset entry line in its final open/untimed state.
    public let entryLine: String
    /// `"Moved before EARLY"` when Bob moved the block, else nil.
    public let movedText: String?
    /// `"Linked bob.md · ^ready into CAPTURE"`; nil for plain resets.
    public let viaText: String?
    /// `"Would reset CAPTURE"` (dry run) or `"Reset CAPTURE"` (committed).
    public let statusText: String
    public let primaryActionTitle: String
    public let notificationTitle: String
    public let notificationBody: String
    /// `" (reset CAPTURE)"`, appended to batch lines for resets.
    public let batchSuffix: String
    public let accessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let summary = capture.pomodoroReset else {
            return nil
        }
        self.init(summary: summary, capture: capture)
    }

    init(summary: PomodoroResetSummary, capture: CaptureCommandSuccess) {
        switch capture.kind.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "pomodoro_link":
            variant = .linkedTask
        case "pomodoro_task":
            variant = .newTask
        default:
            variant = .session
        }
        isDryRun = capture.dryRun
        pomodoroName = summary.pomodoroName ?? "session"
        let verb = isDryRun ? "Would reset" : "Reset"
        title = "Reset \(pomodoroName)"
        statusText = "\(verb) \(pomodoroName)"
        destinationText = "\(summary.dayRelative) · line \(summary.pomodoroLine)"
        entryLine = summary.entryLine
        if summary.moved {
            movedText = "Now the first future Pomodoro"
        } else {
            movedText = nil
        }
        if variant == .linkedTask || variant == .newTask,
            let blockID = capture.blockID,
            let route = capture.route
        {
            let tag = variant == .linkedTask ? "Linked" : "New task"
            viaText = "\(tag) \(route).md · ^\(blockID) into \(pomodoroName)"
        } else {
            viaText = nil
        }
        primaryActionTitle = isDryRun ? "Would reset" : "Reset"
        notificationTitle = "\(verb) \(pomodoroName)"
        notificationBody = "\(summary.dayRelative) · line \(summary.pomodoroLine) · now the first future Pomodoro with its contents kept"
        batchSuffix = " (reset \(pomodoroName))"
        var access = "\(verb) \(pomodoroName), \(destinationText), now the first future Pomodoro with its contents kept"
        if let via = viaText {
            access += ", \(via)"
        }
        accessibilitySummary = access
    }
}
