import Foundation

/// Pure presentation model for a whole-item `!note:block-id` completion
/// (`kind == "task_complete"` with a `task_complete` object), built once from
/// `CaptureCommandSuccess` so the SwiftUI/AppKit layer never branches on
/// completion-specific JSON fields or spells a completion string literal
/// itself. Works equally for a dry-run live preview and a committed capture —
/// `isDryRun` is the only thing that changes the tense of `headline`,
/// `ledgerText`, and `statusText`; every other field describes the same
/// before/after transition.
///
/// Wording mirrors `print_human_task_complete_success` in
/// `src/native/capture/output.rs` so the panel's preview and the CLI's
/// `--dry-run` output describe the same change the same way.
public struct CaptureTaskCompletePresentation: Equatable, Sendable {
    /// One embedded subtask the completion closed.
    public struct SubtaskRow: Equatable, Sendable {
        /// `"[/] → [x]  Write the regression test"`.
        public let transitionText: String
        /// `"sase.md ^write-test"`.
        public let locatorText: String

        public init(transitionText: String, locatorText: String) {
            self.transitionText = transitionText
            self.locatorText = locatorText
        }
    }

    /// One descendant the completion left open.
    public struct LeftOpenRow: Equatable, Sendable {
        /// `"left Blocked [?] Ask infra"`.
        public let displayText: String
        /// `"sase.md ^ask-infra"`.
        public let locatorText: String

        public init(displayText: String, locatorText: String) {
            self.displayText = displayText
            self.locatorText = locatorText
        }
    }

    /// One dependent the completion unblocked.
    public struct UnblockedRow: Equatable, Sendable {
        /// `"[?] → [ ]  Book flights"`.
        public let transitionText: String
        /// `"travel.md ^book-flights"`.
        public let locatorText: String
        /// The dependent's plain text, for notification bodies.
        public let text: String

        public init(transitionText: String, locatorText: String, text: String) {
            self.transitionText = transitionText
            self.locatorText = locatorText
            self.text = text
        }
    }

    public let isDryRun: Bool
    public let isAlreadyDone: Bool
    /// `"Complete"`, `"Would complete"`, or `"Already done"`.
    public let headline: String
    /// `"sase.md · ^fix-flaky"`.
    public let destinationLabel: String
    /// `"[*] → [x]  Fix flaky gkeep test"`, or `"[x]  Fix flaky gkeep test"`
    /// when already done.
    public let transitionText: String
    /// Task body without checkbox, inline fields, or trailing block ID.
    public let previewText: String
    public let subtaskRows: [SubtaskRow]
    public let leftOpenRows: [LeftOpenRow]
    /// Tense-aware ledger sentence, or nil when the ledger was untouched
    /// (or the task was already done).
    public let ledgerText: String?
    public let unblockedRows: [UnblockedRow]
    public let chips: [String]
    /// Always `"Complete"`: it names what pressing Return will do next,
    /// not what a preview already computed.
    public let primaryActionTitle: String
    public let statusText: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard normalizedKind(capture.kind) == "task_complete",
              let summary = capture.taskComplete
        else {
            return nil
        }

        isDryRun = capture.dryRun
        isAlreadyDone = summary.action == "already_done"

        let routeLabel = capture.routeLabel.isEmpty ? capture.relativeTarget : capture.routeLabel
        let blockID = capture.blockID ?? (summary.blockID.isEmpty ? nil : summary.blockID)
        if let blockID {
            destinationLabel = "\(routeLabel) · ^\(blockID)"
        } else {
            destinationLabel = routeLabel
        }

        previewText = CaptureTogglePresentation.taskPreviewText(
            from: capture.taskLine,
            blockID: capture.blockID ?? (summary.blockID.isEmpty ? nil : summary.blockID)
        )
        let previousMarker = CaptureTogglePresentation.marker(for: capture.previousStatusSymbol)
        let currentMarker = CaptureTogglePresentation.marker(for: capture.statusSymbol)
        if isAlreadyDone {
            transitionText = "\(currentMarker)  \(previewText)"
        } else {
            transitionText = "\(previousMarker) → \(currentMarker)  \(previewText)"
        }

        subtaskRows = summary.subtasks.map { subtask in
            let from = CaptureTogglePresentation.marker(for: subtask.previousStatusSymbol)
            let to = CaptureTogglePresentation.marker(for: subtask.statusSymbol)
            let locator = "\(subtask.notePath) ^\(subtask.blockID)"
            if subtask.text.isEmpty {
                return SubtaskRow(transitionText: "\(from) → \(to)", locatorText: locator)
            }
            return SubtaskRow(
                transitionText: "\(from) → \(to)  \(subtask.text)",
                locatorText: locator
            )
        }

        leftOpenRows = summary.subtasksLeftOpen.map { left in
            let marker = CaptureTogglePresentation.marker(for: left.statusSymbol)
            let locator = "\(left.notePath) ^\(left.blockID)"
            if left.text.isEmpty {
                return LeftOpenRow(
                    displayText: "left \(left.statusName) \(marker)",
                    locatorText: locator
                )
            }
            return LeftOpenRow(
                displayText: "left \(left.statusName) \(marker) \(left.text)",
                locatorText: locator
            )
        }

        unblockedRows = summary.unblocked.map { item in
            let from = CaptureTogglePresentation.marker(for: item.previousStatusSymbol)
            let to = CaptureTogglePresentation.marker(for: item.statusSymbol)
            let locator = "\(item.notePath) ^\(item.blockID)"
            if item.text.isEmpty {
                return UnblockedRow(
                    transitionText: "\(from) → \(to)",
                    locatorText: locator,
                    text: ""
                )
            }
            return UnblockedRow(
                transitionText: "\(from) → \(to)  \(item.text)",
                locatorText: locator,
                text: item.text
            )
        }

        if isAlreadyDone {
            ledgerText = nil
        } else if let ledger = summary.ledger {
            ledgerText = Self.ledgerText(ledger: ledger, isDryRun: capture.dryRun)
        } else {
            ledgerText = nil
        }

        chips = []

        primaryActionTitle = "Complete"

        if isAlreadyDone {
            headline = "Already done"
        } else if capture.dryRun {
            headline = "Would complete"
        } else {
            headline = "Complete"
        }

        let fromName = capture.previousStatusName ?? "Unknown"
        let toName = capture.statusName ?? "Unknown"
        if isAlreadyDone {
            statusText = "Already done — nothing to change"
        } else {
            statusText = "\(headline) → \(destinationLabel) (\(fromName) → \(toName))"
        }

        let taskName = previewText.isEmpty ? (blockID.map { "^\($0)" } ?? routeLabel) : previewText
        if isAlreadyDone {
            notificationTitle = "Already done: \(taskName)"
        } else {
            notificationTitle = "Completed: \(taskName)"
        }
        let notePath = summary.notePath.isEmpty ? routeLabel : summary.notePath
        var body = notePath
        let unblockedNames = summary.unblocked.map(\.text).filter { !$0.isEmpty }
        if !unblockedNames.isEmpty {
            body += " · unblocked \(unblockedNames.joined(separator: ", "))"
        }
        if isAlreadyDone {
            body += " · nothing to change"
        }
        notificationBody = body

        var parts = ["\(headline): \(destinationLabel)", transitionText]
        for row in subtaskRows {
            parts.append("closes \(row.transitionText) \(row.locatorText)")
        }
        for row in leftOpenRows {
            parts.append("\(row.displayText) \(row.locatorText)")
        }
        if let ledgerText {
            parts.append(ledgerText)
        }
        for row in unblockedRows {
            parts.append("unblocks \(row.transitionText) \(row.locatorText)")
        }
        previewAccessibilitySummary = parts.joined(separator: ", ")
    }

    private static func ledgerText(ledger: TaskCompleteLedger, isDryRun: Bool) -> String? {
        var parts: [String] = []
        if !ledger.moved.isEmpty {
            let moves = ledger.moved.map { "\($0.from.name) → \($0.to.name)" }
                .joined(separator: ", ")
            let verb = isDryRun ? "Moves" : "Moved"
            parts.append("\(verb) its Task Link \(moves), struck")
        } else if ledger.struck > 0, ledger.deduplicated == 0 {
            parts.append(isDryRun ? "Strikes its Task Link" : "Struck its Task Link")
        }
        if ledger.deduplicated > 0 {
            let noun = ledger.deduplicated == 1 ? "duplicate" : "duplicates"
            parts.append("dropped \(ledger.deduplicated) \(noun) already linked at the destination")
        }
        if !ledger.removedPlaceholders.isEmpty {
            let verb = isDryRun ? "removes" : "removed"
            let names = ledger.removedPlaceholders.map(\.name).joined(separator: ", ")
            parts.append("\(verb) empty \(names)")
        }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: " · ")
    }
}

private func normalizedKind(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
}
