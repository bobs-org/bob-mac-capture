import AppKit
import CaptureCore
import SwiftUI

/// One batch-level Pomodoro block in the preview pane: a status caption row
/// above a card with a status rail, a diff gutter, indent guides, and
/// verbatim tinted lines. Every line is exactly what Bob will write —
/// tinting never adds, drops, or reorders characters — and rows wrap instead
/// of truncating. No animation; the pane updates on every keystroke.
struct PomodoroBlockView: View {
    /// Fixed gutter carrying the diff glyph.
    private static let gutterWidth: CGFloat = 12
    /// One indent step per block depth level.
    private static let indentStep: CGFloat = 18

    let presentation: CapturePomodoroBlockPresentation
    @Environment(\.colorSchemeContrast) private var contrast

    init(block: CapturePomodoroBlock, dryRun: Bool) {
        presentation = CapturePomodoroBlockPresentation(block: block, dryRun: dryRun)
    }

    private var statusTint: Color {
        switch presentation.status {
        case .running:
            return CaptureEditorPalette.color(for: .pomodoroStart)
        case .completed:
            return .green
        case .queued, .other:
            return .secondary
        }
    }

    private func changeTint(for change: CapturePomodoroBlockChange) -> Color? {
        let base: Color? = switch change {
        case .added:
            Color.green
        case .changed:
            Color.accentColor
        case .removed:
            Color.red
        case .unchanged:
            nil
        }
        guard let base else {
            return nil
        }
        // Increased-contrast appearances carry the stronger wash.
        return base.opacity(contrast == .increased ? 0.22 : Self.tintOpacity(for: change))
    }

    private static func tintOpacity(for change: CapturePomodoroBlockChange) -> Double {
        switch change {
        case .added:
            return 0.10
        case .changed:
            return 0.12
        case .removed:
            return 0.08
        case .unchanged:
            return 0
        }
    }

    private var hairline: Color {
        // `Color.separator` is a shape style, not a color, so the hairline
        // reads the AppKit separator directly; it stays adaptive in light,
        // dark, and increased-contrast appearances.
        let base = Color(nsColor: .separatorColor)
        return contrast == .increased ? base : base.opacity(0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            captionRow
            HStack(spacing: 0) {
                statusTint
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(presentation.rows.enumerated()), id: \.offset) { _, row in
                        blockRow(row)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            .background(.quinary)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilitySummary)
    }

    private var captionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: presentation.statusSymbolName)
                .foregroundStyle(statusTint)
                .accessibilityHidden(true)
            Text(presentation.captionText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            // A created block carries the start card's pink New/Created
            // capsule so the fresh entry reads at a glance.
            if let badge = presentation.badgeText {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.pink.opacity(0.15), in: Capsule())
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func blockRow(_ row: CapturePomodoroBlockPresentation.Row) -> some View {
        if row.change == .changed, let before = row.beforeContent, !before.isEmpty {
            // A changed row names what Bob is replacing on hover.
            rowStack(row)
                .help("Was: \(before)")
        } else {
            rowStack(row)
        }
    }

    private func rowStack(_ row: CapturePomodoroBlockPresentation.Row) -> some View {
        HStack(alignment: .top, spacing: 0) {
            gutterGlyph(for: row.change)
                .frame(width: Self.gutterWidth, alignment: .center)
            ForEach(0..<row.depth, id: \.self) { _ in
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                Spacer()
                    .frame(width: Self.indentStep - 1)
            }
            rowContent(row)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(changeTint(for: row.change) ?? .clear)
        )
    }

    private func gutterGlyph(for change: CapturePomodoroBlockChange) -> some View {
        Group {
            switch change {
            case .added:
                Text("+")
                    .foregroundStyle(Color.green)
            case .changed:
                Text("•")
                    .foregroundStyle(Color.accentColor)
            case .removed:
                Text("−")
                    .foregroundStyle(Color.red)
            case .unchanged:
                Text("")
            }
        }
        .font(.caption)
        .fontWeight(.bold)
    }

    @ViewBuilder
    private func rowContent(_ row: CapturePomodoroBlockPresentation.Row) -> some View {
        if row.change == .removed {
            // A removed line reads uniformly: struck, secondary, dimmed.
            Text(row.content)
                .font(.system(.callout, design: .monospaced))
                .strikethrough()
                .foregroundStyle(.secondary)
                .opacity(0.55)
        } else {
            // One text view per row, built the way the close card builds its
            // hint: verbatim bytes with display-only tinting, wrapping as a
            // unit so continuation lines keep the hanging indent.
            Text(
                row.tokens.map { token in
                    var part = AttributedString(token.text)
                    part.foregroundColor = tokenColor(for: token)
                    if token.role == .timeRange || token.role == .name {
                        part.inlinePresentationIntent = .stronglyEmphasized
                    }
                    if token.struck {
                        part.strikethroughStyle = .single
                    }
                    if token.role == .code {
                        part.backgroundColor = Color.secondary.opacity(0.12)
                    }
                    return part
                }.reduce(AttributedString()) { $0 + $1 }
            )
            .font(.system(.callout, design: .monospaced))
        }
    }

    private func tokenColor(for token: CapturePomodoroLineToken) -> Color {
        // Struck `~~…~~` inner text stays secondary whatever its role.
        if token.struck {
            return .secondary
        }
        switch token.role {
        case .syntax:
            // `Color.tertiary` is a shape style, not a color.
            return Color(nsColor: .tertiaryLabelColor)
        case .checkbox(let symbol):
            return CaptureEditorPalette.checkboxSymbolColor(symbol)
        case .timeRange:
            return CaptureEditorPalette.color(for: .pomodoroStart)
        case .field:
            return .secondary
        case .name:
            return .primary
        case .tag:
            return .secondary
        case .blockID:
            return CaptureEditorPalette.color(for: .blockID)
        case .wikilinkDelimiter:
            return CaptureEditorPalette.color(for: .wikilinkDelimiter)
        case .wikilinkTarget:
            return CaptureEditorPalette.color(for: .wikilinkTarget)
        case .wikilinkHeading:
            return CaptureEditorPalette.color(for: .wikilinkHeading)
        case .wikilinkBlock:
            return CaptureEditorPalette.color(for: .wikilinkBlock)
        case .wikilinkAlias:
            return CaptureEditorPalette.color(for: .wikilinkAlias)
        case .code, .text:
            return .primary
        }
    }

}
