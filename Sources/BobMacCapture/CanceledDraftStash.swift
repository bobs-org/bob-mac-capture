import Combine
import Foundation

struct CanceledDraftEntry: Identifiable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
}

@MainActor
final class CanceledDraftStash: ObservableObject {
    nonisolated static let defaultCapacity = 10
    nonisolated static let maximumCapacity = 36

    @Published private(set) var capacity: Int
    @Published private(set) var entries: [CanceledDraftEntry] = []

    private let now: () -> Date
    private let idGenerator: () -> UUID

    init(
        capacity: Int = CanceledDraftStash.defaultCapacity,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.capacity = Self.clampedCapacity(capacity)
        self.now = now
        self.idGenerator = idGenerator
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    var count: Int {
        entries.count
    }

    @discardableResult
    func push(_ text: String) -> CanceledDraftEntry? {
        guard capacity > 0 else {
            return nil
        }

        let entry = CanceledDraftEntry(id: idGenerator(), text: text, createdAt: now())
        entries.insert(entry, at: 0)
        trimToCapacity()
        return entry
    }

    func updateCapacity(_ newCapacity: Int) {
        capacity = Self.clampedCapacity(newCapacity)
        trimToCapacity()
    }

    func clear() {
        entries.removeAll()
    }

    func entry(id: UUID) -> CanceledDraftEntry? {
        entries.first { $0.id == id }
    }

    func entry(at index: Int) -> CanceledDraftEntry? {
        guard entries.indices.contains(index) else {
            return nil
        }
        return entries[index]
    }

    @discardableResult
    func remove(id: UUID) -> CanceledDraftEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return entries.remove(at: index)
    }

    func clampedSelectionIndex(_ index: Int) -> Int {
        guard !entries.isEmpty else {
            return 0
        }
        return min(max(index, 0), entries.count - 1)
    }

    func nextSelectionIndex(after index: Int) -> Int {
        guard !entries.isEmpty else {
            return 0
        }
        return (clampedSelectionIndex(index) + 1) % entries.count
    }

    func previousSelectionIndex(before index: Int) -> Int {
        guard !entries.isEmpty else {
            return 0
        }
        return (clampedSelectionIndex(index) + entries.count - 1) % entries.count
    }

    nonisolated static func clampedCapacity(_ capacity: Int) -> Int {
        min(max(capacity, 0), maximumCapacity)
    }

    nonisolated static func accelerator(for index: Int) -> String? {
        guard acceleratorKeys.indices.contains(index) else {
            return nil
        }
        return acceleratorKeys[index]
    }

    nonisolated static func acceleratorIndex(for characters: String, entryCount: Int) -> Int? {
        let scalars = Array(characters.unicodeScalars)
        guard scalars.count == 1 else {
            return nil
        }

        let key = String(scalars[0]).uppercased()
        guard let index = acceleratorKeys.firstIndex(of: key),
              index < min(entryCount, maximumCapacity)
        else {
            return nil
        }
        return index
    }

    nonisolated static func previewLine(for text: String, maxCharacters: Int = 80) -> String {
        let fallback = "Whitespace only draft"
        let line = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallback

        guard maxCharacters > 0 else {
            return ""
        }
        guard line.count > maxCharacters else {
            return line
        }
        guard maxCharacters > 3 else {
            return String(line.prefix(maxCharacters))
        }

        let visibleCount = maxCharacters - 3
        let endIndex = line.index(line.startIndex, offsetBy: visibleCount)
        return String(line[..<endIndex]) + "..."
    }

    nonisolated static func lineCount(for text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }

        var count = 1
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            if scalar.value == 13 {
                count += 1
                previousWasCarriageReturn = true
            } else if scalar.value == 10 {
                if !previousWasCarriageReturn {
                    count += 1
                }
                previousWasCarriageReturn = false
            } else {
                previousWasCarriageReturn = false
            }
        }
        return count
    }

    nonisolated static func metadataDescription(for entry: CanceledDraftEntry, now: Date = Date()) -> String {
        let lines = lineCount(for: entry.text)
        return "\(lines) \(lines == 1 ? "line" : "lines") - \(relativeAgeDescription(from: entry.createdAt, to: now))"
    }

    nonisolated static func relativeAgeDescription(from start: Date, to end: Date = Date()) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3_600 {
            return "\(seconds / 60)m ago"
        }
        if seconds < 86_400 {
            return "\(seconds / 3_600)h ago"
        }
        return "\(seconds / 86_400)d ago"
    }

    private func trimToCapacity() {
        guard capacity > 0 else {
            clear()
            return
        }
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    private nonisolated static let acceleratorKeys: [String] = Array("1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
}
