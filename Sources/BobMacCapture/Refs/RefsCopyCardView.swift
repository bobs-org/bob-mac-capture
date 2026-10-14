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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            onMeasuredHeight(height)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            RefsKindTile(
                kind: card.item.kind,
                size: RefsVisualTokens.kindTileSize
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                if let picker = card.highlightPicker {
                    Text("HIGHLIGHTS \(picker.entries.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("COPY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(card.item.rawTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var rowsBlock: some View {
        if let picker = card.highlightPicker {
            pickerRows(picker)
        } else {
            catalogRows
        }
    }

    @ViewBuilder
    private var catalogRows: some View {
        let groups = groupedRows
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            if index > 0 {
                separator
            }
            if group.group == .notes {
                notesHeader(loadedCount: group.rows.filter(\.isNoteRow).count)
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
    private func pickerRows(_ picker: RefsHighlightPicker) -> some View {
        ForEach(Array(picker.windowEntries.enumerated()), id: \.offset) { offset, entry in
            let position = offset + 1
            pickerRow(entry, position: position, picker: picker)
        }
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
                    Text(quoteLines?.first ?? entry.line1)
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                let line2 = quoteLines.map { $0.dropFirst().joined(separator: "\n") } ?? entry.line2
                if !line2.isEmpty {
                    Text(line2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
        if card.highlightPicker != nil {
            return "↵ copies · 1–9 pick · A copies all · esc back"
        }
        let label =
            card.rows.first { $0.key == card.selectedKey }?
            .resolved(alternate: alternatesActive).label
            ?? "selection"
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
        if let picker = card.highlightPicker {
            return "HIGHLIGHTS \(picker.entries.count), \(card.item.rawTitle)"
        }
        return "COPY, \(card.item.rawTitle)"
    }

    private var cardAccessibilityLabel: String {
        if let picker = card.highlightPicker {
            return "Highlight picker for \(card.item.rawTitle), \(picker.entries.count) highlights"
        }
        return "Copy menu for \(card.item.rawTitle), \(card.rows.count) options"
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

private extension RefsCopyRow {
    var isNoteRow: Bool {
        if case .note = key { return true }
        return false
    }
}
