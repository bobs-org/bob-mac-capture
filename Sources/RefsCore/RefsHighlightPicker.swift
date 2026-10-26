import Foundation

/// The Copy card's H layer: every copyable highlight and standalone
/// note, a selection, and a window of up to 9 rows that scrolls just
/// enough to keep the selection visible.
public struct RefsHighlightPicker: Equatable, Sendable {
    /// Sentinel group id for the ungrouped tail when sections exist.
    public static let otherGroupID = "\u{0}other"

    public struct Entry: Equatable, Sendable, RefsSectionedWindowEntry {
        public let annotation: RefsShowAnnotation
        public let payload: String
        public let line1: String
        public let line2: String
        public let pageLabel: String?
        public let confirmationTitle: String
        /// Section id, `otherGroupID`, or nil when the picker is unsectioned.
        public let groupID: String?
        public let groupTitle: String?

        public var sectionedWindowGroupID: String? { groupID }
        public var sectionedWindowGroupTitle: String? { groupTitle }

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

    public typealias WindowRow = RefsSectionedWindow<Entry>.Row

    public let entries: [Entry]
    private var sectionedWindow: RefsSectionedWindow<Entry>
    public var selectedIndex: Int { sectionedWindow.selectedIndex }
    public var windowStart: Int { sectionedWindow.windowStart }
    public var windowSize: Int { sectionedWindow.windowSize }
    /// Unsectioned row budget from the card layout. Sectioned windows
    /// shrink so group headers still fit this many entry-row heights.
    public var budgetWindowSize: Int { sectionedWindow.budgetWindowSize }
    public var groupHeaderHeight: Double {
        didSet { sectionedWindow.groupHeaderHeight = max(0, groupHeaderHeight) }
    }
    public var entryRowHeight: Double {
        didSet { sectionedWindow.entryRowHeight = max(0, entryRowHeight) }
    }

    public init(
        entries: [Entry],
        selectedIndex: Int = 0,
        windowSize: Int,
        groupHeaderHeight: Double = 0,
        entryRowHeight: Double = 36
    ) {
        self.entries = entries
        self.groupHeaderHeight = max(0, groupHeaderHeight)
        self.entryRowHeight = max(0, entryRowHeight)
        sectionedWindow = RefsSectionedWindow(
            entries: entries,
            selectedIndex: selectedIndex,
            windowSize: windowSize,
            groupHeaderHeight: groupHeaderHeight,
            entryRowHeight: entryRowHeight
        )
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

    public var hasGroups: Bool { sectionedWindow.hasGroups }

    /// Visible picker rows, including non-selectable group headers.
    /// A window that starts mid-group keeps that group's title at the
    /// top; group starts inside the window emit their own header.
    public var windowRows: [WindowRow] { sectionedWindow.windowRows }

    public var windowEntries: ArraySlice<Entry> { sectionedWindow.windowEntries }

    public var selectedEntry: Entry? { sectionedWindow.selectedEntry }

    public mutating func move(_ delta: Int) {
        sectionedWindow.move(delta)
    }

    public mutating func selectWindowPosition(_ position: Int) -> Entry? {
        sectionedWindow.selectWindowPosition(position)
    }

    public mutating func setWindowSize(_ size: Int) {
        sectionedWindow.setWindowSize(size)
    }

    public func entry(atWindowPosition position: Int) -> Entry? {
        sectionedWindow.entry(atWindowPosition: position)
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

}
