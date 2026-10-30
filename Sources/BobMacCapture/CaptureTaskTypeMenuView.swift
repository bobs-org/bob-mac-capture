import CaptureCore
import SwiftUI

/// Compact `task_type` completion menu. Copy and ranking come from Bob via
/// `CaptureTaskTypeMenuPresentation`; this view only paints them.
@available(macOS 26.0, *)
struct CaptureTaskTypeMenuView: View {
    let presentation: CaptureTaskTypeMenuPresentation
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(Array(presentation.rows.enumerated()), id: \.offset) { index, row in
                if row.isTyped, index == 0 || !presentation.rows[index - 1].isTyped {
                    Divider().padding(.vertical, 2)
                }
                rowView(row, index: index)
                    .id(index)
                    .onTapGesture { onSelect(index) }
            }
            footer
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.listAccessibilityLabel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(presentation.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 8)
            if let hue = presentation.headerFromHue {
                Circle()
                    .fill(PomodoroHomeColor.color(for: hue, scheme: colorScheme))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            if let theme = presentation.headerTheme {
                PomodoroThemeSwatchView(
                    hue: theme.hue,
                    known: theme.known,
                    configured: theme.configured,
                    size: 8
                )
            }
            Text(presentation.headerCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(presentation.title), \(presentation.headerCaption)")
        .frame(height: CapturePanelLayout.taskTypeHeaderHeight)
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private func rowView(
        _ row: CaptureTaskTypeMenuPresentation.Row,
        index: Int
    ) -> some View {
        let selected = index == selectedIndex
        return HStack(spacing: 8) {
            PomodoroThemeSwatchView(
                hue: row.theme?.hue,
                known: row.theme?.known ?? false,
                configured: row.theme?.configured,
                size: 8
            )
            emphasizedName(row)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    pillTint(for: row),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .overlay {
                    if row.theme?.configured == false {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                Color(nsColor: .systemOrange).opacity(0.7),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                            )
                    }
                }
            ForEach(row.badges, id: \.self) { badge in
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let similar = row.similarCaption {
                Text(similar)
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.usageCaption)
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .lineLimit(1)
        }
        .frame(height: CapturePanelLayout.taskTypeRowHeight)
        .padding(.horizontal, 6)
        .background(
            selected
                ? Color.accentColor.opacity(
                    colorSchemeContrast == .increased ? 0.32 : 0.18)
                : .clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .opacity(row.isRefused ? 0.55 : (row.currentlyHidden ? 0.58 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func pillTint(for row: CaptureTaskTypeMenuPresentation.Row) -> Color {
        let swatch =
            row.theme.map(CaptureThemeSwatch.init)
            ?? CaptureThemeSwatch(hue: nil, known: false)
        if swatch.isUnconfigured || (swatch.known && swatch.hue == nil) {
            return Color(nsColor: .quaternaryLabelColor)
        }
        guard let hue = swatch.hue else {
            return Color(nsColor: .quaternaryLabelColor)
        }
        let resting = colorScheme == .dark ? 0.24 : 0.16
        return PomodoroHomeColor.color(for: hue, scheme: colorScheme).opacity(resting)
    }

    private func emphasizedName(_ row: CaptureTaskTypeMenuPresentation.Row) -> Text {
        guard let matchRange = row.queryMatchRange else {
            return Text(row.name)
        }
        let characters = Array(row.name)
        guard matchRange.lowerBound >= 0, matchRange.upperBound <= characters.count else {
            return Text(row.name)
        }
        let prefix = String(characters[0..<matchRange.lowerBound])
        let matched = String(characters[matchRange.lowerBound..<matchRange.upperBound])
        let suffix = String(characters[matchRange.upperBound...])
        return Text("\(Text(prefix))\(Text(matched).fontWeight(.semibold))\(Text(suffix))")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let footer = presentation.selectedFooter {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            keycap("⏎", action: "choose")
            if let hide = presentation.hideKeycap {
                let parts = hide.split(separator: " ", maxSplits: 1).map(String.init)
                keycap(parts.first ?? "⌃D", action: parts.dropFirst().first ?? hide)
            }
        }
        .frame(minHeight: CapturePanelLayout.taskTypeFooterHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [presentation.selectedFooter, "Return choose", presentation.hideKeycap]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }

    private func keycap(_ keys: String, action: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 5)
                .background(.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
