import Foundation

/// Pure presentation model for a `pomodoro_link` capture result
/// (`kind == "pomodoro_link"`), built once from `CaptureCommandSuccess` so the
/// SwiftUI/AppKit layer never branches on link-specific JSON fields itself. Works
/// equally for a dry-run live preview and a committed capture — `isDryRun` is the
/// only thing that changes the tense of `statusText`; every other field describes
/// the same status transition and ledger outcome.
///
/// The preview's only source of truth is Bob's resolved link fields — the status
/// transition, `pomodoro_link_action`, the pre-image source and post-image
/// destination endpoints, and the optional atomic-start summary — which come from
/// `bob capture --dry-run --no-clip --format json` for live preview and the same
/// command without `--dry-run`/`--no-clip` for submission. There is no Swift-side
/// queue, clock, or ledger logic here, only wording.
///
/// Wording mirrors the `pomodoro_link` human output in `src/native/capture.rs`
/// (`would link` / `would start`, the transition line, `Linked under` /
/// `Moved Task Link` / `Task Link already in`, `would start … at line N`) so the
/// panel and the CLI describe the same link the same way. The session row itself
/// stays with `CapturePomodoroStartPresentation`; endpoint labels, status markers,
/// task preview text, and the day-file label are shared with
/// `CaptureTogglePresentation`.
public struct CapturePomodoroLinkPresentation: Equatable, Sendable {
    public let isDryRun: Bool

    /// `"sase.md \u{00b7} ^deep-fix"` — route note label plus the linked block ID.
    public let routeDestinationLabel: String
    /// `"[ ] \u{2192} [*]  Ready thing"`, `"[*] already Next  Fix deep bug"`, or
    /// `"[/] stays In Progress  Outline talk"` — the compact transition line.
    public let transitionText: String
    /// `"Linked under BUGS"`, `"Moved Task Link BUGS \u{2192} FOCUS (created
    /// FOCUS)"`, or `"Task Link already in BUGS; no ledger change."`, each with
    /// an appended ` · <label>` when Bob placed the destination by type.
    /// (`Linked under CHORE · default type`).
    public let ledgerText: String
    /// The resolved destination entry name (`"BUGS"`), used for notification
    /// titles and the day-file destination line.
    public let destinationLabel: String
    /// `"2026/20260710.md \u{00b7} under BUGS"`. `nil` only when Bob omitted
    /// `day_file`, which a link result never does.
    public let dayFileDestinationLabel: String?
    /// Legacy `CaptureOpenPlan` fallback signal for whether to include the daily note
    /// alongside the route note when an older Bob omits `open_notes`.
    public let dayFileChanged: Bool
    /// `"Start"` when Bob reported an atomic `pomodoro_start`, else `"Link"` — the
    /// footer's primary action verb. Does not vary with `isDryRun`: it always
    /// names what pressing Return will do next, not what a preview computed.
    public let primaryActionTitle: String
    /// Dim chips: "dropped dependency on …" / "dropped N dependencies"
    /// first, then the toggle vocabulary "removed future schedule" and
    /// "logged schedule change".
    public let chips: [String]

    public let statusText: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String
    /// Optional task-type line, e.g. `type → FIX · sase_blog suggests WRITE`.
    public let taskThemeLine: String?
    /// Optional ledger relocation, e.g. `BUILD → FIX · running entry renamed`.
    public let typeRelocationLine: String?

    public init?(capture: CaptureCommandSuccess) {
        guard Self.isPomodoroLinkKind(capture.kind) else {
            return nil
        }

        isDryRun = capture.dryRun

        let routeLabel = capture.routeLabel.isEmpty ? capture.relativeTarget : capture.routeLabel
        routeDestinationLabel =
            capture.blockID.map { "\(routeLabel) \u{00b7} ^\($0)" } ?? routeLabel

        let previewText = CaptureTogglePresentation.taskPreviewText(
            from: capture.taskLine,
            blockID: capture.blockID
        )
        let previousMarker = CaptureTogglePresentation.marker(for: capture.previousStatusSymbol)
        let marker = CaptureTogglePresentation.marker(for: capture.statusSymbol)
        let statusChanged = capture.statusChanged
            ?? (capture.previousStatusSymbol != capture.statusSymbol)
        if statusChanged {
            transitionText = "\(previousMarker) \u{2192} \(marker)  \(previewText)"
        } else if capture.statusSymbol == "*" {
            transitionText = "\(marker) already Next  \(previewText)"
        } else if capture.statusSymbol == "/" {
            transitionText = "\(marker) stays In Progress  \(previewText)"
        } else {
            transitionText = "\(marker) unchanged  \(previewText)"
        }

        let destination = capture.pomodoroName
            ?? CaptureTogglePresentation.endpointLabel(capture.pomodoroLinkDestination)
            ?? "today's Pomodoro"
        destinationLabel = destination

        // Additive D7 label: Bob appends ` · <label>` (`from dev`,
        // `default type`) to the destination it placed by type. Older Bob
        // omits `type`, so the suffix stays empty and rendering is unchanged.
        let placedSuffix: String = {
            guard
                let label = capture.pomodoroLinkDestination?.placedType?.label,
                !label.isEmpty
            else {
                return ""
            }
            return " · \(label)"
        }()

        let sourceLabel = CaptureTogglePresentation.endpointLabel(capture.pomodoroLinkSource)
        let createdPomodoro = capture.createsPomodoro ?? false
        switch capture.pomodoroLinkAction {
        case "moved":
            let source = sourceLabel ?? "source"
            if createdPomodoro {
                ledgerText = "Moved Task Link \(source) \u{2192} \(destination)"
                    + " (created \(destination))\(placedSuffix)"
            } else {
                ledgerText =
                    "Moved Task Link \(source) \u{2192} \(destination)\(placedSuffix)"
            }
        case "already_current":
            ledgerText =
                "Task Link already in \(destination)\(placedSuffix); no ledger change."
        default:
            ledgerText = "Linked under \(destination)\(placedSuffix)"
        }

        if let dayFile = capture.dayFile {
            let relativeDayFile = CaptureTogglePresentation.relativeDayFileLabel(
                dayFile: dayFile,
                target: capture.target,
                relativeTarget: capture.relativeTarget
            )
            dayFileDestinationLabel =
                "\(relativeDayFile) \u{00b7} under \(destination)\(placedSuffix)"
        } else {
            dayFileDestinationLabel = nil
        }

        // An already-current link with no start leaves both notes byte-identical;
        // anything else (an insert, a move, or a started session) rewrites the day
        // file.
        dayFileChanged = capture.pomodoroLinkAction != "already_current"
            || capture.pomodoroStart != nil

        primaryActionTitle = capture.pomodoroStart == nil ? "Link" : "Start"

        var chips: [String] = []
        if let dropped = CaptureDroppedDependency.chip(from: capture.droppedDependencies) {
            chips.append(dropped)
        }
        if capture.removedScheduled != nil {
            chips.append("removed future schedule")
        }
        if capture.scheduleLog != nil {
            chips.append("logged schedule change")
        }
        self.chips = chips

        let action = primaryActionTitle.lowercased()
        let verb = capture.dryRun ? "Would \(action)" : primaryActionTitle
        let fromStatusName = capture.previousStatusName ?? "Unknown"
        let toStatusName = capture.statusName ?? "Unknown"
        let statusPhrase = statusChanged
            ? "\(fromStatusName) \u{2192} \(toStatusName)"
            : "\(toStatusName) unchanged"
        statusText = "\(verb) \u{2192} \(routeDestinationLabel) (\(statusPhrase))"

        if capture.pomodoroStart != nil {
            notificationTitle = "Started \(destination)"
        } else {
            switch capture.pomodoroLinkAction {
            case "moved":
                notificationTitle = "Moved to \(destination)"
            case "already_current":
                notificationTitle = "Already in \(destination)"
            default:
                notificationTitle = "Linked to \(destination)"
            }
        }
        taskThemeLine = CaptureTaskThemePresentation.line(
            for: capture.taskTheme, isDryRun: capture.dryRun)
        typeRelocationLine = CaptureTaskThemePresentation.relocationLine(
            for: capture.typeRelocation)

        var bodyLines = ["\(statusPhrase)  \(routeDestinationLabel)"]
        if let dayFileDestinationLabel {
            bodyLines.append(dayFileDestinationLabel)
        }
        bodyLines.append(ledgerText)
        if let taskThemeLine {
            bodyLines.append(taskThemeLine)
        }
        if let typeRelocationLine {
            bodyLines.append(typeRelocationLine)
        }
        if let start = CapturePomodoroStartPresentation(capture: capture) {
            bodyLines.append(start.notificationDetail)
        }
        if !chips.isEmpty {
            bodyLines.append(chips.joined(separator: " \u{00b7} "))
        }
        notificationBody = bodyLines.joined(separator: "\n")

        var previewParts = [routeDestinationLabel, transitionText, ledgerText]
        if let dayFileDestinationLabel {
            previewParts.append(dayFileDestinationLabel)
        }
        if let taskThemeLine {
            previewParts.append(taskThemeLine)
        }
        if let typeRelocationLine {
            previewParts.append(typeRelocationLine)
        }
        if let start = CapturePomodoroStartPresentation(capture: capture) {
            previewParts.append(start.accessibilitySummary)
        }
        previewParts.append(contentsOf: chips)
        previewAccessibilitySummary = previewParts.joined(separator: ", ")
    }

    private static func isPomodoroLinkKind(_ kind: String) -> Bool {
        kind
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_") == "pomodoro_link"
    }
}
