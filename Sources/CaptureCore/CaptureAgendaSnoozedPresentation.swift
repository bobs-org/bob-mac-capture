import Foundation

/// Fold level of the Later today band: full detail or the single
/// persistent summary. The band never folds away while rows remain.
public enum CaptureAgendaSnoozedFold: Equatable, Sendable {
    case full
    case summary
}

/// Per-row facts for one `.snoozedRow`. The view renders the row from
/// these, never from snapshot JSON. Part of the row key, so
/// title/state/countdown changes invalidate sizes.
public struct CaptureAgendaSnoozedRowData: Hashable, Equatable, Sendable {
    /// Bob's wake state for the row.
    public let state: CaptureAgendaSnoozedState
    /// `"19:00"` from the four-digit `target`. Empty when the target
    /// is missing or malformed, so the row stays neutral.
    public let timeText: String
    /// `"in 3h 28m"` / `"in 38m"` / `"now"` for asleep rows with a
    /// valid future wake instant. Nil for due, blocked, unknown, and
    /// invalid-time rows.
    public let countdownText: String?
    /// Trailing status wording that carries state without color:
    /// `"due · waking"` for due, `"waits on prerequisites"` for
    /// blocked, nil otherwise.
    public let trailingText: String?

    public init(
        state: CaptureAgendaSnoozedState = .asleep,
        timeText: String = "",
        countdownText: String? = nil,
        trailingText: String? = nil
    ) {
        self.state = state
        self.timeText = timeText
        self.countdownText = countdownText
        self.trailingText = trailingText
    }
}

/// Fresh-wake accent for an agenda task headline: Bob's `woke_at`
/// (`HH:MM`) on the snapshot day whose age is under sixty minutes.
/// Part of the row key so expiry invalidates sizes.
public struct CaptureAgendaWokeAccent: Hashable, Equatable, Sendable {
    /// The wall-clock stamp as Bob reports it, e.g. `"15:32"`.
    public let timeText: String

    public init(timeText: String) {
        self.timeText = timeText
    }

    /// Display wording for the trailing amber chip.
    public var text: String {
        "alarm woke \(timeText)"
    }
}

/// The Later today band: today's snoozed tasks from Bob's additive
/// `snoozed` block, rendered separately from the ledger groups. Every
/// row is precomputed here, so the fit planner only picks row lists
/// and the view renders verbatim.
public struct CaptureAgendaSnoozedBand: Equatable, Sendable {
    public let headerRow: CaptureAgendaRow
    /// Full-detail rows in Bob's order, each with its countdown or
    /// status wording.
    public let rows: [CaptureAgendaRow]
    /// The persistent one-row summary, e.g.
    /// `"alarm 2 later · next 19:00"`. Never disappears while rows
    /// remain; with only blocked rows it reports the blocked state
    /// without a fabricated next wake.
    public let summaryRow: CaptureAgendaRow
    /// True while any asleep row carries a live countdown: the view
    /// ticks every minute even with no running Pomodoro.
    public let hasTickingEvent: Bool
    /// Raw count of all provided asleep/due/blocked rows, for the
    /// separate budget chip.
    public let count: Int
    public let accessibilityLabel: String

    public init(
        headerRow: CaptureAgendaRow,
        rows: [CaptureAgendaRow] = [],
        summaryRow: CaptureAgendaRow,
        hasTickingEvent: Bool = false,
        count: Int = 0,
        accessibilityLabel: String = "Later today"
    ) {
        self.headerRow = headerRow
        self.rows = rows
        self.summaryRow = summaryRow
        self.hasTickingEvent = hasTickingEvent
        self.count = count
        self.accessibilityLabel = accessibilityLabel
    }

    /// Every precomputed row, for the measurer: the planner picks
    /// subsets per fold, and the fixpoint pass measures new variants.
    public var allRows: [CaptureAgendaRow] {
        [headerRow] + rows + [summaryRow]
    }

    /// Rows for the `full` fold: header plus every snoozed row.
    public func fullRows() -> [CaptureAgendaRow] {
        [headerRow] + rows
    }
}

extension CaptureAgendaPresentation {
    /// Builds the Later today band from Bob's additive `snoozed`
    /// block. Nil when Bob omits `snoozed` (older Bob), when the
    /// snapshot carries no rows, or when the caller passes no `now`
    /// for countdown aging. The caller guards the same-day date; this
    /// builder never shows yesterday's rows.
    static func makeSnoozedBand(
        snoozed: CaptureAgendaSnoozed?,
        now: Date?,
        calendar: Calendar = Calendar.current
    ) -> CaptureAgendaSnoozedBand? {
        guard let snoozed, !snoozed.rows.isEmpty else {
            return nil
        }
        let header = makeSnoozedHeader(count: snoozed.rows.count)
        var rows: [CaptureAgendaRow] = []
        rows.reserveCapacity(snoozed.rows.count)
        var hasTick = false
        for row in snoozed.rows {
            let built = makeSnoozedRow(row: row, now: now, calendar: calendar)
            if built.snoozed?.countdownText != nil {
                hasTick = true
            }
            rows.append(built)
        }
        let summary = makeSnoozedSummary(
            rows: snoozed.rows,
            nextWakeAt: snoozed.nextWakeAt
        )
        let label = snoozedAccessibility(rows: snoozed.rows, nextWakeAt: snoozed.nextWakeAt)
        return CaptureAgendaSnoozedBand(
            headerRow: header,
            rows: rows,
            summaryRow: summary,
            hasTickingEvent: hasTick,
            count: snoozed.rows.count,
            accessibilityLabel: label
        )
    }

    static func makeSnoozedHeader(count: Int) -> CaptureAgendaRow {
        let text = "Later today"
        let label = count == 1 ? "Later today, 1 snoozed task" : "Later today, \(count) snoozed tasks"
        return CaptureAgendaRow(
            kind: .snoozedHeader,
            text: text,
            depth: 0,
            lineLimit: 1,
            accessibilityLabel: label
        )
    }

    static func makeSnoozedRow(
        row: CaptureAgendaSnoozedRow,
        now: Date?,
        calendar: Calendar = Calendar.current
    ) -> CaptureAgendaRow {
        let timeText = Self.snoozedDisplayTime(target: row.target)
        let countdown: String? = {
            guard let now else {
                return nil
            }
            guard row.state == .asleep else {
                return nil
            }
            guard let raw = row.wakeAt, let wake = Self.parseSnoozedWakeAt(raw) else {
                return nil
            }
            return Self.snoozedCountdownText(until: wake, now: now)
        }()
        let trailing: String? = {
            switch row.state {
            case .due:
                return "due · waking"
            case .blocked:
                return "waits on prerequisites"
            case .asleep, .other:
                return nil
            }
        }()
        let data = CaptureAgendaSnoozedRowData(
            state: row.state,
            timeText: timeText,
            countdownText: countdown,
            trailingText: trailing
        )
        let accessibility = Self.snoozedRowAccessibility(
            title: row.title,
            timeText: timeText,
            state: row.state,
            countdown: countdown,
            trailing: trailing
        )
        return CaptureAgendaRow(
            kind: .snoozedRow,
            text: row.title,
            depth: 0,
            lineLimit: CaptureAgendaLayoutMetrics.childLineLimit,
            accessibilityLabel: accessibility,
            snoozed: data
        )
    }

    static func makeSnoozedSummary(
        rows: [CaptureAgendaSnoozedRow],
        nextWakeAt: String?
    ) -> CaptureAgendaRow {
        let count = rows.count
        let blockedOnly = !rows.isEmpty && rows.allSatisfy { $0.state == .blocked }
        let text: String
        let label: String
        if blockedOnly {
            if count == 1 {
                text = "1 later · blocked"
                label = "Later today summary, 1 blocked snoozed task"
            } else {
                text = "\(count) later · blocked"
                label = "Later today summary, \(count) blocked snoozed tasks"
            }
        } else if let raw = nextWakeAt, let wall = Self.snoozedWallTime(fromRFC3339: raw) {
            if count == 1 {
                text = "1 later · next \(wall)"
                label = "Later today summary, 1 snoozed task, next at \(wall)"
            } else {
                text = "\(count) later · next \(wall)"
                label = "Later today summary, \(count) snoozed tasks, next at \(wall)"
            }
        } else {
            if count == 1 {
                text = "1 later"
                label = "Later today summary, 1 snoozed task"
            } else {
                text = "\(count) later"
                label = "Later today summary, \(count) snoozed tasks"
            }
        }
        return CaptureAgendaRow(
            kind: .snoozedSummary,
            text: text,
            depth: 0,
            lineLimit: 1,
            accessibilityLabel: label
        )
    }

    static func snoozedAccessibility(
        rows: [CaptureAgendaSnoozedRow],
        nextWakeAt: String?
    ) -> String {
        let count = rows.count
        if rows.allSatisfy({ $0.state == .blocked }) {
            return count == 1
                ? "Later today, 1 blocked snoozed task"
                : "Later today, \(count) blocked snoozed tasks"
        }
        if let raw = nextWakeAt, let wall = Self.snoozedWallTime(fromRFC3339: raw) {
            return count == 1
                ? "Later today, 1 snoozed task, next at \(wall)"
                : "Later today, \(count) snoozed tasks, next at \(wall)"
        }
        return count == 1
            ? "Later today, 1 snoozed task"
            : "Later today, \(count) snoozed tasks"
    }

    static func snoozedRowAccessibility(
        title: String,
        timeText: String,
        state: CaptureAgendaSnoozedState,
        countdown: String?,
        trailing: String?
    ) -> String {
        let spokenTitle = spokenIconText(title)
        var parts: [String] = []
        if !timeText.isEmpty {
            parts.append("at \(timeText)")
        }
        parts.append(spokenTitle)
        switch state {
        case .asleep:
            parts.append("asleep")
        case .due:
            parts.append("due, waking")
        case .blocked:
            parts.append("blocked, waits on prerequisites")
        case .other:
            parts.append("snoozed")
        }
        if let countdown {
            parts.append(countdown)
        } else if let trailing, state != .due, state != .blocked {
            parts.append(trailing)
        }
        return parts.joined(separator: ", ")
    }

    /// `"1900"` → `"19:00"`. Empty when the target is not four digits
    /// or its hour/minute are out of range, so the row stays neutral.
    static func snoozedDisplayTime(target: String) -> String {
        guard target.count == 4, target.allSatisfy({ $0.isNumber }) else {
            return ""
        }
        let hourText = String(target.prefix(2))
        let minuteText = String(target.suffix(2))
        guard let hour = Int(hourText), let minute = Int(minuteText) else {
            return ""
        }
        guard hour >= 0, hour <= 23, minute >= 0, minute <= 59 else {
            return ""
        }
        return "\(hourText):\(minuteText)"
    }

    /// Offset-aware parse of Bob's RFC 3339 `wake_at`, never the
    /// naive-local parser. Nil when the string does not parse.
    static func parseSnoozedWakeAt(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fallback.date(from: raw)
    }

    /// Wall-clock `"HH:MM"` from an RFC 3339 instant, preserving Bob's
    /// wall time regardless of the app timezone. Nil when the string
    /// carries no clock time.
    static func snoozedWallTime(fromRFC3339 raw: String) -> String? {
        guard let tIndex = raw.firstIndex(of: "T") else {
            return nil
        }
        let afterT = raw[raw.index(after: tIndex)...]
        guard afterT.count >= 5 else {
            return nil
        }
        let clock = String(afterT.prefix(5))
        guard clock.count == 5, clock[clock.index(clock.startIndex, offsetBy: 2)] == ":" else {
            return nil
        }
        let digits = clock.filter { $0 != ":" }
        guard digits.allSatisfy({ $0.isNumber }) else {
            return nil
        }
        let hour = Int(clock.prefix(2)) ?? 99
        let minute = Int(clock.suffix(2)) ?? 99
        guard hour <= 23, minute <= 59 else {
            return nil
        }
        return clock
    }

    /// `"in 38m"` / `"in 3h 28m"` until the wake instant, `"now"`
    /// within the minute. Nil is never returned here; the caller
    /// decides when a countdown applies.
    static func snoozedCountdownText(until wake: Date, now: Date) -> String {
        let remaining = wake.timeIntervalSince(now)
        guard remaining > 60 else {
            return "now"
        }
        let minutes = Int(remaining / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            let padded = rest < 10 ? "0\(rest)" : "\(rest)"
            return "in \(hours)h \(padded)m"
        }
        return "in \(minutes)m"
    }

    /// Fresh-wake accent for a task headline: Bob's `woke_at`
    /// (`HH:MM`) on the snapshot day whose age is in
    /// `[0, 60 minutes)`. Nil for future, malformed, missing, and
    /// prior-day provenance; at exactly 60 minutes the accent is
    /// gone. Uses the existing agenda calendar convention (naive
    /// local on the snapshot date) for display aging.
    static func wokeAccent(
        wokeAt: String?,
        snapshotDate: String?,
        today: String,
        now: Date?,
        calendar: Calendar = Calendar.current
    ) -> CaptureAgendaWokeAccent? {
        guard let wokeAt, !wokeAt.isEmpty else {
            return nil
        }
        guard let snapshotDate, snapshotDate == today else {
            return nil
        }
        guard let now else {
            return nil
        }
        guard let wokeDate = Self.wokeDate(
            wokeAt: wokeAt,
            snapshotDate: snapshotDate,
            calendar: calendar
        ) else {
            return nil
        }
        let age = now.timeIntervalSince(wokeDate)
        guard age >= 0, age < 3600 else {
            return nil
        }
        return CaptureAgendaWokeAccent(timeText: wokeAt)
    }

    /// `"15:32"` on `"2026-08-28"` as a local wall-clock Date. Nil
    /// when either side is malformed.
    static func wokeDate(
        wokeAt: String,
        snapshotDate: String,
        calendar: Calendar = Calendar.current
    ) -> Date? {
        guard wokeAt.count == 5, wokeAt[wokeAt.index(wokeAt.startIndex, offsetBy: 2)] == ":" else {
            return nil
        }
        let hourText = String(wokeAt.prefix(2))
        let minuteText = String(wokeAt.suffix(2))
        guard let hour = Int(hourText), let minute = Int(minuteText) else {
            return nil
        }
        guard hour <= 23, minute <= 59 else {
            return nil
        }
        let parts = snapshotDate.split(separator: "-")
        guard parts.count == 3 else {
            return nil
        }
        guard let year = Int(parts[0]), let month = Int(parts[1]) else {
            return nil
        }
        guard let day = Int(parts[2]) else {
            return nil
        }
        let cal = calendar
        let components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return cal.date(from: components)
    }
}
