import CaptureCore
import Foundation

/// Row captions and date phrases (§8). Every count and date is a
/// `monospacedDigit` in the UI; the strings here carry no attributes.
public enum RefsCaption {
    /// The two-line row's second line: kind label, author (papers,
    /// articles, docs), a date phrase naming the date that explains the
    /// row's position, `N pp` when the page count is known, and — in
    /// search mode — the matched stem or secondary field. Parts join
    /// with `·`; a missing PDF gains "PDF missing". A matched author
    /// the caption already shows is not repeated.
    public static func caption(
        for item: RefItem,
        in section: RefsSectionKind?,
        signals: RefsSignals,
        match: RefsMatch? = nil
    ) -> String {
        captionWithMatch(for: item, in: section, signals: signals, match: match).text
    }

    /// The caption plus the character range of its matched stem or
    /// secondary part, when search mode appended one. The row renders
    /// that range in the accent color. Ranges are `Character` offsets
    /// into the returned text.
    public static func captionWithMatch(
        for item: RefItem,
        in section: RefsSectionKind?,
        signals: RefsSignals,
        match: RefsMatch? = nil
    ) -> (text: String, matchRange: Range<Int>?) {
        // Each part carries the highlight ranges inside its own text,
        // when it is the matched stem or secondary field.
        var parts: [(text: String, ranges: [Range<Int>])] = [(item.kind.label, [])]
        switch item.kind {
        case .paper, .article, .doc:
            if let author = item.author, !author.isEmpty {
                parts.append((author, []))
            }
        case .chat, .book, .slides, .other:
            break
        }
        let phrase = datePhrase(for: item, in: section, signals: signals)
        if !phrase.isEmpty {
            parts.append((phrase, []))
        }
        if let pages = signals.pageCounts[item.id] {
            parts.append(("\(pages) pp", []))
        }
        if section == nil {
            if let secondary = match?.secondary {
                if !repeatsShownAuthor(secondary, item: item) {
                    parts.append((secondary.text, secondary.ranges))
                }
            } else if let stemRanges = match?.stemRanges, !stemRanges.isEmpty {
                parts.append((item.stem, stemRanges))
            }
        }
        if signals.missingPDFs.contains(item.id) {
            parts.append(("PDF missing", []))
        }
        var text = ""
        var matchRange: Range<Int>? = nil
        for (index, part) in parts.enumerated() {
            if index > 0 {
                text += " · "
            }
            let start = text.count
            text += part.text
            if matchRange == nil, !part.ranges.isEmpty {
                let lower = part.ranges.map(\.lowerBound).min() ?? 0
                let upper = part.ranges.map(\.upperBound).max() ?? 0
                matchRange = (start + lower)..<(start + upper)
            }
        }
        return (text, matchRange)
    }

    /// Whether a secondary hit repeats the author the caption already
    /// shows, so the row must not append it again.
    private static func repeatsShownAuthor(_ secondary: RefsSecondaryMatch, item: RefItem) -> Bool {
        guard secondary.field == .author,
              let author = item.author,
              !author.isEmpty,
              secondary.text == author
        else {
            return false
        }
        switch item.kind {
        case .paper, .article, .doc:
            return true
        case .chat, .book, .slides, .other:
            return false
        }
    }

    /// The date phrase for a row: the date that explains its position.
    public static func datePhrase(
        for item: RefItem,
        in section: RefsSectionKind?,
        signals: RefsSignals
    ) -> String {
        switch section {
        case .justScanned, .justAdded, .ready:
            return addedPhrase(item, signals: signals)
        case .reading, .next, .recentlyOpened:
            if let opened = RefsRanker.lastOpened(item, signals: signals) {
                let when = relativeCompact(opened, now: signals.now, calendar: signals.calendar)
                return "opened \(when)"
            }
            return addedPhrase(item, signals: signals)
        case .today, .library:
            if item.state == .read, let finished = item.finished {
                return "read \(absoluteDay(finished, now: signals.now, calendar: signals.calendar))"
            }
            return addedPhrase(item, signals: signals)
        case nil:
            return lastActivityPhrase(item, signals: signals)
        }
    }

    /// Search mode: the last-activity phrase.
    static func lastActivityPhrase(_ item: RefItem, signals: RefsSignals) -> String {
        if let opened = RefsRanker.lastOpened(item, signals: signals) {
            let when = relativeCompact(opened, now: signals.now, calendar: signals.calendar)
            return "opened \(when)"
        }
        if item.state == .read, let finished = item.finished {
            return "read \(absoluteDay(finished, now: signals.now, calendar: signals.calendar))"
        }
        return addedPhrase(item, signals: signals)
    }

    static func addedPhrase(_ item: RefItem, signals: RefsSignals) -> String {
        guard let added = item.added else {
            return ""
        }
        let mark = item.addedIsApproximate ? "≈ " : ""
        return "added \(mark)\(absoluteDay(added, now: signals.now, calendar: signals.calendar))"
    }

    /// Compact relative time for captions: "2h ago".
    public static func relativeCompact(
        _ date: Date, now: Date, calendar: Calendar = .current
    ) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        }
        if seconds < 86_400 {
            return "\(Int(seconds / 3_600))h ago"
        }
        if seconds < 14 * 86_400 {
            return "\(Int(seconds / 86_400))d ago"
        }
        let day = dayComponents(date, calendar: calendar)
        let today = dayComponents(now, calendar: calendar)
        return absoluteDay(day, today: today, calendar: calendar)
    }

    /// Long relative time for why-here lines: "2 hours ago".
    public static func relativeLong(
        _ date: Date, now: Date, calendar: Calendar = .current
    ) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3_600 {
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        if seconds < 86_400 {
            let hours = Int(seconds / 3_600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        if seconds < 30 * 86_400 {
            let days = Int(seconds / 86_400)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
        return absoluteDay(
            dayComponents(date, calendar: calendar),
            today: dayComponents(now, calendar: calendar),
            calendar: calendar
        )
    }

    struct DayParts {
        let year: Int
        let month: Int
        let day: Int
    }

    static func dayComponents(_ date: Date, calendar: Calendar) -> DayParts {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return DayParts(
            year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1
        )
    }

    /// "today", "yesterday", the weekday for 2–6 days ago, "Oct 7"
    /// within the year, and "Oct 7, 2025" otherwise. A date exactly 7
    /// days old shows the month and day, never today's weekday name.
    public static func absoluteDay(_ day: RefDay, now: Date, calendar: Calendar) -> String {
        absoluteDay(
            DayParts(year: day.year, month: day.month, day: day.day),
            today: dayComponents(now, calendar: calendar),
            calendar: calendar
        )
    }

    static func absoluteDay(_ day: DayParts, today: DayParts, calendar: Calendar) -> String {
        let diff = RefsDates.ordinal(year: today.year, month: today.month, day: today.day)
            - RefsDates.ordinal(year: day.year, month: day.month, day: day.day)
        if diff == 0 {
            return "today"
        }
        if diff == 1 {
            return "yesterday"
        }
        if (2...6).contains(diff) {
            let components = DateComponents(year: day.year, month: day.month, day: day.day)
            if let date = calendar.date(from: components) {
                let weekday = calendar.component(.weekday, from: date)
                return weekdayName(weekday)
            }
        }
        let month = monthAbbreviation(day.month)
        if day.year == today.year {
            return "\(month) \(day.day)"
        }
        return "\(month) \(day.day), \(day.year)"
    }

    /// Absolute "Oct 8" form for why-here lines, which pin absolute
    /// dates while captions use the relative rules above.
    public static func absoluteMonthDay(_ day: RefDay, now: Date, calendar: Calendar) -> String {
        let today = dayComponents(now, calendar: calendar)
        let month = monthAbbreviation(day.month)
        if day.year == today.year {
            return "\(month) \(day.day)"
        }
        return "\(month) \(day.day), \(day.year)"
    }

    static func monthAbbreviation(_ month: Int) -> String {
        let names = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        guard (1...12).contains(month) else {
            return "???"
        }
        return names[month - 1]
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = [
            "Sunday", "Monday", "Tuesday", "Wednesday",
            "Thursday", "Friday", "Saturday",
        ]
        guard (1...7).contains(weekday) else {
            return "???"
        }
        return names[weekday - 1]
    }

    /// The display label for a state, with the Blocked overlay applied.
    public static func stateLabel(_ item: RefItem) -> String {
        if item.isBlocked {
            return "Blocked"
        }
        switch item.state {
        case .reading:
            return "Reading"
        case .next:
            return "Next"
        case .ready:
            return "Ready"
        case .read:
            return "Read"
        case .dropped:
            return "Dropped"
        case .unknown:
            return "Unknown"
        }
    }
}

/// The why-here line in the inspector footer: the reason a row sits
/// where it does. Tests pin these exact forms.
public enum RefsExplanation {
    public static func whyHere(
        _ item: RefItem,
        listing: RefsListing,
        signals: RefsSignals
    ) -> String {
        if case let .search(query) = listing.mode {
            return searchWhyHere(item, query: query, listing: listing, signals: signals)
        }
        let section = listing.sections.first { $0.ids.contains(item.id) }.flatMap { $0.kind }
        switch section {
        case .justScanned:
            if let at = signals.scan?.at {
                let when = RefsCaption.relativeLong(
                    at, now: signals.now, calendar: signals.calendar
                )
                return "Added by your scan · \(when)"
            }
            return "Added by your scan"
        case .today:
            if let name = signals.today.entries[item.id]?.pomodoroName, !name.isEmpty {
                return "In Today · \(name) Pomodoro"
            }
            return "In Today"
        case .justAdded:
            if let added = item.added {
                let day = RefsCaption.absoluteMonthDay(
                    added, now: signals.now, calendar: signals.calendar
                )
                return "Just added \(day) · never opened"
            }
            return "Just added · never opened"
        case .reading:
            if let opened = RefsRanker.lastOpened(item, signals: signals) {
                let when = RefsCaption.relativeLong(
                    opened, now: signals.now, calendar: signals.calendar
                )
                return "Reading · opened \(when)"
            }
            return "Reading · never opened"
        case .next:
            if item.isBlocked {
                return "In your Next lane · blocked"
            }
            return "In your Next lane"
        case .ready:
            if let added = item.added {
                let day = RefsCaption.absoluteMonthDay(
                    added, now: signals.now, calendar: signals.calendar
                )
                return "Ready · added \(day)"
            }
            return "Ready"
        case .recentlyOpened:
            if let opened = RefsRanker.lastOpened(item, signals: signals) {
                let when = RefsCaption.relativeLong(
                    opened, now: signals.now, calendar: signals.calendar
                )
                return "Opened \(when)"
            }
            return "Opened"
        case .library, nil:
            if let activity = latestActivityDay(item, signals: signals) {
                let day = RefsCaption.absoluteMonthDay(
                    activity, now: signals.now, calendar: signals.calendar
                )
                return "Library · last activity \(day)"
            }
            return "Library"
        }
    }

    static func searchWhyHere(
        _ item: RefItem,
        query: String,
        listing: RefsListing,
        signals: RefsSignals
    ) -> String {
        guard let match = listing.matches[item.id] else {
            return "Library"
        }
        switch match.tier {
        case .exact:
            if let arxiv = item.arxivID,
                RefsRanker.normalizeArxiv(query) == RefsRanker.normalizeArxiv(arxiv)
            {
                return "Exact arXiv id"
            }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if let doi = item.doi, trimmed.lowercased() == doi.lowercased()
            {
                return "Exact DOI"
            }
            if !item.urls.isEmpty {
                let wanted = RefsRanker.normalizeURL(query)
                if !wanted.isEmpty,
                    item.urls.contains(where: { RefsRanker.normalizeURL($0) == wanted })
                {
                    return "Exact URL match"
                }
            }
            return "Exact title match"
        case .word:
            return "Title word match · \(RefsCaption.stateLabel(item))"
        case .fuzzy:
            return "Fuzzy title match"
        case .secondary:
            switch match.secondary?.field {
            case .author:
                return "Matched author"
            case .area:
                return "Matched area"
            case .kind:
                return "Matched kind"
            case .heading:
                return "Matched heading"
            case nil:
                return "Matched"
            }
        }
    }

    /// The newest of added, finished, and last-opened as a `RefDay`,
    /// for the Library why-here line.
    static func latestActivityDay(_ item: RefItem, signals: RefsSignals) -> RefDay? {
        var best: RefDay?
        var bestOrdinal = Int.min
        func consider(_ day: RefDay?) {
            guard let day else {
                return
            }
            let ordinal = RefsDates.ordinal(day)
            if best == nil || ordinal > bestOrdinal {
                best = day
                bestOrdinal = ordinal
            }
        }
        consider(item.added)
        consider(item.finished)
        if let opened = RefsRanker.lastOpened(item, signals: signals) {
            let parts = signals.calendar.dateComponents([.year, .month, .day], from: opened)
            if let year = parts.year, let month = parts.month, let day = parts.day {
                consider(RefDay(parsing: String(format: "%04d-%02d-%02d", year, month, day)))
            }
        }
        return best
    }
}
