import Foundation

/// Pure presentation model for a `task_toggle` capture result (`kind == "task_toggle"`,
/// `toggle_direction` present), built once from `CaptureCommandSuccess` so the
/// SwiftUI/AppKit layer never branches on toggle-specific JSON fields or spells a
/// toggle string literal itself. Works equally for a dry-run live preview and a
/// committed capture — `isDryRun` is the only thing that changes the tense of
/// `statusText`; every other field describes the same before/after transition.
///
/// Wording choices here (status text, VoiceOver announcement, notification copy) are
/// this type's own decisions, not wire contract — the only bytes that must match the
/// `bob` CLI exactly are `chips`, `addedLinkText`, and `removedLinksText`, which mirror
/// `print_human_task_toggle_success` in `src/native/capture.rs` so the panel's preview
/// and the CLI's `--dry-run` output describe the same change the same way.
public struct CaptureTogglePresentation: Equatable, Sendable {
    public enum Direction: String, Equatable, Sendable {
        case next
        case open
    }

    public let direction: Direction
    public let isDryRun: Bool

    /// `"cash.md \u{00b7} ^goog-exit"` — route note label plus the toggled block ID.
    public let routeDestinationLabel: String
    /// `"2026/20260910.md \u{00b7} under CODING"`, or without the `under` suffix when
    /// there is no named Pomodoro (or the direction is `open`, where naming is inert).
    /// `nil` only when Bob omitted `day_file`, which a toggle result never does.
    public let dayFileDestinationLabel: String?
    /// Whether the daily note's content actually changed, so a Command-Return open
    /// after capture knows whether to also open the day file alongside the route note.
    public let dayFileChanged: Bool

    public let previousTaskLine: String
    public let taskLine: String
    /// `"[ ]"`, `"[*]"`, `"[?]"` — bracket-formatted, matching `style_task_status_marker`
    /// minus the color, which is a view concern. Falls back to `"[?]"` if Bob omitted
    /// the symbol, which a toggle result never does.
    public let previousStatusMarker: String
    public let statusMarker: String

    public let blockID: String?
    public let blockLink: String?
    public let pomodoroName: String?
    /// The block link text to show on a `+` line, direction `next` only. Unprefixed:
    /// the view chooses the `+`/color.
    public let addedLinkText: String?
    /// `"removed N Pomodoro task links"` (direction `open`, always present, even for
    /// zero) or `"removed N later Pomodoro task links"` (direction `next`, present only
    /// when N > 0) — mirrors `print_removed_pomodoro_links` exactly. Unprefixed: the
    /// view chooses the `\u{2212}`/color.
    public let removedLinksText: String?
    /// Dim chips in `print_human_task_toggle_success`'s exact order and wording:
    /// "removed future schedule", "logged schedule change", "already linked",
    /// "#<name> not used when clearing".
    public let chips: [String]

    /// `"Set Next"` / `"Set Open"` — the footer's primary action verb. Does not vary
    /// with `isDryRun`: it always names what pressing Return will do next, not what a
    /// preview already computed.
    public let primaryActionTitle: String

    public let statusText: String
    public let voiceOverAnnouncement: String
    public let notificationTitle: String
    public let notificationBody: String

    public init?(capture: CaptureCommandSuccess) {
        guard let rawDirection = capture.toggleDirection,
              let direction = Direction(rawValue: rawDirection)
        else {
            return nil
        }

        self.direction = direction
        isDryRun = capture.dryRun

        let routeLabel = capture.routeLabel.isEmpty ? capture.relativeTarget : capture.routeLabel
        blockID = capture.blockID
        routeDestinationLabel = blockID.map { "\(routeLabel) \u{00b7} ^\($0)" } ?? routeLabel

        previousTaskLine = capture.previousTaskLine ?? capture.taskLine
        taskLine = capture.taskLine
        previousStatusMarker = Self.marker(for: capture.previousStatusSymbol)
        statusMarker = Self.marker(for: capture.statusSymbol)

        blockLink = capture.blockLink
        pomodoroName = capture.pomodoroName

        let removedLinks = capture.removedPomodoroLinks ?? 0
        let pomodoroAlreadyLinked = capture.pomodoroAlreadyLinked ?? false
        let pomodoroSelectorUnused = capture.pomodoroSelectorUnused ?? false

        switch direction {
        case .next:
            addedLinkText = capture.blockLink
            removedLinksText = removedLinks > 0
                ? Self.removedLinksSummary(count: removedLinks, qualifier: "later ")
                : nil
        case .open:
            addedLinkText = nil
            removedLinksText = Self.removedLinksSummary(count: removedLinks, qualifier: "")
        }

        var chips: [String] = []
        if capture.removedScheduled != nil {
            chips.append("removed future schedule")
        }
        if capture.scheduleLog != nil {
            chips.append("logged schedule change")
        }
        if pomodoroAlreadyLinked {
            chips.append("already linked")
        }
        if pomodoroSelectorUnused {
            let selector = capture.pomodoroName.map { "#\($0)" } ?? "#name"
            chips.append("\(selector) not used when clearing")
        }
        self.chips = chips

        if let dayFile = capture.dayFile {
            let relativeDayFile = Self.relativeDayFileLabel(
                dayFile: dayFile,
                target: capture.target,
                relativeTarget: capture.relativeTarget
            )
            let under = (direction == .next ? capture.pomodoroName : nil)
                .map { " \u{00b7} under \($0)" } ?? ""
            dayFileDestinationLabel = "\(relativeDayFile)\(under)"
        } else {
            dayFileDestinationLabel = nil
        }

        switch direction {
        case .next:
            dayFileChanged = !pomodoroAlreadyLinked || removedLinks > 0
        case .open:
            dayFileChanged = removedLinks > 0
        }

        primaryActionTitle = direction == .next ? "Set Next" : "Set Open"

        let statusVerb: String
        switch (capture.dryRun, direction) {
        case (true, .next): statusVerb = "Would Set Next"
        case (true, .open): statusVerb = "Would Set Open"
        case (false, .next): statusVerb = "Set Next"
        case (false, .open): statusVerb = "Set Open"
        }
        statusText =
            "\(statusVerb) \u{2192} \(routeDestinationLabel) (\(previousStatusMarker) \u{2192} \(statusMarker))"

        let fromStatusName = capture.previousStatusName ?? "Unknown"
        let toStatusName = capture.statusName ?? "Unknown"

        var announcementParts = ["\(statusVerb): \(routeLabel), \(fromStatusName) to \(toStatusName)"]
        if direction == .next, removedLinks == 0, !pomodoroAlreadyLinked {
            announcementParts.append("linked to today's Pomodoro")
        }
        if removedLinks > 0 {
            let qualifier = direction == .next ? "later " : ""
            announcementParts.append(Self.removedLinksSummary(count: removedLinks, qualifier: qualifier))
        }
        announcementParts.append(contentsOf: chips)
        voiceOverAnnouncement = announcementParts.joined(separator: ". ")

        notificationTitle = primaryActionTitle
        var bodyLines = ["\(fromStatusName) \u{2192} \(toStatusName)  \(routeDestinationLabel)"]
        if let dayFileDestinationLabel {
            bodyLines.append(dayFileDestinationLabel)
        }
        if let addedLinkText {
            bodyLines.append("+ \(addedLinkText)")
        }
        if let removedLinksText {
            bodyLines.append("\u{2212} \(removedLinksText)")
        }
        if !chips.isEmpty {
            bodyLines.append(chips.joined(separator: " \u{00b7} "))
        }
        notificationBody = bodyLines.joined(separator: "\n")
    }

    private static func marker(for symbol: String?) -> String {
        guard let symbol, !symbol.isEmpty else {
            return "[?]"
        }
        return "[\(symbol)]"
    }

    private static func removedLinksSummary(count: Int, qualifier: String) -> String {
        let plural = count == 1 ? "" : "s"
        return "removed \(count) \(qualifier)Pomodoro task link\(plural)"
    }

    /// Bob reports `day_file` as an absolute path (it has no `relative_day_file`
    /// counterpart the way the route note has `relative_target`). Derive a
    /// display-friendly relative path the same way `target`/`relative_target` already
    /// relate: by stripping the bob-directory prefix they share. Falls back to the
    /// absolute path if `target` doesn't end with `relativeTarget` (should not happen
    /// for a real Bob response, but a display helper must not crash on it).
    private static func relativeDayFileLabel(
        dayFile: String,
        target: String,
        relativeTarget: String
    ) -> String {
        guard !relativeTarget.isEmpty, target.hasSuffix(relativeTarget) else {
            return dayFile
        }
        let bobDirPrefix = String(target.dropLast(relativeTarget.count))
        guard !bobDirPrefix.isEmpty, dayFile.hasPrefix(bobDirPrefix) else {
            return dayFile
        }
        return String(dayFile.dropFirst(bobDirPrefix.count))
    }
}
