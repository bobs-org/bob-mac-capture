import AppKit
import RefsCore
import SwiftUI

/// The full inspector column (§10): it fills instantly from the list
/// item and upgrades lazily as the loader hydrates summaries,
/// outlines, notes, and thumbnails. Papers, articles, and docs show a
/// fixed 112 x 145 pt thumbnail slot (reserved even while loading, so
/// nothing jumps); chats keep the kind tile and lead with the
/// outline. Absence stays absence: missing facts omit their row.
@available(macOS 26.0, *)
struct RefsInspectorView: View {
    let content: RefsRowContent
    let signals: RefsSignals
    var inspector: RefsInspectorContent? = nil
    var thumbnail: NSImage? = nil
    /// Design fixtures lay the column out statically: `ImageRenderer`
    /// snapshots `ScrollView` content blank, so the live scroll view
    /// never appears in a fixture.
    var previewMode = false

    var body: some View {
        if previewMode {
            column
        } else {
            ScrollView(.vertical) {
                column
            }
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: RefsVisualTokens.inspectorSpacing) {
            if let item = content.item {
                hero(for: item)
                byline(for: item)
                facts(for: item)
                summarySection
                contentsSection
                notesSection
                if content.isMissingPDF {
                    missingCallout(for: item)
                }
                footer(for: item)
            } else {
                Text(content.caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(content.caption)
            }
        }
        .padding(RefsVisualTokens.inspectorPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hero(for item: RefItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if showsThumbnailSlot(for: item) {
                thumbnailSlot
            } else {
                RefsKindTile(kind: item.kind, size: RefsVisualTokens.heroTileSize)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                chips(for: item)
                Text(
                    CapturePickerRichText.displayText(
                        item.title.text,
                        segments: item.title.segments,
                        matches: content.match?.titleRanges ?? []
                    )
                )
                .font(.title3.weight(.semibold))
                .lineLimit(4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title.text), \(item.kind.label)")
    }

    /// Papers, articles, and docs show the page-1 thumbnail; every
    /// other kind keeps the tile.
    private func showsThumbnailSlot(for item: RefKind) -> Bool {
        item == .paper || item == .article || item == .doc
    }

    private func showsThumbnailSlot(for item: RefItem) -> Bool {
        showsThumbnailSlot(for: item.kind)
    }

    private var thumbnailSlot: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: RefsVisualTokens.thumbnailWidth,
                        height: RefsVisualTokens.thumbnailHeight
                    )
                    .clipShape(RoundedRectangle(
                        cornerRadius: RefsVisualTokens.thumbnailRadius
                    ))
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: RefsVisualTokens.thumbnailRadius
                        )
                        .stroke(.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(radius: 3)
                    .accessibilityHidden(true)
            } else if let message = inspector?.previewMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(
                        width: RefsVisualTokens.thumbnailWidth,
                        height: RefsVisualTokens.thumbnailHeight
                    )
                    .background(
                        .secondary.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: RefsVisualTokens.thumbnailRadius
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: RefsVisualTokens.thumbnailRadius
                        )
                        .stroke(.primary.opacity(0.08), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: RefsVisualTokens.thumbnailRadius)
                    .fill(.secondary.opacity(0.08))
                    .frame(
                        width: RefsVisualTokens.thumbnailWidth,
                        height: RefsVisualTokens.thumbnailHeight
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: RefsVisualTokens.thumbnailRadius
                        )
                        .stroke(.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .accessibilityHidden(true)
            }
        }
    }

    private func chips(for item: RefItem) -> some View {
        HStack(spacing: 6) {
            kindChip(for: item)
            stateChip(for: item)
            if let name = todayName(for: item) {
                RefsTodayPill(pomodoroName: name)
            }
        }
    }

    private func kindChip(for item: RefItem) -> some View {
        let tint = RefsVisualTokens.tint(for: item.kind)
        return Label(item.kind.label, systemImage: item.kind.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
    }

    private func stateChip(for item: RefItem) -> some View {
        let resolved = CaptureEditorPalette.taskStatus(
            RefsVisualTokens.paletteStatus(for: item)
        )
        return Label(RefsCaption.stateLabel(item), systemImage: resolved.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(resolved.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(resolved.color.opacity(0.12), in: Capsule())
    }

    private func todayName(for item: RefItem) -> String? {
        signals.today.entries[item.id]?.pomodoroName
    }

    private func byline(for item: RefItem) -> some View {
        Text(bylineText(for: item))
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityLabel(bylineText(for: item))
    }

    private func bylineText(for item: RefItem) -> String {
        if item.kind == .chat {
            var parts = ["Agent report"]
            if let parent = item.parentLabel, !parent.isEmpty {
                parts.append(parent)
            }
            parts.append(contentsOf: reportSuffix(for: item.stem))
            return parts.joined(separator: " · ")
        }
        var parts: [String] = []
        if let author = item.author, !author.isEmpty {
            parts.append(author)
        }
        if let published = item.published, !published.isEmpty {
            parts.append(published)
        }
        if let host = sourceHost(for: item) {
            parts.append(host)
        }
        if let arxiv = item.arxivID, !arxiv.isEmpty {
            parts.append("arXiv:\(arxiv)")
        } else if let doi = item.doi, !doi.isEmpty {
            parts.append(doi)
        }
        return parts.joined(separator: " · ")
    }

    /// Chats add "Consolidated report" for a stem ending in `__final`,
    /// or "Researcher draft (`x`)" for any other `__x` suffix.
    private func reportSuffix(for stem: String) -> [String] {
        let parts = stem.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[parts.count - 2].isEmpty else {
            return []
        }
        let suffix = String(parts.last ?? "")
        guard !suffix.isEmpty else {
            return []
        }
        if suffix == "final" {
            return ["Consolidated report"]
        }
        return ["Researcher draft (\(suffix))"]
    }

    private func sourceHost(for item: RefItem) -> String? {
        guard let first = item.urls.first,
              let host = URL(string: first)?.host,
              !host.isEmpty
        else {
            return nil
        }
        return host
    }

    private func facts(for item: RefItem) -> some View {
        Grid(alignment: .leading, verticalSpacing: 6) {
            factRow(label: "Added", value: addedText(for: item))
            if item.finished != nil {
                factRow(label: "Finished", value: finishedText(for: item))
            }
            if let pages = inspector?.pageCount ?? signals.pageCounts[item.id] {
                factRow(label: "Pages", value: pagesText(pages))
            }
            factRow(label: "Opened", value: openedText(for: item))
            factRow(label: "Notes", value: notesText(for: item))
            if let inspector, !inspector.showFailed {
                factRow(
                    label: "Tasks",
                    value: "\(inspector.openTaskCount) open"
                )
            }
            if item.audioPath != nil {
                factRow(label: "Narration", value: "Available")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pagesText(_ pages: Int) -> String {
        guard let readingTime = inspector?.readingTime else {
            return "\(pages)"
        }
        return "\(pages) · \(readingTime.formatted)"
    }

    private func factRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: RefsVisualTokens.factLabelWidth, alignment: .trailing)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.callout)
                .gridColumnAlignment(.leading)
        }
    }

    private func addedText(for item: RefItem) -> String {
        guard let added = item.added else {
            return "Unknown date"
        }
        let day = RefsCaption.absoluteMonthDay(
            added, now: signals.now, calendar: signals.calendar
        )
        var text = "Added \(day)"
        if item.addedIsApproximate {
            text = text.replacingOccurrences(of: "Added ", with: "Added ≈ ")
        }
        if let source = item.addedSource, !source.isEmpty, source != "git" {
            text += " (\(source))"
        }
        return text
    }

    private func finishedText(for item: RefItem) -> String {
        guard let finished = item.finished else {
            return ""
        }
        return RefsCaption.absoluteMonthDay(
            finished, now: signals.now, calendar: signals.calendar
        )
    }

    private func openedText(for item: RefItem) -> String {
        let count = signals.opens.count(item.id)
        if let opened = RefsRanker.lastOpened(item, signals: signals) {
            let when = RefsCaption.relativeLong(opened, now: signals.now)
            if count > 1 {
                return "\(when) · \(count) times"
            }
            return when
        }
        return "Never opened"
    }

    private func notesText(for item: RefItem) -> String {
        var parts: [String] = []
        if item.annotationCount > 0 {
            let word = item.annotationCount == 1 ? "highlight" : "highlights"
            parts.append("\(item.annotationCount) \(word)")
        }
        if item.commentCount > 0 {
            let word = item.commentCount == 1 ? "comment" : "comments"
            parts.append("\(item.commentCount) \(word)")
        }
        if parts.isEmpty {
            return "None"
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = inspector?.summary {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel(summary.label)
                if let paragraph = summary.paragraph {
                    Text(paragraph)
                        .font(.callout)
                }
                ForEach(summary.bullets.indices, id: \.self) { index in
                    Text("•  \(summary.bullets[index])")
                        .font(.callout)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var contentsSection: some View {
        if let outline = inspector?.outline, !outline.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("CONTENTS")
                ForEach(outline, id: \.self) { heading in
                    Label {
                        Text(heading)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if let inspector {
            if !inspector.notes.isEmpty || inspector.remainingNoteCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("YOUR NOTES")
                    ForEach(inspector.notes.indices, id: \.self) { index in
                        noteView(inspector.notes[index])
                    }
                    if inspector.remainingNoteCount > 0 {
                        Text(
                            "+\(inspector.remainingNoteCount) more · ⌘↵ opens the note"
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
            } else if inspector.showFailed {
                Text("Notes unavailable")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Notes unavailable")
            }
        }
    }

    private func noteView(_ note: RefsShowAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let pageLabel = note.pageLabel, !pageLabel.isEmpty {
                Text("Page \(pageLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let quote = note.quote, !quote.isEmpty {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(.yellow)
                        .frame(width: 2)
                    Text(quote)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .accessibilityElement(children: .combine)
            }
            if let comment = note.comment, !comment.isEmpty {
                Text(comment)
                    .font(.callout)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func missingCallout(for item: RefItem) -> some View {
        Label(
            "The PDF this note points to is missing: \(item.pdfPath). "
                + "Return opens the note instead.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.callout)
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("The PDF this note points to is missing.")
    }

    private func footer(for item: RefItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content.whyHere)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(item.pdfPath)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .accessibilityLabel("PDF path \(item.pdfPath)")
        }
    }
}
