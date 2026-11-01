import AppKit
import CaptureCore
import SwiftUI

/// Hosted Clip card: one `%c` item's clipboard content beneath its preview
/// item. Every string comes from `CaptureClipPresentation`, which itself
/// renders only Bob's `clip` object — kind/count header, Bob's exact child
/// lines, snippet destination, attachment summaries, and entry dividers for
/// `%c<N>` history. `not_read` shows a quiet placeholder. Swift never reads
/// the pasteboard here: image thumbnails decode from the `source` paths Bob
/// already saved, and a missing or unreadable source keeps its summary row.
struct ClipCardView: View {
    let clip: CaptureClipPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "clipboard")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(clip.headerText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if clip.showsPlaceholder {
                if let placeholder = clip.placeholderText {
                    Text(placeholder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(clip.topLevelChildLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let destination = clip.snippetDestination {
                    Text("→ \(destination)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                ForEach(Array(clip.attachmentRows.enumerated()), id: \.offset) { _, row in
                    ClipAttachmentRow(row: row)
                }
                ForEach(Array(clip.historyEntries.enumerated()), id: \.offset) { _, entry in
                    ClipHistoryEntryView(entry: entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(clip.accessibilitySummary)
    }
}

/// One clipboard file row: the summary Bob reported plus, for images with a
/// readable `source`, a thumbnail. A missing or unreadable source keeps the
/// summary row so the card stays useful.
struct ClipAttachmentRow: View {
    let row: CaptureClipPresentation.AttachmentRow

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if row.isImage {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityLabel("Clipboard image \(row.savedPath)")
                }
            }
            Text(row.summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .task(id: row.source) {
            // Reloads whenever the source changes; a nil result keeps the
            // summary row as the useful fallback.
            if row.isImage {
                thumbnail = Self.loadImage(source: row.source)
            }
        }
    }

    /// Decodes a thumbnail source off Bob's saved path. Nil for a missing
    /// or unreadable file; callers keep the summary row.
    static func loadImage(source: String) -> NSImage? {
        NSImage(contentsOfFile: source)
    }
}

/// One `%c<N>` history entry beneath its divider: the entry's mode, exact
/// lines, snippet destination, and attachments.
private struct ClipHistoryEntryView: View {
    let entry: CaptureClipPresentation.HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.dividerText) · \(entry.modeText)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let destination = entry.snippetDestination {
                Text("→ \(destination)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ForEach(Array(entry.attachmentRows.enumerated()), id: \.offset) { _, row in
                ClipAttachmentRow(row: row)
            }
        }
        .padding(.top, 2)
    }
}
