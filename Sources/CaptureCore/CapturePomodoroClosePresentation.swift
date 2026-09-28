import Foundation

/// Presentation for Bob's resolved Pomodoro close summary. It covers a plain `=x`,
/// an existing-task link with `=x`, and a new task linked into the closing session.
/// All timing and task effects come from Bob; this type only turns them into copy.
public struct CapturePomodoroClosePresentation: Equatable, Sendable {
    public enum Variant: Equatable, Sendable {
        case session
        case linkedTask
        case newTask
    }

    public struct TaskRow: Equatable, Sendable {
        public let role: String
        public let blockLink: String
        public let taskText: String
        public let transitionText: String
        public let workLog: [String]
        public let warning: String?
        public let carried: Bool
    }

    public let variant: Variant
    public let isDryRun: Bool
    public let pomodoroName: String
    public let sessionText: String
    public let timingChip: String
    public let taskRows: [TaskRow]
    public let nextSessionText: String?
    public let warnings: [String]
    public let headline: String
    public let statusText: String
    public let notificationTitle: String
    public let notificationBody: String
    public let accessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let summary = capture.pomodoroClose else {
            return nil
        }

        switch capture.kind.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "pomodoro_link":
            variant = .linkedTask
        case "pomodoro_task":
            variant = .newTask
        default:
            variant = .session
        }
        isDryRun = capture.dryRun
        pomodoroName = summary.pomodoroName ?? "current session"
        sessionText =
            "\(summary.closed.start)-\(summary.closed.end) (\(summary.closed.durationMinutes)m)"
        let shortened = summary.decrementedMinutes > 0
            ? " · −\(summary.decrementedMinutes)m"
            : ""
        timingChip = "\(summary.planned.timeRange) → \(summary.closed.timeRange)"
            + " · stopped \(summary.closedAt)\(shortened)"

        taskRows = summary.tasks.map { task in
            let taskText = task.text.map {
                CaptureTogglePresentation.taskPreviewText(from: $0, blockID: task.blockID)
            } ?? task.blockLink
            let previousMarker = CaptureTogglePresentation.marker(for: task.previousStatusSymbol)
            let statusMarker = CaptureTogglePresentation.marker(for: task.statusSymbol)
            let transition: String
            if !task.resolved {
                transition = "Unresolved  \(task.blockLink)"
            } else if task.statusChanged {
                transition = "\(previousMarker) → \(statusMarker)  \(taskText)"
            } else if let statusName = task.statusName {
                transition = "\(statusMarker) stays \(statusName)  \(taskText)"
            } else {
                transition = "\(task.role.capitalized)  \(taskText)"
            }
            return TaskRow(
                role: task.role,
                blockLink: task.blockLink,
                taskText: taskText,
                transitionText: transition,
                workLog: task.workLog,
                warning: task.warning,
                carried: task.carried
            )
        }
        warnings = capture.warnings

        if let next = summary.nextPomodoro {
            let name = next.name ?? "unnamed session"
            let timing = next.timeRange.map { " · \($0)" } ?? " · untimed"
            let created = next.created ? " · created" : ""
            nextSessionText = "Next: \(name)\(timing) · line \(next.line)\(created)"
        } else {
            nextSessionText = "No next session"
        }

        switch variant {
        case .session:
            headline = "Close \(pomodoroName)"
        case .linkedTask:
            headline = "Link task and close \(pomodoroName)"
        case .newTask:
            headline = "Create task and close \(pomodoroName)"
        }
        let verb = isDryRun ? "Would close" : "Closed"
        statusText = "\(verb) \(pomodoroName) \(sessionText) at line \(summary.pomodoroLine)"
        notificationTitle = "Closed \(pomodoroName)"

        var details = [headline, sessionText, timingChip]
        details.append(contentsOf: taskRows.map(\.transitionText))
        details.append(contentsOf: taskRows.flatMap(\.workLog))
        details.append(contentsOf: warnings.map { "Warning: \($0)" })
        if let nextSessionText {
            details.append(nextSessionText)
        }
        notificationBody = details.joined(separator: "\n")
        accessibilitySummary = details.joined(separator: ", ")
    }
}
