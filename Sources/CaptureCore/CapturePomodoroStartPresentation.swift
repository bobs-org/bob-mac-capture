import Foundation

/// Pure presentation model for a Pomodoro start (`pomodoro_start` present on a
/// `bob capture --format json` success), built once from `CaptureCommandSuccess` so the
/// SwiftUI layer never branches on start-specific JSON fields or recomputes clock math.
/// The preview's only source of truth is Bob's resolved `pomodoro_start` object — which
/// itself comes from `bob capture --dry-run --no-clip --format json` for live preview
/// and the same command without `--dry-run`/`--no-clip` for submission — so there is no
/// Swift-side clock or ledger logic here, only wording.
///
/// Wording mirrors `print_human_pomodoro_start_success` in `src/native/capture.rs`
/// (`would start` / `started`, the session line, queued-task rows in the close's row
/// style, `nothing queued`) so the panel and the CLI describe the same session the same
/// way. Works for dry-run previews and committed captures alike; `isDryRun` is the only
/// thing that changes the verb. Link and task starts (`^route:id=`, `Text @route:id=3`)
/// carry no `tasks` array and keep their existing row/suffix rendering; the start card,
/// `Start` footer action, and start notification apply to whole-item `=`/`=<X>` starts
/// (`kind == "pomodoro_start"` — see `isSessionStart`).
///
/// A `==` override keeps the same kind and card: the presentation only rewords it.
/// `variant` drives the title (`Restart CAPTURE` / `Restarted CAPTURE`,
/// `Swap in BUGS` / `Swapped in BUGS`), the status line, the `Takes over` badge
/// for kept-ledger swaps, the idle caption when nothing was running, the
/// `Restart` / `Swap` footer action, and the notification title/body, so the
/// SwiftUI layer never branches on override JSON fields.
public struct CapturePomodoroStartPresentation: Equatable, Sendable {
    /// Which session story this card tells: a plain `=` start, a `==<X>`
    /// restart of the running session, a `==[<X>]#name` swap, or an idle
    /// `==` that behaved exactly like its `=` twin. Decoded once from
    /// `pomodoro_start.override`; an older Bob without it is a plain start.
    public enum Variant: Equatable, Sendable {
        case start
        case restart
        case swap
        case idleStart
    }
    /// The leading glyph for a queued-task row. Resolved rows map the task's
    /// current status symbol; unresolved rows always warn. Dropped rows leave
    /// today entirely and render the close card's `minus.circle` glyph.
    public enum TaskGlyph: Equatable, Sendable {
        case ready
        case next
        case inProgress
        case other
        case unresolved
        case dropped
    }

    /// One segment of the teaching hint: example tokens carry the editor span
    /// category whose color they share, and prose carries `.neutral`.
    public struct HintToken: Equatable, Sendable {
        public let text: String
        public let category: CaptureSemanticCategory

        public init(text: String, category: CaptureSemanticCategory) {
            self.text = text
            self.category = category
        }
    }

    /// The teaching hint shown under the destination before a drop is typed:
    /// structured `tokens` for tinted rendering plus the joined `text`.
    public struct TeachingHint: Equatable, Sendable {
        public let tokens: [HintToken]
        public let text: String

        public init(tokens: [HintToken]) {
            self.tokens = tokens
            self.text = tokens.map(\.text).joined()
        }
    }

    public struct TaskRow: Equatable, Sendable {
        public let glyph: TaskGlyph
        public let blockLink: String
        public let taskText: String
        /// `"bob ^capture-stop"`, or the raw block link when Bob omitted the
        /// resolved target parts.
        public let locatorText: String
        /// Unresolved rows carry the warning the card renders as help text.
        public let warning: String?
        /// The 1-based lineup number Bob assigned this row, or nil for
        /// unnumbered rows (older Bob), which render exactly like today's
        /// card: no badge, still capped under `+N more`.
        public let index: Int?
        /// True for rows removed by the typed `~<K>` list. They render
        /// struck and dimmed with the `minus.circle` gray glyph, in place in
        /// lineup order.
        public let isDropped: Bool
        /// `"\(n).circle"`, or `"\(n).circle.fill"` for dropped (listed)
        /// rows; nil for unnumbered rows and for `n > 50`, which render a
        /// monospaced-digit capsule instead (`usesNumericBadgeFallback`).
        public let badgeSymbolName: String?
        /// True for `n > 50`, which fall back to a monospaced-digit `Text` in
        /// a `Capsule` because no such SF Symbol exists.
        public let usesNumericBadgeFallback: Bool
        /// Dropped rows always dim: they leave today entirely.
        public let isDimmed: Bool
        /// Dropped rows render their text with strikethrough in the card.
        public let isStruck: Bool
        /// `"stays <status>"` and/or `"with N nested line(s)"` on dropped
        /// rows, else nil.
        public let caption: String?
        /// `"Task 1, <text>, queued"` for numbered kept rows;
        /// `"Task 2, <text>, drops from today"` for numbered dropped rows;
        /// the task text for unnumbered rows.
        public let accessibilityLabel: String
    }

    /// At most this many task rows render in the card before a "+N more" line —
    /// the same cap as the close card. Numbered rows never hide under it: the
    /// cap only hides unnumbered rows beyond `max(0, 6 − numbered)`, so a
    /// number is never hidden.
    public static var maxVisibleTaskRows: Int {
        CapturePomodoroClosePresentation.maxVisibleTaskRows
    }

    /// True for a whole-item `=`/`=<X>` start: the only shape that gets the
    /// start card, the `Start` footer action, and the start notification.
    /// Link and task starts share the `pomodoro_start` object but keep their
    /// own presentations.
    public static func isSessionStart(_ capture: CaptureCommandSuccess) -> Bool {
        capture.kind.lowercased().replacingOccurrences(of: "-", with: "_")
            == "pomodoro_start" && capture.pomodoroStart != nil
    }

    public let isDryRun: Bool
    public let pomodoroName: String
    public let start: String
    public let end: String
    public let durationMinutes: Int
    public let offsetUnits: Int
    public let pomodoroLine: Int
    public let createdPomodoro: Bool
    public let timeRange: String

    /// `"Start CAPTURE"` (dry run) or `"Started CAPTURE"`.
    public let title: String
    /// `"Would start CAPTURE 0940-1005 (25m) at line 13"` (dry run) or
    /// `"Started … at line 13"` (committed), plus `" · drops 2"` (dry run)
    /// or `" · dropped 2"` (committed) once a drop is typed.
    public let statusText: String
    /// `"0940-1005 (25m)"` — the calm, legible session line shown in preview.
    public let sessionText: String
    /// `"2026/20260928.md · line 13"` — the day file and `pomodoro_line`.
    public let destinationText: String
    /// Kept and dropped rows merged in lineup order (`index` ascending; rows
    /// without `index` keep ledger order after the numbered rows).
    public let taskRows: [TaskRow]
    public let visibleTaskRows: [TaskRow]
    public let overflowTaskCount: Int
    /// `"Nothing queued"`, shown when `taskRows` is empty.
    public let emptyText: String
    public let accessibilitySummary: String
    public let notificationDetail: String
    /// `"Started CAPTURE"`, the single-capture notification title.
    public let notificationTitle: String
    /// `"0940-1005 (25m) · 2 queued tasks"` (`"1 queued task"` for one,
    /// `"Nothing queued"` for none), plus `" · dropped 2"` once a drop is
    /// typed. The queued count counts `tasks` only, so a drop leaves the
    /// count truthful. A created session instead reads
    /// `"0940–1005 (25m) · New session"`.
    public let notificationBody: String
    /// `"New"` on a dry run that creates the session, `"Created"` once
    /// committed, nil for starts of an existing entry. Rendered as a small
    /// pink capsule next to the card title.
    public let createdBadgeText: String?
    /// The teaching hint, present while no drop is typed and the lineup is
    /// non-empty — or, for a bare start with an empty lineup, today's
    /// `#name` hint. Nil once a drop is typed (the summary shows instead)
    /// and for named starts with an empty lineup. Rendered as a quiet
    /// caption in the close card's teaching-hint style.
    public let teachingHint: TeachingHint?
    /// `"Dropped 2, 4"` once a drop is typed, plus `" · nothing left
    /// queued"` when no kept rows remain. Nil before that.
    public let dropSummary: String?
    /// `" (started CAPTURE 0940-1005)"`, appended to batch lines for starts
    /// (` (restarted CAPTURE 0935-1000)` for restarts,
    /// ` (swapped in BUGS 0920-0945)` for swaps).
    public let batchSuffix: String
    public let primaryActionTitle: String
    /// The session story this card tells (see `Variant`).
    public let variant: Variant
    /// True for a swap that took over the running ledger byte-for-byte.
    public let takesOverLedger: Bool
    /// `"Takes over"` on a kept-ledger swap, nil otherwise. Rendered as a
    /// small pink capsule next to the title, alongside New/Created.
    public let takesOverBadgeText: String?
    /// `"Nothing was running — starts like ="` when an idle `==` behaved
    /// like its `=` twin, nil otherwise.
    public let idleCaption: String?
    /// `"was 0920–0945"` (the pre-image range) on a restart, nil otherwise.
    /// Rendered as a dim caption under the title.
    public let restartWasText: String?
    /// `"CAPTURE → first future · keeps 2 Task Links"` (plus
    /// `" and its notes"`) on a swap, nil otherwise. Rendered as the
    /// demoted row under the title.
    public let demotedText: String?

    public init?(capture: CaptureCommandSuccess) {
        guard let summary = capture.pomodoroStart else {
            return nil
        }
        self.init(
            summary: summary,
            dryRun: capture.dryRun,
            relativeTarget: capture.relativeTarget,
            captureText: capture.text
        )
    }

    public init(
        summary: PomodoroStartSummary,
        dryRun: Bool,
        relativeTarget: String = "",
        captureText: String = ""
    ) {
        isDryRun = dryRun
        pomodoroName = summary.pomodoroName ?? "next session"
        start = summary.start
        end = summary.end
        durationMinutes = summary.durationMinutes
        offsetUnits = summary.offsetUnits
        pomodoroLine = summary.pomodoroLine
        createdPomodoro = summary.createdPomodoro
        timeRange = summary.timeRange

        let override = summary.overrideOutcome
        switch override?.action {
        case "restart":
            variant = .restart
        case "swap":
            variant = .swap
        case "start":
            variant = .idleStart
        default:
            variant = .start
        }
        takesOverLedger = override?.ledger == "kept" && variant == .swap
        takesOverBadgeText = takesOverLedger ? "Takes over" : nil
        idleCaption = variant == .idleStart ? "Nothing was running — starts like =" : nil
        let previousRange = override?.previous?.timeRange ?? ""
        if variant == .restart, !previousRange.isEmpty {
            restartWasText = "was \(enDashRange(previousRange))"
        } else {
            restartWasText = nil
        }
        if variant == .swap, let demoted = override?.demoted {
            let demotedName = demotedNameText(demoted.pomodoroName)
            let links = demoted.taskLinks == 1
                ? "keeps 1 Task Link"
                : "keeps \(demoted.taskLinks) Task Links"
            let notes = demoted.hasNotes ? " and its notes" : ""
            demotedText = "\(demotedName) → first future · \(links)\(notes)"
        } else {
            demotedText = nil
        }

        let dropList = summary.drop
        let hasDrop = !dropList.isEmpty
        let dropNumbers = dropList.map(String.init).joined(separator: ", ")

        sessionText = "\(start)-\(end) (\(durationMinutes)m)"
        destinationText = "\(relativeTarget) · line \(pomodoroLine)"

        let created = summary.createdPomodoro ? " (created)" : ""
        let dropSuffix = hasDrop ? (dryRun ? " · drops \(dropNumbers)" : " · dropped \(dropNumbers)") : ""
        switch variant {
        case .restart:
            title = "\(dryRun ? "Restart" : "Restarted") \(pomodoroName)"
            statusText =
                "\(dryRun ? "Would restart" : "Restarted") \(pomodoroName) \(previousRange) → \(start)-\(end) (\(durationMinutes)m)\(created) at line \(pomodoroLine)\(dropSuffix)"
        case .swap:
            title = "\(dryRun ? "Swap in" : "Swapped in") \(pomodoroName)"
            if takesOverLedger {
                let previousName = demotedNameText(override?.previous?.pomodoroName)
                statusText =
                    "\(dryRun ? "Would swap in" : "Swapped in") \(pomodoroName) \(previousRange) (takes over \(previousName))\(created) at line \(pomodoroLine)\(dropSuffix)"
            } else {
                statusText =
                    "\(dryRun ? "Would swap in" : "Swapped in") \(pomodoroName) \(start)-\(end) (\(durationMinutes)m)\(created) at line \(pomodoroLine)\(dropSuffix)"
            }
        case .start, .idleStart:
            title = "\(dryRun ? "Start" : "Started") \(pomodoroName)"
            let verb = dryRun ? "Would start" : "Started"
            statusText =
                "\(verb) \(pomodoroName) \(start)-\(end) (\(durationMinutes)m)\(created) at line \(pomodoroLine)\(dropSuffix)"
        }

        // The start card only renders for whole-item starts. A `#` in the
        // capture text means a named `=<X>#name` start.
        createdBadgeText = summary.createdPomodoro ? (dryRun ? "New" : "Created") : nil
        let isNamed = captureText.contains("#")

        taskRows = Self.mergedRows(summary: summary)
        let numberedCount = taskRows.filter { $0.index != nil }.count
        let unnumberedAllowance = max(0, Self.maxVisibleTaskRows - numberedCount)
        var visible: [TaskRow] = []
        visible.reserveCapacity(min(taskRows.count, Self.maxVisibleTaskRows))
        var unnumberedShown = 0
        for row in taskRows {
            if row.index != nil {
                visible.append(row)
            } else if unnumberedShown < unnumberedAllowance {
                visible.append(row)
                unnumberedShown += 1
            }
        }
        visibleTaskRows = visible
        overflowTaskCount = taskRows.count - visible.count
        emptyText = "Nothing queued"

        if hasDrop {
            teachingHint = nil
            var summaryText = "Dropped \(dropNumbers)"
            if (summary.tasks ?? []).isEmpty {
                summaryText += " · nothing left queued"
            }
            dropSummary = summaryText
        } else if taskRows.isEmpty {
            dropSummary = nil
            teachingHint = isNamed
                ? nil
                : TeachingHint(
                    tokens: [HintToken(text: "Type ", category: .neutral)]
                        + Self.nameExampleTokens
                )
        } else {
            dropSummary = nil
            teachingHint = TeachingHint(
                tokens: Self.dropHintTokens(rowCount: taskRows.count)
                    + (isNamed
                        ? []
                        : [HintToken(text: " · ", category: .neutral)] + Self.nameExampleTokens)
            )
        }

        var spoken: String
        switch variant {
        case .restart:
            let was = override?.previous.map { "was \($0.start) to \($0.end)" }
            spoken =
                "Restarts \(pomodoroName), \(start) to \(end), \(durationMinutes) minutes, line \(pomodoroLine)"
            if let was {
                spoken += ", \(was)"
            }
        case .swap:
            let previousName = demotedNameText(override?.previous?.pomodoroName)
            let taken = previousRange.isEmpty ? "" : ", takes over \(previousRange) from \(previousName)"
            let demotedName = demotedNameText(override?.demoted?.pomodoroName)
            spoken =
                "Swaps in \(pomodoroName)\(taken), \(demotedName) returns to first future, line \(pomodoroLine)"
            if summary.createdPomodoro {
                spoken += ", created new entry"
            }
        case .start, .idleStart:
            let createdPhrase = summary.createdPomodoro ? ", created new entry" : ", uses existing entry"
            spoken =
                "Starts \(pomodoroName), \(start) to \(end), \(durationMinutes) minutes, line \(pomodoroLine)\(createdPhrase)"
            if summary.createdPomodoro {
                spoken += ", new session"
            }
        }
        if let tasks = summary.tasks {
            spoken += tasks.isEmpty
                ? ", nothing queued"
                : ", \(tasks.count) queued task\(tasks.count == 1 ? "" : "s")"
        }
        spoken += taskRows.compactMap { $0.index == nil ? nil : ", \($0.accessibilityLabel)" }.joined()
        if let idleCaption {
            spoken += ". \(idleCaption)"
        }
        if let teachingHint {
            spoken += ". \(teachingHint.text)"
        }
        if let dropSummary {
            spoken += ". \(dropSummary)"
        }
        accessibilitySummary = spoken
        notificationDetail = statusText

        let notificationDropSuffix = hasDrop ? " · dropped \(dropNumbers)" : ""
        switch variant {
        case .restart:
            notificationTitle = "Restarted \(pomodoroName)"
            if let tasks = summary.tasks, !tasks.isEmpty {
                notificationBody =
                    "\(enDashRange(sessionText)) · \(tasks.count) queued\(notificationDropSuffix)"
            } else {
                notificationBody = "\(enDashRange(sessionText)) · Nothing queued\(notificationDropSuffix)"
            }
        case .swap:
            notificationTitle = "Swapped in \(pomodoroName)"
            let takenRange = takesOverLedger ? previousRange : "\(start)-\(end)"
            let demotedName = demotedNameText(override?.demoted?.pomodoroName)
            notificationBody =
                "\(enDashRange(takenRange)) · \(demotedName) back to first future\(notificationDropSuffix)"
        case .start, .idleStart:
            notificationTitle = "Started \(pomodoroName)"
            if summary.createdPomodoro {
                notificationBody = "\(enDashRange(sessionText)) · New session\(notificationDropSuffix)"
            } else if let tasks = summary.tasks, !tasks.isEmpty {
                notificationBody =
                    "\(sessionText) · \(tasks.count) queued task\(tasks.count == 1 ? "" : "s")\(notificationDropSuffix)"
            } else {
                notificationBody = "\(sessionText) · Nothing queued\(notificationDropSuffix)"
            }
        }
        switch variant {
        case .restart:
            batchSuffix = " (restarted \(pomodoroName) \(start)-\(end))"
        case .swap:
            let takenRange = takesOverLedger ? previousRange : "\(start)-\(end)"
            batchSuffix = " (swapped in \(pomodoroName) \(takenRange))"
        case .start, .idleStart:
            batchSuffix = " (started \(pomodoroName) \(start)-\(end))"
        }
        switch variant {
        case .restart:
            primaryActionTitle = "Restart"
        case .swap:
            primaryActionTitle = "Swap"
        case .start, .idleStart:
            primaryActionTitle = "Start"
        }
    }

    /// Kept (`tasks`) and dropped (`dropped`) rows merged in lineup order:
    /// `index` ascending, with unnumbered rows (older Bob) keeping ledger
    /// order after the numbered rows so they render exactly like today's
    /// card.
    private static func mergedRows(summary: PomodoroStartSummary) -> [TaskRow] {
        let kept = (summary.tasks ?? []).map { ($0, false) }
        let dropped = summary.dropped.map { ($0, true) }
        let ordered = (kept + dropped).enumerated().sorted { lhs, rhs in
            switch (lhs.element.0.index, rhs.element.0.index) {
            case let (a?, b?):
                if a != b {
                    return a < b
                }
                return lhs.offset < rhs.offset
            case (nil, nil):
                return lhs.offset < rhs.offset
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            }
        }
        return ordered.map { taskRow(for: $0.element.0, dropped: $0.element.1) }
    }

    /// The `Type ~N to drop task N` example tokens. The `~N` token shares the
    /// editor `pomodoro_start_drop` span color; prose stays neutral. A lone
    /// row reads `Type ~1 to drop it`.
    static func dropHintTokens(rowCount: Int) -> [HintToken] {
        if rowCount < 2 {
            return [
                HintToken(text: "Type ", category: .neutral),
                HintToken(text: "~1", category: .pomodoroStartDrop),
                HintToken(text: " to drop it", category: .neutral),
            ]
        }
        return [
            HintToken(text: "Type ", category: .neutral),
            HintToken(text: "~2", category: .pomodoroStartDrop),
            HintToken(text: " to drop task 2", category: .neutral),
        ]
    }

    /// The `#name to start a specific Pomodoro` example shared by the bare
    /// hints: the `#name` example shares the editor `pomodoro_name` span
    /// color, prose stays neutral. Callers prepend `"Type "` (empty lineup)
    /// or `" · "` (after the drop hint).
    static var nameExampleTokens: [HintToken] {
        [
            HintToken(text: "#name", category: .section),
            HintToken(text: " to start a specific Pomodoro", category: .neutral),
        ]
    }

    private static func taskRow(for task: PomodoroStartTask, dropped: Bool) -> TaskRow {
        let glyph: TaskGlyph
        if dropped {
            glyph = .dropped
        } else if !task.resolved {
            glyph = .unresolved
        } else {
            switch task.statusSymbol {
            case " ":
                glyph = .ready
            case "*":
                glyph = .next
            case "/":
                glyph = .inProgress
            default:
                glyph = .other
            }
        }
        let locator: String
        if let relativeTarget = task.relativeTarget, !task.blockID.isEmpty {
            let stem = relativeTarget.hasSuffix(".md")
                ? String(relativeTarget.dropLast(3)) : relativeTarget
            locator = "\(stem) ^\(task.blockID)"
        } else {
            locator = task.blockLink
        }
        let taskText = task.text ?? task.blockLink
        let badgeSymbolName: String?
        let usesNumericBadgeFallback: Bool
        if let index = task.index {
            if index > 50 {
                badgeSymbolName = nil
                usesNumericBadgeFallback = true
            } else {
                badgeSymbolName = "\(index).circle\(dropped ? ".fill" : "")"
                usesNumericBadgeFallback = false
            }
        } else {
            badgeSymbolName = nil
            usesNumericBadgeFallback = false
        }
        let caption: String?
        if dropped {
            var parts = [
                "stays \(CaptureTogglePresentation.staysStatusName(symbol: task.statusSymbol, name: task.statusName))"
            ]
            if task.nestedLines > 0 {
                parts.append(
                    "with \(task.nestedLines) nested line\(task.nestedLines == 1 ? "" : "s")"
                )
            }
            caption = parts.joined(separator: " · ")
        } else {
            caption = nil
        }
        let accessibilityLabel: String
        if let index = task.index {
            accessibilityLabel = dropped
                ? "Task \(index), \(taskText), drops from today"
                : "Task \(index), \(taskText), queued"
        } else {
            accessibilityLabel = taskText
        }
        return TaskRow(
            glyph: glyph,
            blockLink: task.blockLink,
            taskText: taskText,
            locatorText: locator,
            warning: task.warning,
            index: task.index,
            isDropped: dropped,
            badgeSymbolName: badgeSymbolName,
            usesNumericBadgeFallback: usesNumericBadgeFallback,
            isDimmed: dropped,
            isStruck: dropped,
            caption: caption,
            accessibilityLabel: accessibilityLabel
        )
    }
}

/// Display name for an override previous/demoted session: Bob's canonical
/// name, falling back to `"session"` when the session was unnamed.
private func demotedNameText(_ name: String?) -> String {
    guard let name, !name.isEmpty else {
        return "session"
    }
    return name
}
