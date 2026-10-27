import CaptureCore
import Foundation

/// Whether bob supplied the `marker_id` field. Missing means the installed
/// bob predates that field; null means the note has no marker ID.
public enum RefMarkerID: Equatable, Hashable, Sendable {
    case present(String)
    case absent
    case unsupported
}

/// Clipboard values stay platform-neutral in RefsCore. The AppKit client is
/// responsible for writing the associated text or file URL.
public enum RefsClipboardPayload: Equatable, Sendable {
    case text(String)
    case fileURL(URL)
}

public enum RefsCopyKey: Equatable, Hashable, Sendable {
    case markerID
    case title
    case wikiLink
    case sourceURL
    case markdownLink
    case arxiv
    case doi
    case notePath
    case obsidianLink
    case pdfPath
    case pdfFile
    case readingTask
    case researchRef
    case note(Int)
    case allNotes
    case highlightPicker
    case codePicker
    case linkPicker
    case sourceMarkdown

    public var glyph: String {
        switch self {
        case .markerID: "I"
        case .title: "T"
        case .wikiLink: "W"
        case .sourceURL: "U"
        case .markdownLink, .linkPicker: "L"
        case .arxiv: "X"
        case .doi: "D"
        case .notePath: "N"
        case .obsidianLink: "O"
        case .pdfPath: "P"
        case .pdfFile: "F"
        case .readingTask: "R"
        case .researchRef: "S"
        case .note(let number): String(number)
        case .allNotes: "A"
        case .highlightPicker: "H"
        case .codePicker: "C"
        case .sourceMarkdown: "M"
        }
    }

    public static func parse(_ character: Character) -> RefsCopyKey? {
        switch String(character).lowercased() {
        case "i": .markerID
        case "t": .title
        case "w": .wikiLink
        case "u": .sourceURL
        case "l": .markdownLink
        case "x": .arxiv
        case "d": .doi
        case "n": .notePath
        case "o": .obsidianLink
        case "p": .pdfPath
        case "f": .pdfFile
        case "r": .readingTask
        case "s": .researchRef
        case "a": .allNotes
        case "h": .highlightPicker
        case "c": .codePicker
        case "m": .sourceMarkdown
        case "1"..."9": Int(String(character)).map(RefsCopyKey.note)
        default: nil
        }
    }
}

public enum RefsCopyGroup: Equatable, Hashable, Sendable {
    case identity
    case sources
    case files
    case contents
    case notes
}

public enum RefsCopyTruncation: Equatable, Sendable {
    case middle
    case tail
}

public enum RefsCopyTag: Equatable, Sendable {
    case shared(Int)
    case missing
    case archived
}

/// A second payload for the same fixed key and row position.
public struct RefsCopyAlternate: Equatable, Sendable {
    public let label: String
    public let payload: RefsClipboardPayload
    public let preview: String
    public let confirmationTitle: String
    public let help: String?

    public init(
        label: String,
        payload: RefsClipboardPayload,
        preview: String,
        confirmationTitle: String,
        help: String? = nil
    ) {
        self.label = label
        self.payload = payload
        self.preview = preview
        self.confirmationTitle = confirmationTitle
        self.help = help
    }
}

public struct RefsCopyRow: Equatable, Sendable {
    public let key: RefsCopyKey
    public let group: RefsCopyGroup
    public let label: String
    public let payload: RefsClipboardPayload
    public let preview: String
    public let truncation: RefsCopyTruncation
    public let tag: RefsCopyTag?
    public let detail: String?
    public let help: String?
    public let confirmationTitle: String
    public let alternate: RefsCopyAlternate?

    public init(
        key: RefsCopyKey,
        group: RefsCopyGroup,
        label: String,
        payload: RefsClipboardPayload,
        preview: String,
        truncation: RefsCopyTruncation = .middle,
        tag: RefsCopyTag? = nil,
        detail: String? = nil,
        help: String? = nil,
        confirmationTitle: String,
        alternate: RefsCopyAlternate? = nil
    ) {
        self.key = key
        self.group = group
        self.label = label
        self.payload = payload
        self.preview = preview
        self.truncation = truncation
        self.tag = tag
        self.detail = detail
        self.help = help
        self.confirmationTitle = confirmationTitle
        self.alternate = alternate
    }

    /// Rows without an alternate retain their primary payload, like native menus.
    public func resolved(alternate active: Bool) -> RefsCopyRow {
        guard active, let alternate else { return self }
        let help: String
        if let alternateHelp = alternate.help {
            help = alternateHelp
        } else {
            switch alternate.payload {
            case .text(let value): help = value
            case .fileURL(let url): help = url.path
            }
        }
        return RefsCopyRow(
            key: key, group: group, label: alternate.label,
            payload: alternate.payload, preview: alternate.preview,
            truncation: truncation, tag: tag, help: help,
            confirmationTitle: alternate.confirmationTitle
        )
    }

    /// The range of the on-page `●` marker in `preview`, if this C/L row
    /// carries one. The Copy card renders that run in the accent color.
    public var onPageDotRange: Range<String.Index>? {
        guard key == .codePicker || key == .linkPicker else { return nil }
        return preview.range(of: "●")
    }
}

public enum RefsCopyNotesState: Equatable, Sendable {
    case loading
    case loaded(RefsShowRow)
    case unavailable
}

/// A pure projection of a frozen reference into the fixed-letter copy
/// catalog. `absolutePDFPath` is supplied by the app's library resolver.
public struct RefsCopyCatalog: Equatable, Sendable {
    public let rows: [RefsCopyRow]
    public let defaultKey: RefsCopyKey
    /// Commented highlights available on the 1–9 rows.
    public let noteCount: Int
    public let visibleNoteCount: Int
    public let noteOverflowCount: Int
    /// All notes copied by A, including standalone notes.
    public let allNotesCount: Int
    public let notesState: RefsCopyNotesState
    public let codeState: RefsCodeLoadState
    public let linksState: RefsLinksLoadState

    private let item: RefItem
    private let absolutePDFPath: String?
    private let pdfExists: Bool
    private let noteCapacity: Int
    private let highlightedPage: Int?

    public init(
        item: RefItem,
        absolutePDFPath: String?,
        pdfExists: Bool,
        notes: RefsCopyNotesState,
        noteCapacity: Int,
        absoluteNotePath: String? = nil,
        homeDirectoryPath: String? = nil,
        narrationFileURL: URL? = nil,
        code: RefsCodeLoadState = .notRequested,
        links: RefsLinksLoadState = .notRequested,
        highlightedPage: Int? = nil
    ) {
        self.item = item
        self.absolutePDFPath = absolutePDFPath
        self.pdfExists = pdfExists
        self.noteCapacity = max(0, noteCapacity)
        self.highlightedPage = highlightedPage
        self.codeState = Self.validatedCodeState(code, itemID: item.id)
        self.linksState = Self.validatedLinksState(links, itemID: item.id)
        if case .loaded(let row) = notes, row.path != item.id {
            notesState = .unavailable
        } else {
            notesState = notes
        }

        let notesRow: RefsShowRow?
        if case .loaded(let row) = notesState {
            notesRow = row
        } else {
            notesRow = nil
        }
        noteCount = notesRow?.commentedHighlights.count ?? 0
        allNotesCount = notesRow?.yourNotes.count ?? 0
        let visible: Int
        if notesRow == nil {
            visible = 0
        } else {
            visible = Self.visibleNoteCount(total: noteCount, cap: self.noteCapacity)
        }
        visibleNoteCount = visible
        noteOverflowCount = max(0, noteCount - visible)
        defaultKey = {
            if case .present(let value) = item.markerID, !value.isEmpty {
                return .markerID
            }
            return .wikiLink
        }()

        var built: [RefsCopyRow] = []
        if case .present(let markerID) = item.markerID, !markerID.isEmpty {
            built.append(Self.valueRow(
                key: .markerID,
                group: .identity,
                label: "Marker ID",
                value: markerID,
                truncation: .middle,
                tag: item.markerIDShareCount >= 2 ? .shared(item.markerIDShareCount) : nil,
                help: item.markerIDShareCount >= 2
                    ? "\(item.markerIDShareCount) notes share this ID — `bob ref show` needs the note path for this one (press N)"
                    : nil,
                confirmationTitle: "Copied Marker ID"
            ))
        }
        built.append(Self.valueRow(
            key: .title,
            group: .identity,
            label: "Title",
            value: item.rawTitle,
            truncation: .tail,
            confirmationTitle: "Copied Title"
        ))
        built.append(Self.valueRow(
            key: .wikiLink,
            group: .identity,
            label: "Wiki link",
            value: item.link,
            truncation: .middle,
            confirmationTitle: "Copied Wiki Link",
            alternate: RefsCopyAlternate(
                label: "Wiki link · titled",
                payload: .text(
                    RefsCopyFormat.titledWikiLink(link: item.link, title: item.rawTitle)),
                preview: RefsCopyFormat.titledWikiLink(link: item.link, title: item.rawTitle),
                confirmationTitle: "Copied Titled Wiki Link"
            )
        ))

        if let sourceURL = item.urls.first(where: { !$0.isEmpty }) {
            let markdown = RefsCopyFormat.markdownLink(title: item.rawTitle, url: sourceURL)
            built.append(Self.valueRow(
                key: .sourceURL,
                group: .sources,
                label: "Source URL",
                value: sourceURL,
                confirmationTitle: "Copied Source URL",
                alternate: RefsCopyAlternate(
                    label: "Markdown link",
                    payload: .text(markdown),
                    preview: markdown,
                    confirmationTitle: "Copied Markdown Link"
                )
            ))
            if item.sourceMarkdown == nil {
                built.append(Self.valueRow(
                    key: .markdownLink,
                    group: .sources,
                    label: "Markdown link",
                    value: markdown,
                    truncation: .middle,
                    confirmationTitle: "Copied Markdown Link"
                ))
            }
        }
        if let arxiv = item.arxivID, !arxiv.isEmpty {
            built.append(Self.valueRow(
                key: .arxiv,
                group: .sources,
                label: "arXiv",
                value: "arXiv:\(arxiv)",
                confirmationTitle: "Copied arXiv"
            ))
        }
        if let doi = item.doi, !doi.isEmpty {
            built.append(Self.valueRow(
                key: .doi,
                group: .sources,
                label: "DOI",
                value: doi,
                confirmationTitle: "Copied DOI"
            ))
        }

        built.append(Self.valueRow(
            key: .notePath,
            group: .files,
            label: "Note path",
            value: item.id,
            confirmationTitle: "Copied Note Path",
            alternate: absoluteNotePath.map {
                let path = RefsCopyFormat.homeAbbreviatedPath(
                    $0, homeDirectoryPath: homeDirectoryPath)
                let shortened = path != $0
                return RefsCopyAlternate(
                    label: shortened ? "Note path · ~" : "Note path · absolute",
                    payload: .text(path), preview: path,
                    confirmationTitle: shortened
                        ? "Copied Note Path · ~" : "Copied Absolute Note Path"
                )
            }
        ))
        if let absoluteNotePath,
            let url = ObsidianOpenURL.url(forAbsolutePath: absoluteNotePath)
        {
            built.append(
                Self.valueRow(
                    key: .obsidianLink, group: .files, label: "Obsidian link",
                    value: url.absoluteString, confirmationTitle: "Copied Obsidian Link"
                ))
        }
        if let absolutePDFPath {
            built.append(Self.valueRow(
                key: .pdfPath,
                group: .files,
                label: "PDF path",
                value: RefsCopyFormat.homeAbbreviatedPath(
                    absolutePDFPath, homeDirectoryPath: homeDirectoryPath),
                tag: pdfExists ? nil : .missing,
                confirmationTitle: "Copied PDF Path",
                alternate: {
                    let path = RefsCopyFormat.homeAbbreviatedPath(
                        absolutePDFPath, homeDirectoryPath: homeDirectoryPath)
                    guard path != absolutePDFPath else { return nil }
                    return RefsCopyAlternate(
                        label: "PDF path · absolute", payload: .text(absolutePDFPath),
                        preview: absolutePDFPath,
                        confirmationTitle: "Copied Absolute PDF Path"
                    )
                }()
            ))
            if pdfExists {
                let fileURL = URL(fileURLWithPath: absolutePDFPath)
                built.append(RefsCopyRow(
                    key: .pdfFile,
                    group: .files,
                    label: "PDF file",
                    payload: .fileURL(fileURL),
                    preview: fileURL.lastPathComponent,
                    truncation: .middle,
                    confirmationTitle: "Copied PDF File",
                    alternate: narrationFileURL.map {
                        RefsCopyAlternate(
                            label: "Narration file", payload: .fileURL($0),
                            preview: $0.lastPathComponent,
                            confirmationTitle: "Copied Narration File",
                            help: RefsCopyFormat.homeAbbreviatedPath(
                                $0.path, homeDirectoryPath: homeDirectoryPath)
                        )
                    }
                ))
            }
        }
        if let task = item.task, let link = task.link, !link.isEmpty {
            built.append(Self.valueRow(
                key: .readingTask,
                group: .files,
                label: task.archived ? "Reading task · archived" : "Reading task",
                value: link,
                tag: task.archived ? .archived : nil,
                confirmationTitle: "Copied Reading Task"
            ))
        }
        if let researchRef = item.researchRef, !researchRef.isEmpty {
            built.append(Self.valueRow(
                key: .researchRef,
                group: .files,
                label: "Research ref",
                value: researchRef,
                confirmationTitle: "Copied Research Ref"
            ))
        }
        built.append(contentsOf: Self.contentsRows(
            code: codeState,
            links: linksState,
            item: item,
            highlightedPage: highlightedPage,
            homeDirectoryPath: homeDirectoryPath
        ))

        if let notesRow {
            let notes = notesRow.commentedHighlights
            for (offset, annotation) in notes.prefix(visible).enumerated() {
                let key = RefsCopyKey.note(offset + 1)
                let payload = RefsCopyFormat.noteBlock(annotation)
                let commentFirstLine = annotation.comment?.components(separatedBy: "\n").first ?? ""
                built.append(RefsCopyRow(
                    key: key,
                    group: .notes,
                    label: "Note \(offset + 1)",
                    payload: .text(payload),
                    preview: "↳ \(commentFirstLine)",
                    truncation: .tail,
                    detail: RefsCopyFormat.shortPageLabel(annotation.displayPageLabel),
                    help: payload,
                    confirmationTitle: "Copied Note \(offset + 1)",
                    alternate: RefsCopyFormat.quoteAlternate(annotation)
                ))
            }
            let ownNotesAvailable = !notesRow.ownNotes.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            if !notesRow.yourNotes.isEmpty || ownNotesAvailable {
                let suffix = ownNotesAvailable ? " + your notes" : ""
                let noteWord = allNotesCount == 1 ? "note" : "notes"
                let confirmationTitle: String
                if allNotesCount == 0 {
                    confirmationTitle = "Copied Your Notes"
                } else if allNotesCount == 1 {
                    confirmationTitle = "Copied 1 Note"
                } else {
                    confirmationTitle = "Copied \(allNotesCount) Notes"
                }
                built.append(RefsCopyRow(
                    key: .allNotes,
                    group: .notes,
                    label: "All your notes",
                    payload: .text(RefsCopyFormat.allNotes(from: notesRow)),
                    preview: "\(allNotesCount) \(noteWord) · Markdown\(suffix)",
                    truncation: .tail,
                    confirmationTitle: confirmationTitle
                ))
            }
            let highlightCount = notesRow.highlightPickerEntries.count
            if highlightCount > 0 {
                let highlightWord = highlightCount == 1 ? "highlight" : "highlights"
                built.append(RefsCopyRow(
                    key: .highlightPicker,
                    group: .notes,
                    label: "Pick a highlight…",
                    payload: .text(""),
                    preview: "\(highlightCount) \(highlightWord)",
                    truncation: .tail,
                    confirmationTitle: "Copied Highlight"
                ))
            }
        }
        rows = built
    }

    public func row(for key: RefsCopyKey) -> RefsCopyRow? {
        rows.first { $0.key == key }
    }

    public func hiddenReason(for key: RefsCopyKey) -> String? {
        switch key {
        case .markerID:
            switch item.markerID {
            case .present(let value) where !value.isEmpty:
                return nil
            case .unsupported:
                return "Marker IDs need a newer bob — N copies the note path"
            case .present, .absent:
                return "No marker ID on this note — N copies its path"
            }
        case .title, .wikiLink, .notePath:
            return nil
        case .sourceURL, .markdownLink:
            return item.urls.first(where: { !$0.isEmpty }) == nil
                ? "No source URL for this reference" : nil
        case .arxiv:
            return item.arxivID?.isEmpty != false ? "No arXiv ID for this reference" : nil
        case .doi:
            return item.doi?.isEmpty != false ? "No DOI for this reference" : nil
        case .obsidianLink:
            return row(for: key) == nil ? "No Obsidian link for this reference" : nil
        case .pdfPath:
            return absolutePDFPath == nil ? "No PDF path for this reference" : nil
        case .pdfFile:
            if absolutePDFPath == nil {
                return "No PDF path for this reference"
            }
            return pdfExists ? nil : "The PDF is missing — P copies its path"
        case .readingTask:
            return item.task?.link?.isEmpty == false ? nil : "No reading task for this reference"
        case .researchRef:
            return item.researchRef?.isEmpty == false ? nil : "No research ref for this reference"
        case .linkPicker:
            return Self.hiddenLinkReason(item: item, state: linksState)
        case .codePicker, .sourceMarkdown:
            return Self.hiddenCodeReason(
                for: key,
                item: item,
                state: codeState
            )
        case .note(let index):
            guard index > 0 else { return "No note \(index)" }
            switch notesState {
            case .loading:
                return nil
            case .unavailable:
                return "Notes unavailable — nothing copied"
            case .loaded:
                if index > noteCount {
                    return "No note \(index)"
                }
                if index > visibleNoteCount {
                    return "Note \(index) doesn't fit — A copies all · H picks one"
                }
                return nil
            }
        case .allNotes:
            switch notesState {
            case .loading:
                return nil
            case .unavailable:
                return "Notes unavailable — nothing copied"
            case .loaded(let row):
                let hasNotes = !row.yourNotes.isEmpty
                let hasOwnNotes = !row.ownNotes.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                return hasNotes || hasOwnNotes ? nil : "No notes on this reference"
            }
        case .highlightPicker:
            switch notesState {
            case .loading:
                return nil
            case .unavailable:
                return "Notes unavailable — nothing copied"
            case .loaded(let row):
                return row.highlightPickerEntries.isEmpty
                    ? "No highlights on this reference" : nil
            }
        }
    }

    /// Overflow line under the visible note rows, or nil when they all fit.
    public var notesOverflowText: String? {
        guard noteOverflowCount > 0 else { return nil }
        return "+\(noteOverflowCount) more — A copies all · H picks one"
    }

    public static func visibleNoteCount(total: Int, cap: Int) -> Int {
        let total = max(0, total)
        let cap = max(0, cap)
        return min(9, total <= cap ? total : max(0, cap - 1))
    }

    private static func validatedCodeState(
        _ state: RefsCodeLoadState,
        itemID: String
    ) -> RefsCodeLoadState {
        guard case .loaded(let response) = state else { return state }
        return response.reference.path == itemID ? state : .failed
    }

    private static func validatedLinksState(
        _ state: RefsLinksLoadState,
        itemID: String
    ) -> RefsLinksLoadState {
        guard case .loaded(let response) = state else { return state }
        return response.reference.path == itemID ? state : .failed
    }

    private static func contentsRows(
        code: RefsCodeLoadState,
        links: RefsLinksLoadState,
        item: RefItem,
        highlightedPage: Int?,
        homeDirectoryPath: String?
    ) -> [RefsCopyRow] {
        var rows: [RefsCopyRow] = []
        if let row = codePickerContentsRow(state: code, highlightedPage: highlightedPage) {
            rows.append(row)
        }
        if let row = linkPickerContentsRow(
            state: links, item: item, highlightedPage: highlightedPage
        ) {
            rows.append(row)
        }
        if let row = markdownContentsRow(state: code, homeDirectoryPath: homeDirectoryPath) {
            rows.append(row)
        }
        return rows
    }

    private static func codePickerContentsRow(
        state: RefsCodeLoadState,
        highlightedPage: Int?
    ) -> RefsCopyRow? {
        switch state {
        case .loading:
            return RefsCopyRow(
                key: .codePicker, group: .contents, label: "Code block…",
                payload: .text(""), preview: "Loading code…",
                confirmationTitle: "Code blocks"
            )
        case .loaded(let response):
            guard response.source?.text != nil, response.status == .available else {
                return nil
            }
            return codeRow(response: response, highlightedPage: highlightedPage)
        case .notRequested, .unsupported, .failed:
            return nil
        }
    }

    private static func markdownContentsRow(
        state: RefsCodeLoadState,
        homeDirectoryPath: String?
    ) -> RefsCopyRow? {
        switch state {
        case .loading:
            return RefsCopyRow(
                key: .sourceMarkdown, group: .contents, label: "Markdown",
                payload: .text(""), preview: "Loading code…",
                confirmationTitle: "Copied Markdown"
            )
        case .loaded(let response):
            guard let source = response.source, let text = source.text else { return nil }
            switch response.status {
            case .available, .noCode, .noCatalog:
                return markdownRow(
                    source: source, text: text, homeDirectoryPath: homeDirectoryPath)
            case .noSource, .sourceMissing, .sourceInvalid, .unknown:
                return nil
            }
        case .notRequested, .unsupported, .failed:
            return nil
        }
    }

    private static func linkPickerContentsRow(
        state: RefsLinksLoadState,
        item: RefItem,
        highlightedPage: Int?
    ) -> RefsCopyRow? {
        guard item.sourceMarkdown != nil else { return nil }
        switch state {
        case .loading:
            return RefsCopyRow(
                key: .linkPicker, group: .contents, label: "Link…",
                payload: .text(""), preview: "Loading links…",
                confirmationTitle: "Links"
            )
        case .loaded(let response):
            guard response.status == .available, !response.links.isEmpty else { return nil }
            return RefsCopyRow(
                key: .linkPicker,
                group: .contents,
                label: "Link…",
                payload: .text(""),
                preview: RefsLinkPicker.rowPreview(
                    links: response.links, highlightedPage: highlightedPage),
                truncation: .tail,
                confirmationTitle: "Links"
            )
        case .notRequested, .unsupported, .failed:
            return nil
        }
    }

    private static func codeRow(
        response: RefsCodeResponse,
        highlightedPage: Int?
    ) -> RefsCopyRow {
        let picker = RefsCodePicker(blocks: response.blocks, highlightedPage: highlightedPage)
        let languages = response.blocks.reduce(into: [(String, Int)]()) { counts, block in
            let language = block.displayLanguage
            if let index = counts.firstIndex(where: { $0.0 == language }) {
                counts[index].1 += 1
            } else {
                counts.append((language, 1))
            }
        }
        let languageSummary = languages
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 == rhs.element.1
                    ? lhs.offset < rhs.offset
                    : lhs.element.1 > rhs.element.1
            }
            .prefix(3)
            .map { $0.element.0 }
            .joined(separator: ", ")
        var preview = "\(response.blocks.count) blocks"
        if highlightedPage != nil, picker.pageBlockCount > 0 {
            preview += " · ● \(picker.pageBlockCount) on this page"
        }
        if !languageSummary.isEmpty { preview += " · \(languageSummary)" }
        return RefsCopyRow(
            key: .codePicker,
            group: .contents,
            label: "Code block…",
            payload: .text(""),
            preview: preview,
            truncation: .tail,
            confirmationTitle: "Code blocks"
        )
    }

    private static func markdownRow(
        source: RefsCodeSource,
        text: String,
        homeDirectoryPath: String?
    ) -> RefsCopyRow {
        let bytes = source.bytes ?? text.utf8.count
        let kilobytes = max(1, Int((Double(bytes) / 1_000).rounded()))
        let captured = source.captured.flatMap(shortCapturedDate)
        let dateDescription = captured.map { " · captured \($0)" } ?? ""
        let sourcePath = source.path
        let home = homeDirectoryPath.map {
            $0.hasSuffix("/") ? String($0.dropLast()) : $0
        } ?? "~"
        let absolute = "\(home)/bob/\(sourcePath)"
        let shortened = RefsCopyFormat.homeAbbreviatedPath(absolute, homeDirectoryPath: homeDirectoryPath)
        let path = homeDirectoryPath == nil ? "~/bob/\(sourcePath)" : shortened
        return RefsCopyRow(
            key: .sourceMarkdown,
            group: .contents,
            label: "Markdown",
            payload: .text(text),
            preview: "source.md · \(kilobytes) KB\(dateDescription)",
            truncation: .tail,
            help: text,
            confirmationTitle: "Copied Markdown · \(kilobytes) KB",
            alternate: RefsCopyAlternate(
                label: "Markdown path · ~",
                payload: .text(path),
                preview: path,
                confirmationTitle: "Copied Markdown Path",
                help: path
            )
        )
    }

    private static func shortCapturedDate(_ captured: String) -> String? {
        let parts = captured.split(separator: "-")
        guard parts.count >= 3,
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2].prefix(2)), (1...31).contains(day)
        else { return nil }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[month - 1]) \(day)"
    }

    private static func hiddenCodeReason(
        for key: RefsCopyKey,
        item: RefItem,
        state: RefsCodeLoadState
    ) -> String? {
        switch state {
        case .loading:
            return nil
        case .notRequested:
            return item.sourceMarkdown == nil
                ? "No saved Markdown — code copy needs a reference bob "
                    + "created from Markdown or a web page"
                : "Code unavailable — nothing copied"
        case .unsupported:
            return "Code copy needs a newer bob"
        case .failed:
            return "Code unavailable — nothing copied"
        case .loaded(let response):
            switch response.status {
            case .available:
                return nil
            case .noCode:
                return key == .codePicker
                    ? "No code blocks in this reference — M copies its Markdown"
                    : nil
            case .noCatalog:
                return key == .codePicker
                    ? "Code blocks weren't recorded for this reference — M copies its Markdown"
                    : nil
            case .noSource:
                return "No saved Markdown — code copy needs a reference bob "
                    + "created from Markdown or a web page"
            case .sourceMissing:
                return "Saved Markdown isn't on this Mac yet — sync the vault"
            case .sourceInvalid:
                return "Saved Markdown doesn't match its digest — run bob ref doctor"
            case .unknown:
                return "Code unavailable — nothing copied"
            }
        }
    }

    private static func hiddenLinkReason(
        item: RefItem,
        state: RefsLinksLoadState
    ) -> String? {
        switch state {
        case .loading:
            return nil
        case .notRequested:
            return item.sourceMarkdown == nil
                ? "No saved Markdown — link copy needs a reference bob "
                    + "created from Markdown or a web page"
                : "Links unavailable — nothing copied"
        case .unsupported:
            return "Link copy needs a newer bob"
        case .failed:
            return "Links unavailable — nothing copied"
        case .loaded(let response):
            switch response.status {
            case .available:
                return response.links.isEmpty ? "No links in this reference" : nil
            case .noLinks:
                return "No links in this reference"
            case .notRecorded:
                return "Links weren't recorded for this reference yet — bob ref recatalog"
            case .noCatalog:
                return "Links weren't recorded for this reference — M copies its Markdown"
            case .noSource:
                return "No saved Markdown — link copy needs a reference bob "
                    + "created from Markdown or a web page"
            case .sourceMissing:
                return "Saved Markdown isn't on this Mac yet — sync the vault"
            case .sourceInvalid:
                return "Saved Markdown doesn't match its digest — run bob ref doctor"
            case .unknown:
                return "Links unavailable — nothing copied"
            }
        }
    }

    private static func valueRow(
        key: RefsCopyKey,
        group: RefsCopyGroup,
        label: String,
        value: String,
        truncation: RefsCopyTruncation = .middle,
        tag: RefsCopyTag? = nil,
        help: String? = nil,
        confirmationTitle: String,
        alternate: RefsCopyAlternate? = nil
    ) -> RefsCopyRow {
        RefsCopyRow(
            key: key,
            group: group,
            label: label,
            payload: .text(value),
            preview: value,
            truncation: truncation,
            tag: tag,
            help: help,
            confirmationTitle: confirmationTitle,
            alternate: alternate
        )
    }
}

public enum RefsCopyFormat {
    public static func titledWikiLink(link: String, title: String) -> String {
        let alias = title.filter { !"[]|".contains($0) }
        guard !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            link.hasPrefix("[["), link.hasSuffix("]]")
        else { return link }
        let target = link.dropFirst(2).dropLast(2).split(separator: "|", maxSplits: 1).first ?? ""
        return "[[\(target)|\(alias)]]"
    }

    public static func abbreviatedPath(_ path: String, homeDirectoryPath: String) -> String {
        let home =
            homeDirectoryPath.hasSuffix("/")
            ? String(homeDirectoryPath.dropLast()) : homeDirectoryPath
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public static func homeAbbreviatedPath(_ path: String, homeDirectoryPath: String?) -> String {
        guard let homeDirectoryPath else { return path }
        return abbreviatedPath(path, homeDirectoryPath: homeDirectoryPath)
    }

    public static func quoteAlternate(_ annotation: RefsShowAnnotation) -> RefsCopyAlternate? {
        guard !annotation.isStandaloneNote else { return nil }
        if annotation.isGroup {
            let quotes = annotation.pieces.map(\.quote).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !quotes.isEmpty else { return nil }
            let joined = quotes.joined(separator: "\n\n")
            return RefsCopyAlternate(
                label: "Quote only", payload: .text(joined), preview: joined,
                confirmationTitle: "Copied Quote"
            )
        }
        guard let quote = annotation.quote,
            !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return RefsCopyAlternate(
            label: "Quote only", payload: .text(quote), preview: quote,
            confirmationTitle: "Copied Quote"
        )
    }

    public static func noteBlock(_ annotation: RefsShowAnnotation) -> String {
        if annotation.isGroup {
            return groupNoteBlock(annotation)
        }
        var lines: [String] = []
        if let quote = annotation.quote,
            !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lines.append(quote.components(separatedBy: "\n").map {
                $0.isEmpty ? ">" : "> \($0)"
            }.joined(separator: "\n"))
        }
        if let comment = annotation.comment,
            !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            var commentLines = comment.components(separatedBy: "\n")
            commentLines[0] = "Comment: \(commentLines[0])"
            lines.append(commentLines.joined(separator: "\n"))
        }
        if let provenance = provenanceLine(for: annotation) {
            lines.append(provenance)
        }
        return lines.joined(separator: "\n\n")
    }

    /// A tucked `<` group as Copy text: each piece's quote followed by
    /// its own `Comment:` lines, in order, with a blank line between
    /// pieces, then the group's provenance line.
    private static func groupNoteBlock(_ annotation: RefsShowAnnotation) -> String {
        var blocks: [String] = []
        for piece in annotation.pieces {
            if !piece.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(piece.quote.components(separatedBy: "\n").map {
                    $0.isEmpty ? ">" : "> \($0)"
                }.joined(separator: "\n"))
            }
            if let comment = piece.trimmedComment, !comment.isEmpty {
                var commentLines = piece.comment?.components(separatedBy: "\n") ?? []
                if !commentLines.isEmpty {
                    commentLines[0] = "Comment: \(commentLines[0])"
                    blocks.append(commentLines.joined(separator: "\n"))
                }
            }
        }
        if let provenance = provenanceLine(for: annotation) {
            blocks.append(provenance)
        }
        return blocks.joined(separator: "\n\n")
    }

    public static func standaloneNote(_ annotation: RefsShowAnnotation) -> String {
        guard let comment = annotation.comment else { return "" }
        var commentLines = comment.components(separatedBy: "\n")
        commentLines[0] = "Note: \(commentLines[0])"
        var parts = [commentLines.joined(separator: "\n")]
        if let provenance = provenanceLine(for: annotation) {
            parts.append(provenance)
        }
        return parts.joined(separator: "\n")
    }

    public static func allNotes(from row: RefsShowRow) -> String {
        let notes = row.yourNotes
        let sections = row.sections
        var blocks: [String] = []
        if sections.isEmpty {
            blocks = notes.map { annotation -> String in
                annotation.isStandaloneNote ? standaloneNote(annotation) : noteBlock(annotation)
            }.filter { !$0.isEmpty }
        } else {
            let ids = Set(sections.compactMap(\.usableID))
            for section in sections {
                guard let id = section.usableID else { continue }
                let members = notes.filter { $0.section == id }
                let memberBlocks = members.map { annotation -> String in
                    annotation.isStandaloneNote
                        ? standaloneNote(annotation) : noteBlock(annotation)
                }.filter { !$0.isEmpty }
                guard !memberBlocks.isEmpty else { continue }
                var group = ["### \(section.title)"]
                if let description = section.description, !description.isEmpty {
                    group.append(blockquote(description))
                }
                group.append(contentsOf: memberBlocks)
                blocks.append(group.joined(separator: "\n\n"))
            }
            let ungrouped = notes.filter { annotation in
                guard let id = annotation.section else { return true }
                return !ids.contains(id)
            }
            let otherBlocks = ungrouped.map { annotation -> String in
                annotation.isStandaloneNote ? standaloneNote(annotation) : noteBlock(annotation)
            }.filter { !$0.isEmpty }
            if !otherBlocks.isEmpty {
                var group = ["### Other highlights"]
                group.append(contentsOf: otherBlocks)
                blocks.append(group.joined(separator: "\n\n"))
            }
        }
        let ownNotes = row.ownNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ownNotes.isEmpty {
            blocks.append("### Notes\n\n\(ownNotes)")
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func blockquote(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            line.isEmpty ? ">" : "> \(line)"
        }.joined(separator: "\n")
    }

    /// One picker entry: a commented highlight, an uncommented quote
    /// plus provenance, or a standalone note.
    public static func highlightBlock(_ annotation: RefsShowAnnotation) -> String {
        annotation.isStandaloneNote ? standaloneNote(annotation) : noteBlock(annotation)
    }

    /// Every picker entry as blocks, joined by a blank line. `own_notes`
    /// is omitted: A on the card copies those, A in the picker does not.
    public static func allHighlights(from row: RefsShowRow) -> String {
        allHighlights(row.highlightPickerEntries)
    }

    public static func allHighlights(_ annotations: [RefsShowAnnotation]) -> String {
        annotations.map(highlightBlock).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    public static func markdownLink(title: String, url: String) -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        let encodedURL = url
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
        return "[\(escapedTitle)](\(encodedURL))"
    }

    public static func shortPageLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        if label.lowercased().hasPrefix("pages ") {
            return "pp. \(label.dropFirst(6))"
        }
        if label.lowercased().hasPrefix("page ") {
            return "p. \(label.dropFirst(5))"
        }
        return label
    }

    private static func provenanceLine(for annotation: RefsShowAnnotation) -> String? {
        let page = annotation.displayPageLabel
        let link = annotation.link?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLink = link?.isEmpty == false
        guard page != nil || hasLink else { return nil }
        let pieces = [page, hasLink ? link : nil].compactMap { $0 }
        return "— \(pieces.joined(separator: " · "))"
    }
}

public struct RefsCopyCardMetrics: Equatable, Sendable {
    public let headerHeight: Double
    public let rowHeight: Double
    public let separatorHeight: Double
    public let notesHeaderHeight: Double
    public let messageLineHeight: Double
    public let verticalPadding: Double

    public init(
        headerHeight: Double,
        rowHeight: Double,
        separatorHeight: Double,
        notesHeaderHeight: Double,
        messageLineHeight: Double,
        verticalPadding: Double
    ) {
        self.headerHeight = headerHeight
        self.rowHeight = rowHeight
        self.separatorHeight = separatorHeight
        self.notesHeaderHeight = notesHeaderHeight
        self.messageLineHeight = messageLineHeight
        self.verticalPadding = verticalPadding
    }
}

public enum RefsCopyCardLayout {
    public static func noteCapacity(
        cardHeight: Double,
        nonNoteRowCount: Int,
        groupCount: Int,
        metrics: RefsCopyCardMetrics
    ) -> Int {
        let fixedHeight = metrics.headerHeight
            + Double(max(0, nonNoteRowCount)) * metrics.rowHeight
            + Double(max(0, groupCount - 1)) * metrics.separatorHeight
            + metrics.notesHeaderHeight
            + metrics.messageLineHeight
            + metrics.verticalPadding
        guard metrics.rowHeight > 0 else { return 0 }
        return max(0, Int(floor((cardHeight - fixedHeight) / metrics.rowHeight)))
    }

    public static func visibleNoteCount(total: Int, cap: Int) -> Int {
        RefsCopyCatalog.visibleNoteCount(total: total, cap: cap)
    }

    /// How many 36 pt picker rows fit under the card header and message
    /// line, capped at 9.
    public static func highlightWindowSize(
        cardHeight: Double,
        metrics: RefsCopyCardMetrics,
        rowHeight: Double
    ) -> Int {
        let fixedHeight = metrics.headerHeight
            + metrics.messageLineHeight
            + metrics.verticalPadding
        guard rowHeight > 0 else { return 0 }
        return min(9, max(0, Int(floor((cardHeight - fixedHeight) / rowHeight))))
    }

    /// Deterministic height reserved for one picker group header.
    /// The picker uses this to shrink a sectioned window so headers
    /// plus entries still fit the unsectioned row budget.
    public static let pickerGroupHeaderHeight: Double = 22
}

public struct RefsCopyKeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let command = Self(rawValue: 1 << 2)
    public static let option = Self(rawValue: 1 << 3)
    public static let capsLock = Self(rawValue: 1 << 4)
    public static let numericPad = Self(rawValue: 1 << 5)
    public static let function = Self(rawValue: 1 << 6)
    public static let help = Self(rawValue: 1 << 7)

    fileprivate var normalized: Self {
        subtracting([.capsLock, .numericPad, .function, .help])
    }
}

public enum RefsCopyCommand: Equatable, Sendable {
    case key(RefsCopyKey, alternate: Bool = false)
    case copySelected
    case openWindowRow(Int)
    case openSelected
    case move(Int)
    case close
    case showActions
    case unknown(Character)
    case consume
}

/// The entry point that opens a Refs Copy card. Highlights shortcuts use
/// the same card as Command-Y, then seed the selected picker with a key.
public enum RefsCopyEntry: Equatable, Sendable {
    case card
    case code
    case links

    public var seedCommand: RefsCopyCommand? {
        switch self {
        case .card:
            nil
        case .code:
            .key(.codePicker)
        case .links:
            .key(.markdownLink)
        }
    }

    public var retryGlyph: String {
        switch self {
        case .card: "⌘Y"
        case .code: "⌘B"
        case .links: "⌘L"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .card: "Copy menu"
        case .code: "Copy code menu"
        case .links: "Copy link menu"
        }
    }
}

public enum RefsCopyKeyMap {
    public static func command(
        characters: String?,
        keyCode: UInt16,
        modifiers: RefsCopyKeyModifiers
    ) -> RefsCopyCommand {
        let flags = modifiers.normalized
        if keyCode == 36 || keyCode == 76 {
            if flags == .shift || flags == [.shift, .option] {
                return .openSelected
            }
            return flags.isEmpty || flags == .option ? .copySelected : .consume
        }
        if keyCode == 53 {
            return flags.isEmpty ? .close : .consume
        }
        if keyCode == 33 {
            if flags == .control { return .close }
        }
        if keyCode == 16, flags == .command || flags == [.command, .option] {
            return .copySelected
        }
        if keyCode == 40, flags == .command {
            return .showActions
        }
        if keyCode == 125, flags.isEmpty {
            return .move(1)
        }
        if keyCode == 126, flags.isEmpty {
            return .move(-1)
        }
        if flags == .control {
            switch keyCode {
            case 45, 38: return .move(1) // N, J
            case 35, 40: return .move(-1) // P, K
            default: break
            }
        }
        guard flags.subtracting([.shift, .option]).isEmpty,
              let text = characters,
              let character = text.first else {
            return .consume
        }
        if character.unicodeScalars.contains(where: {
            (0xF700...0xF8FF).contains($0.value)
        }) {
            return .consume
        }
        let isASCIIDigit = character.unicodeScalars.count == 1
            && character.unicodeScalars.first.map { (0x30...0x39).contains($0.value) } == true
        if flags.contains(.shift), !isASCIIDigit,
           let position = shiftDigitPosition(for: keyCode) {
            return .openWindowRow(position)
        }
        if let key = RefsCopyKey.parse(character) {
            return .key(key, alternate: flags.contains(.option))
        }
        let isControlCharacter = character.unicodeScalars.allSatisfy {
            CharacterSet.controlCharacters.contains($0)
        }
        return isControlCharacter ? .consume : .unknown(character)
    }

    private static func shiftDigitPosition(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: 1 // kVK_ANSI_1
        case 19: 2 // kVK_ANSI_2
        case 20: 3 // kVK_ANSI_3
        case 21: 4 // kVK_ANSI_4
        case 23: 5 // kVK_ANSI_5
        case 22: 6 // kVK_ANSI_6
        case 26: 7 // kVK_ANSI_7
        case 28: 8 // kVK_ANSI_8
        case 25: 9 // kVK_ANSI_9
        default: nil
        }
    }
}

public struct RefsCopyMessage: Equatable, Sendable {
    public let text: String
    public let isError: Bool
    public let isTransient: Bool

    public init(text: String, isError: Bool = false, isTransient: Bool = false) {
        self.text = text
        self.isError = isError
        self.isTransient = isTransient
    }
}

public enum RefsCopyEffect: Equatable, Sendable {
    case none
    case write(RefsCopyRow)
    case openLink(RefsLinkOpenRequest)
    case close
    case closeThenActions
}

/// Value-state for the in-panel card. It only exposes effects; writing the
/// pasteboard, starting the show request, and scheduling timers stay in the app.
public struct RefsCopyCard: Equatable, Sendable {
    public let token: UInt64
    public let frozenItemID: String
    public let item: RefItem
    public let absolutePDFPath: String?
    public let pdfExists: Bool
    public let absoluteNotePath: String?
    public let homeDirectoryPath: String?
    public let narrationFileURL: URL?
    public let highlightedPage: Int?
    private var pendingAlternate = false
    private enum PendingLoad: Equatable { case notes, code, links }
    private var pendingLoad: PendingLoad?
    private var retryRow: RefsCopyRow?
    public private(set) var notes: RefsCopyNotesState
    public private(set) var code: RefsCodeLoadState
    public private(set) var links: RefsLinksLoadState
    public private(set) var noteCapacity: Int
    public private(set) var rows: [RefsCopyRow]
    public private(set) var selectedKey: RefsCopyKey
    public private(set) var pending: RefsCopyKey?
    public private(set) var message: RefsCopyMessage?
    public private(set) var isClosed: Bool
    public private(set) var pickerWindowSize: Int
    public var pickerGroupHeaderHeight: Double
    public var pickerRowHeight: Double
    public private(set) var highlightPicker: RefsHighlightPicker?
    public private(set) var codePicker: RefsCodePicker?
    public private(set) var linkPicker: RefsLinkPicker?
    private var queuedCommands: [QueuedCopyCommand] = []
    private static let commandQueueCap = 16

    private struct QueuedCopyCommand: Equatable, Sendable {
        var command: RefsCopyCommand
        var alternatesActive: Bool
    }

    public init(
        token: UInt64,
        item: RefItem,
        absolutePDFPath: String?,
        pdfExists: Bool,
        notes: RefsCopyNotesState,
        noteCapacity: Int,
        pickerWindowSize: Int = 9,
        pickerGroupHeaderHeight: Double = 0,
        pickerRowHeight: Double = 36,
        absoluteNotePath: String? = nil,
        homeDirectoryPath: String? = nil,
        narrationFileURL: URL? = nil,
        code: RefsCodeLoadState = .notRequested,
        links: RefsLinksLoadState = .notRequested,
        highlightedPage: Int? = nil
    ) {
        self.token = token
        frozenItemID = item.id
        self.item = item
        self.absolutePDFPath = absolutePDFPath
        self.pdfExists = pdfExists
        self.absoluteNotePath = absoluteNotePath
        self.homeDirectoryPath = homeDirectoryPath
        self.narrationFileURL = narrationFileURL
        self.highlightedPage = highlightedPage
        self.notes = notes
        self.code = code
        self.links = links
        self.noteCapacity = max(0, noteCapacity)
        self.pickerWindowSize = min(9, max(0, pickerWindowSize))
        self.pickerGroupHeaderHeight = max(0, pickerGroupHeaderHeight)
        self.pickerRowHeight = max(0, pickerRowHeight)
        let catalog = RefsCopyCatalog(
            item: item,
            absolutePDFPath: absolutePDFPath,
            pdfExists: pdfExists,
            notes: notes,
            noteCapacity: noteCapacity,
            absoluteNotePath: absoluteNotePath,
            homeDirectoryPath: homeDirectoryPath,
            narrationFileURL: narrationFileURL,
            code: code,
            links: links,
            highlightedPage: highlightedPage
        )
        rows = catalog.rows
        selectedKey = catalog.defaultKey
        pending = nil
        message = nil
        isClosed = false
        highlightPicker = nil
        codePicker = nil
        linkPicker = nil
        pendingLoad = nil
        queuedCommands = []
    }

    public var catalog: RefsCopyCatalog {
        RefsCopyCatalog(
            item: item,
            absolutePDFPath: absolutePDFPath,
            pdfExists: pdfExists,
            notes: notes,
            noteCapacity: noteCapacity,
            absoluteNotePath: absoluteNotePath,
            homeDirectoryPath: homeDirectoryPath,
            narrationFileURL: narrationFileURL,
            code: code,
            links: links,
            highlightedPage: highlightedPage
        )
    }

    @discardableResult
    public mutating func handle(
        _ command: RefsCopyCommand, alternatesActive: Bool = false
    ) -> RefsCopyEffect {
        guard !isClosed else { return .none }
        var command = command
        if item.sourceMarkdown != nil, case .key(.markdownLink, let alternate) = command {
            command = .key(.linkPicker, alternate: alternate)
        }
        if command == .copySelected, let retryRow {
            return .write(retryRow)
        }
        if command != .consume { retryRow = nil }
        switch command {
        case .close, .showActions, .consume:
            return perform(command, alternatesActive: alternatesActive)
        default:
            break
        }
        if pending != nil {
            enqueue(command, alternatesActive: alternatesActive)
            return .none
        }
        return perform(command, alternatesActive: alternatesActive)
    }

    @discardableResult
    public mutating func notesLoaded(path: String, row: RefsShowRow) -> RefsCopyEffect {
        guard !isClosed, path == frozenItemID, row.path == frozenItemID else { return .none }
        notes = .loaded(row)
        refreshRows()
        guard pendingLoad == .notes else { return .none }
        let resolved = resolvePendingAfterLoad()
        return replayQueued(after: resolved)
    }

    public mutating func notesFailed(path: String) {
        guard !isClosed, path == frozenItemID else { return }
        notes = .unavailable
        refreshRows()
        guard pendingLoad == .notes else { return }
        queuedCommands = []
        if pending != nil {
            pending = nil
            pendingLoad = nil
            message = RefsCopyMessage(
                text: "Notes unavailable — nothing copied",
                isError: true
            )
        }
    }

    public mutating func pendingTimedOut() {
        guard !isClosed, pending != nil else { return }
        let load = pendingLoad
        pending = nil
        pendingLoad = nil
        queuedCommands = []
        let text: String
        switch load {
        case .code:
            text = "Code unavailable — nothing copied"
        case .links:
            text = "Links unavailable — nothing copied"
        case .notes, nil:
            text = "Notes didn't load — nothing copied"
        }
        message = RefsCopyMessage(text: text, isError: true)
    }

    @discardableResult
    public mutating func codeLoaded(path: String, response: RefsCodeResponse) -> RefsCopyEffect {
        guard !isClosed,
              path == frozenItemID,
              response.reference.path == frozenItemID
        else { return .none }
        code = .loaded(response)
        refreshRows()
        guard pendingLoad == .code else { return .none }
        let resolved = resolvePendingAfterLoad()
        return replayQueued(after: resolved)
    }

    public mutating func codeFailed(path: String, unsupported: Bool = false) {
        guard !isClosed, path == frozenItemID else { return }
        code = unsupported ? .unsupported : .failed
        refreshRows()
        guard pendingLoad == .code else { return }
        queuedCommands = []
        let key = pending
        pending = nil
        pendingLoad = nil
        let reason = key.flatMap { catalog.hiddenReason(for: $0) }
            ?? "Code unavailable — nothing copied"
        message = RefsCopyMessage(text: reason, isError: true)
    }

    @discardableResult
    public mutating func linksLoaded(path: String, response: RefsLinksResponse) -> RefsCopyEffect {
        guard !isClosed,
              path == frozenItemID,
              response.reference.path == frozenItemID
        else { return .none }
        links = .loaded(response)
        refreshRows()
        guard pendingLoad == .links else { return .none }
        let resolved = resolvePendingAfterLoad()
        return replayQueued(after: resolved)
    }

    public mutating func linksFailed(path: String, unsupported: Bool = false) {
        guard !isClosed, path == frozenItemID else { return }
        links = unsupported ? .unsupported : .failed
        refreshRows()
        guard pendingLoad == .links else { return }
        queuedCommands = []
        let key = pending
        pending = nil
        pendingLoad = nil
        let reason = key.flatMap { catalog.hiddenReason(for: $0) }
            ?? "Links unavailable — nothing copied"
        message = RefsCopyMessage(text: reason, isError: true)
    }

    public mutating func writeFailed(key: RefsCopyKey, attemptedRow: RefsCopyRow? = nil) {
        guard !isClosed else { return }
        if highlightPicker == nil, rows.contains(where: { $0.key == key }) {
            selectedKey = key
        }
        retryRow = attemptedRow ?? rows.first { $0.key == key }
        message = RefsCopyMessage(text: "Couldn't copy — ↵ tries again", isError: true)
    }

    public mutating func writeUnavailable(key: RefsCopyKey) {
        guard !isClosed else { return }
        if rows.contains(where: { $0.key == key }) {
            selectedKey = key
        }
        message = RefsCopyMessage(
            text: "Nothing to copy — this value is unavailable",
            isError: true
        )
    }

    public mutating func select(_ key: RefsCopyKey) {
        guard !isClosed, rows.contains(where: { $0.key == key }) else { return }
        selectedKey = key
        message = nil
    }

    public mutating func clearTransientMessage() {
        if pending != nil {
            message = waitingMessage
            return
        }
        guard message?.isTransient == true else { return }
        message = nil
    }

    public mutating func setNoteCapacity(_ capacity: Int) {
        guard !isClosed else { return }
        noteCapacity = max(0, capacity)
        let previousSelection = selectedKey
        refreshRows()
        if rows.contains(where: { $0.key == previousSelection }) {
            selectedKey = previousSelection
        } else if highlightPicker == nil {
            selectedKey = catalog.defaultKey
        }
    }

    public mutating func setPickerWindowSize(_ size: Int) {
        guard !isClosed else { return }
        pickerWindowSize = min(9, max(0, size))
        if var picker = highlightPicker {
            picker.groupHeaderHeight = pickerGroupHeaderHeight
            picker.entryRowHeight = pickerRowHeight
            picker.setWindowSize(max(1, pickerWindowSize))
            highlightPicker = picker
        }
        if var codePicker {
            codePicker.setMetrics(
                groupHeaderHeight: pickerGroupHeaderHeight,
                entryRowHeight: pickerRowHeight
            )
            codePicker.setWindowSize(max(2, pickerWindowSize))
            self.codePicker = codePicker
        }
        if var linkPicker {
            linkPicker.setMetrics(
                groupHeaderHeight: pickerGroupHeaderHeight,
                entryRowHeight: pickerRowHeight
            )
            linkPicker.setWindowSize(max(2, pickerWindowSize))
            self.linkPicker = linkPicker
        }
    }

    private mutating func perform(
        _ command: RefsCopyCommand, alternatesActive: Bool
    ) -> RefsCopyEffect {
        if linkPicker != nil {
            return handleLinkPicker(command, alternatesActive: alternatesActive)
        }
        if codePicker != nil {
            return handleCodePicker(command, alternatesActive: alternatesActive)
        }
        if highlightPicker != nil {
            return handlePicker(command, alternatesActive: alternatesActive)
        }
        switch command {
        case .openWindowRow(let number):
            pending = nil
            message = RefsCopyMessage(text: "Nothing on ‘⇧\(number)’", isTransient: true)
            return .none
        case .openSelected:
            return .none
        case .key(let key, let alternate):
            if case .loading = links, isLinkKey(key) {
                pending = key
                pendingLoad = .links
                pendingAlternate = alternate
                message = RefsCopyMessage(text: "Loading links… esc cancels")
                return .none
            }
            if case .loading = code, isCodeKey(key) {
                pending = key
                pendingLoad = .code
                pendingAlternate = alternate
                message = RefsCopyMessage(text: "Loading code… esc cancels")
                return .none
            }
            if case .loading = notes, isNotesKey(key) {
                pending = key
                pendingLoad = .notes
                pendingAlternate = alternate
                message = RefsCopyMessage(text: "Waiting for notes… esc cancels")
                return .none
            }
            pending = nil
            pendingLoad = nil
            if key == .highlightPicker {
                return openHighlightPicker()
            }
            if key == .codePicker {
                return openCodePicker()
            }
            if key == .linkPicker {
                return openLinkPicker()
            }
            if let row = rows.first(where: { $0.key == key }) {
                selectedKey = key
                message = nil
                return .write(row.resolved(alternate: alternate))
            }
            message = catalog.hiddenReason(for: key).map {
                RefsCopyMessage(text: $0, isError: $0.hasPrefix("Notes unavailable"))
            }
            return .none
        case .copySelected:
            if selectedKey == .highlightPicker {
                return openHighlightPicker()
            }
            if selectedKey == .codePicker {
                return openCodePicker()
            }
            if selectedKey == .linkPicker {
                return openLinkPicker()
            }
            guard let row = rows.first(where: { $0.key == selectedKey }) else {
                return .none
            }
            message = nil
            return .write(row.resolved(alternate: alternatesActive))
        case .move(let delta):
            guard !rows.isEmpty, delta != 0 else { return .none }
            let current = rows.firstIndex(where: { $0.key == selectedKey }) ?? 0
            let next = (current + delta % rows.count + rows.count) % rows.count
            selectedKey = rows[next].key
            message = pending == nil
                ? nil
                : waitingMessage
            return .none
        case .close:
            pending = nil
            pendingLoad = nil
            queuedCommands = []
            message = nil
            isClosed = true
            return .close
        case .showActions:
            pending = nil
            pendingLoad = nil
            queuedCommands = []
            message = nil
            isClosed = true
            return .closeThenActions
        case .unknown(let character):
            pending = nil
            pendingLoad = nil
            message = RefsCopyMessage(text: "Nothing on ‘\(character)’", isTransient: true)
            return .none
        case .consume:
            return .none
        }
    }

    private mutating func enqueue(
        _ command: RefsCopyCommand, alternatesActive: Bool
    ) {
        guard queuedCommands.count < Self.commandQueueCap else { return }
        queuedCommands.append(
            QueuedCopyCommand(command: command, alternatesActive: alternatesActive)
        )
    }

    private mutating func resolvePendingAfterLoad() -> RefsCopyEffect {
        guard let pending else { return .none }
        self.pending = nil
        let load = pendingLoad
        pendingLoad = nil
        if load == .code, pending == .codePicker {
            return openCodePicker()
        }
        if load == .links, pending == .linkPicker {
            return openLinkPicker()
        }
        if pending == .highlightPicker {
            return openHighlightPicker()
        }
        if let value = rows.first(where: { $0.key == pending }) {
            message = nil
            selectedKey = pending
            return .write(value.resolved(alternate: pendingAlternate))
        }
        let reason = catalog.hiddenReason(for: pending) ?? "No notes on this reference"
        message = RefsCopyMessage(text: reason, isError: reason.hasPrefix("Notes unavailable"))
        return .none
    }

    private var waitingMessage: RefsCopyMessage {
        switch pendingLoad {
        case .code:
            return RefsCopyMessage(text: "Loading code… esc cancels")
        case .links:
            return RefsCopyMessage(text: "Loading links… esc cancels")
        case .notes, nil:
            return RefsCopyMessage(text: "Waiting for notes… esc cancels")
        }
    }

    private mutating func handleLinkPicker(
        _ command: RefsCopyCommand,
        alternatesActive: Bool
    ) -> RefsCopyEffect {
        switch command {
        case .key(let key, let alternate):
            if case .note(let number) = key {
                return copyLinkPickerWindowRow(number, markdown: alternate)
            }
            if key == .allNotes {
                return copyAllLinks(markdown: alternate)
            }
            pending = nil
            message = RefsCopyMessage(
                text: "Nothing on ‘\(key.glyph.lowercased())’",
                isTransient: true
            )
            return .none
        case .copySelected:
            return copyLinkPickerSelection(markdown: alternatesActive)
        case .openWindowRow(let number):
            return openLinkPickerWindowRow(number)
        case .openSelected:
            return openLinkPickerSelection()
        case .move(let delta):
            guard var picker = linkPicker else { return .none }
            picker.move(delta)
            linkPicker = picker
            message = nil
            return .none
        case .close:
            linkPicker = nil
            message = nil
            return .none
        case .showActions:
            linkPicker = nil
            pending = nil
            pendingLoad = nil
            message = nil
            isClosed = true
            return .closeThenActions
        case .unknown(let character):
            pending = nil
            message = RefsCopyMessage(
                text: "Nothing on ‘\(character)’",
                isTransient: true
            )
            return .none
        case .consume:
            return .none
        }
    }

    private mutating func openLinkPicker() -> RefsCopyEffect {
        guard case .loaded(let response) = links,
              response.reference.path == frozenItemID,
              response.status == .available,
              !response.links.isEmpty
        else {
            let reason = catalog.hiddenReason(for: .linkPicker)
                ?? "No links in this reference"
            message = RefsCopyMessage(text: reason, isError: true)
            return .none
        }
        selectedKey = .linkPicker
        var picker = RefsLinkPicker(
            links: response.links,
            highlightedPage: highlightedPage,
            windowSize: max(2, pickerWindowSize),
            groupHeaderHeight: pickerGroupHeaderHeight,
            entryRowHeight: pickerRowHeight
        )
        picker.setMetrics(
            groupHeaderHeight: pickerGroupHeaderHeight,
            entryRowHeight: pickerRowHeight
        )
        linkPicker = picker
        message = nil
        return .none
    }

    private mutating func copyLinkPickerWindowRow(
        _ number: Int,
        markdown: Bool
    ) -> RefsCopyEffect {
        guard var picker = linkPicker else { return .none }
        guard let entry = picker.selectWindowPosition(number) else {
            message = RefsCopyMessage(text: "No link \(number)")
            return .none
        }
        linkPicker = picker
        message = nil
        return .write(entry.copyRow(markdown: markdown))
    }

    private mutating func copyLinkPickerSelection(markdown: Bool) -> RefsCopyEffect {
        guard let entry = linkPicker?.selectedEntry else { return .none }
        message = nil
        return .write(entry.copyRow(markdown: markdown))
    }

    private mutating func openLinkPickerWindowRow(_ number: Int) -> RefsCopyEffect {
        guard var picker = linkPicker else { return .none }
        guard let entry = picker.selectWindowPosition(number) else {
            message = RefsCopyMessage(text: "No link \(number)")
            return .none
        }
        linkPicker = picker
        return openLinkPickerEntry(entry)
    }

    private mutating func openLinkPickerSelection() -> RefsCopyEffect {
        guard let entry = linkPicker?.selectedEntry else { return .none }
        return openLinkPickerEntry(entry)
    }

    private mutating func openLinkPickerEntry(
        _ entry: RefsLinkPicker.Entry
    ) -> RefsCopyEffect {
        guard let url = entry.link.webURL else {
            message = RefsCopyMessage(
                text: "Only web links open — ↵ copies it",
                isError: true
            )
            return .none
        }
        message = nil
        return .openLink(RefsLinkOpenRequest(link: entry.link, url: url))
    }

    private mutating func copyAllLinks(markdown: Bool) -> RefsCopyEffect {
        guard let picker = linkPicker, !picker.entries.isEmpty else {
            message = RefsCopyMessage(text: "No links in this reference")
            return .none
        }
        message = nil
        return .write(picker.allLinksRow(markdown: markdown))
    }

    private mutating func handleCodePicker(
        _ command: RefsCopyCommand,
        alternatesActive: Bool
    ) -> RefsCopyEffect {
        switch command {
        case .key(let key, let alternate):
            if case .note(let number) = key {
                return copyCodePickerWindowRow(number, fenced: alternate)
            }
            pending = nil
            message = RefsCopyMessage(
                text: "Nothing on ‘\(key.glyph.lowercased())’",
                isTransient: true
            )
            return .none
        case .copySelected:
            return copyCodePickerSelection(fenced: alternatesActive)
        case .openWindowRow(let number):
            pending = nil
            message = RefsCopyMessage(text: "Nothing on ‘⇧\(number)’", isTransient: true)
            return .none
        case .openSelected:
            return .none
        case .move(let delta):
            guard var picker = codePicker else { return .none }
            picker.move(delta)
            codePicker = picker
            message = nil
            return .none
        case .close:
            codePicker = nil
            message = nil
            return .none
        case .showActions:
            codePicker = nil
            pending = nil
            pendingLoad = nil
            message = nil
            isClosed = true
            return .closeThenActions
        case .unknown(let character):
            pending = nil
            message = RefsCopyMessage(
                text: "Nothing on ‘\(character)’",
                isTransient: true
            )
            return .none
        case .consume:
            return .none
        }
    }

    private mutating func openCodePicker() -> RefsCopyEffect {
        guard case .loaded(let response) = code,
              response.reference.path == frozenItemID,
              response.status == .available,
              !response.blocks.isEmpty
        else {
            let reason = catalog.hiddenReason(for: .codePicker)
                ?? "No code blocks in this reference"
            message = RefsCopyMessage(text: reason, isError: true)
            return .none
        }
        selectedKey = .codePicker
        var picker = RefsCodePicker(
            blocks: response.blocks,
            highlightedPage: highlightedPage,
            windowSize: max(2, pickerWindowSize),
            groupHeaderHeight: pickerGroupHeaderHeight,
            entryRowHeight: pickerRowHeight
        )
        picker.setMetrics(
            groupHeaderHeight: pickerGroupHeaderHeight,
            entryRowHeight: pickerRowHeight
        )
        codePicker = picker
        message = nil
        return .none
    }

    private mutating func copyCodePickerWindowRow(
        _ number: Int,
        fenced: Bool
    ) -> RefsCopyEffect {
        guard var picker = codePicker else { return .none }
        guard let entry = picker.selectWindowPosition(number) else {
            message = RefsCopyMessage(text: "No code block \(number)")
            return .none
        }
        codePicker = picker
        message = nil
        return .write(entry.copyRow(fenced: fenced))
    }

    private mutating func copyCodePickerSelection(fenced: Bool) -> RefsCopyEffect {
        guard let entry = codePicker?.selectedEntry else { return .none }
        message = nil
        return .write(entry.copyRow(fenced: fenced))
    }

    private mutating func replayQueued(after first: RefsCopyEffect) -> RefsCopyEffect {
        if isTerminal(first) {
            queuedCommands = []
            return first
        }
        var last = first
        while !queuedCommands.isEmpty {
            let next = queuedCommands.removeFirst()
            let effect = perform(next.command, alternatesActive: next.alternatesActive)
            if isTerminal(effect) {
                queuedCommands = []
                return effect
            }
            last = effect
        }
        return last
    }

    private func isTerminal(_ effect: RefsCopyEffect) -> Bool {
        switch effect {
        case .write, .openLink, .close, .closeThenActions:
            return true
        case .none:
            return false
        }
    }

    private mutating func handlePicker(
        _ command: RefsCopyCommand, alternatesActive: Bool
    ) -> RefsCopyEffect {
        switch command {
        case .key(let key, let alternate):
            switch key {
            case .note(let number):
                return copyPickerWindowRow(number, alternate: alternate)
            case .allNotes:
                return copyAllHighlights()
            default:
                pending = nil
                message = RefsCopyMessage(
                    text: "Nothing on ‘\(key.glyph.lowercased())’",
                    isTransient: true
                )
                return .none
            }
        case .copySelected:
            return copyPickerSelection(alternate: alternatesActive)
        case .openWindowRow(let number):
            pending = nil
            message = RefsCopyMessage(text: "Nothing on ‘⇧\(number)’", isTransient: true)
            return .none
        case .openSelected:
            return .none
        case .move(let delta):
            guard var picker = highlightPicker else { return .none }
            picker.move(delta)
            highlightPicker = picker
            message = nil
            return .none
        case .close:
            highlightPicker = nil
            message = nil
            return .none
        case .showActions:
            highlightPicker = nil
            pending = nil
            message = nil
            isClosed = true
            return .closeThenActions
        case .unknown(let character):
            pending = nil
            message = RefsCopyMessage(
                text: "Nothing on ‘\(character)’",
                isTransient: true
            )
            return .none
        case .consume:
            return .none
        }
    }

    private mutating func openHighlightPicker() -> RefsCopyEffect {
        guard case .loaded(let row) = notes else {
            if let reason = catalog.hiddenReason(for: .highlightPicker) {
                message = RefsCopyMessage(
                    text: reason,
                    isError: reason.hasPrefix("Notes unavailable")
                )
            }
            return .none
        }
        let entries = RefsHighlightPicker.entries(from: row)
        guard !entries.isEmpty else {
            message = RefsCopyMessage(text: "No highlights on this reference")
            return .none
        }
        selectedKey = .highlightPicker
        highlightPicker = RefsHighlightPicker(
            entries: entries,
            windowSize: max(1, pickerWindowSize),
            groupHeaderHeight: pickerGroupHeaderHeight,
            entryRowHeight: pickerRowHeight
        )
        message = nil
        return .none
    }

    private mutating func copyPickerWindowRow(_ number: Int, alternate: Bool) -> RefsCopyEffect {
        guard var picker = highlightPicker else { return .none }
        guard let entry = picker.selectWindowPosition(number) else {
            message = RefsCopyMessage(text: "No highlight \(number)")
            return .none
        }
        highlightPicker = picker
        message = nil
        return .write(entry.copyRow(key: .note(number)).resolved(alternate: alternate))
    }

    private mutating func copyPickerSelection(alternate: Bool) -> RefsCopyEffect {
        guard let picker = highlightPicker,
              let entry = picker.selectedEntry
        else {
            return .none
        }
        message = nil
        let position = picker.selectedIndex - picker.windowStart + 1
        return .write(entry.copyRow(key: .note(max(1, position))).resolved(alternate: alternate))
    }

    private mutating func copyAllHighlights() -> RefsCopyEffect {
        guard let picker = highlightPicker, !picker.entries.isEmpty else {
            message = RefsCopyMessage(text: "No highlights on this reference")
            return .none
        }
        message = nil
        return .write(picker.allHighlightsRow())
    }

    private mutating func refreshRows() {
        let previousSelection = selectedKey
        rows = catalog.rows
        if rows.contains(where: { $0.key == previousSelection }) {
            selectedKey = previousSelection
        } else if highlightPicker == nil, codePicker == nil, linkPicker == nil {
            selectedKey = catalog.defaultKey
        }
    }

    private func isNotesKey(_ key: RefsCopyKey) -> Bool {
        if case .note = key { return true }
        return key == .allNotes || key == .highlightPicker
    }

    private func isCodeKey(_ key: RefsCopyKey) -> Bool {
        key == .codePicker || key == .sourceMarkdown
    }

    private func isLinkKey(_ key: RefsCopyKey) -> Bool {
        key == .linkPicker
    }
}
