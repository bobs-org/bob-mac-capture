import CaptureCore
import Foundation

public struct RefsTodayLinkToast: Equatable, Sendable {
    public enum Style: Equatable, Sendable { case linked, moved, already, guarded }
    public let style: Style
    public let title: String
    public let value: String
    public let detail: String

    public var glyphName: String { style == .guarded ? "lock.fill" : "timer" }
}

/// All copy and clock-dependent display math for the card and its outcomes.
/// No value here selects a destination or changes a task's lane.
public enum RefsTodayLinkPresentation {
    public static let timeoutMessage = "Linking the reference took too long and was stopped."
    public static let timeoutHint = "Check today's ledger and try again."
    public static let bobTooOldMessage =
        "This bob can't link references to today yet — update bob on this Mac"
    public static let header = "LINK TO TODAY"
    public static let untitled = PomodoroHomesPresentation.untitled
    public static let linking = "Linking…"
    public static let loading = "Loading Pomodoros…"
    public static let reloading = "Refreshing Pomodoros…"
    public static let emptyTitle = "No open Pomodoros today"
    public static let emptyHint = "Type a name to plan one"
    public static let newPill = "New"
    public static let invalidResponse = "Bob returned no link result. Try again."
    public static let filterAccessibilityLabel = "Pomodoro"
    public static let failureTitle = "Could not link reference"
    public static let toastHoldDuration: TimeInterval = 2.2

    public static func taskCaption(path: String?, blockID: String?) -> String {
        [path, blockID.map { "^\($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    public static func placeholder(pomodoros: [RefsTodayLinkPomodoro]) -> String {
        guard let row = pomodoros.first(where: \.isDefault) else { return "Name a Pomodoro" }
        return "Pomodoro — ↵ \(rowTitle(row))"
    }

    public static func rowTitle(_ row: RefsTodayLinkPomodoro) -> String {
        PomodoroHomesPresentation.displayName(authored: row.name, homes: row.homes)
    }

    public static func rowTitleIsDerived(_ row: RefsTodayLinkPomodoro) -> Bool {
        PomodoroHomesPresentation.nameIsDerived(authored: row.name, homes: row.homes)
    }

    public static func namedHomeChip(_ row: RefsTodayLinkPomodoro) -> String? {
        PomodoroHomesPresentation.namedChip(authored: row.name, homes: row.homes)
    }

    public static func namedHomeHue(_ row: RefsTodayLinkPomodoro) -> PomodoroHomeHue? {
        namedHomeChip(row) == nil ? nil : row.homes?.hue
    }

    /// Per-component swatches for the row's Pomodoro name, from Bob's
    /// `themes` refs. Empty when the row is unnamed or an older Bob
    /// omits the array; unknown components render neutral.
    public static func themeSwatches(_ row: RefsTodayLinkPomodoro) -> [CaptureThemeSwatch] {
        guard let name = row.name, !name.isEmpty, !row.themes.isEmpty else {
            return []
        }
        return row.themes.map { CaptureThemeSwatch(hue: $0.hue, known: $0.known) }
    }

    /// Spoken theme colors for the row's accessibility label.
    /// Empty when the row carries no theme refs.
    public static func spokenThemeColors(_ row: RefsTodayLinkPomodoro) -> [String] {
        guard let name = row.name, !name.isEmpty, !row.themes.isEmpty else {
            return []
        }
        return PomodoroThemeSwatches.spokenThemeColors(forName: name, refs: row.themes)
    }

    public static func createTitle(query: String) -> String {
        "New Pomodoro \(RefsTodayLinkCard.canonicalName(query))"
    }

    public static func pills(_ row: RefsTodayLinkPomodoro) -> [String] {
        var result: [String] = []
        if row.running { result.append("Running") } else if row.isDefault { result.append("Next up") }
        if row.linked { result.append("Here") }
        return result
    }

    public static func rowMeta(
        _ row: RefsTodayLinkPomodoro, now: Date, timeZone: TimeZone = .current
    ) -> String {
        var parts = [timeRange(row.timeRange) ?? "planned"]
        if row.running, let end = date(row.endsAt, timeZone: timeZone) {
            let seconds = end.timeIntervalSince(now)
            let minutes = Int(ceil(abs(seconds) / 60))
            parts.append("\(minutes)m \(seconds >= 0 ? "left" : "over")")
        }
        parts.append(
            row.taskLinkCount == 0
                ? "empty" : "\(row.taskLinkCount) \(row.taskLinkCount == 1 ? "task" : "tasks")")
        return parts.joined(separator: " · ")
    }

    public static func progress(
        _ row: RefsTodayLinkPomodoro, now: Date, timeZone: TimeZone = .current
    ) -> Double? {
        guard row.running, let start = date(row.startsAt, timeZone: timeZone),
            let end = date(row.endsAt, timeZone: timeZone), end > start
        else { return nil }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    public static func rowAccessibilityLabel(
        _ row: RefsTodayLinkPomodoro, selected: Bool, now: Date, timeZone: TimeZone = .current
    ) -> String {
        var parts =
            [PomodoroHomesPresentation.accessibilityName(authored: row.name, homes: row.homes)]
            + pills(row).map { $0.lowercased() }
        parts.append(contentsOf: spokenThemeColors(row))
        parts.append(rowMeta(row, now: now, timeZone: timeZone))
        if selected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    public static func defaultProblem(
        _ problem: RefsTodayLinkFailure?, pomodoros: [RefsTodayLinkPomodoro]
    ) -> String? {
        guard let problem else { return nil }
        if problem.code == "multiple_running" {
            // In an ambiguous listing bob deliberately marks no row as `running`.
            // Count its timed open entries only for the banner, never for selection.
            let count = pomodoros.filter { $0.startsAt != nil && $0.endsAt != nil }.count
            return "\(count) Pomodoros are running — pick one"
        }
        return problem.code == "no_open_pomodoro" ? emptyTitle : problem.message
    }

    public static func laneChip(capture: CaptureCommandSuccess?) -> String? {
        guard let capture else { return nil }
        if CaptureLinkGuardPresentation(capture: capture) != nil { return "won't link" }
        guard CapturePomodoroLinkPresentation(capture: capture) != nil else { return nil }
        if capture.statusChanged ?? (capture.previousStatusSymbol != capture.statusSymbol) {
            return "\(capture.previousStatusName ?? "Ready") → \(capture.statusName ?? "Next")"
        }
        return "stays \(capture.statusName ?? "Next")"
    }

    public static func previewLine(_ response: RefsTodayLinkResponse?) -> String? {
        guard let response else { return nil }
        if let problem = response.error { return problem.message }
        guard let capture = response.capture else { return nil }
        if let guardCopy = CaptureLinkGuardPresentation(capture: capture) {
            return [guardCopy.headline, guardCopy.detail].filter { !$0.isEmpty }.joined(separator: " — ")
        }
        guard let link = CapturePomodoroLinkPresentation(capture: capture) else { return nil }
        return ([laneChip(capture: capture), link.ledgerText].compactMap { $0 } + link.chips).joined(
            separator: " · ")
    }

    public static func hints(query: String) -> String {
        let exact =
            RefsTodayLinkCard.canonicalName(query).isEmpty
            ? "" : "   ⇧↵ new \(RefsTodayLinkCard.canonicalName(query))"
        return "↑↓ select   ↵ link\(exact)   esc cancel"
    }

    public static func refusalTitle(_ problem: RefsTodayLinkFailure) -> String {
        switch problem.code {
        case "no_reading_task": return "No reading task to plan"
        case "reading_task_closed":
            return problem.message.contains("already read") ? "Already read" : "Reading task is closed"
        case "ambiguous_reading_task": return "Multiple reading tasks"
        case "v1_reading_task": return "Reading task needs migration"
        case "reading_task_unroutable": return "Reading task can't be linked"
        case "no_daily_note": return "Today's daily note doesn't exist yet"
        case "no_pomodoros_section": return "No Pomodoros section today"
        case "bob_too_old": return "Update bob to link references"
        default: return failureTitle
        }
    }

    /// Destination display name: Bob's authored name when present, else the
    /// target row's derived homes label (R7 display-only), else Untitled.
    /// Rows still display the derived label; routing never uses it.
    public static func destinationDisplayName(
        response: RefsTodayLinkResponse, capture: CaptureCommandSuccess
    ) -> String {
        if let name = capture.pomodoroName, !name.isEmpty { return name }
        if let name = capture.pomodoroLinkDestination?.name, !name.isEmpty { return name }
        if let line = capture.pomodoroLinkDestination?.line,
            let row = response.pomodoros.first(where: { $0.line == line })
        {
            return PomodoroHomesPresentation.displayName(authored: row.name, homes: row.homes)
        }
        return untitled
    }

    static func sourceDisplayName(
        response: RefsTodayLinkResponse, capture: CaptureCommandSuccess
    ) -> String {
        if let name = capture.pomodoroLinkSource?.name, !name.isEmpty { return name }
        if let line = capture.pomodoroLinkSource?.line,
            let row = response.pomodoros.first(where: { $0.line == line })
        {
            return PomodoroHomesPresentation.displayName(authored: row.name, homes: row.homes)
        }
        return untitled
    }

    public static func toast(response: RefsTodayLinkResponse, title: String) -> RefsTodayLinkToast? {
        guard response.ok == true, let capture = response.capture else { return nil }
        if let guardCopy = CaptureLinkGuardPresentation(capture: capture) {
            return RefsTodayLinkToast(
                style: .guarded, title: guardCopy.notificationTitle, value: title, detail: guardCopy.detail)
        }
        guard let link = CapturePomodoroLinkPresentation(capture: capture) else { return nil }
        let destination = destinationDisplayName(response: response, capture: capture)
        var detail = [laneChip(capture: capture)].compactMap { $0 }
        let style: RefsTodayLinkToast.Style
        let headline: String
        switch capture.pomodoroLinkAction {
        case "moved":
            style = .moved
            headline = "Moved to \(destination)"
            detail.insert(
                "from \(sourceDisplayName(response: response, capture: capture))", at: 0)
        case "already_current":
            style = .already
            headline = "Already in \(destination)"
            if response.changed == false {
                detail = ["already \(capture.statusName ?? "Next")", "no change"]
            }
        default:
            style = .linked
            headline = "Linked under \(capture.createsPomodoro == true ? "new " : "")\(destination)"
        }
        return RefsTodayLinkToast(
            style: style, title: headline, value: title,
            detail: (detail + link.chips).joined(separator: " · "))
    }

    public static func announcement(response: RefsTodayLinkResponse, title: String) -> String? {
        guard let toast = toast(response: response, title: title) else { return nil }
        let sentence: String
        switch toast.style {
        case .linked:
            sentence = toast.title.replacingOccurrences(
                of: "Linked under ", with: "Linked \(title) under ")
        case .moved:
            sentence = toast.title.replacingOccurrences(of: "Moved to ", with: "Moved \(title) to ")
        case .already:
            sentence =
                "\(title) is \(toast.title.replacingOccurrences(of: "Already in ", with: "already in "))"
        case .guarded: sentence = "Not linked: \(title)"
        }
        let detail = toast.detail.replacingOccurrences(of: " → ", with: " to ").replacingOccurrences(
            of: " · ", with: ". ")
        return "\(sentence)." + (detail.isEmpty ? "" : " \(detail).")
    }

    public static func notification(response: RefsTodayLinkResponse, title: String) -> (
        title: String, body: String
    )? {
        guard let toast = toast(response: response, title: title) else { return nil }
        return (
            toast.title, [toast.value, toast.detail].filter { !$0.isEmpty }.joined(separator: "\n")
        )
    }

    public static func failureNotification(message: String, hint: String? = nil) -> (
        title: String, body: String
    ) {
        ("Reference link failed", [message, hint].compactMap { $0 }.joined(separator: "\n"))
    }

    private static func timeRange(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-")
        guard parts.count == 2, parts.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isNumber) }) else {
            return raw
        }
        return parts.map { "\($0.prefix(2)):\($0.suffix(2))" }.joined(separator: "–")
    }

    private static func date(_ raw: String?, timeZone: TimeZone) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let value = formatter.date(from: raw) { return value }
        return ISO8601DateFormatter().date(from: raw)
    }
}
