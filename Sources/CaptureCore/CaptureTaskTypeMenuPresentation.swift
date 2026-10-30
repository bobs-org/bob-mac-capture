import Foundation

/// Whether a hideable theme row is currently hidden after combining Bob's
/// `hidden` flag with a draft-scoped local override. A matching override
/// inverts the server value so an already-hidden row can show, and a
/// just-hidden row stays as a ghost until the draft changes.
public func captureThemeCurrentlyHidden(
    candidate: CaptureCompletionCandidate,
    temporarilyHiddenThemeKey: String?
) -> Bool {
    let key = candidate.themes.first?.key ?? candidate.key
    if let key, temporarilyHiddenThemeKey == key {
        return !candidate.hidden
    }
    return candidate.hidden
}

/// True when Bob's `task_type` row is the typed-name fallback.
public func isTypedTaskTypeRow(_ candidate: CaptureCompletionCandidate) -> Bool {
    candidate.origin == "typed"
}

/// Portable task-type menu copy. Bob owns inheritance, ranking, and
/// replacements; Swift only renders the decoded fields.
public struct CaptureTaskTypeMenuPresentation: Equatable, Sendable {
    public let title: String
    public let headerCaption: String
    public let headerTheme: CapturePomodoroThemeRef?
    public let headerFromHue: PomodoroHomeHue?
    public let rows: [Row]
    public let selectedFooter: String?
    public let hideKeycap: String?
    public let listAccessibilityLabel: String

    public struct Row: Equatable, Sendable {
        public let name: String
        public let queryMatchRange: Range<Int>?
        public let theme: CapturePomodoroThemeRef?
        public let badges: [String]
        public let usageCaption: String
        public let isTyped: Bool
        public let isRefused: Bool
        public let similarCaption: String?
        public let origin: String?
        public let hidden: Bool
        public let currentlyHidden: Bool
        public let effect: String?
        public let key: String?
        public let accessibilityLabel: String
    }

    public init(
        response: CaptureCompletionResponse,
        selectedIndex: Int = 0,
        temporarilyHiddenThemeKey: String? = nil,
        today: String
    ) {
        title = "TASK TYPE"
        let suggestion = response.themeSuggestion
        let header = Self.header(subject: response.subject, suggestion: suggestion)
        headerCaption = header.caption
        headerTheme = header.theme
        headerFromHue = header.fromHue
        rows = response.candidates.map { candidate in
            Self.row(
                for: candidate,
                query: response.query ?? "",
                subject: response.subject,
                suggestion: suggestion,
                temporarilyHiddenThemeKey: temporarilyHiddenThemeKey,
                today: today
            )
        }
        let selected =
            response.candidates.indices.contains(selectedIndex)
            ? response.candidates[selectedIndex] : nil
        selectedFooter = selected.map {
            Self.footer(for: $0, subject: response.subject, suggestion: suggestion)
        }
        if let selected,
            selected.origin == "configured" || selected.origin == "history"
        {
            let hidden = captureThemeCurrentlyHidden(
                candidate: selected,
                temporarilyHiddenThemeKey: temporarilyHiddenThemeKey
            )
            hideKeycap = hidden ? "⌃D show" : "⌃D hide"
        } else {
            hideKeycap = nil
        }
        let count = rows.count
        listAccessibilityLabel =
            "Task type suggestions, \(count) result\(count == 1 ? "" : "s")"
    }

    public static func todayISODate(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func usageCaption(
        lastUsed: String?,
        daysUsed: Int?,
        today: String
    ) -> String {
        if let lastUsed, lastUsed == today {
            return "today"
        }
        if let daysUsed, daysUsed > 0 {
            return daysUsed == 1 ? "1 day" : "\(daysUsed) days"
        }
        return "never used"
    }

    public static func header(
        subject: String?,
        suggestion: CaptureThemeSuggestion?
    ) -> (caption: String, theme: CapturePomodoroThemeRef?, fromHue: PomodoroHomeHue?) {
        guard let suggestion else {
            return ("no default here", nil, nil)
        }
        if subject == "existing", suggestion.source == "task" {
            return (
                "this task is \(suggestion.theme.name)",
                suggestion.theme,
                suggestion.from?.hue ?? suggestion.inherited?.value.from?.hue
            )
        }
        let shown = suggestion.inherited?.value ?? suggestion
        if shown.source.isEmpty, shown.theme.name.isEmpty {
            return ("no default here", nil, shown.from?.hue)
        }
        return (caption(for: shown), shown.theme, shown.from?.hue)
    }

    public static func footer(
        for candidate: CaptureCompletionCandidate,
        subject: String?,
        suggestion: CaptureThemeSuggestion?
    ) -> String {
        if candidate.refused != nil {
            return "Add it under types: to use it"
        }
        let name = candidate.name ?? candidate.replacement
        let inherited = inheritedSuggestion(subject: subject, suggestion: suggestion)
        let suggests: String
        let from: String
        if let inherited {
            suggests = caption(for: inherited)
            from = fromLabel(inherited)
        } else {
            suggests = "no default here"
            from = "no default here"
        }
        switch candidate.effect {
        case "set":
            return "this task becomes \(name) · \(suggests)"
        case "clear":
            return "task type cleared · \(suggests)"
        case "keep":
            return "stays \(name) · \(from)"
        default:
            return suggests
        }
    }

    public static func similarCaption(similarTo: [String]) -> String? {
        let names = similarTo.filter { !$0.isEmpty }
        guard let first = names.first else {
            return nil
        }
        if names.count == 1 {
            return "did you mean \(first)?"
        }
        return "did you mean \(first) or \(names[1])?"
    }

    private static func row(
        for candidate: CaptureCompletionCandidate,
        query: String,
        subject: String?,
        suggestion: CaptureThemeSuggestion?,
        temporarilyHiddenThemeKey: String?,
        today: String
    ) -> Row {
        let name = candidate.name ?? candidate.replacement
        let theme = candidate.themes.first
        let isTyped = isTypedTaskTypeRow(candidate)
        let currentlyHidden = captureThemeCurrentlyHidden(
            candidate: candidate,
            temporarilyHiddenThemeKey: temporarilyHiddenThemeKey
        )
        var badges: [String] = []
        if candidate.inherited {
            if let label = candidate.suggestionLabel, !label.isEmpty {
                badges.append(label)
            }
        }
        if candidate.current, subject == "existing" {
            badges.append("Current")
        }
        if theme?.hueSource == "pin" {
            badges.append("Pinned")
        }
        if theme?.hueSource == "exempt" {
            badges.append("Exempt")
        }
        if currentlyHidden {
            badges.append("Hidden")
        }
        if isTyped {
            badges.append(CaptureUnconfiguredThemePresentation.createBadge)
        }
        let similar = isTyped ? similarCaption(similarTo: candidate.similarTo) : nil
        let footer = footer(for: candidate, subject: subject, suggestion: suggestion)
        let spoken =
            theme.map {
                CaptureUnconfiguredThemePresentation.spokenColor(for: $0)
            } ?? name
        var accessibility = "Task type \(name), \(spoken). \(footer)."
        if candidate.refused != nil {
            accessibility += " Unavailable."
        }
        return Row(
            name: name,
            queryMatchRange: completionMatchRange(in: name, query: query),
            theme: theme,
            badges: badges,
            usageCaption: usageCaption(
                lastUsed: candidate.lastUsed, daysUsed: candidate.daysUsed, today: today),
            isTyped: isTyped,
            isRefused: candidate.refused != nil,
            similarCaption: similar,
            origin: candidate.origin,
            hidden: candidate.hidden,
            currentlyHidden: currentlyHidden,
            effect: candidate.effect,
            key: candidate.key ?? theme?.key,
            accessibilityLabel: accessibility
        )
    }

    private static func inheritedSuggestion(
        subject: String?,
        suggestion: CaptureThemeSuggestion?
    ) -> CaptureThemeSuggestion? {
        if subject == "existing", suggestion?.source == "task" {
            return suggestion?.inherited?.value
        }
        return suggestion?.inherited?.value ?? suggestion
    }

    private static func caption(for suggestion: CaptureThemeSuggestion) -> String {
        switch suggestion.source {
        case "task":
            return "this task is \(suggestion.theme.name)"
        case "reading":
            return "reading tasks suggest \(suggestion.theme.name)"
        case "review":
            return "daily review suggests \(suggestion.theme.name)"
        case "default":
            return "default type suggests \(suggestion.theme.name)"
        case "note":
            return "\(stem(of: suggestion)) suggests \(suggestion.theme.name)"
        default:
            return suggestion.theme.name.isEmpty ? "no default here" : suggestion.theme.name
        }
    }

    private static func fromLabel(_ suggestion: CaptureThemeSuggestion) -> String {
        switch suggestion.source {
        case "task":
            return "this task"
        case "reading":
            return "reading task"
        case "default":
            return "default type"
        case "note":
            if !suggestion.label.isEmpty {
                return suggestion.label
            }
            return "from \(stem(of: suggestion))"
        default:
            return suggestion.label.isEmpty ? "no default here" : suggestion.label
        }
    }

    private static func stem(of suggestion: CaptureThemeSuggestion) -> String {
        if let from = suggestion.from, !from.stem.isEmpty {
            return from.stem
        }
        let label = suggestion.label
        if label.hasPrefix("from "), !label.dropFirst(5).isEmpty {
            return String(label.dropFirst(5))
        }
        return label.isEmpty ? "note" : label
    }
}
