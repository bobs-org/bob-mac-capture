import Foundation

/// Pure presentation model for a Pomodoro close (`pomodoro_close` present on a
/// `bob capture --format json` success), built once from
/// `CaptureCommandSuccess` so the SwiftUI layer never branches on
/// close-specific JSON fields or recomputes clock math. The preview's only
/// source of truth is Bob's resolved `pomodoro_close` object — which itself
/// comes from `bob capture --dry-run --no-clip --format json` for live preview
/// and the same command without `--dry-run`/`--no-clip` for submission — so
/// there is no Swift-side clock or ledger logic here, only wording.
///
/// Wording mirrors `print_human_pomodoro_close_success` in
/// `src/native/capture.rs` (`closed`/`would close`, the range change, per-task
/// transitions, the next-session line) so the panel and the CLI describe the
/// same close the same way. Works for dry-run previews and committed captures
/// alike; `isDryRun` is the only thing that changes the verb.
public struct CapturePomodoroClosePresentation: Equatable, Sendable {
    public enum Variant: Equatable, Sendable {
        case session
        case linkedTask
        case newTask
    }

    public enum TimingTone: Equatable, Sendable {
        case early
        case onTime
        case over
    }

    /// The leading glyph family for a task row. `transition` renders the
    /// monospaced transition text itself (worked and mentioned rows); every
    /// other case maps to an SF Symbol in the card. Unknown roles degrade to
    /// `neutral`.
    public enum TaskGlyph: Equatable, Sendable {
        case transition
        case deferred
        case struck
        case dropped
        case embedded
        case unresolved
        case neutral
    }

    /// The outcome Bob's `=x[<N>][!<M>][~<K>]` selection gives a numbered row,
    /// joined from `tasks[].index` to `task_links`. Unknown wire strings
    /// degrade to nil, which renders exactly like today's unnumbered card.
    public enum TaskOutcome: Equatable, Sendable {
        case inProgress
        case deferred
        case complete
        case dropped
    }

    /// Why a numbered row got its outcome: `listed` (its number was typed),
    /// `unlisted` (`<N>` was typed without it), or `ledger` (its own marker).
    public enum TaskSource: Equatable, Sendable {
        case ledger
        case listed
        case unlisted
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

    /// The teaching hint shown under the task rows before a selection is
    /// typed: structured `tokens` for tinted rendering plus the joined `text`.
    public struct TeachingHint: Equatable, Sendable {
        public let tokens: [HintToken]
        public let text: String

        public init(tokens: [HintToken]) {
            self.tokens = tokens
            self.text = tokens.map(\.text).joined()
        }
    }

    public struct TaskRow: Equatable, Sendable {
        public let role: String
        public let glyph: TaskGlyph
        public let blockLink: String
        public let taskText: String
        public let transitionText: String
        /// `"bob.md · ^capture-stop"`, or the raw block link when Bob omitted
        /// the resolved target parts (unresolved rows).
        public let locatorText: String
        public let workLogCount: Int
        /// Typed Work Log entries first, all of them, never capped, with the
        /// `*YYYY-MM-DD* — ` date prefix stripped. An older Bob that omits
        /// `typed_work_log` decodes as empty.
        public let typedWorkLogPreviews: [String]
        /// Up to two remaining entry previews with the `*YYYY-MM-DD* — ` date
        /// prefix stripped, excluding the typed entries above.
        public let workLogPreviews: [String]
        public let warning: String?
        public let carried: Bool
        /// `"linked"` on the row matching a `pomodoro_link` close,
        /// `"new"` on the row matching a `pomodoro_task` close, else nil.
        public let tag: String?
        /// Struck rows render their text with strikethrough in the card.
        public let isStruck: Bool
        /// The 1-based number Bob assigned this row, or nil for unnumbered
        /// rows (struck, mentioned, subtask, Work-Log-only, older Bob).
        public let index: Int?
        /// The selection outcome from `task_links`, or nil when the row is
        /// unnumbered or Bob reported no lineup.
        public let outcome: TaskOutcome?
        /// Why the row got its outcome, or nil when `outcome` is nil.
        public let source: TaskSource?
        /// `"\(n).circle.fill"` when the row is listed, `"\(n).circle"`
        /// otherwise; nil for unnumbered rows and for `n > 50`, which render
        /// a monospaced-digit capsule instead (`usesNumericBadgeFallback`).
        public let badgeSymbolName: String?
        /// True for `n > 50`, which fall back to a monospaced-digit `Text` in
        /// a `Capsule` because no such SF Symbol exists.
        public let usesNumericBadgeFallback: Bool
        /// Unlisted rows render at reduced opacity so the chosen rows stand
        /// out. False whenever no selection was typed. Dropped rows always
        /// dim: they leave today entirely.
        public let isDimmed: Bool
        /// `"stays <status>"` on dropped rows, else nil.
        public let caption: String?
        /// `"Task 1, <text>, stays in progress, chosen"` for numbered rows;
        /// the transition text for unnumbered rows. Dropped rows read
        /// "drops from today".
        public let accessibilityLabel: String
    }

    /// At most this many task rows render in the card before a "+N more" line.
    public static let maxVisibleTaskRows = 6

    public let variant: Variant
    public let isDryRun: Bool
    public let pomodoroName: String
    /// `"Close CAPTURE"`, or `"Close session"` when Bob named no session.
    /// Link and new-task closes keep the same title; their "via" data lives
    /// in `viaText` and the tagged row instead.
    public let title: String
    /// `"0920-0950 → 0920-0940 · 20m"`, or `"0920-0950 · 30m"` when the close
    /// did not decrement the session.
    public let sessionText: String
    /// The planned range alone (`"0920-0950"`); the card tints the decrement
    /// half separately.
    public let sessionPlannedText: String
    /// `"→ 0920-0940 · 20m"` when decremented, else nil.
    public let sessionDecrementText: String?
    /// `"13m early"`, `"on time"`, or `"7m over"`, from `remaining_minutes`.
    public let timingText: String
    public let timingTone: TimingTone
    /// `"2026/20260928.md · line 5"` — the day file and `pomodoro_line`, never
    /// the route note.
    public let destinationText: String
    public let taskRows: [TaskRow]
    public let visibleTaskRows: [TaskRow]
    public let overflowTaskCount: Int
    /// The teaching hint, present when no selection was typed and at least
    /// one row is numbered. Nil once a selection is typed or with no lineup.
    public let teachingHint: TeachingHint?
    /// The outcome summary, present once a selection is typed (for example
    /// `"In progress 1, 3 · Complete 2 · Deferred 4"`). Nil before that.
    public let selectionSummary: String?
    /// True when the draft carried an `=x[<N>][!<M>]` selection
    /// (`in_progress` non-nil or `complete` non-empty).
    public let hasSelection: Bool
    /// How many numbered rows complete (`task_links` outcome `complete`).
    public let completedCount: Int
    /// `"1 note stays"` / `"N notes stay"`, or nil when nothing stays.
    public let notesText: String?
    /// `"Next: CAPTURE · new · carries 2 links"`, or
    /// `"Next: SASE · line 14"` for a pre-existing entry; nil when Bob
    /// reports no next session.
    public let nextText: String?
    /// `"No Task Links — the session simply closes"`, shown when `taskRows`
    /// is empty.
    public let emptyText: String
    /// `"Linked bob.md · ^ready into CAPTURE"`, `"Moved from SASE"`, or
    /// `"New task Draft docs → bob.md · ^draft-docs"`; nil for plain closes.
    public let viaText: String?
    /// `"Would close CAPTURE · 1 started · 3 Work Log entries"`
    /// (dry run) or `"Closed …"` (committed).
    public let statusText: String
    public let primaryActionTitle: String
    public let notificationTitle: String
    public let notificationBody: String
    /// `" (closed CAPTURE)"`, appended to batch lines for closes.
    public let batchSuffix: String
    public let accessibilitySummary: String
    public let warnings: [String]

    public init?(capture: CaptureCommandSuccess) {
        guard let summary = capture.pomodoroClose else {
            return nil
        }
        self.init(summary: summary, capture: capture)
    }

    init(summary: PomodoroCloseSummary, capture: CaptureCommandSuccess) {
        switch capture.kind.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "pomodoro_link":
            variant = .linkedTask
        case "pomodoro_task":
            variant = .newTask
        default:
            variant = .session
        }
        isDryRun = capture.dryRun
        pomodoroName = summary.pomodoroName ?? "session"
        title = "Close \(pomodoroName)"

        let plannedRange = summary.planned.timeRange
        let closedRange = summary.closed.timeRange
        let decremented = summary.decrementedMinutes > 0
        if decremented {
            sessionText =
                "\(plannedRange) → \(closedRange) · \(summary.closed.durationMinutes)m"
            sessionDecrementText = "→ \(closedRange) · \(summary.closed.durationMinutes)m"
        } else {
            sessionText = "\(plannedRange) · \(summary.planned.durationMinutes)m"
            sessionDecrementText = nil
        }
        sessionPlannedText = plannedRange

        let remaining = summary.remainingMinutes
        if remaining > 0 {
            timingText = "\(remaining)m early"
            timingTone = .early
        } else if remaining < 0 {
            timingText = "\(abs(remaining))m over"
            timingTone = .over
        } else {
            timingText = "on time"
            timingTone = .onTime
        }

        let dayFile = summary.dayRelative ?? capture.relativeTarget
        destinationText = "\(dayFile) · line \(summary.pomodoroLine)"

        let taggedBlockID: String? = (variant == .linkedTask || variant == .newTask)
            ? capture.blockID : nil
        let taggedTag = variant == .linkedTask ? "linked" : "new"
        let linksByIndex = Dictionary(
            summary.taskLinks.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        hasSelection = summary.inProgress != nil || !summary.complete.isEmpty || !summary.drop.isEmpty
        completedCount = summary.taskLinks.filter { $0.outcome == "complete" }.count
        taskRows = summary.tasks.map { task in
            Self.taskRow(
                for: task,
                link: task.index.flatMap { linksByIndex[$0] },
                tag: (taggedBlockID != nil && task.blockID == taggedBlockID) ? taggedTag : nil
            )
        }
        // Numbered rows always render: the `+N more` overflow cap only hides
        // unnumbered rows beyond `max(0, 6 − numbered)`, so a number is never
        // hidden.
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
        let numberedLinkCount = summary.taskLinks.count
        if !hasSelection, numberedLinkCount > 0 {
            teachingHint = TeachingHint(tokens: Self.hintTokens(numberedRows: numberedLinkCount))
            selectionSummary = nil
        } else {
            teachingHint = nil
            selectionSummary = hasSelection
                ? Self.summaryText(
                    links: summary.taskLinks,
                    inProgressEmpty: summary.inProgress?.isEmpty == true
                ) : nil
        }

        if summary.notes.isEmpty {
            notesText = nil
        } else if summary.notes.count == 1 {
            notesText = "1 note stays"
        } else {
            notesText = "\(summary.notes.count) notes stay"
        }

        if let next = summary.nextPomodoro {
            let nextName = next.name ?? summary.pomodoroName ?? "session"
            if next.created {
                let carriedCount = summary.carried.count
                nextText =
                    "Next: \(nextName) · new · carries \(carriedCount) link\(carriedCount == 1 ? "" : "s")"
            } else {
                nextText = "Next: \(nextName) · line \(next.line)"
            }
        } else {
            nextText = nil
        }

        emptyText = "No Task Links — the session simply closes"

        switch variant {
        case .session:
            viaText = nil
        case .linkedTask:
            if capture.pomodoroLinkAction == "moved" {
                viaText = "Moved from \(Self.movedSourceName(capture: capture, rows: taskRows))"
            } else {
                let blockID = capture.blockID ?? ""
                viaText = "Linked \(capture.routeLabel) · ^\(blockID) into \(pomodoroName)"
            }
        case .newTask:
            let blockID = capture.blockID ?? ""
            viaText = "New task \(capture.text) → \(capture.routeLabel) · ^\(blockID)"
        }

        let startedCount = summary.tasks.filter(\.statusChanged).count
        let workLogCount = summary.tasks.reduce(0) { $0 + $1.workLog.count }
        let verb = isDryRun ? "Would close" : "Closed"
        let completedFragment = completedCount > 0 ? " · \(completedCount) completed" : ""
        let workLogNoun = workLogCount == 1 ? "entry" : "entries"
        statusText =
            "\(verb) \(pomodoroName) · \(startedCount) started\(completedFragment) · \(workLogCount) Work Log \(workLogNoun)"
        primaryActionTitle = "Close"
        notificationTitle = "Closed \(pomodoroName)"

        var bodyLines = [
            "\(pomodoroName) \(sessionText) · \(timingText)",
            "\(taskRows.count) task\(taskRows.count == 1 ? "" : "s")\(completedFragment) · \(workLogCount) Work Log \(workLogNoun)",
        ]
        if let nextText {
            bodyLines.append(nextText)
        }
        notificationBody = bodyLines.joined(separator: "\n")
        batchSuffix = " (closed \(pomodoroName))"

        var summaryParts = [title, sessionText, timingText, destinationText]
        if let viaText {
            summaryParts.append(viaText)
        }
        summaryParts.append(contentsOf: taskRows.map(\.accessibilityLabel))
        summaryParts.append(contentsOf: taskRows.flatMap(\.typedWorkLogPreviews))
        summaryParts.append(contentsOf: taskRows.flatMap(\.workLogPreviews))
        if let teachingHint {
            summaryParts.append(teachingHint.text)
        }
        if let selectionSummary {
            summaryParts.append(selectionSummary)
        }
        if let notesText {
            summaryParts.append(notesText)
        }
        if let nextText {
            summaryParts.append(nextText)
        } else {
            summaryParts.append(emptyText)
        }
        summaryParts.append(contentsOf: capture.warnings.map { "Warning: \($0)" })
        accessibilitySummary = summaryParts.joined(separator: ", ")

        warnings = capture.warnings
    }

    private static func taskRow(
        for task: PomodoroCloseTask,
        link: PomodoroCloseTaskLink?,
        tag: String?
    ) -> TaskRow {
        let outcome: TaskOutcome? = link.flatMap { link in
            switch link.outcome {
            case "in_progress": .inProgress
            case "deferred": .deferred
            case "complete": .complete
            case "dropped": .dropped
            default: nil
            }
        }
        let source: TaskSource? = link.flatMap { link in
            switch link.source {
            case "ledger": .ledger
            case "listed": .listed
            case "unlisted": .unlisted
            default: nil
            }
        }
        let glyph: TaskGlyph
        let transition: String
        let previousMarker = CaptureTogglePresentation.marker(for: task.previousStatusSymbol)
        let currentMarker = CaptureTogglePresentation.marker(for: task.statusSymbol)
        // A complete row keeps the embedded glyph but tints it green in the
        // card, and strikes its text because the ledger line will be struck.
        // Its transition is the marker change when the status changed, else
        // the unchanged `[x] closed`.
        // A dropped row leaves today entirely: struck text, dimmed, its own
        // glyph. Its transition names the drop; a dropped row keeps its
        // lane elsewhere, hence the "stays <status>" caption.
        if outcome == .complete {
            glyph = .embedded
            if task.statusChanged {
                transition = "\(previousMarker) → \(currentMarker)"
            } else {
                transition = "[x] closed"
            }
        } else if outcome == .dropped || task.role == "dropped" {
            glyph = .dropped
            transition = "[~] dropped"
        } else {
            switch task.role {
            case "worked", "mentioned":
                if task.statusChanged {
                    glyph = .transition
                    transition = "\(previousMarker) → \(currentMarker)"
                } else {
                    glyph = .transition
                    transition = currentMarker
                }
            case "deferred":
                glyph = .deferred
                transition = "\(previousMarker) deferred"
            case "struck":
                glyph = .struck
                transition = "[x]"
            case "embedded", "subtask":
                glyph = .embedded
                transition = "[x] closed"
            case "unresolved":
                glyph = .unresolved
                transition = "[x]"
            default:
                glyph = .neutral
                transition = "[x]"
            }
        }
        let locator: String
        if let relativeTarget = task.relativeTarget, !task.blockID.isEmpty {
            locator = "\(relativeTarget) · ^\(task.blockID)"
        } else {
            locator = task.blockLink
        }
        let taskText = task.text ?? task.blockLink
        let badgeSymbolName: String?
        let usesNumericBadgeFallback: Bool
        if let index = task.index, link != nil {
            if index > 50 {
                badgeSymbolName = nil
                usesNumericBadgeFallback = true
            } else {
                badgeSymbolName = "\(index).circle\(source == .listed ? ".fill" : "")"
                usesNumericBadgeFallback = false
            }
        } else {
            badgeSymbolName = nil
            usesNumericBadgeFallback = false
        }
        let isDropped = outcome == .dropped || task.role == "dropped"
        let isDimmed = source == .unlisted || isDropped
        let isStruck = task.role == "struck" || outcome == .complete || isDropped
        let caption: String? = isDropped
            ? "stays \(CaptureTogglePresentation.staysStatusName(symbol: task.statusSymbol, name: task.statusName))" : nil
        let typedPreviews = task.typedWorkLog.map(Self.strippedWorkLogDate)
        // Subtract typed entries by occurrence count so a hand-written entry
        // with identical dated text survives alongside its typed twin.
        var typedCounts: [String: Int] = [:]
        for entry in task.typedWorkLog {
            typedCounts[entry, default: 0] += 1
        }
        var remaining: [String] = []
        remaining.reserveCapacity(task.workLog.count)
        for entry in task.workLog {
            if let count = typedCounts[entry], count > 0 {
                typedCounts[entry] = count - 1
            } else {
                remaining.append(entry)
            }
        }
        if remaining.count == task.workLog.count, !task.typedWorkLog.isEmpty {
            // Defensive: dated typed entries may differ in whitespace from
            // `work_log`; fall back to stripped comparison, consuming one
            // normalized entry per still-unmatched typed entry.
            var strippedCounts: [String: Int] = [:]
            for preview in typedPreviews {
                strippedCounts[preview, default: 0] += 1
            }
            var strippedRemaining: [String] = []
            strippedRemaining.reserveCapacity(task.workLog.count)
            for entry in task.workLog {
                let stripped = Self.strippedWorkLogDate(entry)
                if let count = strippedCounts[stripped], count > 0 {
                    strippedCounts[stripped] = count - 1
                } else {
                    strippedRemaining.append(entry)
                }
            }
            if strippedRemaining.count != task.workLog.count {
                remaining = strippedRemaining
            }
        }
        let otherPreviews = remaining.prefix(2).map(Self.strippedWorkLogDate)
        let accessibilityLabel: String
        if let index = task.index, let outcome {
            let fate: String
            switch outcome {
            case .inProgress: fate = "stays in progress"
            case .deferred: fate = "deferred"
            case .complete: fate = "completes"
            case .dropped: fate = "drops from today"
            }
            let chosen = source == .listed ? ", chosen" : ""
            let typed = typedPreviews.isEmpty ? "" : ", \(typedPreviews.joined(separator: ", "))"
            accessibilityLabel = "Task \(index), \(taskText), \(fate)\(chosen)\(typed)"
        } else {
            accessibilityLabel = transition
        }
        return TaskRow(
            role: task.role,
            glyph: glyph,
            blockLink: task.blockLink,
            taskText: taskText,
            transitionText: transition,
            locatorText: locator,
            workLogCount: task.workLog.count,
            typedWorkLogPreviews: typedPreviews,
            workLogPreviews: otherPreviews,
            warning: task.warning,
            carried: task.carried,
            tag: tag,
            isStruck: isStruck,
            index: link == nil ? nil : task.index,
            outcome: outcome,
            source: source,
            badgeSymbolName: badgeSymbolName,
            usesNumericBadgeFallback: usesNumericBadgeFallback,
            isDimmed: isDimmed,
            caption: caption,
            accessibilityLabel: accessibilityLabel
        )
    }

    /// The teaching hint tokens for a lineup of `numberedRows` rows. Example
    /// tokens carry the editor span category whose color they share (`=x` is
    /// Pomodoro-session pink, `<N>` digits are orange, `!<M>` digits are
    /// green, `~<K>` digits are muted gray); prose carries `.neutral`.
    static func hintTokens(numberedRows: Int) -> [HintToken] {
        let close: [HintToken] = [HintToken(text: "=x", category: .pomodoroStart)]
        let logExample: [HintToken] = [HintToken(text: " · ", category: .neutral)]
            + close + [HintToken(text: "1", category: .pomodoroCloseLog)]
            + [HintToken(text: " wrote the tests logs work to 1", category: .neutral)]
        if numberedRows >= 2 {
            return close + [HintToken(text: "1,2", category: .pomodoroCloseInProgress)]
                + [HintToken(text: " keeps only these in progress · ", category: .neutral)]
                + close + [HintToken(text: "!2", category: .pomodoroCloseComplete)]
                + [HintToken(text: " completes 2 · ", category: .neutral)]
                + close + [HintToken(text: "~3", category: .pomodoroCloseDrop)]
                + [HintToken(text: " drops 3 · ", category: .neutral)]
                + close + [HintToken(text: "0", category: .pomodoroCloseInProgress)]
                + [HintToken(text: " defers all", category: .neutral)]
                + logExample
        }
        return close + [HintToken(text: "!1", category: .pomodoroCloseComplete)]
            + [HintToken(text: " completes it · ", category: .neutral)]
            + close + [HintToken(text: "~1", category: .pomodoroCloseDrop)]
            + [HintToken(text: " drops it · ", category: .neutral)]
            + close + [HintToken(text: "0", category: .pomodoroCloseInProgress)]
            + [HintToken(text: " defers it", category: .neutral)]
            + logExample
    }

    /// The selection summary from `task_links` in ascending order, for example
    /// `"In progress 1, 3 · Complete 2 · Deferred 4 · Dropped 5"`. Empty
    /// groups are omitted, except that `=x0` (an explicitly empty `<N>` list,
    /// `inProgressEmpty`) shows `"In progress none"`. Nil when every group is
    /// empty.
    static func summaryText(links: [PomodoroCloseTaskLink], inProgressEmpty: Bool) -> String? {
        func group(_ outcome: String) -> [Int] {
            links.filter { $0.outcome == outcome }.map(\.index).sorted()
        }
        func joined(_ numbers: [Int]) -> String {
            numbers.map(String.init).joined(separator: ", ")
        }
        var parts: [String] = []
        let inProgress = group("in_progress")
        let complete = group("complete")
        let deferred = group("deferred")
        let dropped = group("dropped")
        if inProgress.isEmpty, complete.isEmpty, deferred.isEmpty, dropped.isEmpty {
            return nil
        }
        if inProgress.isEmpty, inProgressEmpty {
            // `=x0`: no task stays in progress.
            parts.append("In progress none")
        } else if !inProgress.isEmpty {
            parts.append("In progress \(joined(inProgress))")
        }
        if !complete.isEmpty {
            parts.append("Complete \(joined(complete))")
        }
        if !deferred.isEmpty {
            parts.append("Deferred \(joined(deferred))")
        }
        if !dropped.isEmpty {
            parts.append("Dropped \(joined(dropped))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The pending summary row for a draft whose list dangles: `"Type a task
    /// number after ,"` (or `"after !"` / `"after ~"`).
    public static func pendingText(separator: String) -> String {
        "Type a task number after \(separator)"
    }

    /// The pending summary row for a draft whose Work Log index dangles
    /// (`=x 1`): teaches the entry plus the escape.
    public static func pendingLogText(index: Int) -> String {
        "Type the Work Log entry for task \(index) — or write \\\(index) to keep the number"
    }

    /// Work Log entries arrive dated (`*2026-09-28* — Designed …`); the card
    /// shows them under a dated section already, so strip the date prefix.
    static func strippedWorkLogDate(_ entry: String) -> String {
        guard entry.hasPrefix("*") else {
            return entry
        }
        guard let separator = entry.range(of: "* — ") else {
            return entry
        }
        let datePart = entry[entry.index(after: entry.startIndex)..<separator.lowerBound]
        let isDate = datePart.count == 10
            && datePart.allSatisfy { $0.isNumber || $0 == "-" }
        return isDate ? String(entry[separator.upperBound...]) : entry
    }

    /// The moved-from session name. Newer bob omits the source endpoint name,
    /// so derive it from the moved task's own note stem (Pomodoro entries are
    /// uppercase by convention): `sase.md` → `SASE`. Falls back to the capture
    /// route when no row matches the moved task.
    private static func movedSourceName(
        capture: CaptureCommandSuccess,
        rows: [TaskRow]
    ) -> String {
        let notePath: String?
        if capture.blockID != nil,
           let row = rows.first(where: { $0.tag == "linked" && !$0.locatorText.isEmpty })
        {
            notePath = row.locatorText.split(separator: "·").first.map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        } else {
            notePath = nil
        }
        let rawStem = (notePath ?? capture.route ?? "")
            .split(separator: "/").last.map(String.init) ?? ""
        let stem = rawStem.hasSuffix(".md") ? String(rawStem.dropLast(3)) : rawStem
        let upper = stem.uppercased()
        return upper.isEmpty ? "previous session" : upper
    }
}
