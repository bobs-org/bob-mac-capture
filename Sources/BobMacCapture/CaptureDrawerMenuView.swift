import CaptureCore
import SwiftUI

/// The `drawer` completion menu that opens on a glued `#` after `@route+id`.
/// Grouping, counts, refusals, and the footer consequence all come from Bob
/// through `CaptureDrawerMenuPresentation`; this view only paints them.
@available(macOS 26.0, *)
struct CaptureDrawerMenuView: View {
    let presentation: CaptureDrawerMenuPresentation
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(presentation.groups) { group in
                groupHeader(group)
                ForEach(group.rows) { row in
                    rowView(row)
                        .id(row.index)
                        .onTapGesture { onSelect(row.index) }
                }
            }
            footer
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.listAccessibilityLabel)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(CaptureDrawerMenuPresentation.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if !presentation.headerCaption.isEmpty {
                Text("\u{00B7}")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(presentation.headerCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .frame(height: CapturePanelLayout.drawerHeaderHeight)
    }

    @ViewBuilder
    private func groupHeader(_ group: CaptureDrawerMenuPresentation.Group) -> some View {
        if let title = group.title {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 6)
                .frame(
                    height: CapturePanelLayout.drawerGroupHeaderHeight,
                    alignment: .bottomLeading
                )
                .accessibilityAddTraits(.isHeader)
        } else {
            Divider().padding(.vertical, 2)
        }
    }

    private func rowView(_ row: CaptureDrawerMenuPresentation.Row) -> some View {
        let selected = row.index == selectedIndex
        let tint = CaptureEditorPalette.color(for: row.isNew ? .priority : .section)
        return HStack(spacing: 8) {
            Image(systemName: row.isNew ? "plus.square.dashed" : "tray.full")
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            emphasizedLabel(row)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let refusal = row.refusal {
                Text(refusal)
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .lineLimit(1)
            } else if let detail = row.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
            }
        }
        .frame(height: CapturePanelLayout.drawerRowHeight)
        .padding(.horizontal, 6)
        .background(
            selected
                ? Color.accentColor.opacity(colorSchemeContrast == .increased ? 0.32 : 0.18)
                : .clear
        )
        .overlay {
            // The create row is dashed: it adds a drawer instead of choosing one.
            if row.isNew {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        tint.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .opacity(row.isRefused ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func emphasizedLabel(_ row: CaptureDrawerMenuPresentation.Row) -> Text {
        guard let matchRange = row.queryMatchRange else {
            return Text(row.label)
        }
        let characters = Array(row.label)
        guard matchRange.lowerBound >= 0, matchRange.upperBound <= characters.count else {
            return Text(row.label)
        }
        let prefix = String(characters[0..<matchRange.lowerBound])
        let matched = String(characters[matchRange.lowerBound..<matchRange.upperBound])
        let suffix = String(characters[matchRange.upperBound...])
        return Text("\(Text(prefix))\(Text(matched).fontWeight(.semibold))\(Text(suffix))")
    }

    private var footer: some View {
        Text(presentation.footer)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(
                maxWidth: .infinity,
                minHeight: CapturePanelLayout.drawerFooterHeight,
                alignment: .leading
            )
            .accessibilityLabel(presentation.footer)
    }
}
