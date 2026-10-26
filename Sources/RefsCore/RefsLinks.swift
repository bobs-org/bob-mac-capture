import CaptureCore
import Foundation

public enum RefsLinksStatus: Equatable, Sendable {
    case available
    case noLinks
    case notRecorded
    case noCatalog
    case noSource
    case sourceMissing
    case sourceInvalid
    case unknown

    fileprivate init(rawValue: String) {
        switch rawValue {
        case "available": self = .available
        case "no_links": self = .noLinks
        case "not_recorded": self = .notRecorded
        case "no_catalog": self = .noCatalog
        case "no_source": self = .noSource
        case "source_missing": self = .sourceMissing
        case "source_invalid": self = .sourceInvalid
        default: self = .unknown
        }
    }
}

public enum RefsLinkLabelKind: Equatable, Sendable {
    case text
    case context
    case url
    case unknown

    fileprivate init(rawValue: String?) {
        switch rawValue {
        case "text": self = .text
        case "context": self = .context
        case "url": self = .url
        case nil: self = .text
        default: self = .unknown
        }
    }
}

public struct RefsLinksSource: Decodable, Equatable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? values.decode(String.self, forKey: .path)) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case path }
}

public struct RefsLink: Decodable, Equatable, Sendable {
    public let id: String
    public let number: Int
    public let url: String
    public let text: String
    public let title: String?
    public let autolink: Bool
    public let label: String
    public let labelKind: RefsLinkLabelKind
    public let context: String?
    public let site: String
    public let markdown: String
    public let section: RefsCodeSection?
    public let page: Int?
    public let pageSource: String?

    public init(
        id: String = "",
        number: Int,
        url: String,
        text: String = "",
        title: String? = nil,
        autolink: Bool = false,
        label: String,
        labelKind: RefsLinkLabelKind = .text,
        context: String? = nil,
        site: String,
        markdown: String? = nil,
        section: RefsCodeSection? = nil,
        page: Int? = nil,
        pageSource: String? = nil
    ) {
        self.id = id
        self.number = number
        self.url = url
        self.text = text
        self.title = title
        self.autolink = autolink
        self.label = label
        self.labelKind = labelKind
        self.context = context
        self.site = site
        self.markdown = markdown ?? url
        self.section = section
        self.page = page
        self.pageSource = pageSource
    }

    private enum CodingKeys: String, CodingKey {
        case id, n, url, text, title, autolink, label, context, site, markdown, section, page
        case labelKind = "label_kind"
        case pageSource = "page_source"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decode(String.self, forKey: .url)
        number = try values.decode(Int.self, forKey: .n)
        id = (try? values.decode(String.self, forKey: .id)) ?? ""
        text = (try? values.decode(String.self, forKey: .text)) ?? ""
        title = try? values.decodeIfPresent(String.self, forKey: .title)
        autolink = (try? values.decode(Bool.self, forKey: .autolink)) ?? false
        let decodedLabel = try? values.decodeIfPresent(String.self, forKey: .label)
        label = decodedLabel ?? (text.isEmpty ? url : text)
        let rawKind = try? values.decodeIfPresent(String.self, forKey: .labelKind)
        if rawKind == nil, autolink, decodedLabel == nil {
            labelKind = .url
        } else {
            labelKind = RefsLinkLabelKind(rawValue: rawKind)
        }
        context = try? values.decodeIfPresent(String.self, forKey: .context)
        site = (try? values.decodeIfPresent(String.self, forKey: .site)) ?? ""
        markdown = (try? values.decodeIfPresent(String.self, forKey: .markdown)) ?? url
        section = try? values.decodeIfPresent(RefsCodeSection.self, forKey: .section)
        page = try? values.decodeIfPresent(Int.self, forKey: .page)
        pageSource = try? values.decodeIfPresent(String.self, forKey: .pageSource)
    }

    public var pageLabel: String? {
        guard let page, page > 0 else { return nil }
        return "p. \(page)"
    }

    public func contains(page: Int) -> Bool {
        self.page == page
    }

    /// Path, query, and fragment after the host. Nil when line 1 already
    /// shows the URL or when nothing remains after the host.
    public var pathRemainder: String? {
        guard labelKind != .url else { return nil }
        return Self.pathRemainder(in: url)
    }

    public static func pathRemainder(in url: String) -> String? {
        guard let colon = url.firstIndex(of: ":") else { return nil }
        var rest = url[url.index(after: colon)...]
        guard rest.hasPrefix("//") else { return nil }
        rest = rest.dropFirst(2)
        guard let hostEnd = rest.firstIndex(where: { "/?#".contains($0) }) else {
            return nil
        }
        let remainder = String(rest[hostEnd...])
        return remainder.isEmpty ? nil : remainder
    }
}

private struct LossyRefsLink: Decodable {
    let link: RefsLink?

    init(from decoder: Decoder) throws {
        link = try? RefsLink(from: decoder)
    }
}

public struct RefsLinksResponse: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String?
    public let reference: RefsCodeReference
    public let status: RefsLinksStatus
    public let detail: String?
    public let source: RefsLinksSource?
    public let links: [RefsLink]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case reference, status, detail, source, links
    }

    public init(
        schemaVersion: Int = 1,
        generatedAt: String? = nil,
        reference: RefsCodeReference,
        status: RefsLinksStatus,
        detail: String? = nil,
        source: RefsLinksSource? = nil,
        links: [RefsLink]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.reference = reference
        self.status = status
        self.detail = detail
        self.source = source
        self.links = links
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? values.decode(Int.self, forKey: .schemaVersion)) ?? 1
        generatedAt = try? values.decodeIfPresent(String.self, forKey: .generatedAt)
        reference = (try? values.decode(RefsCodeReference.self, forKey: .reference))
            ?? RefsCodeReference(path: "", title: "", markerID: nil)
        let rawStatus = (try? values.decode(String.self, forKey: .status)) ?? "unknown"
        status = RefsLinksStatus(rawValue: rawStatus)
        detail = try? values.decodeIfPresent(String.self, forKey: .detail)
        source = try? values.decodeIfPresent(RefsLinksSource.self, forKey: .source)
        let decoded = (try? values.decode([LossyRefsLink].self, forKey: .links)) ?? []
        links = decoded.compactMap(\.link)
    }
}

extension RefsLinksResponse: SchemaVersioned {}

public enum RefsLinksLoadState: Equatable, Sendable {
    case notRequested
    case loading
    case loaded(RefsLinksResponse)
    case unsupported
    case failed
}

public struct RefsLinkPicker: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, RefsSectionedWindowEntry {
        public let link: RefsLink
        public let pageIsKnown: Bool
        public let isOnPage: Bool
        public let sectionedWindowGroupID: String?
        public let sectionedWindowGroupTitle: String?

        fileprivate init(link: RefsLink, highlightedPage: Int?) {
            self.link = link
            pageIsKnown = highlightedPage != nil
            isOnPage = highlightedPage.map(link.contains(page:)) ?? false
            sectionedWindowGroupID = link.section?.id
            sectionedWindowGroupTitle = link.section?.heading
        }

        public var label: String { link.label }
        public var site: String { link.site }
        public var pathRemainder: String? { link.pathRemainder }
        public var pageLabel: String? { link.pageLabel }
        public var usesMonospacedLabel: Bool { link.labelKind == .url }

        public func copyRow(markdown: Bool) -> RefsCopyRow {
            let payload = markdown ? link.markdown : link.url
            let confirmation = markdown
                ? "Copied Markdown link · \(link.site)"
                : "Copied link · \(link.site)"
            return RefsCopyRow(
                key: .linkPicker,
                group: .contents,
                label: link.label,
                payload: .text(payload),
                preview: link.label,
                truncation: .tail,
                detail: pageLabel,
                help: payload,
                confirmationTitle: confirmation
            )
        }

        public func voiceOverLabel(index: Int, total: Int, key: Int) -> String {
            var parts = ["Link \(index) of \(total)", link.label]
            if !link.site.isEmpty { parts.append(link.site) }
            if let page = link.page { parts.append("page \(page)") }
            if isOnPage { parts.append("on this page") }
            parts.append("key \(key)")
            return parts.joined(separator: ", ")
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
        links: [RefsLink],
        highlightedPage: Int? = nil,
        windowSize: Int = 9,
        groupHeaderHeight: Double = 22,
        entryRowHeight: Double = 36
    ) {
        entries = links.map { Entry(link: $0, highlightedPage: highlightedPage) }
        self.highlightedPage = highlightedPage
        let selectedIndex = Self.initialSelection(in: links, page: highlightedPage)
        sectionedWindow = RefsSectionedWindow(
            entries: entries,
            selectedIndex: selectedIndex,
            windowStart: selectedIndex,
            windowSize: windowSize,
            groupHeaderHeight: groupHeaderHeight,
            entryRowHeight: entryRowHeight
        )
    }

    public static func initialSelection(in links: [RefsLink], page: Int?) -> Int {
        guard !links.isEmpty else { return 0 }
        guard let page, page > 0 else { return 0 }
        if let containing = links.firstIndex(where: { $0.contains(page: page) }) {
            return containing
        }
        if let following = links.firstIndex(where: { link in
            guard let linkPage = link.page else { return false }
            return linkPage > page
        }) {
            return following
        }
        if let preceding = links.lastIndex(where: { link in
            guard let linkPage = link.page else { return false }
            return linkPage <= page
        }) {
            return preceding
        }
        return 0
    }

    public var pageLinkCount: Int {
        guard let highlightedPage else { return 0 }
        return entries.filter { $0.link.contains(page: highlightedPage) }.count
    }

    public var rowPreview: String {
        Self.rowPreview(links: entries.map(\.link), highlightedPage: highlightedPage)
    }

    public static func rowPreview(links: [RefsLink], highlightedPage: Int?) -> String {
        let count = links.count
        let word = count == 1 ? "link" : "links"
        var preview = "\(count) \(word)"
        if let highlightedPage {
            let onPage = links.filter { $0.contains(page: highlightedPage) }.count
            if onPage > 0 {
                preview += " · ● \(onPage) on this page"
            }
        }
        let sites = siteSummary(from: links)
        if !sites.isEmpty { preview += " · \(sites)" }
        return preview
    }

    public static func siteSummary(from links: [RefsLink], limit: Int = 3) -> String {
        var counts: [(String, Int)] = []
        for link in links {
            let site = link.site
            guard !site.isEmpty else { continue }
            if let index = counts.firstIndex(where: { $0.0 == site }) {
                counts[index].1 += 1
            } else {
                counts.append((site, 1))
            }
        }
        return counts
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 == rhs.element.1
                    ? lhs.offset < rhs.offset
                    : lhs.element.1 > rhs.element.1
            }
            .prefix(limit)
            .map { $0.element.0 }
            .joined(separator: ", ")
    }

    public static let openingAnnouncement = "Links. Press a number or Return."

    public var openingVoiceOverLabel: String {
        Self.openingAnnouncement
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

    public func allLinksRow(markdown: Bool) -> RefsCopyRow {
        var seen = Set<String>()
        var unique: [RefsLink] = []
        for entry in entries where seen.insert(entry.link.url).inserted {
            unique.append(entry.link)
        }
        let payload: String
        if markdown {
            payload = unique.map { "- \($0.markdown)" }.joined(separator: "\n")
        } else {
            payload = unique.map(\.url).joined(separator: "\n")
        }
        let count = unique.count
        let word = count == 1 ? "link" : "links"
        let confirmation = markdown
            ? "Copied \(count) \(word) · Markdown"
            : "Copied \(count) \(word)"
        return RefsCopyRow(
            key: .allNotes,
            group: .contents,
            label: "All links",
            payload: .text(payload),
            preview: "\(count) \(word)",
            truncation: .tail,
            help: payload,
            confirmationTitle: confirmation
        )
    }
}

public enum RefsLinkPreviewRole: Equatable, Sendable {
    case scheme
    case host
    case path
    case query
    case fragment
    case markdownPunctuation
    case markdownText
    case plain
}

public struct RefsLinkPreviewRun: Equatable, Sendable {
    public let text: String
    public let role: RefsLinkPreviewRole

    public init(text: String, role: RefsLinkPreviewRole) {
        self.text = text
        self.role = role
    }
}

public struct RefsLinkPreviewLine: Equatable, Sendable {
    public let runs: [RefsLinkPreviewRun]
    public let isFaded: Bool

    public init(runs: [RefsLinkPreviewRun], isFaded: Bool = false) {
        self.runs = runs
        self.isFaded = isFaded
    }

    public var text: String {
        runs.map(\.text).joined()
    }
}

/// Presentation-only preview for the link well. Copy payloads remain the
/// original `url` and `markdown` strings on `RefsLink`.
public struct RefsLinkPreview: Equatable, Sendable {
    public static let maximumCharacters = 2000
    public static let preferredBreakCharacters = CharacterSet(charactersIn: "/?&=#-_.")

    public let site: String
    public let sectionTitle: String?
    public let pageLabel: String?
    public let markdown: Bool
    public let lines: [RefsLinkPreviewLine]
    public let overflowCharacterCount: Int
    public let displayPayload: String

    public init(link: RefsLink, markdown: Bool, columns: Int, visibleLines: Int) {
        site = link.site
        sectionTitle = link.section?.title
        pageLabel = link.pageLabel
        self.markdown = markdown
        let payload = markdown ? link.markdown : link.url
        let capped = String(payload.prefix(Self.maximumCharacters))
        displayPayload = capped
        let wrapped = Self.wrap(capped, columns: columns)
        let visibleCount = min(wrapped.count, max(0, visibleLines))
        let visible = Array(wrapped.prefix(visibleCount))
        let roles = Self.roles(for: capped, markdown: markdown)
        let characters = Array(capped)
        var offset = 0
        var built: [RefsLinkPreviewLine] = []
        let overflowChars = characters.count - visible.joined().count
        for (index, line) in visible.enumerated() {
            let count = line.count
            let end = min(characters.count, offset + count)
            let sliceChars = Array(characters[offset..<end])
            let sliceRoles = Array(roles[offset..<end])
            let faded = overflowChars > 0 && index == visible.count - 1
            built.append(
                RefsLinkPreviewLine(
                    runs: Self.runs(characters: sliceChars, roles: sliceRoles),
                    isFaded: faded
                )
            )
            offset = end
        }
        lines = built
        overflowCharacterCount = max(0, overflowChars)
    }

    public var voiceOverLabel: String {
        "Preview, link to \(site)"
    }

    public static func wrap(_ text: String, columns: Int) -> [String] {
        let columns = max(1, columns)
        var chars = Array(text)
        var lines: [String] = []
        while !chars.isEmpty {
            if chars.count <= columns {
                lines.append(String(chars))
                break
            }
            let window = Array(chars.prefix(columns))
            let searchStart = max(0, window.count - 12)
            var split = columns
            var index = window.count - 1
            while index >= searchStart {
                if let scalar = window[index].unicodeScalars.first,
                    preferredBreakCharacters.contains(scalar)
                {
                    split = index + 1
                    break
                }
                if index == 0 { break }
                index -= 1
            }
            split = max(1, split)
            lines.append(String(window.prefix(split)))
            chars.removeFirst(split)
        }
        return lines
    }

    public static func roles(for payload: String, markdown: Bool) -> [RefsLinkPreviewRole] {
        let chars = Array(payload)
        if markdown {
            return markdownRoles(chars)
        }
        return urlRoles(chars) ?? Array(repeating: .plain, count: chars.count)
    }

    private static func urlRoles(_ chars: [Character]) -> [RefsLinkPreviewRole]? {
        let text = String(chars)
        guard let schemeRange = text.range(of: "://") else { return nil }
        let schemeEnd = text.distance(from: text.startIndex, to: schemeRange.upperBound)
        guard schemeEnd > 2 else { return nil }
        var roles = Array(repeating: RefsLinkPreviewRole.scheme, count: schemeEnd)
        var i = schemeEnd
        let hostStart = i
        while i < chars.count, chars[i] != "/", chars[i] != "?", chars[i] != "#" {
            i += 1
        }
        if i == hostStart { return nil }
        roles.append(contentsOf: Array(repeating: .host, count: i - hostStart))
        let pathStart = i
        while i < chars.count, chars[i] != "?", chars[i] != "#" {
            i += 1
        }
        roles.append(contentsOf: Array(repeating: .path, count: i - pathStart))
        if i < chars.count, chars[i] == "?" {
            let queryStart = i
            i += 1
            while i < chars.count, chars[i] != "#" { i += 1 }
            roles.append(contentsOf: Array(repeating: .query, count: i - queryStart))
        }
        if i < chars.count {
            roles.append(contentsOf: Array(repeating: .fragment, count: chars.count - i))
        }
        return roles.count == chars.count ? roles : nil
    }

    private static func markdownRoles(_ chars: [Character]) -> [RefsLinkPreviewRole] {
        guard !chars.isEmpty else { return [] }
        if chars.first == "<", chars.last == ">", chars.count >= 2 {
            var roles: [RefsLinkPreviewRole] = [.markdownPunctuation]
            let inner = Array(chars.dropFirst().dropLast())
            if let url = urlRoles(inner) {
                roles.append(contentsOf: url)
            } else {
                roles.append(contentsOf: Array(repeating: .markdownText, count: inner.count))
            }
            roles.append(.markdownPunctuation)
            return roles
        }
        if chars.first == "[", let dest = markdownDestination(chars) {
            var roles: [RefsLinkPreviewRole] = [.markdownPunctuation]
            roles.append(
                contentsOf: Array(repeating: .markdownText, count: max(0, dest.textEnd - 1)))
            roles.append(.markdownPunctuation)
            roles.append(.markdownPunctuation)
            let destChars = Array(chars[dest.destStart..<dest.destEnd])
            if destChars.first == "<", destChars.last == ">", destChars.count >= 2 {
                roles.append(.markdownPunctuation)
                let inner = Array(destChars.dropFirst().dropLast())
                if let url = urlRoles(inner) {
                    roles.append(contentsOf: url)
                } else {
                    roles.append(contentsOf: Array(repeating: .plain, count: inner.count))
                }
                roles.append(.markdownPunctuation)
            } else if let url = urlRoles(destChars) {
                roles.append(contentsOf: url)
            } else {
                roles.append(contentsOf: Array(repeating: .plain, count: destChars.count))
            }
            if dest.destEnd < chars.count {
                roles.append(.markdownPunctuation)
            }
            if roles.count < chars.count {
                roles.append(
                    contentsOf: Array(repeating: .plain, count: chars.count - roles.count))
            }
            return Array(roles.prefix(chars.count))
        }
        return urlRoles(chars) ?? Array(repeating: .plain, count: chars.count)
    }

    private static func markdownDestination(
        _ chars: [Character]
    ) -> (textEnd: Int, destStart: Int, destEnd: Int)? {
        var i = 1
        var escaped = false
        while i < chars.count - 1 {
            if escaped {
                escaped = false
                i += 1
                continue
            }
            if chars[i] == "\\" {
                escaped = true
                i += 1
                continue
            }
            if chars[i] == "]", i + 1 < chars.count, chars[i + 1] == "(" {
                guard chars.last == ")" else { return nil }
                return (textEnd: i, destStart: i + 2, destEnd: chars.count - 1)
            }
            i += 1
        }
        return nil
    }

    private static func runs(
        characters: [Character],
        roles: [RefsLinkPreviewRole]
    ) -> [RefsLinkPreviewRun] {
        var result: [RefsLinkPreviewRun] = []
        var i = 0
        while i < characters.count {
            let role = i < roles.count ? roles[i] : .plain
            var j = i + 1
            while j < characters.count, (j < roles.count ? roles[j] : .plain) == role {
                j += 1
            }
            result.append(RefsLinkPreviewRun(text: String(characters[i..<j]), role: role))
            i = j
        }
        return result
    }
}

public struct RefsLinkPreviewLayout: Equatable, Sendable {
    public let height: Double
    public let bodyLines: Int
    public let pickerWindowSize: Int

    public static func make(
        availableHeightUnderHeader: Double,
        columns: Int,
        longestURL: String,
        headerHeight: Double = 18,
        lineHeight: Double = 16,
        entryRowHeight: Double = 36
    ) -> Self {
        let wrapped = RefsLinkPreview.wrap(longestURL, columns: max(1, columns))
        let bodyLines = min(5, max(2, wrapped.count))
        let height = max(0, headerHeight) + Double(bodyLines) * max(1, lineHeight)
        let remaining = max(0, availableHeightUnderHeader) - height
        let rows = entryRowHeight > 0
            ? Int(floor(remaining / entryRowHeight))
            : 2
        return Self(
            height: height,
            bodyLines: bodyLines,
            pickerWindowSize: min(9, max(2, rows))
        )
    }
}
