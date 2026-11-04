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
    public let slot: CaptureMoveChoiceSlot
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
        guard rows.indices.contains(cursor) else {
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
        selectedCount > 0
    }

    public var counterText: String {
        guard selectedCount > 0 else {
            return "No tasks marked"
        }
        let linkText =
            linkedCount == 0
            ? ""
            : " · \(linkedCount) link\(linkedCount == 1 ? "" : "s") today"
        return "\(selectedCount) move in\(linkText)"
    }

    public var primaryLabel: String {
        guard canConfirm else {
            return "Move"
        }
        let linked = linkedCount == 0 ? "" : " · link \(linkedCount)"
        return "Move \(selectedCount)\(linked)"
    }

    public var sections: [CaptureMoveChoiceSection] {
        var order: [String] = []
        var rowsBySection: [String: [CaptureMoveChoiceRow]] = [:]
        for row in rows {
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
        guard !rows.isEmpty, delta != 0 else {
            return
        }
        cursor = (cursor + delta % rows.count + rows.count) % rows.count
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
        for row in rows where row.choices.contains(where: { $0.sigil == "^" }) {
            answers[row.key] = .move
        }
    }

    public mutating func clearAnswers() {
        answers.removeAll()
    }

    private mutating func advanceToNextSelectable(after index: Int) {
        guard rows.count > 1 else {
            return
        }
        for offset in 1..<rows.count {
            let candidate = (index + offset) % rows.count
            if rows[candidate].choices.contains(where: { $0.sigil == "^" }) {
                cursor = candidate
                return
            }
        }
    }
}

/// Bob-authored strings used by the Move card's title and context strip.
public enum CaptureMoveChoicePresentation {
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
