import Foundation

/// The Newest timeline (⌘0): every row of the scope (or of the query's
/// matches) ordered by capture date and grouped by the panel calendar's
/// day and month. It reorders and groups only; membership always comes
/// from the scope filter and the tiered search.
extension RefsRanker {
    /// What a row's date group is keyed on, before any title exists.
    /// Rows in the weekday window key on their own day, today and future
    /// days key on today, and everything older keys on its month.
    enum AddedGroupKey: Hashable {
        case day(RefDay)
        case month(year: Int, month: Int)
        case undated
    }

    /// Sorts rows into the timeline and cuts it into date groups: `added`
    /// day newest first, then `added_at` newest first with timed rows
    /// ahead of untimed ones, then note path; rows without `added` last.
    static func newestSections(_ items: [RefItem], signals: RefsSignals) -> [RefsSection] {
        let today = RefsCaption.dayComponents(signals.now, calendar: signals.calendar)
        let todayOrdinal = RefsDates.ordinal(signals.now, calendar: signals.calendar)
        var sections: [RefsSection] = []
        var currentKey: AddedGroupKey?
        var currentGroup: RefsAddedGroup?
        var currentIDs: [String] = []

        func flush() {
            if let currentGroup, !currentIDs.isEmpty {
                sections.append(RefsSection(kind: .added(currentGroup), ids: currentIDs))
            }
            currentIDs = []
        }

        for item in items.sorted(by: newestPrecedes) {
            let key = addedGroupKey(for: item.added, today: today, todayOrdinal: todayOrdinal)
            if key != currentKey {
                flush()
                currentKey = key
                currentGroup = addedGroup(
                    for: key, today: today, todayOrdinal: todayOrdinal, signals: signals
                )
            }
            currentIDs.append(item.id)
        }
        flush()
        return sections
    }

    static func newestPrecedes(_ a: RefItem, _ b: RefItem) -> Bool {
        switch (a.added, b.added) {
        case (nil, nil):
            return a.id < b.id
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case let (x?, y?):
            if x != y {
                return x > y
            }
            switch (a.addedAt, b.addedAt) {
            case let (p?, q?):
                if p != q {
                    return p > q
                }
                return a.id < b.id
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return a.id < b.id
            }
        }
    }

    static func addedGroupKey(
        for day: RefDay?,
        today: RefsCaption.DayParts,
        todayOrdinal: Int
    ) -> AddedGroupKey {
        guard let day else {
            return .undated
        }
        let age = todayOrdinal - RefsDates.unixOrdinal(day)
        if age <= 0 {
            return .day(RefDay(year: today.year, month: today.month, day: today.day))
        }
        if age <= 6 {
            return .day(day)
        }
        return .month(year: day.year, month: day.month)
    }

    static func addedGroup(
        for key: AddedGroupKey,
        today: RefsCaption.DayParts,
        todayOrdinal: Int,
        signals: RefsSignals
    ) -> RefsAddedGroup {
        switch key {
        case .undated:
            return RefsAddedGroup(
                id: "undated",
                title: "Undated",
                accessibilityLabel: "Undated",
                style: .undated
            )
        case .month(let year, let month):
            let name = RefsCaption.monthName(month)
            let title = year == today.year ? name : "\(name) \(year)"
            return RefsAddedGroup(
                id: String(format: "month-%04d-%02d", year, month),
                title: title,
                accessibilityLabel: "Added in \(title)",
                style: .month
            )
        case .day(let day):
            let age = todayOrdinal - RefsDates.unixOrdinal(day)
            let title: String
            switch age {
            case ...0:
                title = "Today"
            case 1:
                title = "Yesterday"
            default:
                title = RefsCaption.weekdayName(weekday(of: day))
            }
            let monthDay = "\(RefsCaption.monthName(day.month)) \(day.day)"
            let spoken = day.year == today.year ? monthDay : "\(monthDay), \(day.year)"
            let phrase = age <= 1 ? title.lowercased() : title
            return RefsAddedGroup(
                id: "day-\(day.isoString)",
                title: title,
                detail: RefsCaption.absoluteMonthDay(
                    day, now: signals.now, calendar: signals.calendar
                ),
                accessibilityLabel: "Added \(phrase), \(spoken)",
                style: .day
            )
        }
    }

    /// The weekday number (1 = Sunday) of a civil day. Timezone-free:
    /// Unix day 0, 1970-01-01, was a Thursday.
    static func weekday(of day: RefDay) -> Int {
        ((RefsDates.unixOrdinal(day) % 7) + 7 + 4) % 7 + 1
    }
}
