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
    public private(set) var isEscArmed = false

    public init(
        offers: [TaskCompleteUnblocked],
        closeSupported: Bool = false,
        highlightedKey: String? = nil,
        marks: Set<String>? = nil,
        verdicts: [String: Verdict] = [:]
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
        let keys = usableRows.compactMap { $0.offer?.key }
        let validKeys = Set(keys)
        self.rows = usableRows
        self.closeSupported = closeSupported
        self.highlightedKey =
            highlightedKey.flatMap { validKeys.contains($0) ? $0 : nil }
            ?? keys.first
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
        !verdicts.isEmpty
    }

    public var effectiveSelectionKeys: [String] {
        effectivePickKeys(fallbackKey: highlightedKey)
    }

    public var effectivePickCount: Int {
        effectiveSelectionKeys.count
    }

    public var canCommit: Bool {
        effectivePickCount > 0 || closeCount > 0
    }

    /// Explicit marks win. The highlighted-row fallback applies only before
    /// the user stages any Done or Cancel verdict.
    public func effectivePickKeys(fallbackKey: String? = nil) -> [String] {
        let validKeys = Set(selectableKeys)
        let marked = selectableKeys.filter { marks.contains($0) && verdicts[$0] == nil }
        if !marked.isEmpty {
            return marked
        }
        guard verdicts.isEmpty,
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
        guard selectableKeys.contains(key) else { return }
        highlightedKey = key
        isEscArmed = false
    }

    /// Return a valid offer-key set after Bob refuses a stale or changed row.
    /// Surviving marks, verdict reasons, and highlight remain intact.
    @discardableResult
    public mutating func reseed(validKeys: Set<String>) -> Int {
        let survivingKeys = Set(selectableKeys).intersection(validKeys)
        let staged = Set(marks).union(verdicts.keys)
        let lost = staged.subtracting(survivingKeys).count
        rows = rows.filter { row in
            guard let key = row.offer?.key else { return false }
            return survivingKeys.contains(key)
        }
        marks.formIntersection(survivingKeys)
        verdicts = verdicts.filter { survivingKeys.contains($0.key) }
        if let highlightedKey, !survivingKeys.contains(highlightedKey) {
            self.highlightedKey = selectableKeys.first
        }
        isEscArmed = false
        return lost
    }

    @discardableResult
    public mutating func reseed(validKeys: [String]) -> Int {
        reseed(validKeys: Set(validKeys))
    }

    /// The shared footer copy, with zero-count segments omitted.
    public var footerSummaryText: String {
        var parts: [String] = []
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
        return parts.isEmpty ? "Choose offers" : parts.joined(separator: " · ")
    }

    public var primaryLabel: String {
        let picks = effectivePickCount
        if closeCount > 0 && picks > 0 {
            return "Apply choices"
        }
        if closeCount == 1 {
            return "Apply 1 close"
        }
        if closeCount > 1 {
            return "Apply \(closeCount) closes"
        }
        return picks == 0 ? "Pull In" : "Pull In \(picks)"
    }

    public var skipLabel: String {
        closeCount == 0 ? "Skip" : "Apply closes"
    }

    public var escArmedText: String? {
        guard isEscArmed, closeCount > 0 else { return nil }
        return closeCount == 1
            ? "Esc again to discard 1 close"
            : "Esc again to discard \(closeCount) closes"
    }

    @discardableResult
    public mutating func armEscDiscard() -> Bool {
        guard closeCount > 0 else {
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

    private func nextSelectableKey(after key: String) -> String? {
        guard let index = selectableKeys.firstIndex(of: key),
            selectableKeys.indices.contains(index + 1)
        else {
            return nil
        }
        return selectableKeys[index + 1]
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
