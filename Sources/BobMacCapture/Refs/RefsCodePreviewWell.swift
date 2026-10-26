import RefsCore
import SwiftUI

/// Fixed-height preview of the selected code block. Copy payloads stay
/// on the picker row; this view never speaks the code.
@available(macOS 26.0, *)
struct RefsCodePreviewWellView: View {
    let preview: RefsCore.RefsCodePreviewWell
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: RefsVisualTokens.copyCardCodeWellHeaderHeight)
                .padding(.horizontal, 8)
            ZStack(alignment: .bottomTrailing) {
                codeBody
                if preview.overflowLineCount > 0 {
                    overflowCapsule
                        .padding(.trailing, 8)
                        .padding(.bottom, 4)
                }
            }
            .overlay(alignment: .trailing) {
                trailingFade
                    .frame(width: RefsVisualTokens.copyCardCodeFadeWidth)
            }
            .overlay(alignment: .bottom) {
                if preview.overflowLineCount > 0 {
                    bottomFade
                        .frame(height: RefsVisualTokens.copyCardCodeLineHeight)
                }
            }
        }
        .background(wellFill, in: wellShape)
        .overlay(
            wellShape.strokeBorder(wellStroke, lineWidth: contrast == .increased ? 1 : 0.5)
        )
        .clipShape(wellShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview, \(preview.lineCount) lines")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(headerLeading)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(headerTrailing)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    private var headerLeading: String {
        var parts = [preview.language]
        if let section = preview.sectionTitle, !section.isEmpty {
            parts.append(section)
        }
        return parts.joined(separator: " · ")
    }

    private var headerTrailing: String {
        var parts = ["\(preview.lineCount) lines"]
        if let page = preview.pageLabel {
            parts.append(page)
        }
        if preview.fenced {
            parts.append("fenced")
        }
        return parts.joined(separator: " · ")
    }

    private var codeBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(preview.lines.enumerated()), id: \.offset) { _, line in
                codeLine(line)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: RefsVisualTokens.copyCardCodeLineHeight,
                        alignment: .leading
                    )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func codeLine(_ line: RefsCodePreviewLine) -> some View {
        HStack(spacing: 0) {
            Text(attributedLine(line))
                .font(.system(size: RefsVisualTokens.copyCardCodeFontSize, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
            Spacer(minLength: 0)
        }
        .clipped()
    }

    private func attributedLine(_ line: RefsCodePreviewLine) -> AttributedString {
        var attributed = AttributedString()
        let pieces = line.text.split(separator: "→", omittingEmptySubsequences: false)
        for (index, piece) in pieces.enumerated() {
            if index > 0 {
                var arrow = AttributedString("→")
                arrow.foregroundColor = Color.primary.opacity(0.35)
                attributed.append(arrow)
            }
            if !piece.isEmpty {
                var run = AttributedString(String(piece))
                run.foregroundColor = line.isFence
                    ? Color.primary.opacity(0.35)
                    : Color.primary
                attributed.append(run)
            }
        }
        return attributed
    }

    private var overflowCapsule: some View {
        Text("+\(preview.overflowLineCount) more lines")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.primary.opacity(0.08), in: Capsule())
            .accessibilityHidden(true)
    }

    private var trailingFade: some View {
        LinearGradient(
            colors: [wellFill.opacity(0), wellFill],
            startPoint: .leading,
            endPoint: .trailing
        )
        .allowsHitTesting(false)
    }

    private var bottomFade: some View {
        LinearGradient(
            colors: [wellFill.opacity(0), wellFill],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var wellShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RefsVisualTokens.copyCardCodeWellRadius)
    }

    private var wellFill: Color {
        let increased = contrast == .increased
        return Color.primary.opacity(
            increased
                ? RefsVisualTokens.copyCardCodeWellFillOpacityIncreased
                : RefsVisualTokens.copyCardCodeWellFillOpacity
        )
    }

    private var wellStroke: Color {
        let increased = contrast == .increased
        return Color.primary.opacity(
            increased
                ? RefsVisualTokens.copyCardCodeWellStrokeOpacityIncreased
                : RefsVisualTokens.copyCardCodeWellStrokeOpacity
        )
    }
}
