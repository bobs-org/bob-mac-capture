import Foundation

/// Pure presentation model for the Task Links from a `project_note` capture,
/// authored ` :` bullets and picked `@route:id@` offers alike. Bob reports a
/// pick as an ordinary `project_note.task_links` row (it is a ` :` link) and
/// again in `project_note.successors`, so this model counts every
/// `task_links` row exactly once and the general pulled-in successor count
/// never includes project successors. Built once from `CaptureCommandSuccess`
/// so the SwiftUI/AppKit layer never branches on project-note JSON fields
/// itself.
///
/// The preview's only source of truth is Bob's resolved fields — the
/// `project_note.task_links` rows plus the top-level `pomodoro_name` and
/// `creates_pomodoro` — which come from `bob capture --dry-run --no-clip
/// --format json` for live preview and the same command without
/// `--dry-run`/`--no-clip` for submission. There is no Swift-side ledger or
/// Pomodoro math here, only wording.
public struct CaptureProjectNotePresentation: Equatable, Sendable {
    /// One linked task row: the task text and its `^id`.
    public struct LinkedTaskRow: Equatable, Sendable {
        public let text: String
        public let blockID: String

        public init(text: String, blockID: String) {
            self.text = text
            self.blockID = blockID
        }
    }

    /// `"ADMIN"`, or `"today's Pomodoro"` when Bob reported no name.
    public let destinationLabel: String
    /// `"Links 2 tasks into ADMIN (new)"`, `"Links 1 task into today's
    /// Pomodoro"` — the preview section header.
    public let headerText: String
    /// The linked-task rows in Bob's source order.
    public let linkedTasks: [LinkedTaskRow]
    /// Whether Bob created the destination Pomodoro entry.
    public let createdPomodoro: Bool
    /// `"Linked 2 tasks into ADMIN"` — the notification body line.
    public let notificationDetail: String
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let note = capture.projectNote else {
            return nil
        }
        let linkedTasks = note.taskLinks
        guard !linkedTasks.isEmpty else {
            return nil
        }
        let destination = capture.pomodoroName ?? "today's Pomodoro"
        destinationLabel = destination
        createdPomodoro = capture.createsPomodoro ?? false
        let count = linkedTasks.count
        let noun = count == 1 ? "task" : "tasks"
        let createdSuffix = createdPomodoro ? " (new)" : ""
        headerText = "Links \(count) \(noun) into \(destination)\(createdSuffix)"
        let displayedTasks = linkedTasks.map {
            LinkedTaskRow(text: $0.text, blockID: $0.blockID)
        }
        self.linkedTasks = displayedTasks
        notificationDetail = "Linked \(count) \(noun) into \(destination)"
        previewAccessibilitySummary =
            ([headerText] + displayedTasks.map { "\($0.text), ^\($0.blockID)" })
            .joined(separator: ", ")
    }
}

/// Presentation for the new-project context and its offered task rows. The
/// source remains Bob's `project_note.successors`; the client only supplies
/// concise wording and never derives which tasks can be offered.
public struct CaptureProjectNoteSuccessorPresentation: Equatable, Sendable {
    public let projectName: String
    public let successors: [TaskCompleteUnblocked]
    public let contextText: String
    public let showsNoOpenTasksMessage: Bool
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let note = capture.projectNote, note.form == "offer" else {
            return nil
        }
        projectName = note.basename
        successors = note.successors
        contextText = "New project \(note.basename)"
        showsNoOpenTasksMessage = note.successors.isEmpty && capture.linkGuard == nil
        if showsNoOpenTasksMessage {
            previewAccessibilitySummary = "\(contextText), no open tasks to offer"
        } else if note.successors.isEmpty {
            previewAccessibilitySummary = contextText
        } else {
            let count = note.successors.count
            let noun = count == 1 ? "task" : "tasks"
            previewAccessibilitySummary =
                ([contextText, "Offers \(count) \(noun), press Return to choose what to pull in"]
                    + note.successors.map(\.text))
                    .joined(separator: ", ")
        }
    }
}
