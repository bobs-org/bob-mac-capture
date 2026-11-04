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
/// `creates_pomodoro` — which come from `bob capture --dry-run [--no-clip]
/// --format json` for live preview (`--no-clip` is omitted only for a `%c`
/// draft) and the same command resolving the clipboard for submission.
/// There is no Swift-side ledger or Pomodoro math here, only wording.
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

/// Presentation for the tasks a `project_note` capture moves from the
/// parent note into the new project, in Bob's draft order. Built once from
/// `CaptureCommandSuccess` so the SwiftUI/AppKit layer never branches on
/// project-note JSON fields itself. The preview band sits above the Links
/// and Offers bands; the notification names the created note and the move
/// count; VoiceOver reads the moves in words. There is no Swift-side move
/// math here, only Bob's `moved_tasks` rows and `move_summary` wording.
public struct CaptureProjectNoteMovePresentation: Equatable, Sendable {
    /// One moved task row: its status glyph, title, `^id`, and Bob's detail.
    public struct MovedTaskRow: Equatable, Sendable {
        public let glyph: String
        public let text: String
        public let statusName: String
        public let blockID: String
        public let detail: String?

        public init(
            glyph: String,
            text: String,
            statusName: String,
            blockID: String,
            detail: String?
        ) {
            self.glyph = glyph
            self.text = text
            self.statusName = statusName
            self.blockID = blockID
            self.detail = detail
        }
    }

    /// `"↪ Moves 2 tasks from cash.md"` — the preview band header.
    public let headerText: String
    /// The moved-task rows in Bob's draft order.
    public let movedTasks: [MovedTaskRow]
    /// `"3 links repaired in 2 notes"`, or nil when Bob repaired nothing.
    public let repairFooterText: String?
    /// `"Created cash_goog_exit"` — the notification title.
    public let notificationTitle: String
    /// `"moved 2 tasks from cash"` — the notification body lead.
    public let notificationDetail: String
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let note = capture.projectNote, !note.movedTasks.isEmpty else {
            return nil
        }
        let parent = note.moveSummary?.parent ?? ""
        let count = note.movedTasks.count
        let noun = count == 1 ? "task" : "tasks"
        headerText = "↪ Moves \(count) \(noun) from \(parent)"
        movedTasks = note.movedTasks.map {
            MovedTaskRow(
                glyph: CaptureProjectNoteMoveGlyph.text(for: $0.statusSymbol),
                text: $0.text,
                statusName: $0.statusName,
                blockID: $0.blockID,
                detail: $0.detail.flatMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty ? nil : $0
                }
            )
        }
        if let summary = note.moveSummary, summary.repairedLinks > 0 {
            let linkNoun = summary.repairedLinks == 1 ? "link" : "links"
            let noteNoun = summary.repairedNotes == 1 ? "note" : "notes"
            repairFooterText =
                "\(summary.repairedLinks) \(linkNoun) repaired in "
                + "\(summary.repairedNotes) \(noteNoun)"
        } else {
            repairFooterText = nil
        }
        notificationTitle =
            "Created \((note.basename as NSString).deletingPathExtension)"
        let displayRoute = (parent as NSString).deletingPathExtension
        let links = note.taskLinks.filter { link in
            note.movedTasks.contains { $0.blockID == link.blockID }
        }
        let linkedDetail =
            links.isEmpty
            ? "" : " · \(links.count) linked under \(capture.pomodoroName ?? "today's Pomodoro")"
        notificationDetail = "moved \(count) \(noun) from \(displayRoute)" + linkedDetail
        let rowSummaries = movedTasks.map { row in
            var parts = [row.text]
            if !row.statusName.isEmpty { parts.append(row.statusName) }
            if !row.blockID.isEmpty { parts.append("^\(row.blockID)") }
            if let detail = row.detail { parts.append(detail) }
            return parts.joined(separator: ", ")
        }
        var summaryParts = [headerText] + rowSummaries
        if let footer = repairFooterText { summaryParts.append(footer) }
        previewAccessibilitySummary = summaryParts.joined(separator: "; ")
    }
}

/// Text glyphs for moved-task statuses, shared by the preview band rows
/// and the editor ghost titles. Names stay in Bob's `status_name` words for
/// VoiceOver; these glyphs are visual only.
public enum CaptureProjectNoteMoveGlyph {
    public static func text(for statusSymbol: String) -> String {
        switch statusSymbol {
        case " ": return "○"
        case "*": return "◉"
        case "/": return "◐"
        case "x", "X": return "●"
        case "?": return "?"
        case "-": return "–"
        case "": return "○"
        default: return statusSymbol
        }
    }
}

/// Presentation for the discoverability hint on a project-note draft with
/// no move bullets whose parent still has movable open tasks: a muted
/// one-liner under the project card. Nil whenever the draft already moves
/// tasks or Bob sent no hint.
public struct CaptureProjectNoteMoveHintPresentation: Equatable, Sendable {
    /// `"Type - ^ to move tasks from cash.md (12 open)"`.
    public let hintText: String
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess, moveChoiceSupported: Bool = false) {
        guard let note = capture.projectNote,
            note.movedTasks.isEmpty,
            let hint = note.moveHint
        else {
            return nil
        }
        let noun = hint.openCount == 1 ? "task" : "tasks"
        hintText =
            moveChoiceSupported || capture.moveChoice?.supported == true
            ? "Type - ^ to move a task from \(hint.parent), or - ^^ to choose several (\(hint.openCount) open)"
            : "Type - ^ to move \(noun) from \(hint.parent) (\(hint.openCount) open)"
        previewAccessibilitySummary = hintText
    }
}

/// One inline ghost title the editor draws after a move bullet: the moved
/// task's glyph and title, plus a lane-change suffix for `:` moves. The
/// ghost is drawn, never inserted, and truncated to the line's remaining
/// width by the view.
public struct CaptureProjectNoteMoveGhost: Equatable, Sendable {
    /// 1-based physical line holding the move bullet.
    public let lineNumber: Int
    /// UTF-8 byte offset of the end of that line in the draft.
    public let insertionUTF8Offset: Int
    /// `"○ Collect the equity paperwork"` (`" · becomes Next"` appended
    /// for a `:` lane change).
    public let text: String
    /// Spoken form for VoiceOver.
    public let accessibilityText: String

    public init(
        lineNumber: Int,
        insertionUTF8Offset: Int,
        text: String,
        accessibilityText: String
    ) {
        self.lineNumber = lineNumber
        self.insertionUTF8Offset = insertionUTF8Offset
        self.text = text
        self.accessibilityText = accessibilityText
    }
}

/// Anchor computation and staleness for the editor ghost titles. A ghost
/// appears after a move bullet only while the latest successful preview's
/// draft equals the current draft and the bytes at the reported
/// `draft_range` still read as that move's `sigil + block_id` token, so an
/// edit to the bullet hides its ghost without touching the draft.
public enum CaptureProjectNoteMoveGhosts {
    public static func ghosts(
        draft: String,
        previewDraft: String,
        movedTasks: [CaptureProjectNoteMovedTask]
    ) -> [CaptureProjectNoteMoveGhost] {
        guard draft == previewDraft else { return [] }
        let utf8 = Array(draft.utf8)
        var result: [CaptureProjectNoteMoveGhost] = []
        for task in movedTasks where task.via != "choice" {
            guard let ghost = ghost(utf8: utf8, task: task) else {
                continue
            }
            result.append(ghost)
        }
        return result
    }

    private static func ghost(
        utf8: [UInt8],
        task: CaptureProjectNoteMovedTask
    ) -> CaptureProjectNoteMoveGhost? {
        guard task.draftRange.count == 2 else { return nil }
        let start = task.draftRange[0]
        let end = task.draftRange[1]
        guard start >= 0, end > start, end <= utf8.count else { return nil }
        let token = String(decoding: utf8[start..<end], as: UTF8.self)
        guard token == task.sigil + task.blockID, !task.blockID.isEmpty else {
            return nil
        }
        let lineNumber = utf8[..<start].filter { $0 == 0x0A }.count + 1
        var lineEnd = end
        while lineEnd < utf8.count, utf8[lineEnd] != 0x0A { lineEnd += 1 }
        let glyph = CaptureProjectNoteMoveGlyph.text(for: task.statusSymbol)
        let becomesNext =
            task.sigil == ":"
            && !task.previousStatusSymbol.isEmpty
            && task.statusSymbol != task.previousStatusSymbol
        let text =
            "\(glyph) \(task.text)" + (becomesNext ? " · becomes Next" : "")
        let statusWords =
            task.statusName.isEmpty ? task.statusSymbol : task.statusName
        let accessibilityText =
            "\(task.text), \(statusWords)"
            + (becomesNext ? ", becomes Next" : "")
        return CaptureProjectNoteMoveGhost(
            lineNumber: lineNumber,
            insertionUTF8Offset: lineEnd,
            text: text,
            accessibilityText: accessibilityText
        )
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
