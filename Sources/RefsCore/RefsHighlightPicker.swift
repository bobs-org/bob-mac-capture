import Foundation

/// The Copy card's H layer: every copyable highlight and standalone
/// note, a selection, and a window of up to 9 rows that scrolls just
/// enough to keep the selection visible.
public struct RefsHighlightPicker: Equatable, Sendable {
    /// Sentinel group id for the ungrouped tail when sections exist.
    public static let otherGroupID = "\u{0}other"

    public struct Entry: Equatable, Sendable {
        public let annotation: RefsShowAnnotation
        public let payload: String
        public let line1: String
        public let line2: String
        public let pageLabel: String?
        public let confirmationTitle: String
        /// Section id, `otherGroupID`, or nil when the picker is unsectioned.
        public let groupID: String?
        public let groupTitle: String?

        public init(annotation: RefsShowAnnotation, groupID: String? = nil, groupTitle: String? = nil) {
            self.annotation = annotation
            payload = RefsCopyFormat.highlightBlock(annotation)
            pageLabel = RefsCopyFormat.shortPageLabel(annotation.displayPageLabel)
            if let pageLabel {
                confirmationTitle = "Copied Highlight · \(pageLabel)"
            } else {
                confirmationTitle = "Copied Highlight"
            }
            self.groupID = groupID
            self.groupTitle = groupTitle

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
                confirmationTitle: confirmationTitle,
                alternate: RefsCopyFormat.quoteAlternate(annotation)
            )
        }
    }

    public enum WindowRow: Equatable, Sendable {
        case group(title: String)
        case entry(windowPosition: Int, entry: Entry)
    }

    public let entries: [Entry]
    public private(set) var selectedIndex: Int
    public private(set) var windowStart: Int
    public private(set) var windowSize: Int
    /// Unsectioned row budget from the card layout. Sectioned windows
    /// shrink so group headers still fit this many entry-row heights.
    public private(set) var budgetWindowSize: Int
    public var groupHeaderHeight: Double
    public var entryRowHeight: Double

    public init(
        entries: [Entry],
        selectedIndex: Int = 0,
        windowSize: Int,
        groupHeaderHeight: Double = 0,
        entryRowHeight: Double = 36
    ) {
        self.entries = entries
        self.groupHeaderHeight = groupHeaderHeight
        self.entryRowHeight = entryRowHeight
        // Card row capacity, not entry count: headers may use leftover
        // height when the card is taller than the list.
        budgetWindowSize = Self.clampedBudget(windowSize)
        if entries.isEmpty {
            self.selectedIndex = 0
            self.windowSize = 0
        } else {
            self.selectedIndex = min(max(0, selectedIndex), entries.count - 1)
            self.windowSize = Self.clampedWindowSize(
                budgetWindowSize, total: entries.count
            )
        }
        windowStart = 0
        fitWindow()
    }

    public static func entries(from row: RefsShowRow) -> [Entry] {
        let sections = row.sections
        let ids = Set(sections.compactMap(\.usableID))
        let titles = Dictionary(
            uniqueKeysWithValues: sections.compactMap { section -> (String, String)? in
                guard let id = section.usableID else { return nil }
                return (id, section.title)
            }
        )
        let grouped = !sections.isEmpty
        return row.highlightPickerEntries.map { annotation in
            guard grouped else {
                return Entry(annotation: annotation)
            }
            if let id = annotation.section, ids.contains(id) {
                return Entry(
                    annotation: annotation,
                    groupID: id,
                    groupTitle: titles[id]
                )
            }
            return Entry(
                annotation: annotation,
                groupID: otherGroupID,
                groupTitle: "Other highlights"
            )
        }
    }

    public var hasGroups: Bool {
        entries.contains { $0.groupID != nil }
    }

    /// Visible picker rows, including non-selectable group headers.
    /// A window that starts mid-group keeps that group's title at the
    /// top; group starts inside the window emit their own header.
    public var windowRows: [WindowRow] {
        let slice = windowEntries
        guard !slice.isEmpty else { return [] }
        var rows: [WindowRow] = []
        if hasGroups {
            let first = entries[windowStart]
            if !isGroupStart(windowStart), let title = first.groupTitle {
                rows.append(.group(title: title))
            }
        }
        for (offset, entry) in slice.enumerated() {
            let index = windowStart + offset
            if hasGroups, isGroupStart(index), let title = entry.groupTitle {
                rows.append(.group(title: title))
            }
            rows.append(.entry(windowPosition: offset + 1, entry: entry))
        }
        return rows
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
        fitWindow()
    }

    public mutating func selectWindowPosition(_ position: Int) -> Entry? {
        guard let entry = entry(atWindowPosition: position) else { return nil }
        selectedIndex = windowStart + position - 1
        return entry
    }

    public mutating func setWindowSize(_ size: Int) {
        budgetWindowSize = Self.clampedBudget(size)
        fitWindow()
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

    private mutating func fitWindow() {
        guard !entries.isEmpty else {
            windowSize = 0
            windowStart = 0
            return
        }
        var size = max(1, min(budgetWindowSize, entries.count))
        while size > 1 {
            windowSize = size
            revealSelection()
            if !overflowsCurrentWindow() {
                return
            }
            size -= 1
        }
        windowSize = 1
        revealSelection()
    }

    private func overflowsCurrentWindow() -> Bool {
        guard hasGroups, groupHeaderHeight > 0, entryRowHeight > 0 else {
            return false
        }
        let visible = min(windowSize, max(0, entries.count - windowStart))
        let headers = headerCount(start: windowStart, size: visible)
        let used = Double(visible) * entryRowHeight
            + Double(headers) * groupHeaderHeight
        let budget = Double(max(1, budgetWindowSize)) * entryRowHeight
        return used > budget
    }

    private func headerCount(start: Int, size: Int) -> Int {
        let end = min(entries.count, start + max(0, size))
        guard start < end else { return 0 }
        var groups = Set<String>()
        for index in start..<end {
            groups.insert(entries[index].groupID ?? "")
        }
        return groups.count
    }

    private func isGroupStart(_ index: Int) -> Bool {
        guard entries.indices.contains(index) else { return false }
        if index == 0 { return true }
        return entries[index].groupID != entries[index - 1].groupID
    }

    private static func clampedBudget(_ size: Int) -> Int {
        min(9, max(0, size))
    }

    private static func clampedWindowSize(_ size: Int, total: Int) -> Int {
        min(clampedBudget(size), max(total, 0))
    }
}
