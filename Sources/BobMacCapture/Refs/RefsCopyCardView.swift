import RefsCore
import SwiftUI

/// The inspector turned over: a fixed-letter Copy card that reports its
/// measured height, hover state, and row taps to the panel.
@available(macOS 26.0, *)
struct RefsCopyCardView: View {
    let card: RefsCopyCard
    var alternatesActive = false
    /// Design fixtures lay the column out statically:
    /// `ImageRenderer` snapshots `ScrollView` content blank.
    var previewMode = false
    var onMeasuredHeight: (CGFloat) -> Void = { _ in }
    var onRowTap: (RefsCopyRow) -> Void = { _ in }
    var onRowHover: (RefsCopyKey?) -> Void = { _ in }
    var onPickerRowTap: (Int) -> Void = { _ in }

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hoveredKey: RefsCopyKey?
    @State private var hoveredPickerPosition: Int?
    @State private var measuredHeight: CGFloat = 0
    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: RefsVisualTokens.copyCardHeaderHeight)
            rowsBlock
            Spacer(minLength: 0)
            messageLine
                .frame(height: RefsVisualTokens.copyCardMessageLineHeight)
        }
        .padding(.horizontal, RefsVisualTokens.inspectorPadding)
        .padding(.vertical, RefsVisualTokens.copyCardVerticalPadding / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cardAccessibilityLabel)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            measuredHeight = size.height
            measuredWidth = size.width
            onMeasuredHeight(size.height)
        }
        .onChange(of: card.notes) { _, _ in
            reportMeasuredHeightIfAvailable()
        }
        .onChange(of: card.rows) { _, _ in
            reportMeasuredHeightIfAvailable()
        }
        .onChange(of: card.codePicker) { _, _ in
            reportMeasuredHeightIfAvailable()
        }
        .onChange(of: card.highlightPicker) { _, _ in
            reportMeasuredHeightIfAvailable()
        }
        .onChange(of: card.linkPicker) { _, _ in
            reportMeasuredHeightIfAvailable()
        }
    }

    private func reportMeasuredHeightIfAvailable() {
        guard measuredHeight > 0 else { return }
        onMeasuredHeight(measuredHeight)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            RefsKindTile(
                kind: card.item.kind,
                size: RefsVisualTokens.kindTileSize
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(headerCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(card.item.rawTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if let page = card.highlightedPage {
                Text("p. \(page) in Highlights")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .accessibilityLabel("Page \(page) in Highlights")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    private var headerCaption: String {
        if let picker = card.linkPicker {
            return "LINKS \(picker.entries.count)"
        }
        if let picker = card.codePicker {
            return "CODE BLOCKS \(picker.entries.count)"
        }
        if let picker = card.highlightPicker {
            return "HIGHLIGHTS \(picker.entries.count)"
        }
        return "COPY"
    }

    @ViewBuilder
    private var rowsBlock: some View {
        if let picker = card.linkPicker {
            linkPickerBlock(picker)
        } else if let picker = card.codePicker {
            codePickerBlock(picker)
        } else if let picker = card.highlightPicker {
            pickerRows(picker)
        } else {
            catalogRows
        }
    }

    @ViewBuilder
    private func linkPickerBlock(_ picker: RefsLinkPicker) -> some View {
        let layout = linkPreviewLayout(picker: picker)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(picker.windowRows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .group(let title):
                    codePickerGroupRow(title)
                case .entry(let position, let entry):
                    linkPickerRow(entry, position: position, picker: picker)
                }
            }
            if let entry = picker.selectedEntry {
                RefsLinkPreviewWellView(
                    preview: RefsCore.RefsLinkPreview(
                        link: entry.link,
                        markdown: alternatesActive,
                        columns: layout.columns,
                        visibleLines: layout.layout.bodyLines
                    )
                )
                .frame(height: CGFloat(layout.layout.height), alignment: .top)
                .padding(.top, 6)
            }
        }
    }

    private func linkPreviewLayout(
        picker: RefsLinkPicker
    ) -> (columns: Int, layout: RefsLinkPreviewLayout) {
        let available = max(
            0,
            Double(measuredHeight)
                - Double(RefsVisualTokens.copyCardHeaderHeight)
                - Double(RefsVisualTokens.copyCardMessageLineHeight)
                - Double(RefsVisualTokens.copyCardVerticalPadding)
        )
        let width = measuredWidth > 0 ? measuredWidth : 320
        let columns = RefsVisualTokens.linkWellColumns(cardWidth: width)
        let longestURL = picker.entries.map(\.link.url).max(by: { $0.count < $1.count }) ?? ""
        let layout = RefsVisualTokens.linkWellLayout(
            cardWidth: width, availableHeight: available, longestURL: longestURL)
        return (columns, layout)
    }

    private func linkPickerRow(
        _ entry: RefsLinkPicker.Entry,
        position: Int,
        picker: RefsLinkPicker
    ) -> some View {
        let selected = picker.windowStart + position - 1 == picker.selectedIndex
        let hovering = hoveredPickerPosition == position
        return HStack(alignment: .top, spacing: 8) {
            RefsCopyKeycap(glyph: String(position), isSelected: selected)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.label)
                        .font(
                            entry.usesMonospacedLabel
                                ? .system(size: 11.5, design: .monospaced)
                                : .callout
                        )
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let page = entry.pageLabel {
                        HStack(spacing: 4) {
                            if entry.isOnPage {
                                Text("●")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                            Text(page)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                linkPickerLineTwo(entry)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: RefsVisualTokens.copyCardPickerRowHeight, alignment: .top)
        .background(rowBackground(selected: selected, hovering: hovering))
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredPickerPosition = hovering ? position : nil
        }
        .onTapGesture {
            onPickerRowTap(position)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(linkPickerAccessibilityLabel(entry, position: position, picker: picker))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            onPickerRowTap(position)
        }
        .help(alternatesActive ? entry.link.markdown : entry.link.url)
    }

    private func linkPickerLineTwo(_ entry: RefsLinkPicker.Entry) -> some View {
        HStack(spacing: 4) {
            Text(entry.site)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let path = entry.pathRemainder {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    private func linkPickerAccessibilityLabel(
        _ entry: RefsLinkPicker.Entry,
        position: Int,
        picker: RefsLinkPicker
    ) -> String {
        let index = picker.entries.firstIndex(of: entry).map { $0 + 1 } ?? position
        return entry.voiceOverLabel(
            index: index, total: picker.entries.count, key: position)
    }

    @ViewBuilder
    private var catalogRows: some View {
        let groups = groupedRows
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            if index > 0 {
                separator
            }
            if group.group == .notes {
                notesHeader(loadedCount: card.catalog.allNotesCount)
            }
            ForEach(group.rows, id: \.key) { row in
                rowView(row)
            }
            if group.group == .notes, card.catalog.noteOverflowCount > 0 {
                overflowLine
            }
        }
        if showsNotesPlaceholder {
            if !groups.isEmpty {
                separator
            }
            notesPlaceholder
        }
    }

    @ViewBuilder
    private func codePickerBlock(_ picker: RefsCodePicker) -> some View {
        let layout = codePreviewLayout
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(picker.windowRows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .group(let title):
                    codePickerGroupRow(title)
                case .entry(let position, let entry):
                    codePickerRow(entry, position: position, picker: picker)
                }
            }
            if let entry = picker.selectedEntry {
                RefsCodePreviewWellView(
                    preview: RefsCore.RefsCodePreviewWell(
                        block: entry.block,
                        fenced: alternatesActive,
                        visibleLineCount: layout.visibleCodeLines
                    )
                )
                .frame(height: CGFloat(layout.height), alignment: .top)
                .padding(.top, 6)
            }
        }
    }

    private var codePreviewLayout: RefsCodePreviewWellLayout {
        let available = max(
            0,
            Double(measuredHeight)
                - Double(RefsVisualTokens.copyCardHeaderHeight)
                - Double(RefsVisualTokens.copyCardMessageLineHeight)
                - Double(RefsVisualTokens.copyCardVerticalPadding)
        )
        return RefsCodePreviewWellLayout.make(
            availableHeightUnderHeader: available,
            codeLineHeight: Double(RefsVisualTokens.copyCardCodeLineHeight),
            headerHeight: Double(RefsVisualTokens.copyCardCodeWellHeaderHeight),
            entryRowHeight: Double(RefsVisualTokens.copyCardPickerRowHeight)
        )
    }

    private func codePickerGroupRow(_ title: String) -> some View {
        HStack(spacing: 6) {
            if let number = codeSectionNumber(from: title) {
                Text(number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(codeSectionTitle(from: title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: RefsVisualTokens.copyCardPickerGroupHeaderHeight,
            alignment: .leading
        )
        .padding(.horizontal, 6)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(title)
    }

    private func codeSectionNumber(from title: String) -> String? {
        let parts = title.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, first.allSatisfy({ $0.isNumber || $0 == "." }) else {
            return nil
        }
        return String(first)
    }

    private func codeSectionTitle(from title: String) -> String {
        let parts = title.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].allSatisfy({ $0.isNumber || $0 == "." }) else {
            return title
        }
        return String(parts[1])
    }

    private func codePickerRow(
        _ entry: RefsCodePicker.Entry,
        position: Int,
        picker: RefsCodePicker
    ) -> some View {
        let selected = picker.windowStart + position - 1 == picker.selectedIndex
        let hovering = hoveredPickerPosition == position
        return HStack(alignment: .top, spacing: 8) {
            RefsCopyKeycap(glyph: String(position), isSelected: selected)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    languageChip(entry.language)
                    Text(entry.summary)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let page = entry.pageLabel {
                        HStack(spacing: 4) {
                            if entry.isOnPage {
                                Text("●")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                            Text(page)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                codePickerLineTwo(entry)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: RefsVisualTokens.copyCardPickerRowHeight, alignment: .top)
        .background(rowBackground(selected: selected, hovering: hovering))
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredPickerPosition = hovering ? position : nil
        }
        .onTapGesture {
            onPickerRowTap(position)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(codePickerAccessibilityLabel(entry, position: position, picker: picker))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            onPickerRowTap(position)
        }
        .help(alternatesActive ? entry.block.fenced : entry.block.text)
    }

    private func languageChip(_ language: String) -> some View {
        Text(language)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: RefsVisualTokens.copyCardLanguageChipMinWidth)
            .background(.primary.opacity(0.06), in: Capsule())
    }

    private func codePickerLineTwo(_ entry: RefsCodePicker.Entry) -> some View {
        let caption = entry.block.kind == "mermaid" ? "diagram source" : entry.caption
        return HStack(spacing: 4) {
            if !caption.isEmpty {
                Text(caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("·")
                    .foregroundStyle(.tertiary)
            }
            Text("\(entry.lineCount) lines")
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private func codePickerAccessibilityLabel(
        _ entry: RefsCodePicker.Entry,
        position: Int,
        picker: RefsCodePicker
    ) -> String {
        var parts = [
            "Code block \(entry.block.number) of \(picker.entries.count)",
            entry.language,
            "\(entry.lineCount) lines",
        ]
        if let page = entry.block.page {
            parts.append("page \(page)")
        }
        if entry.isOnPage {
            parts.append("on this page")
        }
        parts.append("key \(position)")
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func pickerRows(_ picker: RefsHighlightPicker) -> some View {
        ForEach(Array(picker.windowRows.enumerated()), id: \.offset) { _, row in
            switch row {
            case .group(let title):
                pickerGroupRow(title)
            case .entry(let position, let entry):
                pickerRow(entry, position: position, picker: picker)
            }
        }
    }

    private func pickerGroupRow(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(
                maxWidth: .infinity,
                minHeight: RefsVisualTokens.copyCardPickerGroupHeaderHeight,
                alignment: .leading
            )
            .padding(.horizontal, 6)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)
    }

    private func pickerRow(
        _ entry: RefsHighlightPicker.Entry,
        position: Int,
        picker: RefsHighlightPicker
    ) -> some View {
        let alternate = alternatesActive ? RefsCopyFormat.quoteAlternate(entry.annotation) : nil
        let quoteLines = alternate?.preview.components(separatedBy: "\n")
        let selected = picker.windowStart + position - 1 == picker.selectedIndex
        let hovering = hoveredPickerPosition == position
        return HStack(alignment: .top, spacing: 8) {
            RefsCopyKeycap(glyph: String(position), isSelected: selected)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if let page = entry.pageLabel {
                        Text(page)
                            .font(.callout)
                            .lineLimit(1)
                    }
                    RefsQuoteText.text(quoteLines?.first ?? entry.line1)
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .refsUnderlineInk()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                let line2 = quoteLines.map { $0.dropFirst().joined(separator: "\n") } ?? entry.line2
                if !line2.isEmpty {
                    RefsQuoteText.text(line2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .refsUnderlineInk()
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: RefsVisualTokens.copyCardPickerRowHeight, alignment: .top)
        .background(rowBackground(selected: selected, hovering: hovering))
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredPickerPosition = hovering ? position : nil
        }
        .onTapGesture {
            onPickerRowTap(position)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pickerAccessibilityLabel(entry, position: position))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            onPickerRowTap(position)
        }
        .help(alternate?.preview ?? entry.payload)
    }

    private func pickerAccessibilityLabel(
        _ entry: RefsHighlightPicker.Entry,
        position: Int
    ) -> String {
        let page = entry.pageLabel.map { ", \($0)" } ?? ""
        let row = entry.copyRow(key: .note(position)).resolved(alternate: alternatesActive)
        return "\(row.label)\(page), \(row.preview), key \(position)"
    }

    private var separator: some View {
        Rectangle()
            .fill(.primary.opacity(contrast == .increased ? 0.25 : 0.10))
            .frame(height: 0.5)
            .padding(.vertical, (RefsVisualTokens.copyCardSeparatorHeight - 0.5) / 2)
    }

    private func notesHeader(loadedCount: Int) -> some View {
        HStack(spacing: 6) {
            Text("YOUR NOTES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(loadedCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Text(alternatesActive ? "· quote only when available" : "· quote + comment + link")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: RefsVisualTokens.copyCardNotesHeaderHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your notes, \(loadedCount)")
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var notesPlaceholder: some View {
        switch card.notes {
        case .loading:
            HStack(spacing: 6) {
                Text("YOUR NOTES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
                Spacer(minLength: 0)
            }
            .frame(height: RefsVisualTokens.copyCardNotesHeaderHeight)
            .accessibilityLabel("Your notes, loading")
        case .unavailable:
            Text("Notes unavailable")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(
                    maxWidth: .infinity,
                    minHeight: RefsVisualTokens.copyCardNotesHeaderHeight,
                    alignment: .leading
                )
                .accessibilityLabel("Notes unavailable")
        case .loaded:
            EmptyView()
        }
    }

    private var overflowLine: some View {
        Text(card.catalog.notesOverflowText ?? "")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(
                height: RefsVisualTokens.copyCardRowHeight,
                alignment: .leading
            )
            .accessibilityLabel(
                "\(card.catalog.noteOverflowCount) more, A copies all, H picks one"
            )
    }

    private func rowView(_ primary: RefsCopyRow) -> some View {
        let row = primary.resolved(alternate: alternatesActive)
        let selected = row.key == card.selectedKey
        let hovering = row.key == hoveredKey
        return HStack(spacing: 8) {
            RefsCopyKeycap(glyph: row.key.glyph, isSelected: selected)
            Text(row.detail ?? row.label)
                .font(.callout)
                .lineLimit(1)
                .frame(
                    width: RefsVisualTokens.copyCardLabelWidth,
                    alignment: .leading
                )
            Text(row.preview)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(row.truncation == .middle ? .middle : .tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let tag = row.tag {
                tagView(tag)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: RefsVisualTokens.copyCardRowHeight)
        .background(rowBackground(selected: selected, hovering: hovering))
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredKey = hovering ? row.key : nil
            onRowHover(hovering ? row.key : nil)
        }
        .onTapGesture {
            onRowTap(primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(row.label), \(row.preview), key \(row.key.glyph)"
        )
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            onRowTap(primary)
        }
        .help(row.help ?? "")
    }

    private func rowBackground(selected: Bool, hovering: Bool) -> some View {
        let increased = contrast == .increased
        return RoundedRectangle(cornerRadius: RefsVisualTokens.copyCardRowCornerRadius)
            .fill(
                selected
                    ? Color.accentColor.opacity(increased ? 0.30 : 0.16)
                    : hovering
                        ? Color.primary.opacity(0.06)
                        : Color.clear
            )
    }

    private func tagView(_ tag: RefsCopyTag) -> some View {
        let text: String
        let color: Color
        switch tag {
        case .shared(let count):
            text = "shared ×\(count)"
            color = .orange
        case .missing:
            text = "missing"
            color = .orange
        case .archived:
            text = "archived"
            color = .secondary
        }
        return Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.primary.opacity(0.06), in: Capsule())
    }

    private var messageLine: some View {
        let message = card.message
        let text = message?.text ?? hintText
        let error = message?.isError == true
        return Text(text)
            .font(.caption)
            .foregroundStyle(error ? Color.red : Color.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }

    private var hintText: String {
        if card.linkPicker != nil {
            return "↵ copies URL · ⌥↵ Markdown · A all · 1–9 pick · esc back"
        }
        if card.codePicker != nil {
            return "↵ copies · ⌥↵ fenced · 1–9 pick · ↑↓ choose · esc back"
        }
        if card.highlightPicker != nil {
            return "↵ copies · 1–9 pick · A copies all · esc back"
        }
        let row =
            card.rows.first { $0.key == card.selectedKey }?
            .resolved(alternate: alternatesActive)
        let label = row?.label ?? "selection"
        if card.selectedKey == .codePicker || card.selectedKey == .highlightPicker
            || card.selectedKey == .linkPicker
        {
            return "↵ opens \(label) · ↑↓ choose · esc back"
        }
        return "↵ copies \(label) · ↑↓ choose · esc back"
    }

    private var groupedRows: [(group: RefsCopyGroup, rows: [RefsCopyRow])] {
        var groups: [(RefsCopyGroup, [RefsCopyRow])] = []
        for row in card.rows {
            if groups.last?.0 == row.group {
                groups[groups.count - 1].1.append(row)
            } else {
                groups.append((row.group, [row]))
            }
        }
        return groups
    }

    private var showsNotesPlaceholder: Bool {
        switch card.notes {
        case .loading:
            return (card.item.annotationCount > 0 || card.item.commentCount > 0)
                && !card.rows.contains { $0.group == .notes }
        case .unavailable:
            return !card.rows.contains { $0.group == .notes }
        case .loaded:
            return false
        }
    }

    private var headerAccessibilityLabel: String {
        var parts = [headerCaption, card.item.rawTitle]
        if let page = card.highlightedPage {
            parts.append("Page \(page) in Highlights")
        }
        return parts.joined(separator: ", ")
    }

    private var cardAccessibilityLabel: String {
        if let picker = card.linkPicker {
            return "Link picker for \(card.item.rawTitle), \(picker.entries.count) links"
        }
        if let picker = card.codePicker {
            return "Code picker for \(card.item.rawTitle), \(picker.entries.count) blocks"
        }
        if let picker = card.highlightPicker {
            return "Highlight picker for \(card.item.rawTitle), \(picker.entries.count) highlights"
        }
        return "Copy menu for \(card.item.rawTitle), \(card.rows.count) options"
    }
}

/// Inspector placeholder while Command-Y waits for the focused PDF, using
/// the Copy card's tokens so it morphs into the card without a jump.
@available(macOS 26.0, *)
struct RefsCopySkeletonView: View {
    let pending: RefsHighlightsCopyPending

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: RefsVisualTokens.copyCardHeaderHeight)
            findingLine
            Spacer(minLength: 0)
            messageLine
                .frame(height: RefsVisualTokens.copyCardMessageLineHeight)
        }
        .padding(.horizontal, RefsVisualTokens.inspectorPadding)
        .padding(.vertical, RefsVisualTokens.copyCardVerticalPadding / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var header: some View {
        Text(headerTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var findingLine: some View {
        switch pending {
        case .finding:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding the open PDF in Highlights…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: RefsVisualTokens.copyCardRowHeight)
        case .failed:
            EmptyView()
        }
    }

    private var messageLine: some View {
        let text: String
        let error: Bool
        switch pending {
        case .finding:
            text = "esc cancels"
            error = false
        case .failed(let message, _):
            text = message
            error = true
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(error ? Color.red : Color.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }

    private var accessibilityText: String {
        switch pending {
        case .finding:
            return "\(pending.entry.accessibilityLabel). Finding the open PDF in Highlights."
        case .failed(let message, _):
            return "\(pending.entry.accessibilityLabel). \(message)"
        }
    }

    private var headerTitle: String {
        switch pending.entry {
        case .card: "COPY"
        case .code: "COPY · CODE"
        case .links: "COPY · LINKS"
        }
    }
}

@available(macOS 26.0, *)
private struct RefsCopyKeycap: View {
    let glyph: String
    let isSelected: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let increased = contrast == .increased
        Text(glyph)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(
                width: RefsVisualTokens.copyCardKeycapSize,
                height: RefsVisualTokens.copyCardKeycapSize
            )
            .background(
                RoundedRectangle(cornerRadius: RefsVisualTokens.copyCardKeycapCornerRadius)
                    .fill(
                        isSelected
                            ? Color.accentColor
                            : Color.primary.opacity(0.06)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: RefsVisualTokens.copyCardKeycapCornerRadius)
                    .strokeBorder(
                        Color.primary.opacity(increased ? 0.30 : 0.14),
                        lineWidth: increased ? 1 : 0.5
                    )
            )
    }
}
