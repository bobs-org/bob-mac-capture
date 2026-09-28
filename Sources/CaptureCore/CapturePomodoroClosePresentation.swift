import Foundation

/// Pure presentation model for a Pomodoro close (`pomodoro_close` present on a
/// `bob capture --format json` success), built once from
/// `CaptureCommandSuccess` so the SwiftUI layer never branches on
/// close-specific JSON fields or recomputes clock math. The preview's only
/// source of truth is Bob's resolved `pomodoro_close` object — which itself
/// comes from `bob capture --dry-run --no-clip --format json` for live preview
/// and the same command without `--dry-run`/`--no-clip` for submission — so
/// there is no Swift-side clock or ledger logic here, only wording.
///
/// Wording mirrors `print_human_pomodoro_close_success` in
/// `src/native/capture.rs` (`closed`/`would close`, the range change, per-task
/// transitions, the next-session line) so the panel and the CLI describe the
/// same close the same way. Works for dry-run previews and committed captures
/// alike; `isDryRun` is the only thing that changes the verb.
public struct CapturePomodoroClosePresentation: Equatable, Sendable {
    public enum Variant: Equatable, Sendable {
        case session
        case linkedTask
        case newTask
    }

    public enum TimingTone: Equatable, Sendable {
        case early
        case onTime
        case over
    }

    /// The leading glyph family for a task row. `transition` renders the
    /// monospaced transition text itself (worked and mentioned rows); every
    /// other case maps to an SF Symbol in the card. Unknown roles degrade to
    /// `neutral`.
    public enum TaskGlyph: Equatable, Sendable {
        case transition
        case deferred
        case struck
        case embedded
        case unresolved
        case neutral
    }

    public struct TaskRow: Equatable, Sendable {
        public let role: String
        public let glyph: TaskGlyph
        public let blockLink: String
        public let taskText: String
        public let transitionText: String
        /// `"bob.md · ^capture-stop"`, or the raw block link when Bob omitted
        /// the resolved target parts (unresolved rows).
        public let locatorText: String
        public let workLogCount: Int
        /// Up to two entry previews with the `*YYYY-MM-DD* — ` date prefix
        /// stripped for compact display.
        public let workLogPreviews: [String]
        public let warning: String?
        public let carried: Bool
        /// `"linked"` on the row matching a `pomodoro_link` close,
        /// `"new"` on the row matching a `pomodoro_task` close, else nil.
        public let tag: String?
        /// Struck rows render their text with strikethrough in the card.
        public let isStruck: Bool
    }

    /// At most this many task rows render in the card before a "+N more" line.
    public static let maxVisibleTaskRows = 6

    public let variant: Variant
    public let isDryRun: Bool
    public let pomodoroName: String
    /// `"Close CAPTURE"`, or `"Close session"` when Bob named no session.
    /// Link and new-task closes keep the same title; their "via" data lives
    /// in `viaText` and the tagged row instead.
    public let title: String
    /// `"0920-0950 → 0920-0940 · 20m"`, or `"0920-0950 · 30m"` when the close
    /// did not decrement the session.
    public let sessionText: String
    /// The planned range alone (`"0920-0950"`); the card tints the decrement
    /// half separately.
    public let sessionPlannedText: String
    /// `"→ 0920-0940 · 20m"` when decremented, else nil.
    public let sessionDecrementText: String?
    /// `"13m early"`, `"on time"`, or `"7m over"`, from `remaining_minutes`.
    public let timingText: String
    public let timingTone: TimingTone
    /// `"2026/20260928.md · line 5"` — the day file and `pomodoro_line`, never
    /// the route note.
    public let destinationText: String
    public let taskRows: [TaskRow]
    public let visibleTaskRows: [TaskRow]
    public let overflowTaskCount: Int
    /// `"1 note stays"` / `"N notes stay"`, or nil when nothing stays.
    public let notesText: String?
    /// `"Next: CAPTURE · new · carries 2 links"`, or
    /// `"Next: SASE · line 14"` for a pre-existing entry; nil when Bob
    /// reports no next session.
    public let nextText: String?
    /// `"No Task Links — the session simply closes"`, shown when `taskRows`
    /// is empty.
    public let emptyText: String
    /// `"Linked bob.md · ^ready into CAPTURE"`, `"Moved from SASE"`, or
    /// `"New task Draft docs → bob.md · ^draft-docs"`; nil for plain closes.
    public let viaText: String?
    /// `"Would close CAPTURE · 1 started · 3 Work Log entries"`
    /// (dry run) or `"Closed …"` (committed).
    public let statusText: String
    public let primaryActionTitle: String
    public let notificationTitle: String
    public let notificationBody: String
    /// `" (closed CAPTURE)"`, appended to batch lines for closes.
    public let batchSuffix: String
    public let accessibilitySummary: String
    public let warnings: [String]

    public init?(capture: CaptureCommandSuccess) {
        guard let summary = capture.pomodoroClose else {
            return nil
        }
        self.init(summary: summary, capture: capture)
    }

    init(summary: PomodoroCloseSummary, capture: CaptureCommandSuccess) {
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
        title = "Close \(pomodoroName)"

        let plannedRange = summary.planned.timeRange
        let closedRange = summary.closed.timeRange
        let decremented = summary.decrementedMinutes > 0
        if decremented {
            sessionText =
                "\(plannedRange) → \(closedRange) · \(summary.closed.durationMinutes)m"
            sessionDecrementText = "→ \(closedRange) · \(summary.closed.durationMinutes)m"
        } else {
            sessionText = "\(plannedRange) · \(summary.planned.durationMinutes)m"
            sessionDecrementText = nil
        }
        sessionPlannedText = plannedRange

        let remaining = summary.remainingMinutes
        if remaining > 0 {
            timingText = "\(remaining)m early"
            timingTone = .early
        } else if remaining < 0 {
            timingText = "\(abs(remaining))m over"
            timingTone = .over
        } else {
            timingText = "on time"
            timingTone = .onTime
        }

        let dayFile = summary.dayRelative ?? capture.relativeTarget
        destinationText = "\(dayFile) · line \(summary.pomodoroLine)"

        let taggedBlockID: String? = (variant == .linkedTask || variant == .newTask)
            ? capture.blockID : nil
        let taggedTag = variant == .linkedTask ? "linked" : "new"
        taskRows = summary.tasks.map { task in
            Self.taskRow(
                for: task,
                tag: (taggedBlockID != nil && task.blockID == taggedBlockID) ? taggedTag : nil
            )
        }
        visibleTaskRows = Array(taskRows.prefix(Self.maxVisibleTaskRows))
        overflowTaskCount = max(0, taskRows.count - Self.maxVisibleTaskRows)

        if summary.notes.isEmpty {
            notesText = nil
        } else if summary.notes.count == 1 {
            notesText = "1 note stays"
        } else {
            notesText = "\(summary.notes.count) notes stay"
        }

        if let next = summary.nextPomodoro {
            let nextName = next.name ?? summary.pomodoroName ?? "session"
            if next.created {
                let carriedCount = summary.carried.count
                nextText =
                    "Next: \(nextName) · new · carries \(carriedCount) link\(carriedCount == 1 ? "" : "s")"
            } else {
                nextText = "Next: \(nextName) · line \(next.line)"
            }
        } else {
            nextText = nil
        }

        emptyText = "No Task Links — the session simply closes"

        switch variant {
        case .session:
            viaText = nil
        case .linkedTask:
            if capture.pomodoroLinkAction == "moved" {
                viaText = "Moved from \(Self.movedSourceName(capture: capture, rows: taskRows))"
            } else {
                let blockID = capture.blockID ?? ""
                viaText = "Linked \(capture.routeLabel) · ^\(blockID) into \(pomodoroName)"
            }
        case .newTask:
            let blockID = capture.blockID ?? ""
            viaText = "New task \(capture.text) → \(capture.routeLabel) · ^\(blockID)"
        }

        let startedCount = summary.tasks.filter(\.statusChanged).count
        let workLogCount = summary.tasks.reduce(0) { $0 + $1.workLog.count }
        let verb = isDryRun ? "Would close" : "Closed"
        statusText =
            "\(verb) \(pomodoroName) · \(startedCount) started · \(workLogCount) Work Log \(workLogCount == 1 ? "entry" : "entries")"
        primaryActionTitle = "Close"
        notificationTitle = "Closed \(pomodoroName)"

        var bodyLines = [
            "\(pomodoroName) \(sessionText) · \(timingText)",
            "\(taskRows.count) task\(taskRows.count == 1 ? "" : "s") · \(workLogCount) Work Log \(workLogCount == 1 ? "entry" : "entries")",
        ]
        if let nextText {
            bodyLines.append(nextText)
        }
        notificationBody = bodyLines.joined(separator: "\n")
        batchSuffix = " (closed \(pomodoroName))"

        var summaryParts = [title, sessionText, timingText, destinationText]
        if let viaText {
            summaryParts.append(viaText)
        }
        summaryParts.append(contentsOf: taskRows.map(\.transitionText))
        summaryParts.append(contentsOf: taskRows.flatMap(\.workLogPreviews))
        if let notesText {
            summaryParts.append(notesText)
        }
        if let nextText {
            summaryParts.append(nextText)
        } else {
            summaryParts.append(emptyText)
        }
        summaryParts.append(contentsOf: capture.warnings.map { "Warning: \($0)" })
        accessibilitySummary = summaryParts.joined(separator: ", ")

        warnings = capture.warnings
    }

    private static func taskRow(for task: PomodoroCloseTask, tag: String?) -> TaskRow {
        let glyph: TaskGlyph
        let transition: String
        let previousMarker = CaptureTogglePresentation.marker(for: task.previousStatusSymbol)
        let currentMarker = CaptureTogglePresentation.marker(for: task.statusSymbol)
        switch task.role {
        case "worked", "mentioned":
            if task.statusChanged {
                glyph = .transition
                transition = "\(previousMarker) → \(currentMarker)"
            } else {
                glyph = .transition
                transition = currentMarker
            }
        case "deferred":
            glyph = .deferred
            transition = "\(previousMarker) deferred"
        case "struck":
            glyph = .struck
            transition = "[x]"
        case "embedded", "subtask":
            glyph = .embedded
            transition = "[x] closed"
        case "unresolved":
            glyph = .unresolved
            transition = "[x]"
        default:
            glyph = .neutral
            transition = "[x]"
        }
        let locator: String
        if let relativeTarget = task.relativeTarget, !task.blockID.isEmpty {
            locator = "\(relativeTarget) · ^\(task.blockID)"
        } else {
            locator = task.blockLink
        }
        return TaskRow(
            role: task.role,
            glyph: glyph,
            blockLink: task.blockLink,
            taskText: task.text ?? task.blockLink,
            transitionText: transition,
            locatorText: locator,
            workLogCount: task.workLog.count,
            workLogPreviews: task.workLog.prefix(2).map(Self.strippedWorkLogDate),
            warning: task.warning,
            carried: task.carried,
            tag: tag,
            isStruck: task.role == "struck"
        )
    }

    /// Work Log entries arrive dated (`*2026-09-28* — Designed …`); the card
    /// shows them under a dated section already, so strip the date prefix.
    static func strippedWorkLogDate(_ entry: String) -> String {
        guard entry.hasPrefix("*") else {
            return entry
        }
        guard let separator = entry.range(of: "* — ") else {
            return entry
        }
        let datePart = entry[entry.index(after: entry.startIndex)..<separator.lowerBound]
        let isDate = datePart.count == 10
            && datePart.allSatisfy { $0.isNumber || $0 == "-" }
        return isDate ? String(entry[separator.upperBound...]) : entry
    }

    /// The moved-from session name. Newer bob omits the source endpoint name,
    /// so derive it from the moved task's own note stem (Pomodoro entries are
    /// uppercase by convention): `sase.md` → `SASE`. Falls back to the capture
    /// route when no row matches the moved task.
    private static func movedSourceName(
        capture: CaptureCommandSuccess,
        rows: [TaskRow]
    ) -> String {
        let notePath: String?
        if capture.blockID != nil,
           let row = rows.first(where: { $0.tag == "linked" && !$0.locatorText.isEmpty })
        {
            notePath = row.locatorText.split(separator: "·").first.map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        } else {
            notePath = nil
        }
        let rawStem = (notePath ?? capture.route ?? "")
            .split(separator: "/").last.map(String.init) ?? ""
        let stem = rawStem.hasSuffix(".md") ? String(rawStem.dropLast(3)) : rawStem
        let upper = stem.uppercased()
        return upper.isEmpty ? "previous session" : upper
    }
}
