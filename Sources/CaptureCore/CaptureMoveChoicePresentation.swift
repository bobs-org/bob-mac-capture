import Foundation

/// A task's explicit choice on the Move card. Leave is represented by the
/// absence of an answer so a newly opened card always preserves Bob's default.
public enum CaptureMoveChoiceAnswer: String, Equatable, Sendable {
    case move = "^"
    case moveAndLink = ":"

    public var sigil: String {
        rawValue
    }
}

/// A section in the Move card, retaining Bob's document order.
public struct CaptureMoveChoiceSection: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let rows: [CaptureMoveChoiceRow]

    public init(id: String, title: String, rows: [CaptureMoveChoiceRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

/// Portable three-state card state. It only stores the user's marks and the
/// highlighted row; all task eligibility, ordering, status, copy, and link
/// consequences come from Bob's decoded slot.
public struct CaptureMoveChoiceState: Equatable, Sendable {
    public private(set) var slot: CaptureMoveChoiceSlot
    public private(set) var filterText = ""
    private var selectAllKeys: Set<String> = []
    public private(set) var cursor: Int
    public private(set) var answers: [String: CaptureMoveChoiceAnswer]

    public init(
        slot: CaptureMoveChoiceSlot,
        cursor: Int = 0,
        answers: [String: CaptureMoveChoiceAnswer] = [:]
    ) {
        self.slot = slot
        self.cursor = min(max(cursor, 0), max(slot.rows.count - 1, 0))
        var acceptedAnswers = answers
        for row in slot.rows where acceptedAnswers[row.key] == nil {
            if let answer = row.answer.flatMap(CaptureMoveChoiceAnswer.init(rawValue:)),
                row.choices.contains(where: { $0.sigil == answer.sigil })
            {
                acceptedAnswers[row.key] = answer
            }
        }
        self.answers = acceptedAnswers.filter { key, answer in
            guard let row = slot.rows.first(where: { $0.key == key }) else {
                return false
            }
            return row.choices.contains(where: { $0.sigil == answer.sigil })
        }
    }

    public var rows: [CaptureMoveChoiceRow] {
        slot.rows
    }

    public var currentRow: CaptureMoveChoiceRow? {
        guard rows.indices.contains(cursor),
            visibleRows.contains(where: { $0.key == rows[cursor].key })
        else {
            return nil
        }
        return rows[cursor]
    }

    public var selectedCount: Int {
        answers.count
    }

    public var linkedCount: Int {
        rows.filter { row in
            guard answers[row.key] == .moveAndLink else {
                return false
            }
            return row.choices.contains(where: { $0.sigil == ":" && $0.addsLink })
        }.count
    }

    public func markedCount(in section: CaptureMoveChoiceSection) -> Int {
        section.rows.filter { answers[$0.key] != nil }.count
    }

    public var canConfirm: Bool {
        selectedCount > 0 && nameRequirementMessage == nil
    }

    public var nameRequirementMessage: String? {
        guard slot.nameNeedsLink, !answers.values.contains(.moveAndLink) else { return nil }
        return
            "#\(slot.pomodoroName?.lowercased() ?? "name") needs a : pick, or remove #\(slot.pomodoroName?.lowercased() ?? "name")"
    }

    /// Opaque keys in Bob's parent order, never the highlight or filter order.
    public var selection: String {
        let keys = rows.compactMap { row -> String? in
            guard let answer = answers[row.key] else { return nil }
            return (answer == .moveAndLink ? ":" : "") + row.key
        }
        return keys.isEmpty ? "none" : keys.joined(separator: ",")
    }

    public var visibleRows: [CaptureMoveChoiceRow] {
        guard !filterText.isEmpty else { return rows }
        return rows.filter { row in
            [row.text, row.section ?? "", row.blockID ?? "", row.mint ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(filterText) }
        }
    }

    public var outsideFilterCount: Int {
        let visible = Set(visibleRows.map(\.key))
        return answers.keys.filter { !visible.contains($0) }.count
    }

    public mutating func updateFilter(_ text: String) {
        filterText = text
        if !visibleRows.contains(where: { $0.key == currentRow?.key }),
            let row = visibleRows.first
        {
            highlight(rowKey: row.key)
        }
    }

    /// Keep only surviving, still-enabled marks when Bob refreshes the parent.
    @discardableResult
    public mutating func reseed(slot: CaptureMoveChoiceSlot) -> Int {
        let oldAnswers = answers
        let oldKey = currentRow?.key
        let filter = filterText
        self = Self(slot: slot, answers: oldAnswers)
        updateFilter(filter)
        if let oldKey, visibleRows.contains(where: { $0.key == oldKey }) {
            highlight(rowKey: oldKey)
        }
        return oldAnswers.keys.filter { answers[$0] == nil }.count
    }

    public var counterText: String {
        guard selectedCount > 0 else {
            return "No tasks marked"
        }
        let linkText =
            linkedCount == 0
            ? ""
            : " · \(linkedCount) link\(linkedCount == 1 ? "" : "s") today"
        let outside =
            outsideFilterCount == 0
            ? "" : " · \(outsideFilterCount) marked outside this filter"
        return "\(selectedCount) move in\(linkText)\(outside)"
    }

    public var primaryLabel: String {
        guard canConfirm else {
            return "Mark tasks with ^ or :"
        }
        let linked = linkedCount == 0 ? "" : " · link \(linkedCount)"
        return "Move \(selectedCount)\(linked)"
    }

    public var sections: [CaptureMoveChoiceSection] {
        var order: [String] = []
        var rowsBySection: [String: [CaptureMoveChoiceRow]] = [:]
        for row in visibleRows {
            let section = row.section?.isEmpty == false ? row.section! : "Tasks"
            if rowsBySection[section] == nil {
                order.append(section)
                rowsBySection[section] = []
            }
            rowsBySection[section, default: []].append(row)
        }
        return order.map { section in
            CaptureMoveChoiceSection(
                id: section,
                title: section,
                rows: rowsBySection[section] ?? []
            )
        }
    }

    public func answer(for row: CaptureMoveChoiceRow) -> CaptureMoveChoiceAnswer? {
        answers[row.key]
    }

    public func consequence(for row: CaptureMoveChoiceRow) -> String {
        guard let answer = answer(for: row) else {
            return slot.copy?.leave ?? "Stays in \(slot.parent)"
        }
        return row.choices.first(where: { $0.sigil == answer.sigil })?.consequence
            ?? slot.copy?.leave
            ?? "Stays in \(slot.parent)"
    }

    /// Sets the current row's move or move-and-link answer and advances to
    /// the next row that Bob marked selectable. The highlighted row is never
    /// implicitly selected.
    @discardableResult
    public mutating func answerCurrent(_ answer: CaptureMoveChoiceAnswer) -> Bool {
        guard let row = currentRow, setAnswer(answer, for: row.key) else {
            return false
        }
        advanceToNextSelectable(after: cursor)
        return true
    }

    /// Sets or clears one row's explicit choice. A row without the requested
    /// Bob-returned choice cannot be marked.
    @discardableResult
    public mutating func setAnswer(
        _ answer: CaptureMoveChoiceAnswer?,
        for key: String
    ) -> Bool {
        guard let row = rows.first(where: { $0.key == key }) else {
            return false
        }
        selectAllKeys.remove(key)
        if let answer {
            guard row.choices.contains(where: { $0.sigil == answer.sigil }) else {
                return false
            }
            answers[key] = answer
        } else {
            answers.removeValue(forKey: key)
        }
        return true
    }

    public mutating func moveHighlight(by delta: Int) {
        let visible = visibleRows
        guard !visible.isEmpty, delta != 0 else { return }
        let index = visible.firstIndex(where: { $0.key == currentRow?.key }) ?? 0
        highlight(rowKey: visible[min(max(index + delta, 0), visible.count - 1)].key)
    }

    public mutating func highlight(rowKey: String) {
        guard let index = rows.firstIndex(where: { $0.key == rowKey }) else {
            return
        }
        cursor = index
    }

    /// Space toggles the current row between Leave and Move.
    @discardableResult
    public mutating func toggleCurrent() -> Bool {
        guard let row = currentRow else {
            return false
        }
        if answer(for: row) == nil {
            return setAnswer(.move, for: row.key)
        }
        return setAnswer(nil, for: row.key)
    }

    /// Marks every enabled and unlocked row as Move, keeping Bob's row order.
    public mutating func selectAll() {
        if !selectAllKeys.isEmpty {
            for key in selectAllKeys where answers[key] == .move {
                answers.removeValue(forKey: key)
            }
            selectAllKeys.removeAll()
            return
        }
        for row in visibleRows
        where answers[row.key] == nil && row.choices.contains(where: { $0.sigil == "^" }) {
            answers[row.key] = .move
            selectAllKeys.insert(row.key)
        }
    }

    public mutating func clearAnswers() {
        answers.removeAll()
        selectAllKeys.removeAll()
    }

    private mutating func advanceToNextSelectable(after index: Int) {
        guard rows.count > 1 else {
            return
        }
        for offset in 1..<rows.count {
            let candidate = (index + offset) % rows.count
            if visibleRows.contains(where: { $0.key == rows[candidate].key }),
                rows[candidate].choices.contains(where: { $0.sigil == "^" })
            {
                cursor = candidate
                return
            }
        }
    }
}

/// Bob-authored strings used by the Move card's title and context strip.
public enum CaptureMoveChoicePresentation {
    public static let oldBobWarning =
        "This bob predates - ^^; it would capture a task named ^^ · update bob"

    /// Only the compatibility warning inspects legacy text. Bob still owns grammar.
    public static func hasWholeLineMarker(_ draft: String) -> Bool {
        draft.split(separator: "\n").contains {
            guard let first = $0.first, "-*+".contains(first) else { return false }
            return ["- ^^", "* ^^", "+ ^^"].contains($0.trimmingCharacters(in: .whitespaces))
        }
    }

    public static func ghosts(
        draft: String, previewDraft: String, report: CaptureMoveChoice?
    ) -> [CaptureProjectNoteMoveGhost] {
        guard draft == previewDraft, report?.supported == true else { return [] }
        let bytes = Array(draft.utf8)
        return (report?.slots ?? []).compactMap { slot in
            guard slot.draftRange.count == 2, let ghost = slot.copy?.ghost, !ghost.isEmpty else {
                return nil
            }
            let start = slot.draftRange[0]
            let end = slot.draftRange[1]
            guard start >= 0, end > start, end <= bytes.count,
                String(decoding: bytes[start..<end], as: UTF8.self) == "^^"
            else { return nil }
            var lineEnd = end
            while lineEnd < bytes.count, bytes[lineEnd] != 10 { lineEnd += 1 }
            return CaptureProjectNoteMoveGhost(
                lineNumber: bytes[..<start].filter { $0 == 10 }.count + 1,
                insertionUTF8Offset: lineEnd, text: ghost, accessibilityText: ghost
            )
        }
    }

    public static func title(for slot: CaptureMoveChoiceSlot) -> String {
        if let title = nonempty(slot.copy?.title) {
            return title
        }
        return "Move into \(slot.destination)"
    }

    public static func subtitle(for slot: CaptureMoveChoiceSlot) -> String {
        if let subtitle = nonempty(slot.copy?.subtitle) {
            return subtitle
        }
        let count = slot.openCount
        return "from \(slot.parent) · \(count) open"
    }

    public static func rowIdentity(for row: CaptureMoveChoiceRow) -> String? {
        if let blockID = nonempty(row.blockID) {
            return "^\(blockID)"
        }
        if let mint = nonempty(row.mint) {
            return "⊕ ^\(mint)"
        }
        return nil
    }

    public static func statusGlyph(for row: CaptureMoveChoiceRow) -> String {
        CaptureProjectNoteMoveGlyph.text(for: row.statusSymbol)
    }

    public static func lockText(for row: CaptureMoveChoiceRow) -> String? {
        guard let lock = row.locked else {
            return nil
        }
        return "moving on line \(lock.itemLine)"
    }

    private static func nonempty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
}
