import Foundation

/// Pure presentation model for a `project_note` capture result that wrote Task
/// Links (`kind == "project_note"` with a non-empty `project_note.task_links`),
/// built once from `CaptureCommandSuccess` so the SwiftUI/AppKit layer never
/// branches on project-note JSON fields itself. Works equally for a dry-run
/// live preview and a committed capture.
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
        guard let note = capture.projectNote, !note.taskLinks.isEmpty else {
            return nil
        }
        let destination = capture.pomodoroName ?? "today's Pomodoro"
        destinationLabel = destination
        createdPomodoro = capture.createsPomodoro ?? false
        let count = note.taskLinks.count
        let noun = count == 1 ? "task" : "tasks"
        let createdSuffix = createdPomodoro ? " (new)" : ""
        headerText = "Links \(count) \(noun) into \(destination)\(createdSuffix)"
        linkedTasks = note.taskLinks.map {
            LinkedTaskRow(text: $0.text, blockID: $0.blockID)
        }
        notificationDetail = "Linked \(count) \(noun) into \(destination)"
        previewAccessibilitySummary =
            ([headerText] + linkedTasks.map { "\($0.text), ^\($0.blockID)" })
            .joined(separator: ", ")
    }
}
