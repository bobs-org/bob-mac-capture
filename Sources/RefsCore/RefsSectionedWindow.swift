import Foundation

/// Metadata required by pickers that share a section-aware scrolling window.
public protocol RefsSectionedWindowEntry: Equatable, Sendable {
    var sectionedWindowGroupID: String? { get }
    var sectionedWindowGroupTitle: String? { get }
}

/// Selects entries while keeping section headers inside a fixed row-height
/// budget. Selection and visible digit positions always refer to entries;
/// group rows are presentation-only.
public struct RefsSectionedWindow<Entry: RefsSectionedWindowEntry>: Equatable, Sendable {
    public enum Row: Equatable, Sendable {
        case group(title: String)
        case entry(windowPosition: Int, entry: Entry)
    }

    public let entries: [Entry]
    public private(set) var selectedIndex: Int
    public private(set) var windowStart: Int
    public private(set) var windowSize: Int
    /// The row budget before section headers consume any of its height.
    public private(set) var budgetWindowSize: Int
    public var groupHeaderHeight: Double {
        didSet { fitWindow() }
    }
    public var entryRowHeight: Double {
        didSet { fitWindow() }
    }

    public init(
        entries: [Entry],
        selectedIndex: Int = 0,
        windowStart: Int = 0,
        windowSize: Int,
        groupHeaderHeight: Double = 0,
        entryRowHeight: Double = 36
    ) {
        self.entries = entries
        self.groupHeaderHeight = max(0, groupHeaderHeight)
        self.entryRowHeight = max(0, entryRowHeight)
        budgetWindowSize = Self.clampedBudget(windowSize)
        self.selectedIndex = entries.isEmpty
            ? 0
            : min(max(0, selectedIndex), entries.count - 1)
        let initialWindowSize = entries.isEmpty
            ? 0
            : Self.clampedWindowSize(windowSize, total: entries.count)
        self.windowSize = initialWindowSize
        self.windowStart = min(
            max(0, windowStart),
            max(0, entries.count - initialWindowSize)
        )
        fitWindow()
    }

    public var hasGroups: Bool {
        entries.contains { $0.sectionedWindowGroupID != nil }
    }

    /// Visible rows with context headers repeated when the window begins in
    /// the middle of a section. Header rows never consume a digit position.
    public var windowRows: [Row] {
        guard !windowEntries.isEmpty else { return [] }
        var rows: [Row] = []
        let firstIndex = windowStart
        if hasGroups,
           let title = entries[firstIndex].sectionedWindowGroupTitle,
           !isGroupStart(firstIndex)
        {
            rows.append(.group(title: title))
        }
        for (offset, entry) in windowEntries.enumerated() {
            let index = windowStart + offset
            if hasGroups,
               isGroupStart(index),
               let title = entry.sectionedWindowGroupTitle
            {
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

    @discardableResult
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
            if !overflowsCurrentWindow() { return }
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
        var count = 0
        var previousGroupID: String?
        for index in start..<end {
            if let id = entries[index].sectionedWindowGroupID {
                if id != previousGroupID { count += 1 }
            }
            previousGroupID = entries[index].sectionedWindowGroupID
        }
        return count
    }

    private func isGroupStart(_ index: Int) -> Bool {
        guard entries.indices.contains(index),
              entries[index].sectionedWindowGroupID != nil
        else {
            return false
        }
        if index == 0 { return true }
        return entries[index].sectionedWindowGroupID
            != entries[index - 1].sectionedWindowGroupID
    }

    private static func clampedBudget(_ size: Int) -> Int {
        min(9, max(0, size))
    }

    private static func clampedWindowSize(_ size: Int, total: Int) -> Int {
        min(clampedBudget(size), max(total, 0))
    }
}
