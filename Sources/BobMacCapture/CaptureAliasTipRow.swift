import CaptureCore
import SwiftUI

/// One pinned "Next time" line at the foot of a completion list or picker.
/// No icon, emoji, "Tip:" label, button, focus stop, or animation.
@available(macOS 26.0, *)
struct CaptureAliasTipRow: View {
    let presentation: CaptureAliasTipPresentation
    var sigilColor: Color = .primary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(includePhrase: true)
            line(includePhrase: false)
            Color.clear.frame(height: CapturePanelLayout.aliasTipRowHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CapturePanelLayout.aliasTipRowHeight)
        .padding(.leading, 8)
        .help(presentation.helpText)
        .accessibilityHidden(true)
    }

    private func line(includePhrase: Bool) -> some View {
        HStack(spacing: 0) {
            Text(presentation.leadText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Color.clear.frame(width: 8, height: 1)
            CaptureKeycap(keys: presentation.key)
            Text("→")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
            Text(presentation.sigil)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(sigilColor)
            if includePhrase, let phrase = presentation.phrase, !phrase.isEmpty {
                Color.clear.frame(width: 8, height: 1)
                Text(phrase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
