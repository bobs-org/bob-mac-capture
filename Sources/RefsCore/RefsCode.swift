import CaptureCore
import Foundation

public enum RefsCodeStatus: Equatable, Sendable {
    case available
    case noCode
    case noCatalog
    case noSource
    case sourceMissing
    case sourceInvalid
    case unknown

    fileprivate init(rawValue: String) {
        switch rawValue {
        case "available": self = .available
        case "no_code": self = .noCode
        case "no_catalog": self = .noCatalog
        case "no_source": self = .noSource
        case "source_missing": self = .sourceMissing
        case "source_invalid": self = .sourceInvalid
        default: self = .unknown
        }
    }
}

public struct RefsCodeReference: Decodable, Equatable, Sendable {
    public let path: String
    public let title: String
    public let markerID: String?

    private enum CodingKeys: String, CodingKey {
        case path, title
        case markerID = "marker_id"
    }

    public init(path: String, title: String, markerID: String? = nil) {
        self.path = path
        self.title = title
        self.markerID = markerID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? values.decode(String.self, forKey: .path)) ?? ""
        title = (try? values.decode(String.self, forKey: .title)) ?? ""
        markerID = try? values.decodeIfPresent(String.self, forKey: .markerID)
    }
}

public struct RefsCodeSource: Decodable, Equatable, Sendable {
    public let path: String
    public let sha256: String?
    public let bytes: Int?
    public let captured: String?
    public let route: String?
    public let text: String?

    private enum CodingKeys: String, CodingKey {
        case path, sha256, bytes, captured, route, text
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? values.decode(String.self, forKey: .path)) ?? ""
        sha256 = try? values.decodeIfPresent(String.self, forKey: .sha256)
        bytes = try? values.decodeIfPresent(Int.self, forKey: .bytes)
        captured = try? values.decodeIfPresent(String.self, forKey: .captured)
        route = try? values.decodeIfPresent(String.self, forKey: .route)
        text = try? values.decodeIfPresent(String.self, forKey: .text)
    }
}

public struct RefsCodeSection: Decodable, Equatable, Sendable {
    public let number: String?
    public let title: String

    private enum CodingKeys: String, CodingKey { case number, title }

    public init(number: String? = nil, title: String) {
        self.number = number
        self.title = title
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        number = try? values.decodeIfPresent(String.self, forKey: .number)
        title = (try? values.decode(String.self, forKey: .title)) ?? ""
    }

    public var id: String {
        "\(number ?? "")\u{0}\(title)"
    }

    public var heading: String {
        guard let number, !number.isEmpty else { return title }
        return "\(number)  \(title)"
    }
}

public struct RefsCodeBlock: Decodable, Equatable, Sendable {
    public let id: String
    public let number: Int
    public let kind: String
    public let language: String?
    public let title: String?
    public let summary: String?
    public let caption: String?
    public let lines: Int
    public let bytes: Int
    public let text: String
    public let fenced: String
    public let section: RefsCodeSection?
    public let page: Int?
    public let pageEnd: Int?
    public let pageSource: String?

    private enum CodingKeys: String, CodingKey {
        case id, n, kind, lang, title, summary, caption, lines, bytes, text, fenced, section, page
        case pageEnd = "page_end"
        case pageSource = "page_source"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(String.self, forKey: .id)) ?? ""
        number = try values.decode(Int.self, forKey: .n)
        kind = (try? values.decode(String.self, forKey: .kind)) ?? "code"
        language = try? values.decodeIfPresent(String.self, forKey: .lang)
        title = try? values.decodeIfPresent(String.self, forKey: .title)
        summary = try? values.decodeIfPresent(String.self, forKey: .summary)
        caption = try? values.decodeIfPresent(String.self, forKey: .caption)
        text = try values.decode(String.self, forKey: .text)
        lines = max(0, (try? values.decode(Int.self, forKey: .lines)) ?? Self.lineCount(text))
        bytes = max(0, (try? values.decode(Int.self, forKey: .bytes)) ?? text.utf8.count)
        fenced = (try? values.decode(String.self, forKey: .fenced)) ?? Self.fence(text, language: language)
        section = try? values.decodeIfPresent(RefsCodeSection.self, forKey: .section)
        page = try? values.decodeIfPresent(Int.self, forKey: .page)
        pageEnd = try? values.decodeIfPresent(Int.self, forKey: .pageEnd)
        pageSource = try? values.decodeIfPresent(String.self, forKey: .pageSource)
    }

    public var displayLanguage: String {
        guard let language, !language.isEmpty else { return "text" }
        return language.lowercased()
    }

    public var pageRange: ClosedRange<Int>? {
        guard let page, page > 0 else { return nil }
        return page...max(page, pageEnd ?? page)
    }

    public func contains(page: Int) -> Bool {
        pageRange?.contains(page) == true
    }

    public var pageLabel: String? {
        guard let pageRange else { return nil }
        if pageRange.lowerBound == pageRange.upperBound {
            return "p. \(pageRange.lowerBound)"
        }
        return "pp. \(pageRange.lowerBound)–\(pageRange.upperBound)"
    }

    private static func lineCount(_ text: String) -> Int {
        text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
            - (text.hasSuffix("\n") ? 1 : 0)
    }

    private static func fence(_ text: String, language: String?) -> String {
        var maxTicks = 0
        var currentTicks = 0
        for character in text {
            if character == "`" {
                currentTicks += 1
                maxTicks = max(maxTicks, currentTicks)
            } else {
                currentTicks = 0
            }
        }
        let ticks = String(repeating: "`", count: max(3, maxTicks + 1))
        return "\(ticks)\(language ?? "")\n\(text)\n\(ticks)\n"
    }
}

private struct LossyRefsCodeBlock: Decodable {
    let block: RefsCodeBlock?

    init(from decoder: Decoder) throws {
        block = try? RefsCodeBlock(from: decoder)
    }
}

public struct RefsCodeResponse: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String?
    public let reference: RefsCodeReference
    public let status: RefsCodeStatus
    public let detail: String?
    public let source: RefsCodeSource?
    public let blocks: [RefsCodeBlock]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case reference, status, detail, source, blocks
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? values.decode(Int.self, forKey: .schemaVersion)) ?? 1
        generatedAt = try? values.decodeIfPresent(String.self, forKey: .generatedAt)
        reference = (try? values.decode(RefsCodeReference.self, forKey: .reference))
            ?? RefsCodeReference(path: "", title: "", markerID: nil)
        let rawStatus = (try? values.decode(String.self, forKey: .status)) ?? "unknown"
        status = RefsCodeStatus(rawValue: rawStatus)
        detail = try? values.decodeIfPresent(String.self, forKey: .detail)
        source = try? values.decodeIfPresent(RefsCodeSource.self, forKey: .source)
        let decodedBlocks = (try? values.decode([LossyRefsCodeBlock].self, forKey: .blocks)) ?? []
        blocks = decodedBlocks.compactMap(\.block)
    }

}

extension RefsCodeResponse: SchemaVersioned {}

public enum RefsCodeLoadState: Equatable, Sendable {
    case notRequested
    case loading
    case loaded(RefsCodeResponse)
    case unsupported
    case failed
}

public struct RefsCodePicker: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, RefsSectionedWindowEntry {
        public let block: RefsCodeBlock
        public let pageIsKnown: Bool
        public let isOnPage: Bool
        public let sectionedWindowGroupID: String?
        public let sectionedWindowGroupTitle: String?

        fileprivate init(block: RefsCodeBlock, highlightedPage: Int?) {
            self.block = block
            pageIsKnown = highlightedPage != nil
            isOnPage = highlightedPage.map(block.contains(page:)) ?? false
            sectionedWindowGroupID = block.section?.id
            sectionedWindowGroupTitle = block.section?.heading
        }

        public var language: String { block.displayLanguage }
        public var summary: String { block.summary ?? "(empty block)" }
        public var caption: String { block.caption ?? "" }
        public var pageLabel: String? { block.pageLabel }
        public var lineCount: Int { block.lines }

        public func copyRow(fenced: Bool) -> RefsCopyRow {
            let language = block.displayLanguage
            let confirmation: String
            if block.kind == "mermaid" {
                confirmation = "Copied Mermaid source"
            } else if fenced {
                confirmation = "Copied \(language) · fenced"
            } else {
                confirmation = "Copied \(language) · \(block.lines) lines"
            }
            return RefsCopyRow(
                key: .codePicker,
                group: .contents,
                label: "Code block \(block.number)",
                payload: .text(fenced ? block.fenced : block.text),
                preview: summary,
                truncation: .tail,
                detail: block.pageLabel,
                help: fenced ? block.fenced : block.text,
                confirmationTitle: confirmation
            )
        }
    }

    public typealias WindowRow = RefsSectionedWindow<Entry>.Row

    public let entries: [Entry]
    public let highlightedPage: Int?
    private var sectionedWindow: RefsSectionedWindow<Entry>
    public var selectedIndex: Int { sectionedWindow.selectedIndex }
    public var windowStart: Int { sectionedWindow.windowStart }
    public var windowSize: Int { sectionedWindow.windowSize }
    public var budgetWindowSize: Int { sectionedWindow.budgetWindowSize }
    public var windowRows: [WindowRow] { sectionedWindow.windowRows }
    public var windowEntries: ArraySlice<Entry> { sectionedWindow.windowEntries }
    public var selectedEntry: Entry? { sectionedWindow.selectedEntry }

    public init(
        blocks: [RefsCodeBlock],
        highlightedPage: Int? = nil,
        windowSize: Int = 9,
        groupHeaderHeight: Double = 22,
        entryRowHeight: Double = 36
    ) {
        entries = blocks.map { Entry(block: $0, highlightedPage: highlightedPage) }
        self.highlightedPage = highlightedPage
        let selectedIndex = Self.initialSelection(in: blocks, page: highlightedPage)
        sectionedWindow = RefsSectionedWindow(
            entries: entries,
            selectedIndex: selectedIndex,
            windowStart: selectedIndex,
            windowSize: windowSize,
            groupHeaderHeight: groupHeaderHeight,
            entryRowHeight: entryRowHeight
        )
    }

    public static func initialSelection(in blocks: [RefsCodeBlock], page: Int?) -> Int {
        guard !blocks.isEmpty else { return 0 }
        guard let page, page > 0 else { return 0 }
        if let containing = blocks.firstIndex(where: { $0.contains(page: page) }) {
            return containing
        }
        if let following = blocks.firstIndex(where: { block in
            guard let blockPage = block.page else { return false }
            return blockPage > page
        }) {
            return following
        }
        if let preceding = blocks.lastIndex(where: { block in
            guard let blockPage = block.page else { return false }
            return blockPage <= page
        }) {
            return preceding
        }
        return 0
    }

    public var pageBlockCount: Int {
        guard let highlightedPage else { return 0 }
        return entries.filter { $0.block.contains(page: highlightedPage) }.count
    }

    public mutating func move(_ delta: Int) { sectionedWindow.move(delta) }

    @discardableResult
    public mutating func selectWindowPosition(_ position: Int) -> Entry? {
        sectionedWindow.selectWindowPosition(position)
    }

    public mutating func setWindowSize(_ size: Int) {
        sectionedWindow.setWindowSize(size)
    }

    public mutating func setMetrics(groupHeaderHeight: Double, entryRowHeight: Double) {
        sectionedWindow.groupHeaderHeight = groupHeaderHeight
        sectionedWindow.entryRowHeight = entryRowHeight
    }

    public func entry(atWindowPosition position: Int) -> Entry? {
        sectionedWindow.entry(atWindowPosition: position)
    }
}

public struct RefsCodePreviewLine: Equatable, Sendable {
    public let text: String
    public let isFence: Bool
    public let wasTruncated: Bool

    public init(text: String, isFence: Bool = false, wasTruncated: Bool = false) {
        self.text = text
        self.isFence = isFence
        self.wasTruncated = wasTruncated
    }
}

/// Presentation-only code for the preview well. Copy payloads remain the
/// original `text` and `fenced` strings on `RefsCodeBlock`.
public struct RefsCodePreviewWell: Equatable, Sendable {
    public static let maximumSourceLines = 200
    public static let maximumCharactersPerLine = 400
    public static let tabStop = 4

    public let language: String
    public let sectionTitle: String?
    public let lineCount: Int
    public let pageLabel: String?
    public let fenced: Bool
    public let lines: [RefsCodePreviewLine]
    public let overflowLineCount: Int

    public init(block: RefsCodeBlock, fenced: Bool, visibleLineCount: Int) {
        language = block.displayLanguage
        sectionTitle = block.section?.title
        lineCount = block.lines
        pageLabel = block.pageLabel
        self.fenced = fenced

        let sourceLines = Self.sourceLines(block: block, fenced: fenced)
        let capped = Array(sourceLines.prefix(Self.maximumSourceLines))
        let visible = Array(capped.prefix(max(0, visibleLineCount)))
        lines = visible.map { raw, isFence in
            let trimmed = Self.truncate(raw)
            return RefsCodePreviewLine(
                text: Self.drawTabs(trimmed.text),
                isFence: isFence,
                wasTruncated: trimmed.truncated
            )
        }
        overflowLineCount = max(0, sourceLines.count - visible.count)
    }

    private static func sourceLines(block: RefsCodeBlock, fenced: Bool) -> [(String, Bool)] {
        let source = fenced ? block.fenced : block.text
        var lines = source.components(separatedBy: "\n")
        if source.hasSuffix("\n") { lines.removeLast() }
        guard fenced, !lines.isEmpty else { return lines.map { ($0, false) } }
        return lines.enumerated().map { index, line in
            (line, index == 0 || index == lines.count - 1)
        }
    }

    private static func truncate(_ line: String) -> (text: String, truncated: Bool) {
        let characters = Array(line)
        guard characters.count > maximumCharactersPerLine else { return (line, false) }
        return (String(characters.prefix(maximumCharactersPerLine - 1)) + "…", true)
    }

    private static func drawTabs(_ line: String) -> String {
        var output = ""
        var column = 0
        for character in line {
            if character == "\t" {
                output.append("→")
                column += 1
                let spaces = tabStop - (column % tabStop)
                output += String(repeating: " ", count: spaces)
                column += spaces
            } else {
                output.append(character)
                column += 1
            }
        }
        return output
    }
}

public struct RefsCodePreviewWellLayout: Equatable, Sendable {
    public let height: Double
    public let visibleCodeLines: Int
    public let pickerWindowSize: Int

    public static func make(
        availableHeightUnderHeader: Double,
        codeLineHeight: Double = 16,
        headerHeight: Double = 18,
        entryRowHeight: Double = 36
    ) -> Self {
        let available = max(0, availableHeightUnderHeader)
        let lineHeight = max(1, codeLineHeight)
        let wellHeader = max(0, headerHeight)
        let minHeight = 6 * lineHeight + wellHeader
        let maxHeight = 18 * lineHeight + wellHeader
        let height = min(max(available * 0.45, minHeight), maxHeight)
        let visibleLines = min(18, max(6, Int(floor((height - wellHeader) / lineHeight))))
        let rows = entryRowHeight > 0
            ? Int(floor(max(0, available - height) / entryRowHeight))
            : 2
        return Self(
            height: height,
            visibleCodeLines: visibleLines,
            pickerWindowSize: min(9, max(2, rows))
        )
    }
}

