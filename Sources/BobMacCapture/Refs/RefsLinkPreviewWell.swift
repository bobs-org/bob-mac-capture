import RefsCore
import SwiftUI

/// Fixed-height preview of the selected link's exact copy payload.
/// Payloads stay on the picker row; this view never speaks the URL.
@available(macOS 26.0, *)
struct RefsLinkPreviewWellView: View {
    let preview: RefsCore.RefsLinkPreview
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: RefsVisualTokens.copyCardLinkWellHeaderHeight)
                .padding(.horizontal, RefsVisualTokens.copyCardLinkWellHorizontalInset)
            ZStack(alignment: .bottomTrailing) {
                payloadBody
                if preview.overflowCharacterCount > 0 {
                    overflowCapsule
                        .padding(.trailing, RefsVisualTokens.copyCardLinkWellHorizontalInset)
                        .padding(.bottom, 4)
                }
            }
            .overlay(alignment: .bottom) {
                if preview.overflowCharacterCount > 0 {
                    bottomFade
                        .frame(height: RefsVisualTokens.copyCardLinkWellFadeHeight)
                }
            }
        }
        .background(wellFill, in: wellShape)
        .overlay(
            wellShape.strokeBorder(wellStroke, lineWidth: contrast == .increased ? 1 : 0.5)
        )
        .clipShape(wellShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preview.voiceOverLabel)
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
        if let section = preview.sectionTitle, !section.isEmpty {
            return "\(preview.site) · \(section)"
        }
        return preview.site
    }

    private var headerTrailing: String {
        var parts: [String] = []
        if let page = preview.pageLabel {
            parts.append(page)
        }
        if preview.markdown {
            parts.append("Markdown")
        }
        return parts.joined(separator: " · ")
    }

    private var payloadBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(preview.lines.enumerated()), id: \.offset) { _, line in
                payloadLine(line)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: RefsVisualTokens.copyCardLinkWellLineHeight,
                        alignment: .leading
                    )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, RefsVisualTokens.copyCardLinkWellHorizontalInset)
        .padding(.bottom, RefsVisualTokens.copyCardLinkWellBottomPadding)
        .accessibilityHidden(true)
    }

    private func payloadLine(_ line: RefsLinkPreviewLine) -> some View {
        HStack(spacing: 0) {
            Text(attributedLine(line))
                .font(
                    .system(
                        size: RefsVisualTokens.copyCardLinkWellFontSize,
                        design: .monospaced
                    )
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
            Spacer(minLength: 0)
        }
        .clipped()
        .opacity(line.isFaded ? 0.45 : 1)
        .help(preview.displayPayload)
    }

    private func attributedLine(_ line: RefsLinkPreviewLine) -> AttributedString {
        var attributed = AttributedString()
        for run in line.runs {
            var piece = AttributedString(run.text)
            switch run.role {
            case .scheme:
                piece.foregroundColor = Color.primary.opacity(0.45)
            case .host:
                piece.foregroundColor = Color.primary
                piece.font = .system(
                    size: RefsVisualTokens.copyCardLinkWellFontSize,
                    weight: .semibold,
                    design: .monospaced
                )
            case .path:
                piece.foregroundColor = Color.primary
            case .query, .fragment:
                piece.foregroundColor = Color.secondary
            case .markdownPunctuation:
                piece.foregroundColor = Color.primary.opacity(0.45)
            case .markdownText:
                piece.foregroundColor = Color.secondary
            case .plain:
                piece.foregroundColor = Color.primary
            }
            attributed.append(piece)
        }
        return attributed
    }

    private var overflowCapsule: some View {
        Text("+\(preview.overflowCharacterCount) chars")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.primary.opacity(0.08), in: Capsule())
            .accessibilityHidden(true)
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
        RoundedRectangle(cornerRadius: RefsVisualTokens.copyCardLinkWellRadius)
    }

    private var wellFill: Color {
        let increased = contrast == .increased
        return Color.primary.opacity(
            increased
                ? RefsVisualTokens.copyCardLinkWellFillOpacityIncreased
                : RefsVisualTokens.copyCardLinkWellFillOpacity
        )
    }

    private var wellStroke: Color {
        let increased = contrast == .increased
        return Color.primary.opacity(
            increased
                ? RefsVisualTokens.copyCardLinkWellStrokeOpacityIncreased
                : RefsVisualTokens.copyCardLinkWellStrokeOpacity
        )
    }
}
