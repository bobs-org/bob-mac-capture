import RefsCore
import SwiftUI

/// The basic inspector column (§10): it fills instantly from the list
/// item. A later phase upgrades it with thumbnails, summaries, and
/// notes; the layout reserves nothing that would jump when that lands.
@available(macOS 26.0, *)
struct RefsInspectorView: View {
    let content: RefsRowContent
    let signals: RefsSignals

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: RefsVisualTokens.inspectorSpacing) {
                if let item = content.item {
                    hero(for: item)
                    byline(for: item)
                    facts(for: item)
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
    }

    private func hero(for item: RefItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RefsKindTile(kind: item.kind, size: RefsVisualTokens.heroTileSize)
                .accessibilityHidden(true)
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
            if let parent = item.parentLabel, !parent.isEmpty {
                return "Agent report · \(parent)"
            }
            return "Agent report"
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
            if let pages = signals.pageCounts[item.id] {
                factRow(label: "Pages", value: "\(pages)")
            }
            factRow(label: "Opened", value: openedText(for: item))
            factRow(label: "Notes", value: notesText(for: item))
            if item.audioPath != nil {
                factRow(label: "Narration", value: "Available")
            }
        }
        .accessibilityElement(children: .combine)
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
