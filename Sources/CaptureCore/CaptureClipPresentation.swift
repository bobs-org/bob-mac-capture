import Foundation

/// Pure presentation model for Bob's `clip` object on one capture, built once
/// from `CaptureCommandSuccess` so the SwiftUI layer never branches on clip
/// JSON fields or spells a clip string literal itself. Works equally for a
/// live-preview dry run that read the clipboard and a committed capture — the
/// card always describes the same `clip` object.
///
/// A `%c` Bob read has `status == "read"`, a `mode` (`inline`, `lines`,
/// `attachments`, `snippet`, or `history`), and the rendered child `lines`,
/// `attachments`, optional `snippet` destination, and history `entries` (each
/// entry is itself a read clip object). A `%c` Bob was told not to read has
/// only `status` and `count`, and renders as a quiet placeholder. Nil when
/// the capture carries no `clip` object at all (a draft without `%c`).
public struct CaptureClipPresentation: Equatable, Sendable {
    /// One clipboard file Bob saved: its `saved` vault path, `kind`
    /// (`image` or `file`), the pasteboard `source` it was read from, and
    /// whether Bob reused an earlier save. The card renders one summary row
    /// per attachment, plus a thumbnail for images whose source is readable.
    /// A missing or unreadable source keeps its summary row.
    public struct AttachmentRow: Equatable, Sendable {
        /// `"img/shot.png · image"` (`" · reused"` appended when reused).
        public let summaryText: String
        /// Pasteboard path Bob read the bytes from; the thumbnail source.
        public let source: String
        /// Bob's `saved` vault path.
        public let savedPath: String
        public let kind: String
        public let isImage: Bool
        public let reused: Bool

        public init(
            summaryText: String,
            source: String,
            savedPath: String,
            kind: String,
            isImage: Bool,
            reused: Bool
        ) {
            self.summaryText = summaryText
            self.source = source
            self.savedPath = savedPath
            self.kind = kind
            self.isImage = isImage
            self.reused = reused
        }
    }

    /// One `%c<N>` history entry: its divider plus the entry's own mode,
    /// exact child lines, snippet destination, and attachments. Entry lines
    /// are Bob's exact bytes, the same lines flattened onto the top-level
    /// `lines` for the written block.
    public struct HistoryEntry: Equatable, Sendable {
        /// `"Entry 1 of 3"`.
        public let dividerText: String
        /// The entry's own mode (`inline`, `attachments`, …).
        public let modeText: String
        public let lines: [String]
        public let snippetDestination: String?
        public let attachmentRows: [AttachmentRow]

        public init(
            dividerText: String,
            modeText: String,
            lines: [String],
            snippetDestination: String?,
            attachmentRows: [AttachmentRow]
        ) {
            self.dividerText = dividerText
            self.modeText = modeText
            self.lines = lines
            self.snippetDestination = snippetDestination
            self.attachmentRows = attachmentRows
        }
    }

    /// Kind header: `"Clipboard · 3 lines"`, `"2 files · 1 image"`,
    /// `"Snippet · 42 lines → file/clip-…md"`, `"Last 3 clips"`, or
    /// `"Clipboard"` beside the quiet placeholder when unread.
    public let headerText: String
    /// Bob's exact child lines, as they will be written. The item's verbatim
    /// `previewBlockLines` stack carries the same bytes as the write block;
    /// the task-block dedup keeps matching them there, so this card never
    /// feeds lines into a task block.
    public let childLines: [String]
    /// Snippet-mode note destination (`snippet`), nil otherwise.
    public let snippetDestination: String?
    public let attachmentRows: [AttachmentRow]
    /// History-mode entries in Bob's newest-first order; empty otherwise.
    public let historyEntries: [HistoryEntry]
    public let isHistory: Bool
    /// True when Bob did not read the clipboard (`status == "not_read"` or
    /// an unknown status): the card shows only the quiet placeholder.
    public let showsPlaceholder: Bool
    /// Lines shown above the card's attachment and history sections. History
    /// lines appear only inside their entry dividers.
    public var topLevelChildLines: [String] {
        isHistory ? [] : childLines
    }
    /// Quiet placeholder copy (`"Clipboard not read"`), nil when read.
    public let placeholderText: String?
    public let accessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let clip = capture.clip else {
            return nil
        }
        guard clip.wasRead else {
            self.init(
                headerText: "Clipboard",
                childLines: [],
                snippetDestination: nil,
                attachmentRows: [],
                historyEntries: [],
                isHistory: false,
                showsPlaceholder: true,
                placeholderText: "Clipboard not read",
                accessibilitySummary: "Clipboard not read"
                    + (clip.count.map { ", \($0) requested" } ?? "")
            )
            return
        }
        let mode = clip.mode ?? "clip"
        let attachmentRows = clip.attachments.map(Self.attachmentRow(for:))
        switch mode {
        case "history":
            let total = clip.entries.count
            let entries = clip.entries.enumerated().map { index, entry in
                HistoryEntry(
                    dividerText: "Entry \(index + 1) of \(total)",
                    modeText: entry.mode ?? "clip",
                    lines: entry.lines,
                    snippetDestination: entry.snippet,
                    attachmentRows: entry.attachments.map(Self.attachmentRow(for:))
                )
            }
            let header = total == 1 ? "Last 1 clip" : "Last \(total) clips"
            self.init(
                headerText: header,
                childLines: clip.lines,
                snippetDestination: nil,
                attachmentRows: [],
                historyEntries: entries,
                isHistory: true,
                showsPlaceholder: false,
                placeholderText: nil,
                accessibilitySummary: "\(header): \(pluralCount(clip.lines.count, unit: "line"))"
            )
        case "attachments":
            let images = clip.attachments.filter { $0.kind == "image" }.count
            let files = clip.attachments.count - images
            var parts: [String] = []
            if files > 0 {
                parts.append(pluralCount(files, unit: "file"))
            }
            if images > 0 {
                parts.append(pluralCount(images, unit: "image"))
            }
            let header = parts.isEmpty ? "Clipboard · attachments" : parts.joined(separator: " · ")
            self.init(
                headerText: header,
                childLines: clip.lines,
                snippetDestination: nil,
                attachmentRows: attachmentRows,
                historyEntries: [],
                isHistory: false,
                showsPlaceholder: false,
                placeholderText: nil,
                accessibilitySummary: "Clipboard, \(header)"
            )
        case "snippet":
            let count = pluralCount(clip.lines.count, unit: "line")
            let header: String
            if let destination = clip.snippet {
                header = "Snippet · \(count) → \(destination)"
            } else {
                header = "Snippet · \(count)"
            }
            self.init(
                headerText: header,
                childLines: clip.lines,
                snippetDestination: clip.snippet,
                attachmentRows: attachmentRows,
                historyEntries: [],
                isHistory: false,
                showsPlaceholder: false,
                placeholderText: nil,
                accessibilitySummary: "Clipboard snippet\(clip.snippet.map { " to \($0)" } ?? "")"
            )
        case "inline", "lines":
            let header = "Clipboard · \(pluralCount(clip.lines.count, unit: "line"))"
            self.init(
                headerText: header,
                childLines: clip.lines,
                snippetDestination: nil,
                attachmentRows: attachmentRows,
                historyEntries: [],
                isHistory: false,
                showsPlaceholder: false,
                placeholderText: nil,
                accessibilitySummary: "\(header)"
            )
        default:
            let header = "Clipboard · \(mode)"
            self.init(
                headerText: header,
                childLines: clip.lines,
                snippetDestination: clip.snippet,
                attachmentRows: attachmentRows,
                historyEntries: [],
                isHistory: false,
                showsPlaceholder: false,
                placeholderText: nil,
                accessibilitySummary: header
            )
        }
    }

    private init(
        headerText: String,
        childLines: [String],
        snippetDestination: String?,
        attachmentRows: [AttachmentRow],
        historyEntries: [HistoryEntry],
        isHistory: Bool,
        showsPlaceholder: Bool,
        placeholderText: String?,
        accessibilitySummary: String
    ) {
        self.headerText = headerText
        self.childLines = childLines
        self.snippetDestination = snippetDestination
        self.attachmentRows = attachmentRows
        self.historyEntries = historyEntries
        self.isHistory = isHistory
        self.showsPlaceholder = showsPlaceholder
        self.placeholderText = placeholderText
        self.accessibilitySummary = accessibilitySummary
    }

    private static func attachmentRow(for attachment: CaptureAttachmentOutput) -> AttachmentRow {
        var summary = "\(attachment.saved) · \(attachment.kind)"
        if attachment.reused {
            summary += " · reused"
        }
        return AttachmentRow(
            summaryText: summary,
            source: attachment.source,
            savedPath: attachment.saved,
            kind: attachment.kind,
            isImage: attachment.kind == "image",
            reused: attachment.reused
        )
    }
}

/// House pluralization: `"1 line"`, `"3 lines"`.
private func pluralCount(_ count: Int, unit: String) -> String {
    count == 1 ? "1 \(unit)" : "\(count) \(unit)s"
}
