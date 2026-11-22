import Foundation

// The tasks mode of the Pull-In cancel reason `LINK` band: `((` task links in
// plain prose, answered by `bob capture-complete --links-only --task-links`.
// Bob owns discovery, ranking, guards, and every byte range; this file only
// decodes what bob returned into the band's row actions and drives the NAME
// stage that names an ID-less task through `bob capture-task-id`.

/// The task the Pull-In reason row itself is about, identified by the exact
/// note path and block ID of the offer being cancelled. Rows bob returned for
/// that same task are dimmed with `PullInLinkBandPresentation.subjectReason`:
/// naming it would rewrite the line under the Pull-In's own pending write, and
/// a self-mention carries no information. Matching never guesses: a missing
/// ID means no subject.
public struct PullInLinkSubject: Equatable, Sendable {
    public let notePath: String
    public let blockID: String

    public init?(notePath: String, blockID: String) {
        guard !notePath.isEmpty, !blockID.isEmpty else { return nil }
        self.notePath = notePath
        self.blockID = blockID
    }

    /// Whether bob's row is this task: same exact `note_path` and `block_id`.
    public func matches(_ candidate: CaptureCompletionCandidate) -> Bool {
        guard let path = candidate.notePath, let blockID = candidate.blockID else {
            return false
        }
        return path == notePath && blockID == self.blockID
    }
}

/// What the NAME stage needs to name one ID-less task, copied from bob's
/// row so the stage never reads the candidate list again.
public struct PullInLinkNameTarget: Equatable, Sendable {
    /// Exact vault-relative path including extension: the identity
    /// `capture-task-id --note-path` takes, never a lowercased route.
    public let notePath: String
    /// Bob's stale-safe `line:digest` task ref.
    public let taskRef: String
    /// Bob's block ID suggestions; the first prefills the field.
    public let suggestions: [String]
    /// Done and Cancelled rows pass `--allow-closed`.
    public let allowClosed: Bool
    /// Display-only task text.
    public let taskText: String
    /// Display-only text bob would put before `#^` (stem or full path).
    public let linkTarget: String?

    public init(
        notePath: String,
        taskRef: String,
        suggestions: [String],
        allowClosed: Bool,
        taskText: String,
        linkTarget: String?
    ) {
        self.notePath = notePath
        self.taskRef = taskRef
        self.suggestions = suggestions
        self.allowClosed = allowClosed
        self.taskText = taskText
        self.linkTarget = linkTarget
    }

    /// The link the detail strip previews for `id`. Display only: the
    /// inserted text is always bob's `wikilink_replacement`.
    public func previewLink(blockID id: String) -> String? {
        guard let linkTarget, !linkTarget.isEmpty else { return nil }
        return "[[\(linkTarget)#^\(id)]]"
    }
}

/// What Return or Tab does on the selected row of a tasks-mode band.
public enum PullInLinkRowAction: Equatable, Sendable {
    /// An identified, usable row: splice bob's `[[target#^id]]`.
    case insert(link: String)
    /// An ID-less row: Return opens the NAME stage.
    case name(PullInLinkNameTarget)
    /// A guarded row, or the prompt's own task: nothing is inserted and
    /// the band stays put. `badge` is the short row capsule.
    case disabled(reason: String, badge: String)
}

/// The NAME stage of the tasks band: a block ID field for an ID-less task,
/// drawn inside the band while the reason field's text stays untouched. The
/// reason draft is captured at entry and is never mutated before the write
/// succeeds; a changed draft inserts nothing.
public struct PullInLinkNameStage: Equatable, Sendable {
    public let target: PullInLinkNameTarget
    /// The reason text, the UTF-8 caret, and bob's `((` range at entry.
    public let fieldText: String
    public let caretUTF8: Int
    public let replacement: CaptureRange
    public var authoredID: String
    public var errorMessage: String?
    public var isSaving = false

    public init(
        target: PullInLinkNameTarget,
        fieldText: String,
        caretUTF8: Int,
        replacement: CaptureRange
    ) {
        self.target = target
        self.fieldText = fieldText
        self.caretUTF8 = caretUTF8
        self.replacement = replacement
        self.authoredID = target.suggestions.first ?? ""
    }

    /// Short validation reason for `id`, or nil when it is usable.
    public static func validationMessage(for id: String) -> String? {
        if id.isEmpty {
            return "Enter a block ID."
        }
        let valid = id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45
        }
        return valid ? nil : "Use only letters, numbers, and hyphens."
    }

    /// The reason the current ID cannot be written yet, or nil.
    public var validationMessage: String? {
        Self.validationMessage(for: authoredID)
    }

    /// Typing in the ID field. Clears a previous write error.
    public mutating func edit(_ id: String) {
        guard !isSaving else { return }
        authoredID = id
        errorMessage = nil
    }

    /// Tab / ↓ and Shift+Tab / ↑ cycle bob's suggestions into the field.
    @discardableResult
    public mutating func cycle(forward: Bool) -> Bool {
        guard !isSaving, !target.suggestions.isEmpty else { return false }
        let count = target.suggestions.count
        let current = target.suggestions.firstIndex(of: authoredID) ?? (forward ? -1 : 0)
        let next = forward ? (current + 1) % count : (current - 1 + count) % count
        authoredID = target.suggestions[next]
        errorMessage = nil
        return true
    }

    /// Apply bob's `wikilink_replacement` over bob's `((` range, but only
    /// while the live field is exactly what the stage opened on. A changed
    /// draft or a moved caret yields nil so nothing is inserted over text
    /// bob never saw.
    public func splice(
        link: String, liveText: String, liveCaretUTF8: Int
    ) -> PullInLinkAcceptEdit? {
        guard !link.isEmpty, liveText == fieldText, liveCaretUTF8 == caretUTF8 else {
            return nil
        }
        return pullInLinkAcceptEdit(
            draft: fieldText, replacement: replacement, insertion: link, cursorAfter: nil)
    }
}

extension PullInLinkState {
    /// Whether bob reported a `((` task field.
    public var isTasks: Bool { context == .wikilinkTask }

    /// Whether the NAME stage is open.
    public var isNaming: Bool { name != nil }

    /// What Return does on `candidate`. The prompt's own task and every
    /// guarded row are disabled; an ID-less row names; anything else
    /// inserts bob's link.
    public func rowAction(for candidate: CaptureCompletionCandidate) -> PullInLinkRowAction {
        if let subject, subject.matches(candidate) {
            return .disabled(
                reason: PullInLinkBandPresentation.subjectReason,
                badge: PullInLinkBandPresentation.subjectBadge)
        }
        if let reason = candidate.disabledReason, !reason.isEmpty {
            return .disabled(reason: reason, badge: reason)
        }
        if candidate.requiresBlockID {
            guard let path = candidate.notePath ?? candidate.route,
                let ref = candidate.taskRef, !path.isEmpty, !ref.isEmpty
            else {
                return .disabled(
                    reason: PullInLinkBandPresentation.unusableReason,
                    badge: PullInLinkBandPresentation.unusableBadge)
            }
            let closed = candidate.statusType == "DONE" || candidate.statusType == "CANCELLED"
            return .name(
                PullInLinkNameTarget(
                    notePath: path,
                    taskRef: ref,
                    suggestions: candidate.blockIDSuggestions,
                    allowClosed: closed,
                    taskText: TaskDisplayText(parsing: candidate.text ?? "").text,
                    linkTarget: candidate.linkTarget ?? candidate.locator ?? candidate.route))
        }
        if candidate.replacement.isEmpty {
            return .disabled(
                reason: PullInLinkBandPresentation.unusableReason,
                badge: PullInLinkBandPresentation.unusableBadge)
        }
        return .insert(link: candidate.replacement)
    }

    /// What Return does on the selected row. Nil outside tasks mode or
    /// without a selection.
    public var selectedAction: PullInLinkRowAction? {
        guard isTasks, let candidate = selectedCandidate else { return nil }
        return rowAction(for: candidate)
    }

    /// Whether Tab may act on the selection: a row that inserts or names.
    public var selectionCanAccept: Bool {
        guard let candidate = selectedCandidate else { return false }
        guard isTasks else { return true }
        switch rowAction(for: candidate) {
        case .insert, .name:
            return true
        case .disabled:
            return false
        }
    }

    /// Open the NAME stage on the selected ID-less row against the live
    /// field. The live text and caret must still match the answered
    /// request, so a caret that raced the reply never names a stale range.
    @discardableResult
    public mutating func beginName(fieldText: String, caretUTF8: Int) -> Bool {
        guard name == nil, case .name(let target)? = selectedAction,
            fieldText == text, caretUTF8 == cursorUTF8
        else {
            return false
        }
        name = PullInLinkNameStage(
            target: target, fieldText: fieldText, caretUTF8: caretUTF8,
            replacement: replacement)
        return true
    }

    /// Esc / Ctrl+[ in the NAME stage: back to the list with the filter and
    /// selection intact. Returns true when the stage was open.
    @discardableResult
    public mutating func cancelName() -> Bool {
        guard name != nil else { return false }
        name = nil
        return true
    }

    /// The detail strip left side for the selected row of a tasks band,
    /// or nil when nothing is selected or the stage is not tasks mode.
    public var tasksDetailLine: String? {
        if let name {
            return PullInLinkBandPresentation.nameDetail(for: name)
        }
        guard isTasks else { return nil }
        guard let candidate = selectedCandidate else {
            return candidates.isEmpty ? PullInLinkBandPresentation.emptyTasksDetail : nil
        }
        switch rowAction(for: candidate) {
        case .insert(let link):
            return "↵ \(link)"
        case .name(let target):
            return PullInLinkBandPresentation.namesDetail(for: target)
        case .disabled(let reason, _):
            return "⊘ \(reason)"
        }
    }
}

/// The layout facts of one task row in the tasks band: status glyph, display
/// text, the locator drawn as the link it will insert, and capsules. Pure so
/// tests pin it without SwiftUI.
public struct PullInTaskRowContent: Equatable, Sendable {
    public let status: CapturePickerTaskStatus
    public let text: String
    public let segments: [TaskDisplaySegment]
    /// Link target in the muted colour; nil on rows without one.
    public let locatorTarget: String?
    /// The block ID, or bob's first suggestion on an ID-less row.
    public let locatorID: String?
    /// True when `locatorID` is a suggestion that will be written, drawn
    /// italic and faint behind a `⊕`.
    public let locatorIsSuggestion: Bool
    /// Capsule naming the group, for the first row of each run on an empty
    /// query.
    public var groupCapsule: String?
    /// Character ranges of `text` the query terms matched, for restrained
    /// emphasis. Bob ranks; this only marks what the user typed.
    public var matchRanges: [Range<Int>] = []
    /// `Hidden`, `Done`, `Cancelled`, or a guard's short badge.
    public let badge: String?
    /// Done, cancelled, hidden, and disabled rows dim.
    public let isDimmed: Bool
    public let accessibilityLabel: String

    public init(
        candidate: CaptureCompletionCandidate,
        action: PullInLinkRowAction
    ) {
        let display = TaskDisplayText(parsing: candidate.text ?? candidate.replacement)
        let status = CapturePickerTaskStatus(
            symbol: candidate.statusSymbol, name: candidate.statusName)
        self.status = status
        self.text = display.text
        self.segments = display.segments
        self.locatorTarget = candidate.linkTarget ?? candidate.locator ?? candidate.route
        if let id = candidate.blockID, !id.isEmpty {
            self.locatorID = id
            self.locatorIsSuggestion = false
        } else if let suggestion = candidate.blockIDSuggestions.first {
            self.locatorID = suggestion
            self.locatorIsSuggestion = true
        } else {
            self.locatorID = nil
            self.locatorIsSuggestion = false
        }
        self.groupCapsule = nil
        var badge: String?
        var disabled = false
        if case .disabled(_, let short) = action {
            badge = short
            disabled = true
        } else if candidate.hidden {
            badge = "Hidden"
        } else {
            switch status {
            case .done:
                badge = "Done"
            case .canceled:
                badge = "Cancelled"
            default:
                break
            }
        }
        self.badge = badge
        switch status {
        case .done, .canceled:
            self.isDimmed = true
        default:
            self.isDimmed = disabled || candidate.hidden
        }
        var parts = [candidate.statusName.flatMap { $0.isEmpty ? nil : $0 } ?? status.displayName]
        parts.append(display.text)
        if let target = locatorTarget, let id = locatorID {
            parts.append(
                locatorIsSuggestion
                    ? "Note \(target), suggested block \(id)" : "\(target)#^\(id)")
        }
        if case .disabled(let reason, _) = action {
            parts.append(reason)
        }
        self.accessibilityLabel = parts.joined(separator: ", ")
    }

    /// Character ranges of every whitespace-separated query term in `text`,
    /// case-insensitively and merged. Empty for an empty query.
    public static func matchRanges(in text: String, query: String) -> [Range<Int>] {
        let chars = Array(text).map { String($0).lowercased() }
        var positions: [Int] = []
        for term in query.split(whereSeparator: { $0.isWhitespace }) {
            let needle = Array(term).map { String($0).lowercased() }
            guard !needle.isEmpty, needle.count <= chars.count else { continue }
            var start = 0
            while start + needle.count <= chars.count {
                if Array(chars[start..<start + needle.count]) == needle {
                    positions += Array(start..<start + needle.count)
                    start += needle.count
                } else {
                    start += 1
                }
            }
        }
        return WikilinkMatchHighlights.coalesced(positions)
    }

    /// The capsule text for bob's `group` wire value.
    public static func capsule(forGroup wire: String?) -> String {
        switch WikilinkTaskGroup(wireValue: wire) {
        case .thisNote:
            return "this note"
        case .inProgress:
            return "in progress"
        case .next:
            return "next"
        case .open:
            return "open"
        case .completed:
            return "history"
        }
    }

    /// Row contents for the visible window, in order. On an empty query
    /// the first row of each group run wears its group capsule; a query
    /// is one ranked flat list with no capsules.
    public static func rows(
        for visible: [CaptureCompletionCandidate],
        state: PullInLinkState,
        query: String
    ) -> [PullInTaskRowContent] {
        var previousGroup: String?
        var result: [PullInTaskRowContent] = []
        for candidate in visible {
            var row = PullInTaskRowContent(
                candidate: candidate, action: state.rowAction(for: candidate))
            let key = Self.capsule(forGroup: candidate.group)
            if query.isEmpty, previousGroup != key {
                row.groupCapsule = key
            }
            row.matchRanges = Self.matchRanges(in: row.text, query: query)
            previousGroup = key
            result.append(row)
        }
        return result
    }
}
