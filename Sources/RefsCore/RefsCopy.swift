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

    public var glyph: String {
        switch self {
        case .markerID: "I"
        case .title: "T"
        case .wikiLink: "W"
        case .sourceURL: "U"
        case .markdownLink: "L"
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
        case "1"..."9": Int(String(character)).map(RefsCopyKey.note)
        default: nil
        }
    }
}

public enum RefsCopyGroup: Equatable, Hashable, Sendable {
    case identity
    case sources
    case files
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

    private let item: RefItem
    private let absolutePDFPath: String?
    private let pdfExists: Bool
    private let noteCapacity: Int

    public init(
        item: RefItem,
        absolutePDFPath: String?,
        pdfExists: Bool,
        notes: RefsCopyNotesState,
        noteCapacity: Int,
        absoluteNotePath: String? = nil,
        homeDirectoryPath: String? = nil,
        narrationFileURL: URL? = nil
    ) {
        self.item = item
        self.absolutePDFPath = absolutePDFPath
        self.pdfExists = pdfExists
        self.noteCapacity = max(0, noteCapacity)
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
            built.append(Self.valueRow(
                key: .sourceURL,
                group: .sources,
                label: "Source URL",
                value: sourceURL,
                confirmationTitle: "Copied Source URL"
            ))
            built.append(Self.valueRow(
                key: .markdownLink,
                group: .sources,
                label: "Markdown link",
                value: RefsCopyFormat.markdownLink(title: item.rawTitle, url: sourceURL),
                truncation: .middle,
                confirmationTitle: "Copied Markdown Link"
            ))
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
        var blocks = row.yourNotes.map { annotation -> String in
            annotation.isStandaloneNote ? standaloneNote(annotation) : noteBlock(annotation)
        }.filter { !$0.isEmpty }
        let ownNotes = row.ownNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ownNotes.isEmpty {
            blocks.append("### Notes\n\n\(ownNotes)")
        }
        return blocks.joined(separator: "\n\n")
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
    case move(Int)
    case close
    case showActions
    case unknown(Character)
    case consume
}

public enum RefsCopyKeyMap {
    public static func command(
        characters: String?,
        keyCode: UInt16,
        modifiers: RefsCopyKeyModifiers
    ) -> RefsCopyCommand {
        let flags = modifiers.normalized
        if keyCode == 36 || keyCode == 76 {
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
        if let key = RefsCopyKey.parse(character) {
            return .key(key, alternate: flags.contains(.option))
        }
        let isControlCharacter = character.unicodeScalars.allSatisfy {
            CharacterSet.controlCharacters.contains($0)
        }
        return isControlCharacter ? .consume : .unknown(character)
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
    private var pendingAlternate = false
    private var retryRow: RefsCopyRow?
    public private(set) var notes: RefsCopyNotesState
    public private(set) var noteCapacity: Int
    public private(set) var rows: [RefsCopyRow]
    public private(set) var selectedKey: RefsCopyKey
    public private(set) var pending: RefsCopyKey?
    public private(set) var message: RefsCopyMessage?
    public private(set) var isClosed: Bool
    public private(set) var pickerWindowSize: Int
    public private(set) var highlightPicker: RefsHighlightPicker?

    public init(
        token: UInt64,
        item: RefItem,
        absolutePDFPath: String?,
        pdfExists: Bool,
        notes: RefsCopyNotesState,
        noteCapacity: Int,
        pickerWindowSize: Int = 9,
        absoluteNotePath: String? = nil,
        homeDirectoryPath: String? = nil,
        narrationFileURL: URL? = nil
    ) {
        self.token = token
        frozenItemID = item.id
        self.item = item
        self.absolutePDFPath = absolutePDFPath
        self.pdfExists = pdfExists
        self.absoluteNotePath = absoluteNotePath
        self.homeDirectoryPath = homeDirectoryPath
        self.narrationFileURL = narrationFileURL
        self.notes = notes
        self.noteCapacity = max(0, noteCapacity)
        self.pickerWindowSize = min(9, max(0, pickerWindowSize))
        let catalog = RefsCopyCatalog(
            item: item,
            absolutePDFPath: absolutePDFPath,
            pdfExists: pdfExists,
            notes: notes,
            noteCapacity: noteCapacity,
            absoluteNotePath: absoluteNotePath,
            homeDirectoryPath: homeDirectoryPath,
            narrationFileURL: narrationFileURL
        )
        rows = catalog.rows
        selectedKey = catalog.defaultKey
        pending = nil
        message = nil
        isClosed = false
        highlightPicker = nil
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
            narrationFileURL: narrationFileURL
        )
    }

    @discardableResult
    public mutating func handle(
        _ command: RefsCopyCommand, alternatesActive: Bool = false
    ) -> RefsCopyEffect {
        guard !isClosed else { return .none }
        if command == .copySelected, let retryRow {
            return .write(retryRow)
        }
        if command != .consume { retryRow = nil }
        if highlightPicker != nil {
            return handlePicker(command, alternatesActive: alternatesActive)
        }
        switch command {
        case .key(let key, let alternate):
            if case .loading = notes, isNotesKey(key) {
                pending = key
                pendingAlternate = alternate
                message = RefsCopyMessage(text: "Waiting for notes… esc cancels")
                return .none
            }
            pending = nil
            if key == .highlightPicker {
                return openHighlightPicker()
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
                : RefsCopyMessage(text: "Waiting for notes… esc cancels")
            return .none
        case .close:
            pending = nil
            message = nil
            isClosed = true
            return .close
        case .showActions:
            pending = nil
            message = nil
            isClosed = true
            return .closeThenActions
        case .unknown(let character):
            pending = nil
            message = RefsCopyMessage(text: "Nothing on ‘\(character)’", isTransient: true)
            return .none
        case .consume:
            return .none
        }
    }

    @discardableResult
    public mutating func notesLoaded(path: String, row: RefsShowRow) -> RefsCopyEffect {
        guard !isClosed, path == frozenItemID, row.path == frozenItemID else { return .none }
        notes = .loaded(row)
        refreshRows()
        guard let pending else { return .none }
        self.pending = nil
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

    public mutating func notesFailed(path: String) {
        guard !isClosed, path == frozenItemID else { return }
        notes = .unavailable
        refreshRows()
        if pending != nil {
            pending = nil
            message = RefsCopyMessage(
                text: "Notes unavailable — nothing copied",
                isError: true
            )
        }
    }

    public mutating func pendingTimedOut() {
        guard !isClosed, pending != nil else { return }
        pending = nil
        message = RefsCopyMessage(text: "Notes didn't load — nothing copied", isError: true)
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
            message = RefsCopyMessage(text: "Waiting for notes… esc cancels")
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
        guard var picker = highlightPicker else { return }
        picker.setWindowSize(max(1, pickerWindowSize))
        highlightPicker = picker
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
            windowSize: max(1, pickerWindowSize)
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
        } else if highlightPicker == nil {
            selectedKey = catalog.defaultKey
        }
    }

    private func isNotesKey(_ key: RefsCopyKey) -> Bool {
        if case .note = key { return true }
        return key == .allNotes || key == .highlightPicker
    }
}
