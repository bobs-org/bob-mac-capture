import Foundation

/// Band copy, metrics, and age formatting for the pull-in cancel
/// `USED BEFORE` band. Uses the `SimilarTasksBandView` vocabulary:
/// a 0.5pt hairline, `clock.arrow.circlepath` at `.caption2` `.tertiary`,
/// a `USED BEFORE` header in `.caption2.weight(.semibold).tracking(0.6)`
/// `.secondary`, trailing keycaps, 22pt `.callout` rows, and
/// `.caption.monospacedDigit()` `.tertiary` metadata.
public enum LogRecallBandPresentation {
    public static let headerHeight: Double = 16
    public static let rowHeight: Double = 22
    public static let maxRows = 3
    public static let kindEmoji = "❌"
    public static let bandTitle = "USED BEFORE"

    public static func trimmedLength(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    public struct Header: Equatable, Sendable {
        public let title: String
        public let trailing: String
        public let showsKeycaps: Bool

        public init(title: String, trailing: String, showsKeycaps: Bool) {
            self.title = title
            self.trailing = trailing
            self.showsKeycaps = showsKeycaps
        }
    }

    /// Header copy per Design §4. RECALLING shows `… · k of n`; DRAFT with
    /// no match shows `… · no match for "q"` without keycaps.
    public static func header(
        draft: String, selectedIndex: Int?, total: Int
    ) -> Header {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selectedIndex {
            let restore =
                trimmed.isEmpty ? "esc clears" : "esc restores “\(trimmed)”"
            return Header(
                title: "\(kindEmoji) \(bandTitle) · \(selectedIndex) of \(total)",
                trailing: restore,
                showsKeycaps: false
            )
        }
        if trimmed.isEmpty {
            return Header(
                title: "\(kindEmoji) \(bandTitle)",
                trailing: "⌃N ⌃P",
                showsKeycaps: true
            )
        }
        if total == 0 {
            return Header(
                title:
                    "\(kindEmoji) \(bandTitle) · no match for “\(trimmed)”",
                trailing: "",
                showsKeycaps: false
            )
        }
        return Header(
            title: "\(kindEmoji) \(bandTitle) · matching “\(trimmed)”",
            trailing: "⌃N ⌃P",
            showsKeycaps: true
        )
    }

    /// Row metadata: `N×  ·  age`. Day-precision kinds (cancel) use
    /// `today`, `yesterday`, `3d`, `Nov 2` (or `Nov 2, 2025`).
    public static func meta(uses: Int, lastUsed: String, today: Date = Date()) -> String {
        "\(uses)×  ·  \(age(lastUsed: lastUsed, today: today))"
    }

    public static func age(lastUsed: String, today: Date = Date()) -> String {
        let trimmed = lastUsed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":") {
            return minuteAge(trimmed, today: today)
        }
        return dayAge(trimmed, today: today)
    }

    /// Day-precision age for Rotten/Cancel stamps (`YYYY-MM-DD`).
    public static func dayAge(_ stamp: String, today: Date = Date()) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: stamp) else { return stamp }
        let startToday = calendar.startOfDay(for: today)
        let startDate = calendar.startOfDay(for: date)
        let days =
            calendar.dateComponents([.day], from: startDate, to: startToday).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d" }
        let sameYear =
            calendar.component(.year, from: date) == calendar.component(.year, from: today)
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return out.string(from: date)
    }

    /// Minute-precision age for Work stamps (`YYYY-MM-DD HH:MM`).
    public static func minuteAge(_ stamp: String, today: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: stamp) {
            let minutes = Int(today.timeIntervalSince(date) / 60)
            if minutes < 1 { return "now" }
            if minutes < 60 { return "\(minutes)m" }
            let hours = minutes / 60
            if hours < 24, Calendar.current.isDate(date, inSameDayAs: today) {
                return "\(hours)h"
            }
        }
        let day = String(stamp.prefix(10))
        return dayAge(day, today: today)
    }

    public static func tooltip(lastUsed: String, uses: Int) -> String {
        "Last used \(lastUsed) · \(uses) uses"
    }

    public static func announcement(index: Int, total: Int, text: String) -> String {
        "Recalled \(index) of \(total): \(text)"
    }

    /// Band height while visible (header + rows), for the card height policy.
    public static func bandHeight(rowCount: Int) -> Double {
        guard rowCount > 0 else { return headerHeight }
        return headerHeight + Double(min(rowCount, maxRows)) * rowHeight
    }
}
