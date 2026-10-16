import CaptureCore
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

  private let store: CanceledDraftStashStoring?
  private let now: () -> Date
  private let idGenerator: () -> UUID

  init(
    capacity: Int = CanceledDraftStash.defaultCapacity,
    store: CanceledDraftStashStoring? = nil,
    now: @escaping () -> Date = Date.init,
    idGenerator: @escaping () -> UUID = UUID.init
  ) {
    self.capacity = Self.clampedCapacity(capacity)
    self.store = store
    self.now = now
    self.idGenerator = idGenerator

    if self.capacity == 0 {
      store?.save([])
      return
    }

    guard let store else {
      return
    }

    entries = store.load().map(Self.entry(from:))
    let loadedCount = entries.count
    trimToCapacity()
    if entries.count != loadedCount {
      persist()
    }
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
    persist()
    return entry
  }

  func updateCapacity(_ newCapacity: Int) {
    capacity = Self.clampedCapacity(newCapacity)
    trimToCapacity()
    persist()
  }

  func clear() {
    entries.removeAll()
    persist()
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
    let removed = entries.remove(at: index)
    persist()
    return removed
  }

  func clampedSelectionIndex(_ index: Int) -> Int {
    CapturePickerHelpers.clampedSelectionIndex(index, entryCount: entries.count)
  }

  func nextSelectionIndex(after index: Int) -> Int {
    CapturePickerHelpers.nextSelectionIndex(after: index, entryCount: entries.count)
  }

  func previousSelectionIndex(before index: Int) -> Int {
    CapturePickerHelpers.previousSelectionIndex(before: index, entryCount: entries.count)
  }

  nonisolated static func clampedCapacity(_ capacity: Int) -> Int {
    min(max(capacity, 0), maximumCapacity)
  }

  nonisolated static func accelerator(for index: Int) -> String? {
    CapturePickerHelpers.accelerator(for: index)
  }

  nonisolated static func acceleratorIndex(for characters: String, entryCount: Int) -> Int? {
    CapturePickerHelpers.acceleratorIndex(for: characters, entryCount: entryCount)
  }

  nonisolated static func previewLine(for text: String, maxCharacters: Int = 80) -> String {
    let fallback = "Whitespace only draft"
    let line =
      text
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

  nonisolated static func metadataDescription(for entry: CanceledDraftEntry, now: Date = Date())
    -> String
  {
    let lines = lineCount(for: entry.text)
    return
      "\(lines) \(lines == 1 ? "line" : "lines") - \(relativeAgeDescription(from: entry.createdAt, to: now))"
  }

  nonisolated static func relativeAgeDescription(from start: Date, to end: Date = Date()) -> String
  {
    CapturePickerHelpers.relativeAgeDescription(from: start, to: end)
  }

  private func persist() {
    store?.save(entries.map(Self.persisted(from:)))
  }

  private func trimToCapacity() {
    guard capacity > 0 else {
      entries.removeAll()
      return
    }
    if entries.count > capacity {
      entries.removeLast(entries.count - capacity)
    }
  }

  private static func entry(from draft: PersistedCanceledDraft) -> CanceledDraftEntry {
    CanceledDraftEntry(id: draft.id, text: draft.text, createdAt: draft.createdAt)
  }

  private static func persisted(from entry: CanceledDraftEntry) -> PersistedCanceledDraft {
    PersistedCanceledDraft(id: entry.id, text: entry.text, createdAt: entry.createdAt)
  }

}
