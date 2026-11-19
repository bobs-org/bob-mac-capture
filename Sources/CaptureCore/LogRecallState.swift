import Foundation

/// Pure reducer for the pull-in cancel `USED BEFORE` band (Design §3).
///
/// Selection is tracked by phrase `key`, never by index. The filter keys off
/// a preserved `draft`, never off the filled value. A background refresh
/// re-ranks only in DRAFT; in RECALLING it waits until the next return to
/// DRAFT, so a late reply can never move a highlight or fill a field.
public struct LogRecallState: Equatable, Sendable {
    /// The field's preserved draft (what Esc restores).
    public var draft: String = ""
    /// Selected phrase key, or nil for DRAFT (nothing selected).
    public var selectedKey: String?
    /// Catalog phrases in bob's canonical order.
    public var catalog: [LogRecallPhrase] = []
    /// Catalog that arrived while RECALLING; applied on return to DRAFT.
    public var pendingCatalog: [LogRecallPhrase]?
    /// Whether the band has been revealed for this edit session (first
    /// Ctrl+N/P, or a 2+ character draft). Once shown it stays for the edit.
    public var revealed: Bool = false
    /// Generation guard: a stale reply never moves a highlight or fills.
    public var generation: UInt64 = 0

    public init() {}

    public var isRecalling: Bool { selectedKey != nil }

    /// Ranked rows for the current draft.
    public var ranked: [LogRecallRanking.Ranked] {
        LogRecallRanking.rank(phrases: catalog, query: draft)
    }

    public var rankedKeys: [String] {
        ranked.map(\.phrase.key)
    }

    /// 1-based position of the selection, or nil in DRAFT.
    public var selectedIndex: Int? {
        guard let selectedKey else { return nil }
        guard let position = rankedKeys.firstIndex(of: selectedKey) else { return nil }
        return position + 1
    }

    /// Dense gate: at most 3 rows, shown only after the first Ctrl+N/P or
    /// once the draft has 2+ non-space characters.
    public var shouldShowBand: Bool {
        guard !catalog.isEmpty else { return false }
        guard revealed else {
            return LogRecallBandPresentation.trimmedLength(draft) >= 2
        }
        return true
    }

    /// Visible rows, capped at 3 for the dense pull-in card.
    public var visibleRows: [LogRecallRanking.Ranked] {
        guard shouldShowBand else { return [] }
        return Array(ranked.prefix(LogRecallBandPresentation.maxRows))
    }

    /// Open the field with its initial text and a catalog snapshot.
    public mutating func open(draft: String, catalog: [LogRecallPhrase]) {
        self.draft = draft
        self.catalog = catalog
        pendingCatalog = nil
        selectedKey = nil
        revealed = false
        generation &+= 1
    }

    /// Typing adopts the shown text as the new draft and resets selection.
    public mutating func draftChanged(_ text: String) {
        draft = text
        selectedKey = nil
        if let pending = pendingCatalog {
            catalog = pending
            pendingCatalog = nil
        }
        if LogRecallBandPresentation.trimmedLength(text) >= 2 {
            revealed = true
        }
    }

    /// A background refresh: re-rank now in DRAFT, defer while RECALLING.
    public mutating func applyCatalog(
        _ phrases: [LogRecallPhrase], generation: UInt64
    ) -> Bool {
        guard generation == self.generation else { return false }
        if isRecalling {
            pendingCatalog = phrases
            return false
        }
        catalog = phrases
        return true
    }

    public enum Step {
        case enteredTop
        case moved
        case bumpedBottom
        case bumpedTop
    }

    /// Ctrl+N / ↓: enter the band at the top row, then move down.
    /// Bottom row clamps with a 120 ms edge bump, no wrap.
    public mutating func moveNext() -> Step? {
        let keys = rankedKeys
        guard !keys.isEmpty else { return nil }
        revealed = true
        guard let selectedKey else {
            self.selectedKey = keys[0]
            return .enteredTop
        }
        guard let position = keys.firstIndex(of: selectedKey) else {
            self.selectedKey = keys[0]
            return .enteredTop
        }
        if position + 1 < keys.count {
            self.selectedKey = keys[position + 1]
            return .moved
        }
        return .bumpedBottom
    }

    /// Ctrl+P / ↑: move up; above the top row returns to DRAFT.
    public mutating func movePrevious() -> Step? {
        let keys = rankedKeys
        guard !keys.isEmpty else { return nil }
        revealed = true
        guard let selectedKey else {
            self.selectedKey = keys[0]
            return .enteredTop
        }
        guard let position = keys.firstIndex(of: selectedKey) else {
            self.selectedKey = keys[0]
            return .enteredTop
        }
        if position > 0 {
            self.selectedKey = keys[position - 1]
            return .moved
        }
        self.selectedKey = nil
        if let pending = pendingCatalog {
            catalog = pending
            pendingCatalog = nil
        }
        return .bumpedTop
    }

    /// Esc / Ctrl+[: restore the draft (exactly one layer). Returns true
    /// when consumed (was RECALLING); the host runs its normal back-out
    /// only when this returns false.
    public mutating func backOut() -> Bool {
        guard isRecalling else { return false }
        selectedKey = nil
        if let pending = pendingCatalog {
            catalog = pending
            pendingCatalog = nil
        }
        return true
    }

    /// Clicking a row fills the field and enters RECALLING; it never commits.
    public mutating func select(key: String) -> Bool {
        guard rankedKeys.contains(key) else { return false }
        selectedKey = key
        revealed = true
        return true
    }

    /// Filled field text for the selection, or nil in DRAFT.
    public func filledText() -> String? {
        guard let selectedKey else { return nil }
        return ranked.first(where: { $0.phrase.key == selectedKey })?.phrase.text
    }
}
