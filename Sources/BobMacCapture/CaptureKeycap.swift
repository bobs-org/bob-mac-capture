import SwiftUI

/// House keycap used by picker key hints and the typing-tip row, so the two
/// can never drift. Neutral, never tinted.
@available(macOS 26.0, *)
struct CaptureKeycap: View {
    var keys: String

    var body: some View {
        Text(keys)
            .font(.caption.monospaced())
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
    }
}
