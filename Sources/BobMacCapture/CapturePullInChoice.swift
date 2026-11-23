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
        case "notebook", "notebook_note", "notebook_sub_note":
            return "book.closed"
        case "requirement", "requirements":
            return "diamond"
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

    /// The `@note` a note-pull row was requested from. Bob freezes it on the
    /// offer; `notePath` is the task's final home, which a later move in the
    /// same draft can change. Older payloads without the field fall back.
    var sourceNotePath: String {
        pullInNonempty(offerRow?.offer?.note) ?? notePath
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
    let ownerKey: String?
    let requirementRows: [CaptureRequirementRow]

    init(
        group: String,
        project: String? = nil,
        note: String? = nil,
        after: CapturePullInAfter? = nil,
        label: String? = nil,
        event: String? = nil,
        copy: CapturePullInGroupCopy? = nil,
        folded: CapturePullInFolded? = nil,
        rows: [CapturePullInChoiceRow] = [],
        ownerKey: String? = nil,
        requirementRows: [CaptureRequirementRow] = []
    ) {
        self.group = group
        self.project = project
        self.note = note
        self.after = after
        self.label = label
        self.event = event
        self.copy = copy
        self.folded = folded
        self.rows = rows
        self.ownerKey = ownerKey
        self.requirementRows = requirementRows
    }

    var id: String {
        Self.key(
            group: group, project: project, note: note, after: after?.key, label: label,
            owner: ownerKey)
    }

    var isRequirement: Bool {
        group == "requirements"
    }

    var showsRequirementMark: Bool {
        isRequirement || copy?.glyph == "requirement"
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

    /// Bob-authored scope line for a requirement section (for example
    /// "4 requirements"). History is the vault-stored context line; footer carries
    /// the canonical key hints. All three are optional additive copy.
    var requirementScope: String? {
        pullInNonempty(copy?.scope)
    }

    var requirementHistory: String? {
        pullInNonempty(copy?.history)
    }

    var requirementFooter: String? {
        pullInNonempty(copy?.footer)
    }

    /// Selectable requirement count for the section header. Ordinary
    /// sections keep their row count; requirement sections count pending
    /// requirement rows, not ordinary offers.
    var selectableRequirementCount: Int {
        requirementRows.filter(\.isSelectable).count
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
        label: String? = nil,
        owner: String? = nil
    ) -> String {
        let ownerPart = pullInNonempty(owner) ?? ""
        guard let note = pullInNonempty(note) else {
            return
                "\(group)\u{1F}\(project ?? "")\u{1F}\(after ?? "")\u{1F}\(label ?? "")\u{1F}\(ownerPart)"
        }
        return
            "\(group)\u{1F}\(project ?? "")\u{1F}\(note)\u{1F}\(after ?? "")\u{1F}\(label ?? "")\u{1F}\(ownerPart)"
    }

    static func capitalizedLabel(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return String(first).uppercased() + text.dropFirst()
    }
}

/// Transient in-panel choice state. Selection and verdicts live in
/// `outcomes`; row eligibility and consequence copy come from Bob's close
/// descriptors and are never inferred here.
struct CapturePullInChoiceState: Equatable {
    var moveInSelection: String? = nil

    let draftSnapshot: String
    let processClientIdentity: String
    var openAfterCapture: Bool
    let priorityRollSeed: String
    let generation: UInt64
    let requestID: UUID?
    var pullIn: CapturePullIn
    let planBudget: CapturePlanBudget?
    var rows: [CapturePullInChoiceRow]
    var outcomes: CapturePullInOutcomes
    var filterText = ""
    var collapsedGroups: Set<String> = []
    var errorMessage: String?
    var activeReasonKey: String?
    var activeReasonText = ""
    var savedPriorVerdict: CapturePullInOfferVerdict?
    var savedPriorRequirementChoice: CaptureRequirementStagedVerdict? = nil
    var consequenceMessage: String?
    var verdictRefusalMessage: String?

    init(
        moveInSelection: String? = nil,
        draftSnapshot: String,
        processClientIdentity: String,
        openAfterCapture: Bool,
        priorityRollSeed: String,
        generation: UInt64,
        requestID: UUID?,
        pullIn: CapturePullIn,
        planBudget: CapturePlanBudget? = nil,
        rows: [CapturePullInChoiceRow],
        highlightedKey: String? = nil,
        markedKeys: Set<String> = [],
        filterText: String = "",
        collapsedGroups: Set<String> = [],
        errorMessage: String? = nil
    ) {
        self.moveInSelection = moveInSelection
        self.draftSnapshot = draftSnapshot
        self.processClientIdentity = processClientIdentity
        self.openAfterCapture = openAfterCapture
        self.priorityRollSeed = priorityRollSeed
        self.generation = generation
        self.requestID = requestID
        self.pullIn = pullIn
        self.planBudget = planBudget
        self.rows = rows
        let offers = rows.compactMap(\.offerRow)
        let reqRows = pullIn.groups.filter { $0.isRequirementGroup }.flatMap(\.rows)
            .filter { $0.isSelectable }
        self.outcomes = CapturePullInOutcomes(
            offers: offers,
            requirements: reqRows,
            closeSupported: pullIn.close?.supported == true,
            highlightedKey: highlightedKey,
            marks: markedKeys.isEmpty ? nil : markedKeys)
        self.filterText = filterText
        self.collapsedGroups = collapsedGroups
        self.errorMessage = errorMessage
    }

    var highlightedKey: String? {
        get { outcomes.highlightedKey }
        set { outcomes.setHighlightedKeyForCard(newValue) }
    }

    var markedKeys: Set<String> {
        get { outcomes.marks }
        set { outcomes.setMarksForCard(newValue) }
    }

    var closeSupported: Bool {
        pullIn.close?.supported == true
    }

    /// Whether Bob advertised the jump capability that gates `--jump-offer`.
    var jumpSupported: Bool {
        pullIn.jump?.supported == true
    }

    var jumpKey: String? {
        outcomes.jumpKey
    }

    var jumpLabel: String? {
        outcomes.jumpLabel
    }

    /// Toggle the jump pin on one offer or requirement row. Unknown rows refuse.
    mutating func toggleJump(_ key: String) {
        guard outcomes.combinedSelectableKeys.contains(key) else {
            return
        }
        cancelActiveReasonEditing()
        verdictRefusalMessage = nil
        outcomes.toggleJump(for: key)
    }

    var hasVerdicts: Bool {
        outcomes.hasVerdicts
    }

    var requirementSelectableKeys: [String] {
        outcomes.requirementSelectableKeys
    }

    var combinedSelectableKeys: [String] {
        outcomes.combinedSelectableKeys
    }

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
        let validMarked = outcomes.marks.intersection(Set(selectableKeys))
        if !validMarked.isEmpty {
            return selectableKeys.filter(validMarked.contains)
        }
        // Once any verdict exists — task or structural requirement — or a
        // jump pin is staged, Return has no highlight fallback. A hidden
        // highlight or a highlighted requirement never supplies one.
        guard outcomes.verdicts.isEmpty,
            outcomes.requirementChoices.isEmpty,
            outcomes.jumpKey == nil,
            let highlighted = outcomes.highlightedKey,
            visibleSelectableKeys.contains(highlighted)
        else {
            return []
        }
        return [highlighted]
    }

    var verdicts: [String: CapturePullInOfferVerdict] {
        outcomes.verdicts
    }

    var doneCount: Int {
        outcomes.doneCount
    }

    var cancelCount: Int {
        outcomes.cancelCount
    }

    var closeCount: Int {
        outcomes.closeCount
    }

    var totalCloseCount: Int {
        outcomes.totalCloseCount
    }

    var requirementStructuralCount: Int {
        outcomes.requirementStructuralCount
    }

    var canCommit: Bool {
        // All-default requirement cards are committable.
        if !outcomes.requirementRows.isEmpty {
            return true
        }
        return !effectiveSelectionKeys.isEmpty || totalCloseCount > 0 || jumpKey != nil
    }

    var footerSummaryText: String {
        if effectivePickCount > 0 || totalCloseCount > 0 || !outcomes.requirementRows.isEmpty {
            // Requirement summary leads when requirement rows exist.
            if !outcomes.requirementRows.isEmpty {
                return outcomes.footerSummaryText
            }
            return outcomes.footerSummaryText
        }
        let base = isOnlyNotePull ? "Choose tasks to pull in" : "Choose offers"
        return base + (outcomes.jumpSummarySuffix ?? "")
    }

    var primaryCommitLabel: String {
        outcomes.primaryLabel(pickCount: effectivePickCount)
    }

    var skipCommitLabel: String {
        outcomes.skipLabel
    }

    var visibleSelectableKeys: [String] {
        sections.flatMap { section in
            visibleRows(in: section).compactMap(\.offerKey)
        }
    }

    var visibleRequirementKeys: [String] {
        sections.flatMap { section in
            visibleRequirementRows(in: section).map(\.offer.key)
        }
    }

    var visibleCombinedKeys: [String] {
        // Bob order: requirements first by shared numbering.
        let reqKeys = visibleRequirementKeys
        let taskKeys = visibleSelectableKeys
        // When both exist, requirements precede tasks by numbering.
        // Deduplicate to guard against stale keys.
        var seen = Set<String>()
        var combined: [String] = []
        for key in reqKeys + taskKeys where seen.insert(key).inserted {
            combined.append(key)
        }
        return combined
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

    var showsRequirementFilterMark: Bool {
        authoredCopy?.glyph == "requirement"
            || (!sections.isEmpty && sections.allSatisfy(\.showsRequirementMark))
    }

    var isOnlyKeepMoving: Bool {
        let offers = rows.compactMap(\.offerRow)
        return !offers.isEmpty && offers.allSatisfy { $0.offer?.group == "keep_moving" }
    }

    var isOnlyNotePull: Bool {
        let offers = rows.compactMap(\.offerRow)
        return !offers.isEmpty && offers.allSatisfy { $0.offer?.group == "note_pull" }
    }

    /// Distinct requested source notes in Bob's group order, then any row
    /// source Bob's groups do not list.
    var notePullSources: [String] {
        var sources: [String] = []
        let grouped = pullIn.groups.filter { $0.group == "note_pull" }
            .compactMap { pullInNonempty($0.note) }
        let fromRows = rows.filter(\.isNotePull).compactMap { pullInNonempty($0.sourceNotePath) }
        for note in grouped + fromRows where !sources.contains(note) {
            sources.append(note)
        }
        return sources
    }

    var isOnlyRelation: Bool {
        let offers = rows.compactMap(\.offerRow)
        return !offers.isEmpty && offers.allSatisfy { $0.offer?.group == "relation" }
    }

    var promptStatusText: String {
        if isOnlyNotePull {
            let sources = notePullSources
            if sources.count > 1 {
                return "Choose tasks to pull in from \(sources.count) notes"
            }
            let note = sources.first ?? ""
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

    func isStagedDone(_ key: String) -> Bool {
        outcomes.verdicts[key] == .done
    }

    func stagedCancelReason(_ key: String) -> String? {
        guard case .cancel(let reason) = outcomes.verdicts[key] else {
            return nil
        }
        return reason
    }

    func isCloseEligible(_ key: String) -> Bool {
        outcomes.isEligible(.done, for: key) || outcomes.isEligible(.cancel(""), for: key)
    }

    func refusalReason(for key: String) -> String? {
        outcomes.refusalReason(for: key)
    }

    func consequenceText(for verdict: CapturePullInOfferVerdict, rowKey: String) -> String? {
        var parts: [String] = []
        if let consequence = outcomes.consequence(for: verdict, rowKey: rowKey) {
            parts.append(consequence)
        }
        if let scope = outcomes.scopeNote(for: rowKey), !scope.isEmpty {
            parts.append(scope)
        }
        let unblocks = outcomes.unblocksCount(for: rowKey)
        if unblocks > 0 {
            parts.append(unblocks == 1 ? "unblocks 1" : "unblocks \(unblocks)")
        }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: " ")
    }

    /// Valid marks inside one section (stale keys never count).
    func markedCount(in section: CapturePullInChoiceSection) -> Int {
        let valid = outcomes.marks.intersection(Set(selectableKeys))
        guard !valid.isEmpty else {
            return 0
        }
        return section.rows.compactMap(\.offerKey).filter(valid.contains).count
    }

    /// "Pull In N" / "Pull In" when nothing would be picked.
    /// Verdict-aware commits use `primaryCommitLabel`.
    var pullInActionTitle: String {
        primaryCommitLabel
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
                rows: sortedRows(sectionRows),
                ownerKey: pullInNonempty(group?.owner?.key) ?? identity.owner,
                requirementRows: []
            )
        }

        func makeRequirementSection(
            ownerKey: String,
            rows: [CaptureRequirementRow],
            group: CapturePullInGroup?
        ) -> CapturePullInChoiceSection? {
            let reqRows = rows.filter { $0.isSelectable }.sorted {
                $0.offer.n == $1.offer.n ? $0.offer.key < $1.offer.key : $0.offer.n < $1.offer.n
            }
            guard !reqRows.isEmpty else { return nil }
            let kind = group?.effectiveKind ?? "requirements"
            return CapturePullInChoiceSection(
                group: kind,
                project: group?.project,
                note: group?.note,
                after: group?.after,
                label: group?.label,
                event: group?.event,
                copy: group?.copy,
                folded: group?.folded,
                rows: [],
                ownerKey: ownerKey,
                requirementRows: reqRows)
        }
        func groupMatching(_ identity: PullInSectionIdentity) -> CapturePullInGroup? {
            pullIn.groups.first { PullInSectionIdentity(group: $0) == identity }
        }
        func requirementGroupMatching(ownerKey: String) -> CapturePullInGroup? {
            pullIn.groups.first {
                $0.isRequirementGroup
                    && ($0.owner?.key == ownerKey || $0.requirementOwnerKey == ownerKey)
            }
        }
        // Requirement sections precede ordinary groups in Bob's closing
        // owner order, preserving canonical copy and folds. History is not
        // actionable scope: only pending rows appear. Built from staged
        // outcomes rows so refresh stays in sync; copy comes from Bob groups.
        let reqSections: [CapturePullInChoiceSection] = {
            let byOwner = Dictionary(grouping: outcomes.requirementRows, by: \.req.ownerKey)
            guard !byOwner.isEmpty else { return [] }
            var ownerOrder: [String] = []
            for group in pullIn.groups where group.isRequirementGroup {
                let key = group.owner?.key ?? group.requirementOwnerKey
                if let key, !key.isEmpty, byOwner[key] != nil, !ownerOrder.contains(key) {
                    ownerOrder.append(key)
                }
            }
            for key in byOwner.keys.sorted() where !ownerOrder.contains(key) {
                ownerOrder.append(key)
            }
            return ownerOrder.compactMap { owner in
                makeRequirementSection(
                    ownerKey: owner,
                    rows: byOwner[owner] ?? [],
                    group: requirementGroupMatching(ownerKey: owner))
            }
        }()
        // When Bob supplies copy, his group array is authoritative: emit
        // supplied groups in Bob order, then append any unmatched fallback
        // groups deterministically. This preserves authored copy/order and
        // keeps distinct relation labels at the same target distinct.
        // Copy-less payloads keep the legacy order unless every row identity
        // is listed, so keep-moving still ranks last for partial lists.
        let listedIdentities = pullIn.groups.filter { !$0.isRequirementGroup }.map(
            PullInSectionIdentity.init(group:))
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
            return reqSections + ordered
        }
        if !carriesBobCopy,
            !pullIn.groups.isEmpty,
            Set(rowsByIdentity.keys).isSubset(of: Set(listedIdentities))
        {
            let ordinary = listedIdentities.compactMap { identity -> CapturePullInChoiceSection? in
                guard let sectionRows = rowsByIdentity[identity], !sectionRows.isEmpty else {
                    return nil
                }
                return makeSection(
                    identity: identity,
                    group: groupMatching(identity),
                    sectionRows: sectionRows
                )
            }
            return reqSections + ordinary
        }
        let ordinary = rowsByIdentity.keys.sorted(by: Self.legacySectionOrder).map { identity in
            makeSection(
                identity: identity,
                group: groupMatching(identity),
                sectionRows: rowsByIdentity[identity] ?? []
            )
        }
        return reqSections + ordinary
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

    func visibleRequirementRows(in section: CapturePullInChoiceSection) -> [CaptureRequirementRow] {
        guard section.isRequirement else { return [] }
        guard !collapsedGroups.contains(section.id) || !filterText.isEmpty else {
            return []
        }
        // Fold hides descendants of staged structural ancestors; filtering
        // and collapse never erase staged choices.
        let folds = Dictionary(
            uniqueKeysWithValues: outcomes.requirementFolds().map { ($0.key, $0) })
        var rows = section.requirementRows
        // Preserve Bob's row numbers.
        rows.sort {
            $0.offer.n == $1.offer.n ? $0.offer.key < $1.offer.key : $0.offer.n < $1.offer.n
        }
        if !filterText.isEmpty {
            let query = filterText.localizedLowercase
            let headerMatches = section.title.localizedLowercase.contains(query)
            if !headerMatches {
                rows = rows.filter { row in
                    row.req.text.localizedLowercase.contains(query)
                        || row.req.ownerKey.localizedLowercase.contains(query)
                }
            }
        }
        // Fold applies after filter: a hidden descendant stays hidden even
        // when the filter matches, but its staged choice is retained.
        if filterText.isEmpty {
            rows = rows.filter { folds[$0.offer.key]?.visible ?? true }
        } else {
            // When filtering, still hide folded descendants unless the
            // header matches (which shows the whole branch for context).
            let headerMatches = section.title.localizedLowercase.contains(
                filterText.localizedLowercase)
            if !headerMatches {
                rows = rows.filter { folds[$0.offer.key]?.visible ?? true }
            }
        }
        return rows
    }

    mutating func moveHighlight(by delta: Int) {
        verdictRefusalMessage = nil
        // Navigate across combined visible keys: requirements first, then
        // ordinary offers, in Bob order. Task-only cards keep legacy order.
        let keys = visibleCombinedKeys.isEmpty ? visibleSelectableKeys : visibleCombinedKeys
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
        guard let current = highlightedKey else {
            return
        }
        // Space on a requirement stages Carry-plus-pull and stays on the
        // row; repeating it returns to Met. Ordinary offers keep mark.
        if outcomes.requirementRow(for: current) != nil {
            stageRequirementCarryPulled(current)
            // Staging advances via outcomes; Space stays.
            highlightedKey = current
            return
        }
        guard visibleSelectableKeys.contains(current) else {
            return
        }
        cancelActiveReasonEditing()
        outcomes.toggleMark(for: current)
        updateConsequenceForHighlight()
    }

    mutating func toggleHighlightedAndAdvance() {
        if let current = highlightedKey,
            outcomes.requirementRow(for: current) != nil
        {
            // Tab on a requirement stages Carry-plus-pull then advances
            // once in combined Bob order.
            stageRequirementCarryPulled(current)
            highlightedKey = current
            moveHighlight(by: 1)
            updateConsequenceForHighlight()
            return
        }
        toggleHighlighted()
        moveHighlight(by: 1)
        updateConsequenceForHighlight()
    }

    mutating func toggleOffer(_ key: String) {
        // Pointer on a requirement stages Carry-plus-pull, sharing keyboard
        // validation; it never advances and never becomes a mark.
        if outcomes.requirementRow(for: key) != nil {
            highlightedKey = key
            stageRequirementCarryPulled(key)
            highlightedKey = key
            return
        }
        guard selectableKeys.contains(key) else {
            return
        }
        cancelActiveReasonEditing()
        highlightedKey = key
        outcomes.toggleMark(for: key)
        updateConsequenceForHighlight()
    }

    mutating func markAll() {
        cancelActiveReasonEditing()
        outcomes.setAllMarked(true)
    }

    mutating func toggleAllMarks() {
        cancelActiveReasonEditing()
        outcomes.toggleAllMarks()
    }

    mutating func toggleOfferDone(_ key: String) {
        guard closeSupported else {
            return
        }
        cancelActiveReasonEditing()
        if outcomes.verdicts[key] == .done {
            _ = outcomes.clearVerdict(for: key)
            consequenceMessage = nil
            return
        }
        guard outcomes.isEligible(.done, for: key) else {
            verdictRefusalMessage = outcomes.refusalReason(for: key)
            return
        }
        verdictRefusalMessage = nil
        _ = outcomes.replaceVerdict(.done, for: key, visibleOrder: visibleSelectableKeys)
        if let verdict = outcomes.verdicts[key] {
            consequenceMessage = consequenceText(for: verdict, rowKey: key)
        }
    }

    mutating func beginOfferCancel(_ key: String) {
        guard closeSupported else {
            return
        }
        if case .cancel = outcomes.verdicts[key] {
            // Same Cancel chord on an already staged Cancel row clears it
            // regardless of its stored reason.
            cancelActiveReasonEditing()
            _ = outcomes.clearVerdict(for: key)
            consequenceMessage = nil
            return
        }
        guard outcomes.isEligible(.cancel(""), for: key) else {
            verdictRefusalMessage = outcomes.refusalReason(for: key)
            return
        }
        verdictRefusalMessage = nil
        savedPriorVerdict = outcomes.verdicts[key]
        activeReasonKey = key
        if case .cancel(let reason) = outcomes.verdicts[key] {
            activeReasonText = reason
        } else {
            activeReasonText = ""
        }
    }

    mutating func confirmOfferCancel(_ key: String? = nil) {
        guard let target = key ?? activeReasonKey else {
            return
        }
        let reason = CapturePullInCancelOffer(key: "", reason: activeReasonText).reason
        activeReasonKey = nil
        activeReasonText = ""
        savedPriorVerdict = nil
        guard outcomes.isEligible(.cancel(reason), for: target) else {
            verdictRefusalMessage = outcomes.refusalReason(for: target)
            return
        }
        verdictRefusalMessage = nil
        _ = outcomes.replaceVerdict(
            .cancel(reason), for: target, visibleOrder: visibleSelectableKeys)
        if let verdict = outcomes.verdicts[target] {
            consequenceMessage = consequenceText(for: verdict, rowKey: target)
        }
    }

    mutating func restoreOfferCancel() {
        guard let target = activeReasonKey else {
            return
        }
        // Esc in a requirement reason editor restores the previous choice
        // without arming card discard.
        if outcomes.requirementRow(for: target) != nil {
            activeReasonKey = nil
            activeReasonText = ""
            savedPriorRequirementChoice = nil
            savedPriorVerdict = nil
            outcomes.disarmEscDiscard()
            // Restore the exact prior requirement outcome: re-stage the
            // saved choice when one existed, otherwise ensure Met.
            if let prior = savedPriorRequirementChoiceForRestore {
                _ = stageRequirementWithoutRefusal(prior, for: target)
            } else {
                _ = outcomes.clearRequirementChoice(for: target)
                updateRequirementConsequence(for: target)
            }
            savedPriorRequirementChoiceForRestore = nil
            return
        }
        activeReasonKey = nil
        activeReasonText = ""
        savedPriorVerdict = nil
        savedPriorRequirementChoice = nil
        // Esc in the reason field restores the exact prior outcome without
        // arming the card discard warning.
        outcomes.disarmEscDiscard()
    }

    // Stash for Esc-restoring a requirement reason edit.
    var savedPriorRequirementChoiceForRestore: CaptureRequirementStagedVerdict? = nil

    mutating func cancelActiveReasonEditing() {
        activeReasonKey = nil
        activeReasonText = ""
        savedPriorVerdict = nil
        savedPriorRequirementChoice = nil
        savedPriorRequirementChoiceForRestore = nil
        verdictRefusalMessage = nil
    }

    // MARK: - Requirements

    func requirementChoice(for key: String) -> CaptureRequirementStagedVerdict? {
        outcomes.requirementChoice(for: key)
    }

    func isRequirementMet(_ key: String) -> Bool {
        outcomes.isRequirementMet(key)
    }

    func requirementConsequenceText(
        for choice: CaptureRequirementStagedVerdict?,
        rowKey: String
    ) -> String? {
        outcomes.requirementConsequence(for: choice, rowKey: rowKey)
    }

    func requirementAccessibility(for key: String) -> String? {
        outcomes.requirementAccessibility(for: key)
    }

    /// Ctrl+X on a requirement restores Met and never means task Done.
    mutating func stageRequirementMet(_ key: String) {
        guard outcomes.requirementRow(for: key) != nil else { return }
        cancelActiveReasonEditing()
        verdictRefusalMessage = nil
        _ = outcomes.clearRequirementChoice(for: key)
        updateRequirementConsequence(for: key)
    }

    mutating func stageRequirementCarry(_ key: String) {
        guard outcomes.requirementRow(for: key) != nil else { return }
        cancelActiveReasonEditing()
        if let overlap = outcomes.stageRequirementCarry(
            for: key, visibleOrder: visibleRequirementKeys)
        {
            verdictRefusalMessage = overlap.message
            return
        }
        verdictRefusalMessage = nil
        updateRequirementConsequence(for: key)
    }

    mutating func stageRequirementCarryPulled(_ key: String) {
        guard outcomes.requirementRow(for: key) != nil else { return }
        cancelActiveReasonEditing()
        if let overlap = outcomes.stageRequirementCarryPulled(
            for: key, visibleOrder: visibleRequirementKeys)
        {
            verdictRefusalMessage = overlap.message
            return
        }
        verdictRefusalMessage = nil
        updateRequirementConsequence(for: key)
    }

    mutating func beginRequirementDrop(_ key: String) {
        guard outcomes.requirementRow(for: key) != nil else { return }
        if outcomes.requirementChoice(for: key)?.isDrop == true {
            // Same Drop chord on an already staged Drop row clears it to Met.
            cancelActiveReasonEditing()
            _ = outcomes.clearRequirementChoice(for: key)
            updateRequirementConsequence(for: key)
            return
        }
        verdictRefusalMessage = nil
        savedPriorRequirementChoice = outcomes.requirementChoice(for: key)
        savedPriorRequirementChoiceForRestore = savedPriorRequirementChoice
        savedPriorVerdict = nil
        activeReasonKey = key
        if case .drop(let reason) = outcomes.requirementChoice(for: key) {
            activeReasonText = reason
        } else {
            activeReasonText = ""
        }
    }

    mutating func confirmRequirementDrop(_ key: String? = nil) {
        guard let target = key ?? activeReasonKey else { return }
        guard outcomes.requirementRow(for: target) != nil else { return }
        let reason = CaptureRequirementBranch.normalizedReason(activeReasonText)
        activeReasonKey = nil
        activeReasonText = ""
        savedPriorVerdict = nil
        savedPriorRequirementChoice = nil
        savedPriorRequirementChoiceForRestore = nil
        if let overlap = outcomes.stageRequirementDrop(
            reason: reason, for: target, visibleOrder: visibleRequirementKeys)
        {
            verdictRefusalMessage = overlap.message
            return
        }
        verdictRefusalMessage = nil
        updateRequirementConsequence(for: target)
    }

    mutating func restoreRequirementDrop() {
        guard activeReasonKey != nil else { return }
        restoreOfferCancel()
    }

    private mutating func stageRequirementWithoutRefusal(
        _ choice: CaptureRequirementStagedVerdict,
        for key: String
    ) -> CaptureRequirementOverlapError? {
        switch choice {
        case .drop(let reason):
            return outcomes.stageRequirementDrop(
                reason: reason, for: key, visibleOrder: visibleRequirementKeys)
        case .carry:
            return outcomes.stageRequirementCarry(
                for: key, visibleOrder: visibleRequirementKeys)
        case .carryPulled:
            return outcomes.stageRequirementCarryPulled(
                for: key, visibleOrder: visibleRequirementKeys)
        }
    }

    mutating func updateRequirementConsequence(for key: String) {
        consequenceMessage = outcomes.requirementConsequence(
            for: outcomes.requirementChoice(for: key), rowKey: key)
    }

    func commitProjection(shiftReturn: Bool) -> (
        pullIn: CapturePullInSelection,
        requirements: CaptureRequirementSubmission,
        jumpKey: String?
    ) {
        return outcomes.commitProjection(shiftReturn: shiftReturn)
    }

    mutating func updateReasonText(_ text: String) {
        activeReasonText = text
    }

    /// Vault-relative note path for the row the reason editor is open on,
    /// or nil when the row carries none. The LINK band passes it as
    /// `--source-note` so same-note `[[#` fields resolve.
    var activeReasonNotePath: String? {
        guard let activeReasonKey else { return nil }
        let path = rows.first { $0.offerKey == activeReasonKey }?.notePath ?? ""
        return path.isEmpty ? nil : path
    }

    /// The task the reason row itself is about: its exact note path and
    /// block ID. The tasks band dims bob's row for this same task. Nil when
    /// the row has no block ID, so a path alone never dims a whole note.
    var activeReasonSubject: PullInLinkSubject? {
        guard let activeReasonKey,
            let row = rows.first(where: { $0.offerKey == activeReasonKey })
        else {
            return nil
        }
        return PullInLinkSubject(notePath: row.notePath, blockID: row.blockID)
    }

    mutating func updateConsequenceForHighlight() {
        guard let highlighted = highlightedKey else {
            return
        }
        if let verdict = outcomes.verdicts[highlighted] {
            consequenceMessage = consequenceText(for: verdict, rowKey: highlighted)
            return
        }
        if outcomes.requirementRow(for: highlighted) != nil {
            updateRequirementConsequence(for: highlighted)
        }
    }

    mutating func clearVerdictForHighlight() {
        guard let highlighted = highlightedKey else {
            return
        }
        verdictRefusalMessage = nil
        if outcomes.requirementRow(for: highlighted) != nil {
            _ = outcomes.clearRequirementChoice(for: highlighted)
            updateRequirementConsequence(for: highlighted)
            // Clearing to Met leaves no consequence copy.
            if outcomes.requirementChoice(for: highlighted) == nil {
                consequenceMessage = outcomes.requirementConsequence(
                    for: nil, rowKey: highlighted)
            }
            return
        }
        _ = outcomes.clearVerdict(for: highlighted)
        if consequenceMessage != nil {
            consequenceMessage = nil
        }
    }

    /// Ctrl+X on the highlighted row: requirements restore Met, ordinary
    /// offers toggle Done/Cancel? No: Ctrl+X on a requirement restores Met
    /// and never means task Done. Ordinary rows keep their current keys.
    mutating func clearRequirementForHighlight() {
        guard let highlighted = highlightedKey else { return }
        guard outcomes.requirementRow(for: highlighted) != nil else { return }
        verdictRefusalMessage = nil
        cancelActiveReasonEditing()
        _ = outcomes.clearRequirementChoice(for: highlighted)
        updateRequirementConsequence(for: highlighted)
    }

    mutating func armEscDiscard() -> Bool {
        outcomes.armEscDiscard()
    }

    mutating func disarmEscDiscard() {
        outcomes.disarmEscDiscard()
    }

    mutating func discardVerdicts() {
        outcomes.discardVerdicts()
        consequenceMessage = nil
        verdictRefusalMessage = nil
        cancelActiveReasonEditing()
    }

    /// Refresh rows from Bob, preserving marks, verdicts, reasons,
    /// highlight and pin. Exact complete keys only; reports removed choices
    /// and revalidates surviving branch choices.
    mutating func refresh(
        offers fresh: [TaskCompleteUnblocked],
        requirements freshReqs: [CaptureRequirementRow]? = nil
    ) -> Int {
        if let freshReqs {
            // Update Bob groups so requirement sections stay in sync; copy
            // and folds come from the fresh groups.
            var groups = pullIn.groups
            for index in groups.indices where groups[index].isRequirementGroup {
                let owner = groups[index].owner?.key ?? groups[index].requirementOwnerKey
                let freshRows = freshReqs.filter { $0.req.ownerKey == owner }
                groups[index] = groups[index].replacingRequirementRows(freshRows)
            }
            pullIn = CapturePullIn(
                supported: pullIn.supported,
                offerCount: pullIn.offerCount,
                choice: pullIn.choice,
                pickedCount: pullIn.pickedCount,
                groups: groups,
                copy: pullIn.copy,
                close: pullIn.close,
                jump: pullIn.jump,
                reqs: pullIn.reqs)
        }
        let freshReqRows = freshReqs ?? outcomes.requirementRows
        let lost = outcomes.refresh(taskRows: fresh, requirementRows: freshReqRows)
        let freshRowsByKey = Dictionary(
            uniqueKeysWithValues: fresh.compactMap { row in
                row.offer.map { ($0.key, row) }
            })
        var rebuilt: [CapturePullInChoiceRow] = []
        for row in rows {
            guard let key = row.offerKey,
                let freshOffer = freshRowsByKey[key]
            else {
                if row.offerKey == nil {
                    rebuilt.append(row)
                }
                continue
            }
            rebuilt.append(CapturePullInChoiceRow(
                offerRow: freshOffer,
                blockedRow: nil,
                group: freshOffer.offer?.group ?? row.group,
                project: freshOffer.offer?.project ?? row.project))
        }
        let known = Set(rebuilt.compactMap(\.offerKey))
        for offer in fresh where !known.contains(offer.offer?.key ?? "") {
            guard let o = offer.offer, !o.key.isEmpty else {
                continue
            }
            rebuilt.append(CapturePullInChoiceRow(
                offerRow: offer,
                blockedRow: nil,
                group: o.group,
                project: o.project))
        }
        rows = rebuilt
        return lost
    }

    mutating func updateFilter(_ text: String) {
        filterText = text
        cancelActiveReasonEditing()
        // Filtering never erases selection state; highlight follows the
        // combined visible keys so a requirement highlight survives.
        let combined = visibleCombinedKeys
        if let highlightedKey, combined.contains(highlightedKey) {
            return
        }
        highlightedKey = combined.first ?? visibleSelectableKeys.first
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
    let owner: String?

    init(
        group: String,
        project: String?,
        note: String? = nil,
        after: String?,
        label: String?,
        owner: String? = nil
    ) {
        self.group = group
        self.project = pullInNonempty(project)
        self.note = pullInNonempty(note)
        self.after = pullInNonempty(after)
        self.label = pullInNonempty(label)
        self.owner = pullInNonempty(owner)
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
                note: row.isNotePull ? row.sourceNotePath : nil,
                after: row.after,
                label: row.label
            )
        } else {
            self.init(
                group: row.group,
                project: row.project,
                note: row.isNotePull ? row.sourceNotePath : nil,
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
            label: group.label,
            owner: group.owner?.key
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
