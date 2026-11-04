import CaptureCore
import Foundation

/// Maps Bob's pull-in glyph keys to SF Symbols. Unknown keys are a
/// neutral circle; never `lock.open`.
enum CapturePullInGlyph {
    static func systemImageName(for key: String) -> String {
        switch key {
        case "hand_off":
            return "arrow.turn.down.right"
        case "project":
            return "folder"
        case "project_created":
            return "folder.badge.plus"
        case "project_finished":
            return "checkmark.circle"
        case "keep_moving":
            return "forward.end.fill"
        case "note_pull":
            return "tray.and.arrow.down.fill"
        case "relation":
            return "link"
        default:
            return "circle"
        }
    }
}

private func pullInNonempty(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func pullInQuotedTask(_ text: String) -> String {
    "“\(SuccessorRows.truncate(text))”"
}

struct CapturePullInChoiceRow: Equatable, Identifiable {
    let offerRow: TaskCompleteUnblocked?
    let blockedRow: TaskCompleteStillBlocked?
    let group: String
    let project: String?

    var id: String {
        if let key = offerRow?.offer?.key, !key.isEmpty {
            return "offer|\(key)"
        }
        if let blockedRow {
            return "blocked|\(blockedRow.notePath)|\(blockedRow.blockID)|\(blockedRow.line)"
        }
        let row = offerRow
        return "unkeyed|\(row?.notePath ?? "")|\(row?.blockID ?? "")|\(row?.line ?? 0)"
    }

    var offerKey: String? {
        guard let key = offerRow?.offer?.key, !key.isEmpty else {
            return nil
        }
        return key
    }

    var isSelectable: Bool {
        offerKey != nil
    }

    var offerNumber: Int? {
        offerRow?.offer?.n
    }

    var text: String {
        offerRow?.text ?? blockedRow?.text ?? ""
    }

    var notePath: String {
        offerRow?.notePath ?? blockedRow?.notePath ?? ""
    }

    var blockID: String {
        offerRow?.blockID ?? blockedRow?.blockID ?? ""
    }

    var statusText: String {
        guard let offerRow else {
            return blockedRow.map { "[\($0.statusSymbol)] \($0.statusName)" } ?? ""
        }
        if isRelation {
            return offerRow.statusName
        }
        return "[\(offerRow.previousStatusSymbol)] → [\(offerRow.statusSymbol)]"
    }

    var destinationText: String? {
        guard let destination = offerRow?.offer?.destination else {
            return nil
        }
        let name = destination.entryName.isEmpty ? destination.dayFile : destination.entryName
        guard !name.isEmpty else {
            return nil
        }
        let role = destination.entryRole.replacingOccurrences(of: "_", with: " ")
        var suffix = role.isEmpty ? "" : " · \(role)"
        if destination.fallback {
            suffix += " · fallback"
        }
        return "→ \(name)\(suffix)"
    }

    var needsBlockID: Bool {
        offerRow?.offer?.blockIDNeeded == true
    }

    var isNewProjectOffer: Bool {
        offerRow?.trigger == "project_created"
    }

    var isKeepMoving: Bool {
        offerRow?.offer?.group == "keep_moving"
    }

    var isNotePull: Bool {
        offerRow?.offer?.group == "note_pull"
    }

    var isRelation: Bool {
        group == "relation"
    }

    var after: String? {
        pullInNonempty(offerRow?.offer?.after)
    }

    var label: String? {
        pullInNonempty(offerRow?.relation?.label)
    }

    var laneText: String? {
        if isRelation, let name = offerRow?.statusName, !name.isEmpty {
            return name
        }
        guard let offerRow else {
            return nil
        }
        if isNotePull {
            let symbol = offerRow.previousStatusSymbol.isEmpty
                ? offerRow.statusSymbol
                : offerRow.previousStatusSymbol
            switch symbol {
            case "/": return "Pending"
            case "*": return "Next"
            case " ": return "Ready"
            case "?": return "Blocked"
            default: return pullInNonempty(offerRow.previousStatusName) ?? offerRow.statusName
            }
        }
        guard isKeepMoving else { return nil }
        if !offerRow.statusName.isEmpty {
            return offerRow.statusName
        }
        switch offerRow.statusSymbol {
        case "/": return "Pending"
        case "*": return "Next"
        case " ": return "Ready"
        case "?": return "Blocked"
        default: return nil
        }
    }

    /// The parent note a moved offer row came from (`cash.md`), or nil for
    /// ordinary offers. Moved rows keep this label in every Pull-In surface.
    var movedFrom: String? {
        pullInNonempty(offerRow?.offer?.movedFrom)
    }

    /// Presentation-only meta fragments for offer rows. Unlike `detailText`,
    /// this never includes the recovered "Ready · not pulled in" caption.
    var metaDetails: [String] {
        guard let offerRow else {
            return []
        }
        var details: [String] = []
        if let movedFrom {
            details.append("moved from \(movedFrom)")
        }
        if offerRow.hideRemoved {
            details.append("removed #hide")
        }
        if let trigger = offerRow.trigger, !trigger.isEmpty {
            if trigger == "project_empty" {
                if group != "project_finished" {
                    details.append("project finished")
                }
            } else if trigger != "project_created"
                && trigger != "last_planned"
                && trigger != "note_pull"
                && trigger != "relation"
            {
                details.append("trigger: \(trigger)")
            }
        }
        if let suffix = relationAfterSuffix {
            details.append(suffix)
        }
        if let reason = relationSecondReason {
            details.append(reason)
        }
        return details
    }

    /// `after “T1” and “T2”` / `after “T1” and k more` when several
    /// relation targets triggered the same row.
    var relationAfterSuffix: String? {
        guard let targets = offerRow?.relation?.after else {
            return nil
        }
        let names = targets.map(\.text).compactMap(pullInNonempty)
        guard names.count > 1, let first = names.first else {
            return nil
        }
        if names.count == 2 {
            return "after \(pullInQuotedTask(first)) and \(pullInQuotedTask(names[1]))"
        }
        return "after \(pullInQuotedTask(first)) and \(names.count - 1) more"
    }

    /// Relation as a second reason on another group's row: `label “T”`.
    var relationSecondReason: String? {
        guard !isRelation, let relation = offerRow?.relation else {
            return nil
        }
        guard let label = pullInNonempty(relation.label),
            let target = relation.after.first.flatMap({ pullInNonempty($0.text) })
        else {
            return nil
        }
        return "\(label) \(pullInQuotedTask(target))"
    }

    var detailText: String? {
        if isRelation {
            // Lane-only relation status plus the shared meta path, which
            // already suppresses the raw `trigger: relation` text.
            var details = metaDetails
            if let lane = laneText {
                details.insert(lane, at: 0)
            }
            return details.isEmpty ? nil : details.joined(separator: " · ")
        }
        if let offerRow {
            if offerRow.trigger == "last_planned" {
                var parts: [String] = []
                if let lane = laneText {
                    parts.append(lane)
                }
                parts.append(contentsOf: metaDetails)
                return parts.isEmpty ? nil : parts.joined(separator: " · ")
            }
            let presentation = SuccessorRows.unblockedRows(
                from: [offerRow],
                transition: { _ in "" },
                locator: { _ in "" }
            ).first
            // Reuse the shared meta path so passive previews and
            // accessibility both see the second reason without duplicate
            // trigger/hide fragments.
            var details = [presentation?.captionText].compactMap { $0 }
            details.append(contentsOf: metaDetails)
            return details.isEmpty ? nil : details.joined(separator: " · ")
        }
        guard let blockedRow else {
            return nil
        }
        return SuccessorRows.stillBlockedRows(
            from: [blockedRow],
            locator: { _ in "" }
        ).first?.captionText
    }

    var accessibilityLabel: String {
        var parts = [text]
        if let offerNumber {
            parts.insert("Offer \(offerNumber)", at: 0)
        }
        if !notePath.isEmpty {
            parts.append(notePath + (blockID.isEmpty ? "" : " ^\(blockID)"))
        }
        if let destinationText {
            parts.append(destinationText)
        }
        if needsBlockID {
            parts.append("needs block ID")
        }
        if let detailText {
            parts.append(detailText)
        } else {
            parts.append(contentsOf: metaDetails)
        }
        if !isSelectable {
            parts.append("not selectable")
        }
        return parts.joined(separator: ", ")
    }
}

struct CapturePullInChoiceSection: Equatable, Identifiable {
    let group: String
    let project: String?
    let note: String?
    let after: CapturePullInAfter?
    let label: String?
    let event: String?
    let copy: CapturePullInGroupCopy?
    let folded: CapturePullInFolded?
    let rows: [CapturePullInChoiceRow]

    var id: String {
        Self.key(group: group, project: project, note: note, after: after?.key, label: label)
    }

    var isNewProject: Bool {
        let offers = rows.compactMap(\.offerRow)
        return group == "project" && !offers.isEmpty
            && offers.allSatisfy { $0.trigger == "project_created" }
    }

    var isKeepMoving: Bool {
        group == "keep_moving"
    }

    var isNotePull: Bool {
        group == "note_pull"
    }

    var isRelation: Bool {
        group == "relation"
    }

    /// Bob's `why` when a copy object is present (even if `why` is absent —
    /// that absence does not authorize a legacy string). Otherwise the
    /// keep-moving and relation no-copy fallbacks.
    var caption: String? {
        if copy != nil {
            return pullInNonempty(copy?.why)
        }
        if isRelation {
            return relationWhyFallback
        }
        guard isKeepMoving, let first = keepMovingCauses.first else {
            return nil
        }
        let projectName = project.map(Self.projectLabel) ?? "project"
        let task = SuccessorRows.truncate(first.text)
        if keepMovingCauses.count == 1 {
            return "✓ \(task) was the last \(projectName) task planned today"
        }
        return
            "✓ \(task) and \(keepMovingCauses.count - 1) more were the last \(projectName) tasks planned today"
    }

    var contextCaption: String? {
        if copy != nil {
            return pullInNonempty(copy?.why)
        }
        if isRelation {
            return relationWhyFallback
        }
        guard isKeepMoving, let first = keepMovingCauses.first else {
            return nil
        }
        let projectName = project.map(Self.projectLabel) ?? "project"
        let task = SuccessorRows.truncate(first.text)
        if keepMovingCauses.count == 1 {
            return "\(task) was the last \(projectName) task planned today"
        }
        return
            "\(task) and \(keepMovingCauses.count - 1) more were the last \(projectName) tasks planned today"
    }

    var contrastTag: String? {
        if copy != nil {
            return pullInNonempty(copy?.tag)
        }
        if isRelation {
            return "your links · not dependents"
        }
        if isNotePull {
            let name = note.map(Self.projectLabel) ?? "note"
            return "ready in \(name)"
        }
        guard isKeepMoving else {
            return nil
        }
        let projectName = project.map(Self.projectLabel) ?? "project"
        return "ready in \(projectName) · not dependents"
    }

    /// Bob's `fold` string when a copy object is present. Otherwise the
    /// counter-based no-copy fallback, including relation `already_started`
    /// and `waits_for`.
    var foldText: String? {
        if copy != nil {
            return pullInNonempty(copy?.fold)
        }
        guard let folded else {
            return nil
        }
        var parts: [String] = []
        if isKeepMoving {
            if folded.blocked > 0 {
                parts.append("\(folded.blocked) blocked")
            }
            if folded.scheduled > 0 {
                parts.append("\(folded.scheduled) scheduled later")
            }
            if folded.hidden > 0 {
                parts.append("\(folded.hidden) hidden")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        if isRelation {
            if folded.alreadyStarted > 0 {
                parts.append("\(folded.alreadyStarted) already started")
            }
            if folded.waitsFor > 0 {
                parts.append("\(folded.waitsFor) waiting")
            }
            if folded.blocked > 0 {
                parts.append("\(folded.blocked) blocked")
            }
            if folded.hidden > 0 {
                parts.append("\(folded.hidden) hidden")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        if isNotePull {
            return CaptureNotePullPresentation.foldedText(folded)
        }
        if folded.hidden > 0 {
            parts.append("\(folded.hidden) hidden")
        }
        if folded.alreadyPlanned > 0 {
            parts.append("\(folded.alreadyPlanned) already planned")
        }
        if folded.subProjects > 0 {
            parts.append("\(folded.subProjects) sub-projects stay blocked until the next reconcile")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var glyph: String {
        if let key = pullInNonempty(copy?.glyph) {
            return CapturePullInGlyph.systemImageName(for: key)
        }
        if isNewProject {
            return CapturePullInGlyph.systemImageName(for: "project_created")
        }
        if isRelation {
            return CapturePullInGlyph.systemImageName(for: "relation")
        }
        return CapturePullInGlyph.systemImageName(for: group)
    }

    private var relationWhyFallback: String? {
        let rowTarget = rows.first?.offerRow?.relation?.after.first?.text
        guard let text = pullInNonempty(after?.text) ?? pullInNonempty(rowTarget) else {
            return nil
        }
        let quoted = pullInQuotedTask(text)
        if event == "done" {
            return "\(quoted) is done"
        }
        return "\(quoted) is parked · Pending, off today's plan"
    }

    private var keepMovingCauses: [TaskCompleteUnblockedCause] {
        var seen = Set<String>()
        return
            rows
            .compactMap(\.offerRow)
            .flatMap(\.unblockedBy)
            .filter { cause in
                let key = "\(cause.notePath)\u{1F}\(cause.blockID)"
                return seen.insert(key).inserted
            }
    }

    var title: String {
        if let copyTitle = pullInNonempty(copy?.title) {
            return copyTitle
        }
        switch group {
        case "hand_off":
            return "Hand-offs"
        case "project":
            let label = project.map(Self.projectLabel) ?? ""
            return label.isEmpty ? "Project" : "Project \(label)"
        case "project_finished":
            return "Project finished"
        case "keep_moving":
            let label = project.map(Self.projectLabel) ?? "project"
            return "Keep \(label) moving"
        case "relation":
            if let text = pullInNonempty(after?.text) {
                let heading = pullInNonempty(label).map(Self.capitalizedLabel) ?? "Starts after"
                return "\(heading) \(pullInQuotedTask(text))"
            }
            return "Starts after"
        case "note_pull":
            let name = note.map(Self.projectLabel) ?? "note"
            return "Pull from ‹\(name)›"
        default:
            return group.isEmpty ? "Successor offers" : group
        }
    }

    static func projectLabel(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    static func projectFileName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    static func key(
        group: String,
        project: String?,
        note: String? = nil,
        after: String? = nil,
        label: String? = nil
    ) -> String {
        guard let note = pullInNonempty(note) else {
            return "\(group)\u{1F}\(project ?? "")\u{1F}\(after ?? "")\u{1F}\(label ?? "")"
        }
        return "\(group)\u{1F}\(project ?? "")\u{1F}\(note)\u{1F}\(after ?? "")\u{1F}\(label ?? "")"
    }

    static func capitalizedLabel(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return String(first).uppercased() + text.dropFirst()
    }
}

/// Transient in-panel choice state. This stores only Bob-returned identities
/// and metadata, plus local focus/filter state. It has no vault or eligibility
/// logic.
struct CapturePullInChoiceState: Equatable {
    let draftSnapshot: String
    let processClientIdentity: String
    var openAfterCapture: Bool
    let priorityRollSeed: String
    let generation: UInt64
    let requestID: UUID?
    let pullIn: CapturePullIn
    let planBudget: CapturePlanBudget?
    var rows: [CapturePullInChoiceRow]
    var highlightedKey: String?
    var markedKeys: Set<String> = []
    var filterText = ""
    var collapsedGroups: Set<String> = []
    var errorMessage: String?

    var selectableKeys: [String] {
        rows.compactMap(\.offerKey).sorted { lhs, rhs in
            let left = rows.first(where: { $0.offerKey == lhs })?.offerNumber ?? Int.max
            let right = rows.first(where: { $0.offerKey == rhs })?.offerNumber ?? Int.max
            if left == right {
                return lhs < rhs
            }
            return left < right
        }
    }

    var effectiveSelectionKeys: [String] {
        let validMarked = markedKeys.intersection(Set(selectableKeys))
        if !validMarked.isEmpty {
            return selectableKeys.filter(validMarked.contains)
        }
        guard let highlightedKey,
            visibleSelectableKeys.contains(highlightedKey)
        else {
            return []
        }
        return [highlightedKey]
    }

    var visibleSelectableKeys: [String] {
        sections.flatMap { section in
            visibleRows(in: section).compactMap(\.offerKey)
        }
    }

    var effectivePickCount: Int {
        effectiveSelectionKeys.count
    }

    var projectedLinkCount: Int? {
        guard let planBudget else {
            return nil
        }
        return planBudget.links.count + effectivePickCount
    }

    var projectedLinksOverCap: Bool {
        guard let planBudget, let projectedLinkCount else {
            return false
        }
        return projectedLinkCount > planBudget.links.cap
    }

    var projectedTodayBadge: TodayBadgePresentation? {
        guard let planBudget, let projectedLinkCount else {
            return nil
        }
        return TodayBadgePresentation(
            count: projectedLinkCount,
            cap: planBudget.links.cap
        )
    }

    /// Distinct `unblockedBy` causes across offer rows, in first-seen order.
    var causes: [TaskCompleteUnblockedCause] {
        var seen = Set<String>()
        var ordered: [TaskCompleteUnblockedCause] = []
        for row in rows where !row.isKeepMoving && !row.isRelation {
            guard let offerRow = row.offerRow else {
                continue
            }
            for cause in offerRow.unblockedBy {
                let key = "\(cause.notePath)\u{1F}\(cause.blockID)"
                guard seen.insert(key).inserted else {
                    continue
                }
                ordered.append(cause)
            }
        }
        return ordered
    }

    var isNewProjectPrompt: Bool {
        let offers = rows.compactMap(\.offerRow)
        return !offers.isEmpty && offers.allSatisfy { $0.trigger == "project_created" }
    }

    var isOnlyKeepMoving: Bool {
        let offers = rows.compactMap(\.offerRow)
        return !offers.isEmpty && offers.allSatisfy { $0.offer?.group == "keep_moving" }
    }

    var isOnlyNotePull: Bool {
        let offers = rows.compactMap(\.offerRow)
        return !offers.isEmpty && offers.allSatisfy { $0.offer?.group == "note_pull" }
    }

    var isOnlyRelation: Bool {
        let offers = rows.compactMap(\.offerRow)
        return !offers.isEmpty && offers.allSatisfy { $0.offer?.group == "relation" }
    }

    var promptStatusText: String {
        if isOnlyNotePull {
            let note = pullIn.groups.first(where: { $0.group == "note_pull" })?.note
                ?? rows.first?.notePath
                ?? ""
            let name = note.isEmpty ? "note" : CapturePullInChoiceSection.projectLabel(note)
            return "Choose tasks to pull in from ‹\(name)›"
        }
        if isNewProjectPrompt {
            return "Choose tasks to pull in"
        }
        return isOnlyKeepMoving ? "Choose tasks to keep moving" : "Choose successor offers"
    }

    /// Top-level Bob copy when present. Empty objects do not count.
    var authoredCopy: CapturePullInCopy? {
        guard let copy = pullIn.copy else {
            return nil
        }
        if pullInNonempty(copy.title) == nil,
            pullInNonempty(copy.capsule) == nil,
            pullInNonempty(copy.glyph) == nil
        {
            return nil
        }
        return copy
    }

    /// True when Bob supplied copy on the card or any group, so sections
    /// render Bob's order and copy. Copy-less payloads keep the legacy order.
    private var carriesBobCopy: Bool {
        authoredCopy != nil || pullIn.groups.contains(where: { $0.copy != nil })
    }

    /// "Unblocked by X" / "Unblocked by X and N more" / nil.
    /// Relation-only cards never derive an unblocking story. When Bob
    /// supplies group copy, sections already render it: the card line
    /// respects that copy and never invents a legacy caption. An absent
    /// `why` in a supplied copy object means no caption. Legacy strings
    /// survive only for absent-copy payloads.
    var contextText: String? {
        // When Bob supplies copy (any group copy or top-level copy),
        // sections already render it: never invent a legacy Unblocked/New
        // caption. An absent `why` means no caption. Absent-copy payloads
        // (older Bob without copy objects) keep the legacy strings.
        if carriesBobCopy {
            if isOnlyKeepMoving {
                guard let section = sections.first(where: \.isKeepMoving) else {
                    return nil
                }
                return pullInNonempty(section.copy?.why)
            }
            return nil
        }
        if isOnlyRelation {
            return nil
        }
        if isOnlyKeepMoving {
            guard let section = sections.first(where: \.isKeepMoving),
                let why = section.contextCaption
            else {
                return nil
            }
            if section.copy != nil {
                return why
            }
            return "\(why) · ready tasks, not dependents"
        }
        if isNewProjectPrompt {
            if let cause = rows.first(where: \.isNewProjectOffer)?.offerRow?.unblockedBy.first,
                !cause.text.isEmpty
            {
                return "New project · \(SuccessorRows.truncate(cause.text))"
            }
            return "New project"
        }
        let all = causes
        guard let first = all.first, !first.text.isEmpty else {
            return nil
        }
        let head = SuccessorRows.truncate(first.text)
        guard all.count > 1 else {
            return "Unblocked by \(head)"
        }
        return "Unblocked by \(head) and \(all.count - 1) more"
    }

    /// True when rows should show their own "from ‹cause›" suffix.
    var showsRowCauses: Bool {
        !isNewProjectPrompt && causes.count > 1
    }

    /// "3 offers" / "1 offer" / "1 of 3" while filtering.
    var countText: String {
        let total = selectableKeys.count
        if !filterText.isEmpty {
            return "\(visibleSelectableKeys.count) of \(total)"
        }
        return total == 1 ? "1 offer" : "\(total) offers"
    }

    func isEffectivelySelected(_ key: String) -> Bool {
        effectiveSelectionKeys.contains(key)
    }

    /// Valid marks inside one section (stale keys never count).
    func markedCount(in section: CapturePullInChoiceSection) -> Int {
        let valid = markedKeys.intersection(Set(selectableKeys))
        guard !valid.isEmpty else {
            return 0
        }
        return section.rows.compactMap(\.offerKey).filter(valid.contains).count
    }

    /// "Pull In N" / "Pull In" when nothing would be picked.
    var pullInActionTitle: String {
        effectivePickCount == 0 ? "Pull In" : "Pull In \(effectivePickCount)"
    }

    /// "+N" when the budget is present and something would be picked.
    var projectedLinksDeltaText: String? {
        guard planBudget != nil, effectivePickCount > 0 else {
            return nil
        }
        return "+\(effectivePickCount)"
    }

    /// Character offsets of the first case-insensitive filter match in
    /// `text`, or nil when the filter is empty or absent.
    func filterMatchRange(in text: String) -> Range<Int>? {
        guard !filterText.isEmpty else {
            return nil
        }
        guard let range = text.range(of: filterText, options: [.caseInsensitive]) else {
            return nil
        }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        return lower..<upper
    }

    var sections: [CapturePullInChoiceSection] {
        let rowsByIdentity = Dictionary(grouping: rows, by: PullInSectionIdentity.init(row:))
        func sortedRows(_ sectionRows: [CapturePullInChoiceRow]) -> [CapturePullInChoiceRow] {
            sectionRows.sorted { left, right in
                switch (left.offerNumber, right.offerNumber) {
                case let (a?, b?):
                    return a == b ? left.id < right.id : a < b
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return left.id < right.id
                }
            }
        }
        func makeSection(
            identity: PullInSectionIdentity,
            group: CapturePullInGroup?,
            sectionRows: [CapturePullInChoiceRow]
        ) -> CapturePullInChoiceSection {
            let after = group?.after ?? identity.afterTarget(from: sectionRows)
            return CapturePullInChoiceSection(
                group: identity.group,
                project: identity.project,
                note: pullInNonempty(group?.note) ?? identity.note,
                after: after,
                label: pullInNonempty(group?.label) ?? identity.label,
                event: pullInNonempty(group?.event)
                    ?? pullInNonempty(sectionRows.first?.offerRow?.relation?.event),
                copy: group?.copy,
                folded: group?.folded,
                rows: sortedRows(sectionRows)
            )
        }
        func groupMatching(_ identity: PullInSectionIdentity) -> CapturePullInGroup? {
            pullIn.groups.first { PullInSectionIdentity(group: $0) == identity }
        }
        // When Bob supplies copy, his group array is authoritative: emit
        // supplied groups in Bob order, then append any unmatched fallback
        // groups deterministically. This preserves authored copy/order and
        // keeps distinct relation labels at the same target distinct.
        // Copy-less payloads keep the legacy order unless every row identity
        // is listed, so keep-moving still ranks last for partial lists.
        let listedIdentities = pullIn.groups.map(PullInSectionIdentity.init(group:))
        if carriesBobCopy, !pullIn.groups.isEmpty {
            var ordered: [CapturePullInChoiceSection] = []
            var seen = Set<PullInSectionIdentity>()
            for identity in listedIdentities {
                guard let sectionRows = rowsByIdentity[identity], !sectionRows.isEmpty else {
                    continue
                }
                seen.insert(identity)
                ordered.append(
                    makeSection(
                        identity: identity,
                        group: groupMatching(identity),
                        sectionRows: sectionRows
                    )
                )
            }
            let extras = rowsByIdentity.keys.filter { !seen.contains($0) }
                .sorted(by: Self.legacySectionOrder)
            for identity in extras {
                ordered.append(
                    makeSection(
                        identity: identity,
                        group: groupMatching(identity),
                        sectionRows: rowsByIdentity[identity] ?? []
                    )
                )
            }
            return ordered
        }
        if !carriesBobCopy,
            !pullIn.groups.isEmpty,
            Set(rowsByIdentity.keys).isSubset(of: Set(listedIdentities))
        {
            return listedIdentities.compactMap { identity in
                guard let sectionRows = rowsByIdentity[identity], !sectionRows.isEmpty else {
                    return nil
                }
                return makeSection(
                    identity: identity,
                    group: groupMatching(identity),
                    sectionRows: sectionRows
                )
            }
        }
        return rowsByIdentity.keys.sorted(by: Self.legacySectionOrder).map { identity in
            makeSection(
                identity: identity,
                group: groupMatching(identity),
                sectionRows: rowsByIdentity[identity] ?? []
            )
        }
    }

    private static func legacySectionOrder(
        _ left: PullInSectionIdentity,
        _ right: PullInSectionIdentity
    ) -> Bool {
        let rank: [String: Int] = [
            "hand_off": 0,
            "relation": 1,
            "project": 2,
            "project_finished": 3,
            "keep_moving": 4,
            "note_pull": 5,
        ]
        let l = rank[left.group] ?? 5
        let r = rank[right.group] ?? 5
        if l != r {
            return l < r
        }
        let leftAfter = left.after ?? ""
        let rightAfter = right.after ?? ""
        if leftAfter != rightAfter {
            return leftAfter.localizedCaseInsensitiveCompare(rightAfter) == .orderedAscending
        }
        let leftLabel = left.label ?? ""
        let rightLabel = right.label ?? ""
        if leftLabel != rightLabel {
            return leftLabel.localizedCaseInsensitiveCompare(rightLabel) == .orderedAscending
        }
        let leftProject = left.project ?? ""
        let rightProject = right.project ?? ""
        return leftProject.localizedCaseInsensitiveCompare(rightProject) == .orderedAscending
    }

    func visibleRows(in section: CapturePullInChoiceSection) -> [CapturePullInChoiceRow] {
        guard !collapsedGroups.contains(section.id) || !filterText.isEmpty else {
            return []
        }
        guard !filterText.isEmpty else {
            return section.rows
        }
        let query = filterText.localizedLowercase
        let headerMatches = section.title.localizedLowercase.contains(query)
        return section.rows.filter { row in
            headerMatches
                || [
                    row.text,
                    row.notePath,
                    row.blockID,
                    row.destinationText ?? "",
                    row.detailText ?? "",
                    row.metaDetails.joined(separator: " "),
                ]
                .contains { $0.localizedLowercase.contains(query) }
        }
    }

    mutating func moveHighlight(by delta: Int) {
        let keys = visibleSelectableKeys
        guard !keys.isEmpty else {
            highlightedKey = nil
            return
        }
        guard let current = highlightedKey, let index = keys.firstIndex(of: current) else {
            highlightedKey = delta < 0 ? keys.last : keys.first
            return
        }
        highlightedKey = keys[min(max(index + delta, 0), keys.count - 1)]
    }

    mutating func toggleHighlighted() {
        guard let highlightedKey, visibleSelectableKeys.contains(highlightedKey) else {
            return
        }
        if markedKeys.contains(highlightedKey) {
            markedKeys.remove(highlightedKey)
        } else {
            markedKeys.insert(highlightedKey)
        }
    }

    mutating func markAll() {
        markedKeys = Set(selectableKeys)
    }

    mutating func updateFilter(_ text: String) {
        filterText = text
        if let highlightedKey, visibleSelectableKeys.contains(highlightedKey) {
            return
        }
        highlightedKey = visibleSelectableKeys.first
    }

    mutating func toggleGroup(_ id: String) {
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
    }
}

/// Join key for one pull-in section, including note-pull source identity.
/// Empty strings collapse to nil so older payloads without `after` still
/// group with Bob groups that omit it.
private struct PullInSectionIdentity: Hashable {
    let group: String
    let project: String?
    let note: String?
    let after: String?
    let label: String?

    init(group: String, project: String?, note: String? = nil, after: String?, label: String?) {
        self.group = group
        self.project = pullInNonempty(project)
        self.note = pullInNonempty(note)
        self.after = pullInNonempty(after)
        self.label = pullInNonempty(label)
    }

    init(row: CapturePullInChoiceRow) {
        // Relation discriminators join only primary relation groups. A
        // hand-off/project/keep-moving row may carry secondary relation
        // metadata for display; it must not split Bob's group, lose authored
        // copy, or fall back to legacy ordering.
        if row.group == "relation" {
            self.init(
                group: row.group,
                project: row.project,
                note: row.isNotePull ? row.notePath : nil,
                after: row.after,
                label: row.label
            )
        } else {
            self.init(
                group: row.group,
                project: row.project,
                note: row.isNotePull ? row.notePath : nil,
                after: nil,
                label: nil
            )
        }
    }

    init(group: CapturePullInGroup) {
        self.init(
            group: group.group,
            project: group.project,
            note: group.note,
            after: group.after?.key,
            label: group.label
        )
    }

    func afterTarget(from rows: [CapturePullInChoiceRow]) -> CapturePullInAfter? {
        if let target = rows.first?.offerRow?.relation?.after.first {
            return CapturePullInAfter(
                key: after ?? "",
                notePath: target.notePath,
                blockID: target.blockID,
                text: target.text
            )
        }
        guard let after else {
            return nil
        }
        return CapturePullInAfter(key: after)
    }
}
