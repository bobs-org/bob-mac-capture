import Foundation

/// Pure reducer for the Pull-In cancel reason `LINK` band: wikilink
/// completion inside plain prose, answered by
/// `bob capture-complete --links-only` (thin client: bob owns discovery,
/// ranking, and byte ranges; the app only decodes and presents).
///
/// Selection is tracked by candidate `id` (bob's composite row key), never
/// by index. While a request is in flight the previous rows stay visible;
/// a stale reply never moves a highlight. The band shows whenever bob
/// reports a link field (`context != nil`), even with zero candidates, so
/// Return on an empty field closes the band instead of confirming.
///
/// Mirrors `LogRecallState` (the `USED BEFORE` band this replaces in its
/// slot): the same move/clamp shape, one layer of Esc, and row keys.
public struct PullInLinkState: Equatable, Sendable {
    /// Draft text the live request was sent for (or "" before the first).
    public var text: String = ""
    /// UTF-8 byte offset the live request was sent for.
    public var cursorUTF8: Int = 0
    /// Link field bob reported, or nil when the caret is not in a field.
    public var context: CaptureCompletionContext?
    /// Byte range bob's replacement covers in `text`.
    public var replacement = CaptureRange(start: 0, end: 0)
    /// Bob's candidates in bob's order.
    public var candidates: [CaptureCompletionCandidate] = []
    /// Selected candidate `id`, or nil for nothing selected.
    public var selectedID: String?
    /// Generation guard: a stale reply never moves a highlight or fills.
    public var generation: UInt64 = 0
    /// The task the reason row itself is about, so the tasks band can dim it.
    public var subject: PullInLinkSubject?
    /// The tasks band's NAME stage, while it names an ID-less task.
    public var name: PullInLinkNameStage?
    /// First visible row of the window. The window follows the selection so
    /// a long `((` list never selects a row the band does not show.
    public private(set) var windowStart = 0

    public init() {}

    /// Whether the band is visible: bob reported a link field.
    public var isOpen: Bool { context != nil }

    /// Rows the band shows: a window of at most `maxRows` rows that always
    /// contains the selection, for the dense pull-in card.
    public var visibleCandidates: [CaptureCompletionCandidate] {
        let start = min(max(windowStart, 0), candidates.count)
        let end = min(start + PullInLinkBandPresentation.maxRows, candidates.count)
        return Array(candidates[start..<end])
    }

    /// Slide the window just far enough to show the selected row.
    private mutating func revealSelection() {
        guard let selectedID,
            let position = candidates.firstIndex(where: { $0.id == selectedID })
        else {
            return
        }
        let rows = PullInLinkBandPresentation.maxRows
        if position < windowStart {
            windowStart = position
        } else if position >= windowStart + rows {
            windowStart = position - rows + 1
        }
    }

    /// 1-based position of the selection, or nil when nothing is selected.
    public var selectedIndex: Int? {
        guard let selectedID else { return nil }
        guard let position = candidates.firstIndex(where: { $0.id == selectedID }) else {
            return nil
        }
        return position + 1
    }

    public var selectedCandidate: CaptureCompletionCandidate? {
        guard let selectedID else { return nil }
        return candidates.first(where: { $0.id == selectedID })
    }

    /// A new reason edit session: forget the band, arm the next generation.
    /// `subject` names the task the reason row is about; it lasts for the
    /// session and is dropped by the next plain `beginReason()`.
    public mutating func beginReason(subject: PullInLinkSubject? = nil) {
        text = ""
        cursorUTF8 = 0
        context = nil
        replacement = CaptureRange(start: 0, end: 0)
        candidates = []
        selectedID = nil
        name = nil
        windowStart = 0
        self.subject = subject
        generation &+= 1
    }

    /// Typing or a caret move adopts the new input. Rows stay visible while
    /// the refetch is in flight; the reply re-selects.
    public mutating func inputChanged(text: String, cursorUTF8: Int) {
        self.text = text
        self.cursorUTF8 = cursorUTF8
        generation &+= 1
    }

    /// A background reply: apply only when it answers the live input.
    /// Selects the first row unless bob opened without a selection.
    @discardableResult
    public mutating func receive(
        text: String,
        cursorUTF8: Int,
        context: CaptureCompletionContext?,
        replacement: CaptureRange,
        candidates: [CaptureCompletionCandidate],
        opensWithoutSelection: Bool,
        generation: UInt64
    ) -> Bool {
        guard generation == self.generation else { return false }
        // The NAME stage owns the band: a late reply never replaces the rows
        // under it, so Esc returns to the list that was selected.
        guard name == nil else { return false }
        self.text = text
        self.cursorUTF8 = cursorUTF8
        self.context = context
        self.replacement = replacement
        self.candidates = candidates
        if context == nil {
            selectedID = nil
        } else if opensWithoutSelection || candidates.isEmpty {
            selectedID = nil
        } else {
            selectedID = candidates[0].id
        }
        windowStart = 0
        return true
    }

    /// Esc / Ctrl+[: close the band only (one layer, the reason stays).
    /// Returns true when consumed (the band was open).
    public mutating func close() -> Bool {
        guard context != nil else { return false }
        context = nil
        candidates = []
        selectedID = nil
        name = nil
        windowStart = 0
        generation &+= 1
        return true
    }

    public enum Step {
        case enteredTop
        case moved
        case bumpedBottom
        case bumpedTop
    }

    /// ↓ / Ctrl+N: enter the band at the top row, then move down. The
    /// bottom row clamps with an edge bump, no wrap.
    public mutating func moveNext() -> Step? {
        guard context != nil, name == nil, !candidates.isEmpty else { return nil }
        guard let selectedID else {
            self.selectedID = candidates[0].id
            revealSelection()
            return .enteredTop
        }
        guard let position = candidates.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = candidates[0].id
            revealSelection()
            return .enteredTop
        }
        if position + 1 < candidates.count {
            self.selectedID = candidates[position + 1].id
            revealSelection()
            return .moved
        }
        return .bumpedBottom
    }

    /// ↑ / Ctrl+P: move up; above the top row clears the selection but
    /// leaves the band open (Return then only closes it).
    public mutating func movePrevious() -> Step? {
        guard context != nil, name == nil, !candidates.isEmpty else { return nil }
        guard let selectedID else {
            self.selectedID = candidates[0].id
            revealSelection()
            return .enteredTop
        }
        guard let position = candidates.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = candidates[0].id
            revealSelection()
            return .enteredTop
        }
        if position > 0 {
            self.selectedID = candidates[position - 1].id
            revealSelection()
            return .moved
        }
        self.selectedID = nil
        return .bumpedTop
    }

    /// Row click inserts: select, so the controller can accept in one step.
    /// Returns false for an unknown key.
    @discardableResult
    public mutating func select(id: String) -> Bool {
        guard context != nil, name == nil, candidates.contains(where: { $0.id == id }) else {
            return false
        }
        selectedID = id
        revealSelection()
        return true
    }

    /// Query text between bob's replacement start and the request cursor,
    /// for restrained match emphasis. Empty when the range is stale.
    public func queryText() -> String {
        guard cursorUTF8 >= replacement.start else { return "" }
        guard let range = stringRange(in: text, start: replacement.start, end: cursorUTF8) else {
            return ""
        }
        let raw = String(text[range])
        // A `((` replacement starts at its opener, which is not the query.
        if isTasks, raw.hasPrefix("((") {
            return String(raw.dropFirst(2))
        }
        return raw
    }

    /// Accept the selected row against the LIVE field text and caret. The
    /// edit applies only when both still match the answered request, so a
    /// caret that raced the reply closes the band instead of splicing a
    /// stale range.
    public func acceptEdit(fieldText: String, caretUTF8: Int) -> PullInLinkAcceptEdit? {
        guard context != nil, name == nil else { return nil }
        guard let candidate = selectedCandidate else { return nil }
        guard fieldText == text, caretUTF8 == cursorUTF8 else { return nil }
        // A `((` row inserts only when bob says it is usable: ID-less and
        // guarded rows carry an empty replacement and never splice.
        if isTasks {
            guard case .insert? = selectedAction else { return nil }
        }
        return pullInLinkAcceptEdit(
            draft: fieldText,
            replacement: replacement,
            insertion: candidate.replacement,
            cursorAfter: candidate.cursorAfter
        )
    }

    /// The exact `[[…]]` link the selected row would insert, for the
    /// detail strip. Nil when the accept itself is stale.
    public func acceptedLinkPreview(fieldText: String, caretUTF8: Int) -> String? {
        guard let edit = acceptEdit(fieldText: fieldText, caretUTF8: caretUTF8) else {
            return nil
        }
        return pullInLinkToken(in: edit.text, replacementStart: replacement.start)
    }
}

/// The result of accepting one LINK row: bob's replacement applied at
/// bob's byte range, with the UTF-8 caret bob named.
public struct PullInLinkAcceptEdit: Equatable, Sendable {
    public let text: String
    public let caretUTF8: Int

    public init(text: String, caretUTF8: Int) {
        self.text = text
        self.caretUTF8 = caretUTF8
    }
}

/// Apply bob's insertion at bob's byte range. Nil when the range is not a
/// character boundary in `draft` or `cursorAfter` is unusable.
public func pullInLinkAcceptEdit(
    draft: String,
    replacement: CaptureRange,
    insertion: String,
    cursorAfter: Int?
) -> PullInLinkAcceptEdit? {
    guard let range = stringRange(in: draft, byteRange: replacement) else {
        return nil
    }
    var text = draft
    text.replaceSubrange(range, with: insertion)
    let fallbackCaret = replacement.start + insertion.utf8.count
    let caret: Int
    if let cursorAfter,
        cursorAfter >= 0,
        cursorAfter <= text.utf8.count,
        String.Index(
            text.utf8.index(text.utf8.startIndex, offsetBy: cursorAfter),
            within: text
        ) != nil
    {
        caret = cursorAfter
    } else {
        caret = fallbackCaret
    }
    return PullInLinkAcceptEdit(text: text, caretUTF8: caret)
}

/// The `[[…]]` token around a just-applied insertion, for the detail
/// strip. Scans back from `replacementStart` for the opener and forward
/// for its closer; nil when either is missing.
public func pullInLinkToken(in text: String, replacementStart: Int) -> String? {
    guard replacementStart >= 0, replacementStart <= text.utf8.count else {
        return nil
    }
    let startIndex = text.utf8.index(
        text.utf8.startIndex, offsetBy: replacementStart)
    guard let insertionPoint = String.Index(startIndex, within: text) else {
        return nil
    }
    // A `[[` completion replaces text after its opener; a `((` replacement
    // begins with the opener itself, so the scan reaches two characters
    // past the insertion point.
    let scanEnd = text.index(insertionPoint, offsetBy: 2, limitedBy: text.endIndex)
        ?? text.endIndex
    let openerRange = text.range(
        of: "[[", options: .backwards,
        range: text.startIndex..<scanEnd)
    guard let openerRange else {
        return nil
    }
    let searchFrom = text.index(
        openerRange.lowerBound, offsetBy: 2, limitedBy: text.endIndex)
        ?? text.endIndex
    let closerRange = text.range(of: "]]", range: searchFrom..<text.endIndex)
    guard let closerRange else {
        return nil
    }
    return String(text[openerRange.lowerBound..<closerRange.upperBound])
}

/// Band copy, metrics, and announcements for the Pull-In `LINK` band. Same
/// anatomy as the `USED BEFORE` band it replaces in the slot: a 0.5pt
/// hairline, a `link` symbol at `.caption2` `.tertiary`, a `LINK` header in
/// `.caption2.weight(.semibold).tracking(0.6)` `.secondary`, trailing
/// keycaps, 22pt `.callout` rows, `.caption.monospacedDigit()` `.tertiary`
/// metadata, and a detail strip naming the exact link Return inserts.
public enum PullInLinkBandPresentation {
    public static let headerHeight: Double = 16
    public static let rowHeight: Double = 22
    public static let detailHeight: Double = 20
    public static let maxRows = 5
    public static let bandTitle = "LINK"

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

    /// Header copy. A selection shows `LINK · k of n` with the insert
    /// hint; an open band without one shows the row count and keycaps;
    /// zero rows names the empty field. The tasks mode reads
    /// `LINK · tasks · k of n`.
    public static func header(
        selectedIndex: Int?, total: Int, tasks: Bool = false
    ) -> Header {
        let title = tasks ? "\(bandTitle) · \(tasksTitle)" : bandTitle
        if let selectedIndex {
            return Header(
                title: "\(title) · \(selectedIndex) of \(total)",
                trailing: "↵ inserts",
                showsKeycaps: false
            )
        }
        if total == 0 {
            return Header(
                title: "\(title) · no match",
                trailing: "",
                showsKeycaps: false
            )
        }
        return Header(
            title: "\(title) · \(total)",
            trailing: "↑↓ ↵ ⇥",
            showsKeycaps: true
        )
    }

    /// The tasks mode's header word.
    public static let tasksTitle = "tasks"

    /// The NAME stage header: `LINK · tasks › name it`, with the note the
    /// ID is written to on the right.
    public static func nameHeader(for stage: PullInLinkNameStage) -> Header {
        Header(
            title: "\(bandTitle) · \(tasksTitle) › name it",
            trailing: "in \(stage.target.notePath)",
            showsKeycaps: false
        )
    }

    /// The prompt's own task is dimmed with this reason and badge.
    public static let subjectReason = "The task this prompt is about"
    public static let subjectBadge = "this prompt"
    /// A row bob returned with neither a link nor a way to name it.
    public static let unusableReason = "This task can't be linked"
    public static let unusableBadge = "unavailable"
    /// Zero task rows: Return closes the band and inserts nothing.
    public static let emptyTasksDetail = "↵ closes this list · nothing is inserted"

    /// The detail strip for an ID-less row: what Return will write.
    public static func namesDetail(for target: PullInLinkNameTarget) -> String {
        if let first = target.suggestions.first {
            return "↵ names it ^\(first) in \(target.notePath), then links it"
        }
        return "↵ names this task in \(target.notePath), then links it"
    }

    /// The detail strip in the NAME stage: the ID and the link it will
    /// produce, or the reason the ID cannot be written.
    public static func nameDetail(for stage: PullInLinkNameStage) -> String {
        if stage.isSaving {
            return "Adding ^\(stage.authoredID)…"
        }
        if let message = stage.errorMessage ?? stage.validationMessage {
            return "⊘ \(message)"
        }
        if let link = stage.target.previewLink(blockID: stage.authoredID) {
            return "↵ adds ^\(stage.authoredID), then links \(link)"
        }
        return "↵ adds ^\(stage.authoredID), then links it"
    }

    public static func announcement(index: Int, total: Int, text: String) -> String {
        "Link \(index) of \(total): \(text)"
    }

    /// Announcement for entering the NAME stage.
    public static func nameAnnouncement(for stage: PullInLinkNameStage) -> String {
        "Name a block ID for \(stage.target.taskText): \(stage.authoredID). Return adds it and links."
    }

    /// Band height while visible (header + rows + detail strip), for the
    /// card height policy. The strip shows only with a selection.
    public static func bandHeight(rowCount: Int, hasSelection: Bool) -> Double {
        let rows = Double(min(max(rowCount, 0), maxRows)) * rowHeight
        return headerHeight + rows + (hasSelection ? detailHeight : 0)
    }

    /// The NAME stage keeps the list's footprint: a header, the pinned task
    /// row, the ID line, a suggestions row, and the detail strip.
    public static let nameFieldHeight: Double = 26
    public static let nameStageHeight: Double =
        headerHeight + rowHeight + nameFieldHeight + rowHeight + detailHeight

    /// Band height for `state`, covering the list and the NAME stage. A tasks
    /// band shows a detail strip for zero rows too, so Return's outcome is
    /// always readable.
    public static func bandHeight(for state: PullInLinkState) -> Double {
        if state.isNaming {
            return nameStageHeight
        }
        let showsDetail =
            state.selectedCandidate != nil || (state.isTasks && state.candidates.isEmpty)
        return bandHeight(
            rowCount: state.visibleCandidates.count, hasSelection: showsDetail)
    }
}
