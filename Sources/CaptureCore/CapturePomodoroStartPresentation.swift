import Foundation

/// Pure presentation model for a Pomodoro start (`pomodoro_start` present on a
/// `bob capture --format json` success), built once from `CaptureCommandSuccess` so the
/// SwiftUI layer never branches on start-specific JSON fields or recomputes clock math.
/// The preview's only source of truth is Bob's resolved `pomodoro_start` object — which
/// itself comes from `bob capture --dry-run --no-clip --format json` for live preview
/// and the same command without `--dry-run`/`--no-clip` for submission — so there is no
/// Swift-side clock or ledger logic here, only wording.
///
/// Wording mirrors `print_human_pomodoro_start_success` in `src/native/capture.rs`
/// (`would start` / `started`, the session line, queued-task rows in the close's row
/// style, `nothing queued`) so the panel and the CLI describe the same session the same
/// way. Works for dry-run previews and committed captures alike; `isDryRun` is the only
/// thing that changes the verb. Link and task starts (`^route:id=`, `Text @route:id=3`)
/// carry no `tasks` array and keep their existing row/suffix rendering; the start card,
/// `Start` footer action, and start notification apply to whole-item `=`/`=<X>` starts
/// (`kind == "pomodoro_start"` — see `isSessionStart`).
public struct CapturePomodoroStartPresentation: Equatable, Sendable {
    /// The leading glyph for a queued-task row. Resolved rows map the task's
    /// current status symbol; unresolved rows always warn.
    public enum TaskGlyph: Equatable, Sendable {
        case ready
        case next
        case inProgress
        case other
        case unresolved
    }

    public struct TaskRow: Equatable, Sendable {
        public let glyph: TaskGlyph
        public let blockLink: String
        public let taskText: String
        /// `"bob ^capture-stop"`, or the raw block link when Bob omitted the
        /// resolved target parts.
        public let locatorText: String
        /// Unresolved rows carry the warning the card renders as help text.
        public let warning: String?
    }

    /// At most this many task rows render in the card before a "+N more" line —
    /// the same cap as the close card.
    public static var maxVisibleTaskRows: Int {
        CapturePomodoroClosePresentation.maxVisibleTaskRows
    }

    /// True for a whole-item `=`/`=<X>` start: the only shape that gets the
    /// start card, the `Start` footer action, and the start notification.
    /// Link and task starts share the `pomodoro_start` object but keep their
    /// own presentations.
    public static func isSessionStart(_ capture: CaptureCommandSuccess) -> Bool {
        capture.kind.lowercased().replacingOccurrences(of: "-", with: "_")
            == "pomodoro_start" && capture.pomodoroStart != nil
    }

    public let isDryRun: Bool
    public let pomodoroName: String
    public let start: String
    public let end: String
    public let durationMinutes: Int
    public let offsetUnits: Int
    public let pomodoroLine: Int
    public let createdPomodoro: Bool
    public let timeRange: String

    /// `"Start CAPTURE"` (dry run) or `"Started CAPTURE"`.
    public let title: String
    /// `"Would start CAPTURE 0940-1005 (25m) at line 13"` (dry run) or
    /// `"Started … at line 13"` (committed).
    public let statusText: String
    /// `"0940-1005 (25m)"` — the calm, legible session line shown in preview.
    public let sessionText: String
    /// `"2026/20260928.md · line 13"` — the day file and `pomodoro_line`.
    public let destinationText: String
    public let taskRows: [TaskRow]
    public let visibleTaskRows: [TaskRow]
    public let overflowTaskCount: Int
    /// `"Nothing queued"`, shown when `taskRows` is empty.
    public let emptyText: String
    public let accessibilitySummary: String
    public let notificationDetail: String
    /// `"Started CAPTURE"`, the single-capture notification title.
    public let notificationTitle: String
    /// `"0940-1005 (25m) · 2 queued tasks"` (`"1 queued task"` for one,
    /// `"Nothing queued"` for none).
    public let notificationBody: String
    /// `" (started CAPTURE 0940-1005)"`, appended to batch lines for starts.
    public let batchSuffix: String
    public let primaryActionTitle: String

    public init?(capture: CaptureCommandSuccess) {
        guard let summary = capture.pomodoroStart else {
            return nil
        }
        self.init(summary: summary, dryRun: capture.dryRun, relativeTarget: capture.relativeTarget)
    }

    public init(summary: PomodoroStartSummary, dryRun: Bool, relativeTarget: String = "") {
        isDryRun = dryRun
        pomodoroName = summary.pomodoroName ?? "next session"
        start = summary.start
        end = summary.end
        durationMinutes = summary.durationMinutes
        offsetUnits = summary.offsetUnits
        pomodoroLine = summary.pomodoroLine
        createdPomodoro = summary.createdPomodoro
        timeRange = summary.timeRange

        title = "\(dryRun ? "Start" : "Started") \(pomodoroName)"
        let verb = dryRun ? "Would start" : "Started"
        let created = summary.createdPomodoro ? " (created)" : ""
        statusText =
            "\(verb) \(pomodoroName) \(start)-\(end) (\(durationMinutes)m)\(created) at line \(pomodoroLine)"
        sessionText = "\(start)-\(end) (\(durationMinutes)m)"
        destinationText = "\(relativeTarget) · line \(pomodoroLine)"

        taskRows = (summary.tasks ?? []).map(Self.taskRow(for:))
        visibleTaskRows = Array(taskRows.prefix(Self.maxVisibleTaskRows))
        overflowTaskCount = max(0, taskRows.count - Self.maxVisibleTaskRows)
        emptyText = "Nothing queued"

        let createdPhrase = summary.createdPomodoro ? ", created new entry" : ", uses existing entry"
        var spoken =
            "Starts \(pomodoroName), \(start) to \(end), \(durationMinutes) minutes, line \(pomodoroLine)\(createdPhrase)"
        if let tasks = summary.tasks {
            spoken += tasks.isEmpty
                ? ", nothing queued"
                : ", \(tasks.count) queued task\(tasks.count == 1 ? "" : "s")"
        }
        accessibilitySummary = spoken
        notificationDetail = statusText

        notificationTitle = "Started \(pomodoroName)"
        if let tasks = summary.tasks, !tasks.isEmpty {
            notificationBody =
                "\(sessionText) · \(tasks.count) queued task\(tasks.count == 1 ? "" : "s")"
        } else {
            notificationBody = "\(sessionText) · Nothing queued"
        }
        batchSuffix = " (started \(pomodoroName) \(start)-\(end))"
        primaryActionTitle = "Start"
    }

    private static func taskRow(for task: PomodoroStartTask) -> TaskRow {
        let glyph: TaskGlyph
        if !task.resolved {
            glyph = .unresolved
        } else {
            switch task.statusSymbol {
            case " ":
                glyph = .ready
            case "*":
                glyph = .next
            case "/":
                glyph = .inProgress
            default:
                glyph = .other
            }
        }
        let locator: String
        if let relativeTarget = task.relativeTarget, !task.blockID.isEmpty {
            let stem = relativeTarget.hasSuffix(".md")
                ? String(relativeTarget.dropLast(3)) : relativeTarget
            locator = "\(stem) ^\(task.blockID)"
        } else {
            locator = task.blockLink
        }
        return TaskRow(
            glyph: glyph,
            blockLink: task.blockLink,
            taskText: task.text ?? task.blockLink,
            locatorText: locator,
            warning: task.warning
        )
    }
}
