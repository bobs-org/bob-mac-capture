import Foundation

/// The Copy card's H layer: every copyable highlight and standalone
/// note, a selection, and a window of up to 9 rows that scrolls just
/// enough to keep the selection visible.
public struct RefsHighlightPicker: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let annotation: RefsShowAnnotation
        public let payload: String
        public let line1: String
        public let line2: String
        public let pageLabel: String?
        public let confirmationTitle: String

        public init(annotation: RefsShowAnnotation) {
            self.annotation = annotation
            payload = RefsCopyFormat.highlightBlock(annotation)
            pageLabel = RefsCopyFormat.shortPageLabel(annotation.displayPageLabel)
            if let pageLabel {
                confirmationTitle = "Copied Highlight · \(pageLabel)"
            } else {
                confirmationTitle = "Copied Highlight"
            }

            if annotation.isStandaloneNote {
                let commentLines = (annotation.comment ?? "").components(
                    separatedBy: "\n"
                )
                line1 = commentLines.first ?? ""
                line2 = commentLines.dropFirst().joined(separator: "\n")
            } else if annotation.hasComment {
                let commentFirst = annotation.comment?
                    .components(separatedBy: "\n").first ?? ""
                line1 = annotation.quote ?? ""
                line2 = "↳ \(commentFirst)"
            } else {
                let quoteLines = (annotation.quote ?? "").components(
                    separatedBy: "\n"
                )
                line1 = quoteLines.first ?? ""
                line2 = quoteLines.dropFirst().joined(separator: "\n")
            }
        }

        public func copyRow(key: RefsCopyKey) -> RefsCopyRow {
            RefsCopyRow(
                key: key,
                group: .notes,
                label: "Highlight",
                payload: .text(payload),
                preview: line1,
                truncation: .tail,
                detail: pageLabel,
                help: payload,
                confirmationTitle: confirmationTitle
            )
        }
    }

    public let entries: [Entry]
    public private(set) var selectedIndex: Int
    public private(set) var windowStart: Int
    public private(set) var windowSize: Int

    public init(entries: [Entry], selectedIndex: Int = 0, windowSize: Int) {
        self.entries = entries
        let clampedSize = Self.clampedWindowSize(windowSize, total: entries.count)
        self.windowSize = clampedSize
        if entries.isEmpty {
            self.selectedIndex = 0
        } else {
            self.selectedIndex = min(max(0, selectedIndex), entries.count - 1)
        }
        windowStart = 0
        revealSelection()
    }

    public static func entries(from row: RefsShowRow) -> [Entry] {
        row.highlightPickerEntries.map(Entry.init(annotation:))
    }

    public var windowEntries: ArraySlice<Entry> {
        guard !entries.isEmpty, windowSize > 0 else { return [] }
        let end = min(entries.count, windowStart + windowSize)
        return entries[windowStart..<end]
    }

    public var selectedEntry: Entry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    public mutating func move(_ delta: Int) {
        guard !entries.isEmpty, delta != 0 else { return }
        let count = entries.count
        selectedIndex = (selectedIndex + (delta % count) + count) % count
        revealSelection()
    }

    public mutating func selectWindowPosition(_ position: Int) -> Entry? {
        guard let entry = entry(atWindowPosition: position) else { return nil }
        selectedIndex = windowStart + position - 1
        return entry
    }

    public mutating func setWindowSize(_ size: Int) {
        windowSize = Self.clampedWindowSize(size, total: entries.count)
        revealSelection()
    }

    public func entry(atWindowPosition position: Int) -> Entry? {
        let index = windowStart + position - 1
        guard position >= 1,
              position <= windowSize,
              entries.indices.contains(index)
        else {
            return nil
        }
        return entries[index]
    }

    public func allHighlightsRow() -> RefsCopyRow {
        let count = entries.count
        let word = count == 1 ? "Highlight" : "Highlights"
        return RefsCopyRow(
            key: .allNotes,
            group: .notes,
            label: "All highlights",
            payload: .text(
                entries.map(\.payload).filter { !$0.isEmpty }.joined(
                    separator: "\n\n"
                )
            ),
            preview: "\(count) \(count == 1 ? "highlight" : "highlights")",
            truncation: .tail,
            confirmationTitle: "Copied \(count) \(word)"
        )
    }

    private mutating func revealSelection() {
        guard windowSize > 0, !entries.isEmpty else {
            windowStart = 0
            return
        }
        if selectedIndex < windowStart {
            windowStart = selectedIndex
        } else if selectedIndex >= windowStart + windowSize {
            windowStart = selectedIndex - windowSize + 1
        }
        let maxStart = max(0, entries.count - windowSize)
        windowStart = min(max(0, windowStart), maxStart)
    }

    private static func clampedWindowSize(_ size: Int, total: Int) -> Int {
        min(9, max(0, min(size, max(total, 0))))
    }
}
