import Foundation

/// One verdict staged for a Bob successor-offer row. Leave is represented by
/// the absence of a value so previews keep Bob's default behavior.
public enum CapturePullInOfferVerdict: Equatable, Sendable {
    case done
    case cancel(String)
}

/// One Cancel argument, kept as an opaque offer key plus its optional reason.
public struct CapturePullInCancelOffer: Equatable, Sendable {
    public let key: String
    public let reason: String

    public init(key: String, reason: String = "") {
        self.key = key
        self.reason = Self.normalizedReason(reason)
    }

    private static func normalizedReason(_ reason: String) -> String {
        reason.split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The offer-close subset BobProcessClient turns into `-x` and `-X` argv.
public struct CapturePullInOfferVerdicts: Equatable, Sendable {
    public let completeKeys: [String]
    public let cancelOffers: [CapturePullInCancelOffer]

    public init(
        completeKeys: [String] = [],
        cancelOffers: [CapturePullInCancelOffer] = []
    ) {
        self.completeKeys = completeKeys
        self.cancelOffers = cancelOffers
    }

    public var isEmpty: Bool {
        completeKeys.isEmpty && cancelOffers.isEmpty
    }
}

/// Complete argv selection for one Pull-In card commit. `.none` is explicit:
/// it lets a verdict-only commit skip every pull-in row.
public struct CapturePullInOutcomeSelection: Equatable, Sendable {
    public let pullInSelection: CapturePullInSelection
    public let offerVerdicts: CapturePullInOfferVerdicts

    public init(
        pullInSelection: CapturePullInSelection,
        offerVerdicts: CapturePullInOfferVerdicts
    ) {
        self.pullInSelection = pullInSelection
        self.offerVerdicts = offerVerdicts
    }
}

/// Portable staged state for the Pull-In card. It stores only selection and
/// verdict state; row eligibility and consequence copy come from Bob's close
/// descriptors and are never inferred by CaptureCore.
public struct CapturePullInOutcomes: Equatable, Sendable {
    public typealias Verdict = CapturePullInOfferVerdict

    public private(set) var rows: [TaskCompleteUnblocked]
    public let closeSupported: Bool
    public private(set) var highlightedKey: String?
    public private(set) var marks: Set<String>
    public private(set) var verdicts: [String: Verdict]
    /// Navigation-only jump pin: at most one offer key, never a write.
    /// It rides alongside verdicts and marks, fires on every commit key,
    /// and dies when the card closes without committing.
    public private(set) var jumpKey: String?
    public private(set) var isEscArmed = false
    /// Pending requirement rows in Bob's order. Empty for legacy offer-only cards.
    public private(set) var requirementRows: [CaptureRequirementRow] = []
    /// Explicitly staged structural requirement choices. Absence is Met.
    public private(set) var requirementChoices: [String: CaptureRequirementStagedVerdict] = [:]

    /// Card compatibility: direct highlight assignment, including nil when
    /// filtering hides every row. Staged verdicts never move the highlight
    /// except through the explicit staging calls. The highlight may name a
    /// requirement row; it never becomes an effective pull-in pick.
    public mutating func setHighlightedKeyForCard(_ key: String?) {
        if let key, combinedSelectableKeys.contains(key) {
            highlightedKey = key
            isEscArmed = false
        } else if key == nil {
            highlightedKey = nil
            isEscArmed = false
        }
    }

    /// Card compatibility: direct mark replacement for filter/group tests.
    /// Surviving verdicts still win over marks. Marks touch ordinary
    /// task offers only and preserve requirement choices.
    public mutating func setMarksForCard(_ keys: Set<String>) {
        marks = keys.intersection(Set(selectableKeys))
        for key in verdicts.keys {
            marks.remove(key)
        }
        isEscArmed = false
    }

    public init(
        offers: [TaskCompleteUnblocked],
        closeSupported: Bool = false,
        highlightedKey: String? = nil,
        marks: Set<String>? = nil,
        verdicts: [String: Verdict] = [:],
        jumpKey: String? = nil
    ) {
        self.init(
            offers: offers,
            requirements: [],
            closeSupported: closeSupported,
            highlightedKey: highlightedKey,
            marks: marks,
            verdicts: verdicts,
            requirementChoices: [:],
            jumpKey: jumpKey
        )
    }

    /// Requirement-aware initializer. Task-only callers keep the legacy
    /// initializer above, which delegates here with no requirements.
    public init(
        offers: [TaskCompleteUnblocked],
        requirements: [CaptureRequirementRow],
        closeSupported: Bool = false,
        highlightedKey: String? = nil,
        marks: Set<String>? = nil,
        verdicts: [String: Verdict] = [:],
        requirementChoices: [String: CaptureRequirementStagedVerdict] = [:],
        jumpKey: String? = nil
    ) {
        var seen = Set<String>()
        let usableRows = offers.compactMap { row -> TaskCompleteUnblocked? in
            guard let offer = row.offer, !offer.key.isEmpty, seen.insert(offer.key).inserted else {
                return nil
            }
            return row
        }.sorted {
            let left = $0.offer?.n ?? .max
            let right = $1.offer?.n ?? .max
            return left == right
                ? ($0.offer?.key ?? "") < ($1.offer?.key ?? "")
                : left < right
        }
        var seenReq = Set<String>()
        let usableReqs = requirements.filter { $0.isSelectable }.compactMap {
            row -> CaptureRequirementRow? in
            guard !row.offer.key.isEmpty, seenReq.insert(row.offer.key).inserted else {
                return nil
            }
            return row
        }.sorted {
            $0.offer.n == $1.offer.n ? $0.offer.key < $1.offer.key : $0.offer.n < $1.offer.n
        }
        let keys = usableRows.compactMap { $0.offer?.key }
        let validKeys = Set(keys)
        let reqKeys = usableReqs.map(\.offer.key)
        let validReqKeys = Set(reqKeys)
        let combinedValid = validKeys.union(validReqKeys)
        self.rows = usableRows
        self.requirementRows = usableReqs
        self.closeSupported = closeSupported
        // Highlight may target a requirement row; task-only cards keep the
        // legacy first-offer fallback. A highlighted requirement never
        // becomes an effective pull-in pick.
        if let highlightedKey, combinedValid.contains(highlightedKey) {
            self.highlightedKey = highlightedKey
        } else if let highlightedKey, validKeys.contains(highlightedKey) {
            self.highlightedKey = highlightedKey
        } else {
            self.highlightedKey = highlightedKey.flatMap { validReqKeys.contains($0) ? $0 : nil }
                ?? keys.first ?? reqKeys.first
        }
        self.marks =
            (marks
            ?? Set(
                usableRows.compactMap { row in
                    row.offer?.selected == true ? row.offer?.key : nil
                })).intersection(validKeys)
        self.verdicts = verdicts.filter { key, verdict in
            guard validKeys.contains(key) else { return false }
            return Self.isEligible(
                verdict, in: usableRows.first { $0.offer?.key == key }?.offer?.close,
                closeSupported: closeSupported)
        }
        // Only staged structural requirement choices for surviving rows.
        // Met is the absence of a value and is never stored.
        self.requirementChoices = requirementChoices.filter { validReqKeys.contains($0.key) }
        // A jump pin may target an ordinary offer or a requirement row.
        self.jumpKey = jumpKey.flatMap { combinedValid.contains($0) ? $0 : nil }
        for key in self.verdicts.keys {
            self.marks.remove(key)
        }
    }

    /// Bob's offer order, which is also the stable argv order.
    public var selectableKeys: [String] {
        rows.compactMap { $0.offer?.key }
    }

    public var selectedCount: Int {
        marks.intersection(Set(selectableKeys)).count
    }

    public var doneCount: Int {
        verdicts.values.filter { if case .done = $0 { true } else { false } }.count
    }

    public var cancelCount: Int {
        verdicts.values.filter { if case .cancel = $0 { true } else { false } }.count
    }

    public var closeCount: Int {
        doneCount + cancelCount
    }

    public var hasVerdicts: Bool {
        !verdicts.isEmpty || !requirementChoices.isEmpty
    }

    /// Requirement offer keys in Bob's order.
    public var requirementSelectableKeys: [String] {
        requirementRows.map(\.offer.key)
    }

    /// Combined Bob order for highlight and jump validation: requirements
    /// first by shared numbering, then ordinary offers. Task-only
    /// `selectableKeys` stays the stable argv order for ordinary offers.
    public var combinedSelectableKeys: [String] {
        let typed: [CapturePullInTypedRow] = requirementRows.map { .requirement($0) }
            + rows.map { .task($0) }
        return typed.sorted {
            $0.number == $1.number ? $0.key < $1.key : $0.number < $1.number
        }.map(\.key)
    }

    public var typedRowsInBobOrder: [CapturePullInTypedRow] {
        let typed: [CapturePullInTypedRow] = requirementRows.map { .requirement($0) }
            + rows.map { .task($0) }
        return typed.sorted {
            $0.number == $1.number ? $0.key < $1.key : $0.number < $1.number
        }
    }

    public var effectiveSelectionKeys: [String] {
        effectivePickKeys(fallbackKey: highlightedKey)
    }

    public var effectivePickCount: Int {
        effectiveSelectionKeys.count
    }

    public var canCommit: Bool {
        // All-default requirement cards are committable: Met writes no
        // bytes but still closes the owner.
        if !requirementRows.isEmpty {
            return true
        }
        return effectivePickCount > 0 || closeCount > 0 || jumpKey != nil
    }

    /// Explicit structural requirement choices (Drop/Carry/Carry-plus-pull).
    public var requirementStructuralCount: Int {
        requirementChoices.count
    }

    public var requirementDropCount: Int {
        requirementChoices.values.filter { $0.isDrop }.count
    }

    public var requirementCarryCount: Int {
        requirementChoices.count - requirementDropCount
    }

    /// Explicit marks win. The highlighted-row fallback applies only before
    /// the user stages any Done, Cancel, or structural requirement verdict,
    /// and never while a jump pin is staged or the highlight names a
    /// requirement: a pin-only commit jumps without pulling anything in,
    /// and Return never silently pulls a highlighted requirement.
    public func effectivePickKeys(fallbackKey: String? = nil) -> [String] {
        let validKeys = Set(selectableKeys)
        let marked = selectableKeys.filter { marks.contains($0) && verdicts[$0] == nil }
        if !marked.isEmpty {
            return marked
        }
        guard verdicts.isEmpty,
            requirementChoices.isEmpty,
            jumpKey == nil,
            let fallbackKey,
            validKeys.contains(fallbackKey),
            verdicts[fallbackKey] == nil
        else {
            return []
        }
        return [fallbackKey]
    }

    public func isEligible(_ verdict: Verdict, for key: String) -> Bool {
        guard closeSupported,
            let descriptor = rows.first(where: { $0.offer?.key == key })?.offer?.close
        else {
            return false
        }
        return Self.isEligible(verdict, in: descriptor, closeSupported: true)
    }

    /// Bob-authored refusal copy for an ineligible row.
    public func refusalReason(for key: String) -> String? {
        rows.first(where: { $0.offer?.key == key })?.offer?.close?.why
    }

    /// Bob-authored consequence copy; no local eligibility or consequence
    /// wording is assembled here.
    public func consequence(for verdict: Verdict, rowKey: String) -> String? {
        guard let descriptor = rows.first(where: { $0.offer?.key == rowKey })?.offer?.close else {
            return nil
        }
        switch verdict {
        case .done:
            return descriptor.completeConsequence
        case .cancel:
            return descriptor.cancelConsequence
        }
    }

    public func scopeNote(for key: String) -> String? {
        rows.first(where: { $0.offer?.key == key })?.offer?.close?.scopeNote
    }

    /// Toggle a Pull-In mark. A mark replaces a staged row verdict.
    public mutating func toggleMark(for key: String) {
        guard selectableKeys.contains(key) else { return }
        isEscArmed = false
        if marks.contains(key) {
            marks.remove(key)
        } else {
            verdicts.removeValue(forKey: key)
            marks.insert(key)
        }
    }

    /// Apply or clear a bulk mark, leaving every Done or Cancel row unchanged.
    public mutating func setAllMarked(_ marked: Bool) {
        let eligibleKeys = selectableKeys.filter { verdicts[$0] == nil }
        if marked {
            marks.formUnion(eligibleKeys)
        } else {
            marks.subtract(eligibleKeys)
        }
        isEscArmed = false
    }

    /// Toggle all Leave/Pull-In rows while preserving every staged verdict.
    public mutating func toggleAllMarks() {
        let eligibleKeys = selectableKeys.filter { verdicts[$0] == nil }
        guard !eligibleKeys.isEmpty else { return }
        let allMarked = eligibleKeys.allSatisfy { marks.contains($0) }
        setAllMarked(!allMarked)
    }

    /// Set or replace a verdict on one row, then advance to the next offer in
    /// Bob's visual order. At the end of the list the highlight stays put.
    @discardableResult
    public mutating func replaceVerdict(_ verdict: Verdict, for key: String) -> String? {
        guard selectableKeys.contains(key), isEligible(verdict, for: key) else {
            return highlightedKey
        }
        verdicts[key] = Self.normalized(verdict)
        marks.remove(key)
        isEscArmed = false
        let target = nextSelectableKey(after: key) ?? key
        highlightedKey = target
        return target
    }

    /// Toggle one verdict. Repeating the same verdict clears it and keeps the
    /// highlight on that row; a different verdict replaces and advances.
    @discardableResult
    public mutating func toggleVerdict(_ verdict: Verdict, for key: String) -> String? {
        if verdicts[key] == Self.normalized(verdict) {
            return clearVerdict(for: key)
        }
        return replaceVerdict(verdict, for: key)
    }

    /// Visible-order staging: the card navigates grouped/filter-visible rows,
    /// while argv keeps Bob's offer order. Callers pass the card's
    /// `visibleSelectableKeys`; nil falls back to Bob order.
    @discardableResult
    public mutating func replaceVerdict(
        _ verdict: Verdict,
        for key: String,
        visibleOrder: [String]?
    ) -> String? {
        guard selectableKeys.contains(key), isEligible(verdict, for: key) else {
            return highlightedKey
        }
        verdicts[key] = Self.normalized(verdict)
        marks.remove(key)
        isEscArmed = false
        let order = visibleOrder ?? selectableKeys
        let target = Self.nextKey(after: key, in: order) ?? key
        highlightedKey = selectableKeys.contains(target) ? target : key
        return highlightedKey
    }

    @discardableResult
    public mutating func toggleVerdict(
        _ verdict: Verdict,
        for key: String,
        visibleOrder: [String]?
    ) -> String? {
        if verdicts[key] == Self.normalized(verdict) {
            return clearVerdict(for: key)
        }
        return replaceVerdict(verdict, for: key, visibleOrder: visibleOrder)
    }

    /// Toggle the jump pin: radio toggle and move, keyed by offer key,
    /// never by list index. Accepts ordinary offers and requirement rows;
    /// returns false for unknown rows, which the card surfaces as a refusal
    /// instead of a pin. A navigation-only descendant pin remains valid
    /// while its ancestor is carried or dropped. Verdicts, marks, and the
    /// highlight are untouched; Ctrl+J never moves the highlight.
    @discardableResult
    public mutating func toggleJump(for key: String) -> Bool {
        guard combinedSelectableKeys.contains(key) else { return false }
        if jumpKey == key {
            jumpKey = nil
        } else {
            jumpKey = key
        }
        if !verdicts.isEmpty || !requirementChoices.isEmpty {
            isEscArmed = false
        }
        return true
    }

    /// The pinned row's plain text, for status and VoiceOver copy.
    public var jumpLabel: String? {
        guard let jumpKey else { return nil }
        if let text = rows.first(where: { $0.offer?.key == jumpKey })?.text,
            !text.isEmpty
        {
            return text
        }
        let reqText = requirementRows.first(where: { $0.offer.key == jumpKey })?.req.text ?? ""
        return reqText.isEmpty ? nil : reqText
    }

    /// Footer safety net: the staged pin is never a surprise, even when the
    /// filter hides its row. S is truncated to 40 characters plus `…`.
    public var jumpSummarySuffix: String? {
        guard let label = jumpLabel else { return nil }
        return " · ↗ “\(Self.truncatedJumpLabel(label))”"
    }

    public static func truncatedJumpLabel(_ text: String) -> String {
        guard text.count > 40 else { return text }
        return String(text.prefix(40)) + "…"
    }

    /// Clear a row back to Leave without moving the highlight.
    @discardableResult
    public mutating func clearVerdict(for key: String) -> String? {
        guard verdicts.removeValue(forKey: key) != nil else {
            return highlightedKey
        }
        isEscArmed = false
        highlightedKey = key
        return key
    }

    public mutating func highlight(_ key: String) {
        guard combinedSelectableKeys.contains(key) else { return }
        highlightedKey = key
        isEscArmed = false
    }

    /// Return a valid offer-key set after Bob refuses a stale or changed row.
    /// Surviving marks, verdict reasons, and highlight remain intact.
    /// Requirement rows and choices survive a task-only reseed; use the
    /// combined reseed when Bob returns fresh requirement keys.
    @discardableResult
    public mutating func reseed(validKeys: Set<String>) -> Int {
        let survivingKeys = Set(selectableKeys).intersection(validKeys)
        var staged = Set(marks).union(verdicts.keys)
        if let jumpKey, selectableKeys.contains(jumpKey) {
            staged.insert(jumpKey)
        }
        let lost = staged.subtracting(survivingKeys).count
        rows = rows.filter { row in
            guard let key = row.offer?.key else { return false }
            return survivingKeys.contains(key)
        }
        marks.formIntersection(survivingKeys)
        verdicts = verdicts.filter { survivingKeys.contains($0.key) }
        let combinedSurviving = survivingKeys.union(Set(requirementSelectableKeys))
        if let jumpKey, !combinedSurviving.contains(jumpKey) {
            self.jumpKey = nil
        }
        if let highlightedKey, !combinedSurviving.contains(highlightedKey) {
            self.highlightedKey = selectableKeys.first ?? requirementSelectableKeys.first
        }
        isEscArmed = false
        return lost
    }

    @discardableResult
    public mutating func reseed(validKeys: [String]) -> Int {
        reseed(validKeys: Set(validKeys))
    }

    /// Combined reseed for task offers and requirement rows. Exact complete
    /// keys only: a changed owner preimage never transfers by label or
    /// sibling path. Reports removed staged choices.
    @discardableResult
    public mutating func reseedCombined(taskKeys: Set<String>, requirementKeys: Set<String>) -> Int {
        let survivingTasks = Set(selectableKeys).intersection(taskKeys)
        let survivingReqs = Set(requirementSelectableKeys).intersection(requirementKeys)
        var staged = Set(marks).union(verdicts.keys).union(requirementChoices.keys)
        if let jumpKey { staged.insert(jumpKey) }
        let survivingCombined = survivingTasks.union(survivingReqs)
        let lost = staged.subtracting(survivingCombined).count
        rows = rows.filter { row in
            guard let key = row.offer?.key else { return false }
            return survivingTasks.contains(key)
        }
        requirementRows = requirementRows.filter { survivingReqs.contains($0.offer.key) }
        marks.formIntersection(survivingTasks)
        verdicts = verdicts.filter { survivingTasks.contains($0.key) }
        requirementChoices = requirementChoices.filter { survivingReqs.contains($0.key) }
        revalidateRequirementBranches()
        if let jumpKey, !survivingCombined.contains(jumpKey) {
            self.jumpKey = nil
        }
        if let highlightedKey, !survivingCombined.contains(highlightedKey) {
            self.highlightedKey = selectableKeys.first ?? requirementSelectableKeys.first
        }
        isEscArmed = false
        return lost
    }

    /// Bob-authored unblock count for one row; never derived locally.
    public func unblocksCount(for key: String) -> Int {
        rows.first(where: { $0.offer?.key == key })?.offer?.close?.unblocks ?? 0
    }

    /// Refresh row descriptors from Bob, preserving surviving marks,
    /// verdicts, reasons, and highlight. Unlike `reseed(validKeys:)`, this
    /// replaces eligibility and consequence copy so a refused-then-refreshed
    /// row never keeps stale data. Removed keys are dropped and counted.
    @discardableResult
    public mutating func refresh(rows freshRows: [TaskCompleteUnblocked]) -> Int {
        return refresh(taskRows: freshRows, requirementRows: requirementRows)
    }

    /// Refresh task and requirement descriptors from Bob, preserving
    /// surviving marks, verdicts, reasons, highlight and pin. Exact
    /// complete keys only; a changed owner preimage never transfers by
    /// label or sibling path. Reports removed staged choices and
    /// revalidates surviving branch choices.
    @discardableResult
    public mutating func refresh(
        taskRows freshTasks: [TaskCompleteUnblocked],
        requirementRows freshReqs: [CaptureRequirementRow]
    ) -> Int {
        var seen = Set<String>()
        let usable = freshTasks.compactMap { row -> TaskCompleteUnblocked? in
            guard let offer = row.offer, !offer.key.isEmpty,
                seen.insert(offer.key).inserted
            else {
                return nil
            }
            return row
        }.sorted {
            let left = $0.offer?.n ?? .max
            let right = $1.offer?.n ?? .max
            return left == right
                ? ($0.offer?.key ?? "") < ($1.offer?.key ?? "")
                : left < right
        }
        var seenReq = Set<String>()
        let usableReqs = freshReqs.filter { $0.isSelectable }.compactMap {
            row -> CaptureRequirementRow? in
            guard !row.offer.key.isEmpty, seenReq.insert(row.offer.key).inserted else {
                return nil
            }
            return row
        }.sorted {
            $0.offer.n == $1.offer.n ? $0.offer.key < $1.offer.key : $0.offer.n < $1.offer.n
        }
        let validKeys = Set(usable.compactMap { $0.offer?.key })
        let validReqKeys = Set(usableReqs.map(\.offer.key))
        let validCombined = validKeys.union(validReqKeys)
        var staged = Set(marks).union(verdicts.keys).union(requirementChoices.keys)
        if let jumpKey { staged.insert(jumpKey) }
        let lostPre = staged.subtracting(validCombined).count
        rows = usable
        requirementRows = usableReqs
        marks.formIntersection(validKeys)
        // Keep surviving staged verdicts visible even when Bob's fresh
        // descriptor now refuses them; Bob remains the final write
        // validator and the user changes the judgment explicitly.
        verdicts = verdicts.filter { validKeys.contains($0.key) }
        requirementChoices = requirementChoices.filter { validReqKeys.contains($0.key) }
        let droppedBranches = revalidateRequirementBranches()
        // A refresh that loses the pinned key drops the pin; the caller
        // reports it with the visible status line.
        if let jumpKey, !validCombined.contains(jumpKey) {
            self.jumpKey = nil
        }
        if let highlightedKey, !validCombined.contains(highlightedKey) {
            self.highlightedKey = usable.compactMap { $0.offer?.key }.first
                ?? usableReqs.map(\.offer.key).first
        }
        isEscArmed = false
        return lostPre + droppedBranches
    }

    /// Refresh requirement rows only, preserving task state.
    @discardableResult
    public mutating func refreshRequirements(_ freshReqs: [CaptureRequirementRow]) -> Int {
        return refresh(taskRows: rows, requirementRows: freshReqs)
    }

    /// Row-aware semantic summary: descendants excluded by staged
    /// structural choices are not counted as met.
    public func requirementSummaryCounts() -> (met: Int, dropped: Int, carried: Int) {
        let folds = Dictionary(uniqueKeysWithValues: requirementFolds().map { ($0.key, $0) })
        var met = 0
        var dropped = 0
        var carried = 0
        for row in requirementRows {
            let key = row.offer.key
            if let choice = requirementChoices[key] {
                switch choice {
                case .drop:
                    dropped += 1
                case .carry, .carryPulled:
                    carried += 1
                }
                continue
            }
            // Unstaged rows hidden by a staged ancestor are excluded, never met.
            if folds[key]?.visible == false {
                continue
            }
            met += 1
        }
        return (met, dropped, carried)
    }

    public var requirementSummaryText: String? {
        guard !requirementRows.isEmpty else { return nil }
        let counts = requirementSummaryCounts()
        return CaptureRequirementCopy.summary(
            met: counts.met, dropped: counts.dropped, carried: counts.carried)
    }

    /// The shared footer copy, with zero-count segments omitted.
    /// Requirement summary leads when requirement rows exist; a staged pin
    /// always appends the jump safety-net suffix.
    public var footerSummaryText: String {
        var parts: [String] = []
        if let reqSummary = requirementSummaryText {
            parts.append(reqSummary)
        }
        let picks = effectivePickCount
        if picks > 0 {
            parts.append("pull in \(picks)")
        }
        if doneCount > 0 {
            parts.append("✓ \(doneCount) done")
        }
        if cancelCount > 0 {
            parts.append("⊘ \(cancelCount) cancel")
        }
        let base: String
        if parts.isEmpty {
            base = requirementRows.isEmpty ? "Choose offers" : "Choose requirements"
        } else {
            base = parts.joined(separator: " · ")
        }
        return base + (jumpSummarySuffix ?? "")
    }

    public var primaryLabel: String {
        primaryLabel(pickCount: effectivePickCount)
    }

    /// Copy-table primary label. The card passes its visible pick count so a
    /// collapsed highlight never shows "Pull In 1" on a disabled button.
    /// Requirement structural choices count as closes.
    public func primaryLabel(pickCount: Int) -> String {
        let total = totalCloseCount
        if jumpKey != nil {
            if total > 0 {
                return "Apply & Jump"
            }
            if pickCount > 0 {
                return "Pull In \(pickCount) & Jump"
            }
            return "Leave Open & Jump"
        }
        if pickCount > 0, total > 0 {
            return "Pull In \(pickCount) · Close \(total)"
        }
        if total > 0 {
            return "Close \(total)"
        }
        return pickCount == 0 ? "Pull In" : "Pull In \(pickCount)"
    }

    /// Total closes for labels and Esc: ordinary Done/Cancel plus
    /// explicit structural requirement choices. Default Met never arms.
    public var totalCloseCount: Int {
        closeCount + requirementStructuralCount
    }

    public var skipLabel: String {
        let total = totalCloseCount
        let base = total == 0 ? "Skip" : "Skip pull-ins · Close \(total)"
        return jumpKey != nil ? base + " & Jump" : base
    }

    public var escArmedText: String? {
        let total = totalCloseCount
        guard isEscArmed, total > 0 else { return nil }
        return total == 1
            ? "Esc again to discard 1 close"
            : "Esc again to discard \(total) closes"
    }

    @discardableResult
    public mutating func armEscDiscard() -> Bool {
        guard totalCloseCount > 0 else {
            isEscArmed = false
            return false
        }
        isEscArmed = true
        return true
    }

    public mutating func disarmEscDiscard() {
        isEscArmed = false
    }

    public mutating func discardVerdicts() {
        verdicts.removeAll()
        requirementChoices.removeAll()
        isEscArmed = false
    }

    /// Stable argv projection. Keys remain opaque and follow Bob's offer
    /// order; no key parsing or display-text inference occurs here.
    public func argvSelection() -> CapturePullInOutcomeSelection {
        let picked = effectiveSelectionKeys
        let pullInSelection: CapturePullInSelection = picked.isEmpty ? .none : .keys(picked)
        var completeKeys: [String] = []
        var cancelOffers: [CapturePullInCancelOffer] = []
        for key in selectableKeys {
            guard let verdict = verdicts[key] else { continue }
            switch verdict {
            case .done:
                completeKeys.append(key)
            case .cancel(let reason):
                cancelOffers.append(CapturePullInCancelOffer(key: key, reason: reason))
            }
        }
        return CapturePullInOutcomeSelection(
            pullInSelection: pullInSelection,
            offerVerdicts: CapturePullInOfferVerdicts(
                completeKeys: completeKeys,
                cancelOffers: cancelOffers
            )
        )
    }

    // MARK: - Requirements

    public func requirementRow(for key: String) -> CaptureRequirementRow? {
        requirementRows.first(where: { $0.offer.key == key })
    }

    public func requirementChoice(for key: String) -> CaptureRequirementStagedVerdict? {
        requirementChoices[key]
    }

    public func isRequirementMet(_ key: String) -> Bool {
        requirementSelectableKeys.contains(key) && requirementChoices[key] == nil
    }

    /// Bob-authored consequence copy for a requirement row.
    public func requirementConsequence(
        for choice: CaptureRequirementStagedVerdict?,
        rowKey: String
    ) -> String? {
        guard let row = requirementRow(for: rowKey) else { return nil }
        switch choice {
        case .none:
            return row.consequences.met
        case .drop:
            return row.consequences.drop
        case .carry:
            return row.consequences.carry
        case .carryPulled:
            return row.consequences.carryPulled
        }
    }

    public func requirementAccessibility(for key: String) -> String? {
        guard let row = requirementRow(for: key) else { return nil }
        return CaptureRequirementCopy.accessibility(
            depth: row.req.depth,
            verb: CaptureRequirementCopy.verb(for: requirementChoices[key]))
    }

    public func requirementOwnerText(for key: String) -> String? {
        requirementRow(for: key).map { $0.req.ownerKey }
    }

    private func requirementIndexByKey() -> [String: CaptureRequirementRow] {
        Dictionary(uniqueKeysWithValues: requirementRows.map { ($0.offer.key, $0) })
    }

    /// Overlap refusal for one new structural choice against surviving
    /// staged choices. Same-key replacement is allowed; every other branch
    /// overlap in either staging order refuses without mutating.
    public func requirementOverlap(
        staging key: String,
        choice: CaptureRequirementStagedVerdict
    ) -> CaptureRequirementOverlapError? {
        guard let target = requirementRow(for: key) else { return nil }
        _ = choice
        for (existingKey, _) in requirementChoices {
            if existingKey == key { continue }
            guard let existing = requirementRow(for: existingKey) else { continue }
            guard existing.req.ownerKey == target.req.ownerKey else { continue }
            let existingPath = existing.req.path.components
            let targetPath = target.req.path.components
            if CaptureRequirementBranch.isStrictAncestor(
                ancestorPath: existingPath, descendantPath: targetPath)
            {
                return CaptureRequirementOverlapError(
                    ancestorKey: existingKey,
                    ancestorText: existing.req.text,
                    descendantKey: key)
            }
            if CaptureRequirementBranch.isStrictAncestor(
                ancestorPath: targetPath, descendantPath: existingPath)
            {
                return CaptureRequirementOverlapError(
                    ancestorKey: key,
                    ancestorText: target.req.text,
                    descendantKey: existingKey)
            }
        }
        return nil
    }

    /// Folded display rows: a staged Drop/Carry folds descendant display
    /// rows. Met unfolds them. Descendant staged choices are retained.
    public func requirementFolds() -> [CaptureRequirementFold] {
        let byKey = requirementIndexByKey()
        return requirementRows.map { row in
            let key = row.offer.key
            var ancestorKey: String? = nil
            // Nearest staged structural ancestor wins for display.
            var bestDepth = -1
            for (stagedKey, _) in requirementChoices {
                if stagedKey == key { continue }
                guard let stagedRow = byKey[stagedKey] else { continue }
                guard stagedRow.req.ownerKey == row.req.ownerKey else { continue }
                if CaptureRequirementBranch.isStrictAncestor(
                    ancestorPath: stagedRow.req.path.components,
                    descendantPath: row.req.path.components)
                {
                    let depth = stagedRow.req.path.components.count
                    if depth > bestDepth {
                        bestDepth = depth
                        ancestorKey = stagedKey
                    }
                }
            }
            if let ancestorKey {
                return CaptureRequirementFold(
                    key: key, visible: false, hiddenBy: ancestorKey, nestedGoWithIt: nil)
            }
            let choice = requirementChoices[key]
            let nested: Int? = {
                guard choice != nil, row.req.pendingDescendants > 0 else { return nil }
                return row.req.pendingDescendants
            }()
            return CaptureRequirementFold(key: key, visible: true, hiddenBy: nil, nestedGoWithIt: nested)
        }
    }

    public func visibleRequirementKeys() -> [String] {
        requirementFolds().filter(\.visible).map(\.key)
    }

    public func nestedGoWithItText(for key: String) -> String? {
        guard let fold = requirementFolds().first(where: { $0.key == key }),
            let count = fold.nestedGoWithIt
        else {
            return nil
        }
        return CaptureRequirementCopy.nestedGoWithIt(count)
    }

    /// Revalidate surviving branch choices after refresh. Drops descendant
    /// choices that now overlap a surviving ancestor and reports the count.
    @discardableResult
    private mutating func revalidateRequirementBranches() -> Int {
        let byKey = requirementIndexByKey()
        let ordered = requirementChoices.keys.sorted { lhs, rhs in
            let leftDepth = byKey[lhs]?.req.path.components.count ?? Int.max
            let rightDepth = byKey[rhs]?.req.path.components.count ?? Int.max
            if leftDepth == rightDepth { return lhs < rhs }
            return leftDepth < rightDepth
        }
        var kept: [String: CaptureRequirementStagedVerdict] = [:]
        var dropped = 0
        for key in ordered {
            guard let choice = requirementChoices[key],
                let row = byKey[key]
            else {
                continue
            }
            var overlaps = false
            for (keptKey, _) in kept {
                guard let keptRow = byKey[keptKey] else { continue }
                guard keptRow.req.ownerKey == row.req.ownerKey else { continue }
                if CaptureRequirementBranch.isStrictAncestor(
                    ancestorPath: keptRow.req.path.components,
                    descendantPath: row.req.path.components)
                    || CaptureRequirementBranch.isStrictAncestor(
                        ancestorPath: row.req.path.components,
                        descendantPath: keptRow.req.path.components)
                {
                    overlaps = true
                    break
                }
            }
            if overlaps {
                dropped += 1
                continue
            }
            kept[key] = choice
        }
        requirementChoices = kept
        return dropped
    }

    /// Ctrl+X on a requirement restores Met and never means task Done.
    @discardableResult
    public mutating func clearRequirementChoice(for key: String) -> String? {
        guard requirementChoices.removeValue(forKey: key) != nil else {
            return highlightedKey
        }
        isEscArmed = false
        highlightedKey = key
        return key
    }

    public mutating func stageRequirementMet(for key: String) -> String? {
        return clearRequirementChoice(for: key)
    }

    @discardableResult
    public mutating func stageRequirementDrop(
        reason: String,
        for key: String,
        visibleOrder: [String]? = nil
    ) -> CaptureRequirementOverlapError? {
        let normalized = CaptureRequirementBranch.normalizedReason(reason)
        let choice = CaptureRequirementStagedVerdict.drop(reason: normalized)
        return stageRequirement(choice, for: key, visibleOrder: visibleOrder)
    }

    @discardableResult
    public mutating func stageRequirementCarry(
        for key: String,
        visibleOrder: [String]? = nil
    ) -> CaptureRequirementOverlapError? {
        return stageRequirement(.carry, for: key, visibleOrder: visibleOrder)
    }

    @discardableResult
    public mutating func stageRequirementCarryPulled(
        for key: String,
        visibleOrder: [String]? = nil
    ) -> CaptureRequirementOverlapError? {
        return stageRequirement(.carryPulled, for: key, visibleOrder: visibleOrder)
    }

    /// Core staging: repeating the same verdict returns to Met; another
    /// verdict replaces it. Overlaps refuse without mutating.
    @discardableResult
    private mutating func stageRequirement(
        _ choice: CaptureRequirementStagedVerdict,
        for key: String,
        visibleOrder: [String]?
    ) -> CaptureRequirementOverlapError? {
        guard requirementRow(for: key) != nil else { return nil }
        if requirementChoices[key] == choice {
            _ = clearRequirementChoice(for: key)
            return nil
        }
        if let overlap = requirementOverlap(staging: key, choice: choice) {
            return overlap
        }
        requirementChoices[key] = choice
        isEscArmed = false
        let order = visibleOrder ?? visibleRequirementKeys()
        if order.contains(key) {
            let target = Self.nextKey(after: key, in: order) ?? key
            highlightedKey = combinedSelectableKeys.contains(target) ? target : key
        } else {
            highlightedKey = key
        }
        return nil
    }

    /// Typed commit projection. Shift-Return downgrades carry-plus-pull to
    /// Carry, keeps Drop/ordinary verdicts and the jump pin, and selects no
    /// ordinary pull-ins. Never mutates staged UI choices.
    public func commitProjection(shiftReturn: Bool) -> (
        pullIn: CapturePullInSelection,
        requirements: CaptureRequirementSubmission,
        jumpKey: String?
    ) {
        var verdicts: [CaptureRequirementVerdictSubmission] = []
        for key in requirementSelectableKeys {
            guard let choice = requirementChoices[key] else { continue }
            switch choice {
            case .drop(let reason):
                verdicts.append(.drop(key: key, reason: reason))
            case .carry:
                verdicts.append(.carry(key: key))
            case .carryPulled:
                if shiftReturn {
                    verdicts.append(.carry(key: key))
                } else {
                    verdicts.append(.carryAndPull(key: key))
                }
            }
        }
        let pullIn: CapturePullInSelection
        if shiftReturn {
            pullIn = .none
        } else {
            let picked = effectiveSelectionKeys
            pullIn = picked.isEmpty ? .none : .keys(picked)
        }
        return (pullIn, CaptureRequirementSubmission(verdicts: verdicts), jumpKey)
    }

    public func requirementSubmission(shiftReturn: Bool = false) -> CaptureRequirementSubmission {
        return commitProjection(shiftReturn: shiftReturn).requirements
    }

    private func nextSelectableKey(after key: String) -> String? {
        Self.nextKey(after: key, in: selectableKeys)
    }

    func nextRequirementKey(after key: String, in order: [String]? = nil) -> String? {
        let order = order ?? requirementSelectableKeys
        return Self.nextKey(after: key, in: order)
    }

    static func nextKey(after key: String, in order: [String]) -> String? {
        guard let index = order.firstIndex(of: key),
            order.indices.contains(index + 1)
        else {
            return nil
        }
        return order[index + 1]
    }

    private static func isEligible(
        _ verdict: Verdict,
        in descriptor: TaskCompleteOfferClose?,
        closeSupported: Bool
    ) -> Bool {
        guard closeSupported, let descriptor else { return false }
        switch verdict {
        case .done:
            return descriptor.complete
        case .cancel:
            return descriptor.cancel
        }
    }

    private static func normalized(_ verdict: Verdict) -> Verdict {
        switch verdict {
        case .done:
            return .done
        case .cancel(let reason):
            return .cancel(CapturePullInCancelOffer(key: "", reason: reason).reason)
        }
    }
}
