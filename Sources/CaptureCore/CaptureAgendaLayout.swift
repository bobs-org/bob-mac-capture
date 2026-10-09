import Foundation

/// Shared agenda geometry: every constant the fit planner budgets and
/// the agenda views lay out with. Views must use these, never local
/// numbers, so the planner's total matches the rendered height.
public enum CaptureAgendaLayoutMetrics {
    /// Outer padding of the agenda pane (matches `PreviewPane`).
    public static let panePadding: Double = 10
    /// Corner radius of the agenda pane and the Now card.
    public static let cornerRadius: Double = 8
    /// Inner padding of the Now card.
    public static let nowCardInnerPadding: Double = 6
    /// Width of the pink Now rail.
    public static let railWidth: Double = 3
    /// Vertical space between groups.
    public static let groupSpacing: Double = 10
    /// Vertical space between rows inside a group.
    public static let rowSpacing: Double = 2
    /// Space after a group header.
    public static let headerBottomSpacing: Double = 4
    /// Horizontal indent per depth, measured from the title column.
    public static let indentStep: Double = 14
    /// Width reserved for the `=x` number badge column.
    public static let badgeColumnWidth: Double = 26
    /// Width reserved for the status glyph column.
    public static let glyphColumnWidth: Double = 16
    /// Width reserved for the trailing accessory (chips, captions).
    public static let trailingAccessoryWidth: Double = 72
    /// Line-limit clamps shared by the planner and the views.
    public static let headlineLineLimit = 3
    public static let childLineLimit = 4
    public static let oneLineLimit = 1
    public static let stripLineLimit = 3
    /// Height used when the measurer has no entry for a row key.
    /// Matches the acceptance row-height model (19 pt per row).
    public static let defaultRowHeight: Double = 19
    /// Screen margin below the eye line kept clear of the panel.
    public static let screenMargin: Double = 24
    /// Longest `·`-joined title list kept in a Later one-row summary.
    public static let maxOneRowLength = 120
    /// Longest warning sentence kept in a warning row.
    public static let maxWarningLength = 120
    /// Character budget for the Later name strip; names past it fold
    /// into a `+N` overflow token.
    public static let maxStripCharacters = 300

    /// Vertical chrome the planner adds around a group's rows. The Now
    /// card's wash and padding cost more than a plain Later group.
    public static func groupVerticalInsets(role: CaptureAgendaRole) -> Double {
        switch role {
        case .current:
            return 12
        case .open, .next:
            return 8
        case .later, .completed, .other:
            return 4
        }
    }
}

/// Pure below-eye-line budget: the agenda's ideal height is capped at
/// this, so the panel never slides up for the agenda and never depends
/// on its own current height (which would cause resize loops).
public struct CaptureAgendaBudget: Equatable, Sendable {
    /// Top edge of the compact panel (editor + footer, no auxiliary
    /// region), in screen coordinates.
    public var eyeLineTop: Double
    /// Bottom of the screen's visible frame, in screen coordinates.
    public var visibleMinY: Double
    public var frameChrome: Double
    public var titlebarDragInset: Double
    public var compactEditorHeight: Double
    public var footerHeight: Double
    public var rootBottomPadding: Double
    public var previewPaneInsets: Double
    public var slackRowHeight: Double
    public var sectionSpacing: Double

    public init(
        eyeLineTop: Double = 0,
        visibleMinY: Double = 0,
        frameChrome: Double = 0,
        titlebarDragInset: Double = 0,
        compactEditorHeight: Double = 0,
        footerHeight: Double = 0,
        rootBottomPadding: Double = 0,
        previewPaneInsets: Double = 0,
        slackRowHeight: Double = 0,
        sectionSpacing: Double = 0
    ) {
        self.eyeLineTop = eyeLineTop
        self.visibleMinY = visibleMinY
        self.frameChrome = frameChrome
        self.titlebarDragInset = titlebarDragInset
        self.compactEditorHeight = compactEditorHeight
        self.footerHeight = footerHeight
        self.rootBottomPadding = rootBottomPadding
        self.previewPaneInsets = previewPaneInsets
        self.slackRowHeight = slackRowHeight
        self.sectionSpacing = sectionSpacing
    }

    /// Usable height for the agenda, never negative.
    public var value: Double {
        let chrome = frameChrome + titlebarDragInset
        let panel = compactEditorHeight + footerHeight
        let padding = rootBottomPadding + previewPaneInsets
        let slack = slackRowHeight + 2 * sectionSpacing
        let available = eyeLineTop - visibleMinY
        let used = CaptureAgendaLayoutMetrics.screenMargin
        let total = chrome + panel + padding + slack + used
        return max(0, available - total)
    }
}

/// Pure countdown and time wording for the agenda header. bob owns the
/// facts (`starts_at`, `ends_at`); this only turns them into strings.
public enum CaptureAgendaClock {
    /// `"12m left"`, `"1h 05m left"`, `"ending now"` within a minute of
    /// the end, or `"overdue 8m"` past it. Nil when `endsAt` is missing
    /// or unparseable. The view paints the overdue string orange.
    public static func remainingText(
        endsAt: String?,
        now: Date,
        calendar: Calendar = Calendar.current
    ) -> String? {
        guard let raw = endsAt, let end = parseNaiveDateTime(raw, calendar: calendar) else {
            return nil
        }
        let remaining = end.timeIntervalSince(now)
        if remaining >= 60 {
            let minutes = Int(remaining / 60)
            if minutes >= 60 {
                let hours = minutes / 60
                let rest = minutes % 60
                let padded = rest < 10 ? "0\(rest)" : "\(rest)"
                return "\(hours)h \(padded)m left"
            }
            return "\(minutes)m left"
        }
        if remaining > -60 {
            return "ending now"
        }
        let overdue = max(1, Int(-remaining / 60))
        return "overdue \(overdue)m"
    }

    /// `"14:10–14:35"` from naive local datetimes. Nil unless both ends
    /// carry a clock time.
    public static func timeRangeText(startsAt: String?, endsAt: String?) -> String? {
        guard let start = clockTime(startsAt), let end = clockTime(endsAt) else {
            return nil
        }
        return "\(start)–\(end)"
    }

    /// Spoken form of the range for accessibility labels.
    public static func accessibilityRangeText(startsAt: String?, endsAt: String?) -> String? {
        guard let start = clockTime(startsAt), let end = clockTime(endsAt) else {
            return nil
        }
        return "\(start) to \(end)"
    }

    /// `"Fri 9 Oct"` from a `"YYYY-MM-DD"` date, in the given locale.
    /// Empty when the date is missing or unparseable.
    public static func titleDateText(rawDate: String?, locale: Locale = Locale.current) -> String {
        guard let raw = rawDate else {
            return ""
        }
        let parts = raw.split(separator: "-")
        guard parts.count == 3 else {
            return ""
        }
        guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return ""
        }
        guard month >= 1, month <= 12, day >= 1, day <= 31 else {
            return ""
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            return ""
        }
        let weekday = calendar.component(.weekday, from: date)
        let weekdays = calendar.shortWeekdaySymbols
        let months = calendar.shortMonthSymbols
        guard weekdays.indices.contains(weekday - 1), months.indices.contains(month - 1) else {
            return ""
        }
        return "\(weekdays[weekday - 1]) \(day) \(months[month - 1])"
    }

    /// `"5 done · 2h 40m"` for the title row's right side. Nil when the
    /// count is 0, so the view omits it.
    public static func summaryText(count: Int, minutes: Int) -> String? {
        guard count > 0 else {
            return nil
        }
        guard minutes > 0 else {
            return "\(count) done"
        }
        if minutes >= 60 {
            let rest = minutes % 60
            let padded = rest < 10 ? "0\(rest)" : "\(rest)"
            return "\(count) done · \(minutes / 60)h \(padded)m"
        }
        return "\(count) done · \(minutes)m"
    }

    /// `"HH:MM"` clock time from a `"YYYY-MM-DDTHH:MM"` datetime.
    static func clockTime(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let halves = raw.split(separator: "T", maxSplits: 1)
        guard halves.count == 2 else {
            return nil
        }
        let clock = String(halves[1].prefix(5))
        let digits = clock.filter { $0 != ":" }
        guard clock.count == 5, clock[clock.index(clock.startIndex, offsetBy: 2)] == ":" else {
            return nil
        }
        guard digits.allSatisfy({ $0.isNumber }) else {
            return nil
        }
        return clock
    }

    /// A naive `"YYYY-MM-DDTHH:MM"` datetime read as local wall-clock time.
    static func parseNaiveDateTime(_ raw: String, calendar: Calendar) -> Date? {
        let halves = raw.split(separator: "T", maxSplits: 1)
        guard halves.count == 2 else {
            return nil
        }
        let dateParts = halves[0].split(separator: "-")
        let timeParts = halves[1].split(separator: ":")
        guard dateParts.count == 3, timeParts.count >= 2 else {
            return nil
        }
        guard let year = Int(dateParts[0]), let month = Int(dateParts[1]) else {
            return nil
        }
        guard let day = Int(dateParts[2]), let hour = Int(timeParts[0]) else {
            return nil
        }
        guard let minute = Int(timeParts[1]) else {
            return nil
        }
        var calendar = calendar
        let components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: components)
    }
}
