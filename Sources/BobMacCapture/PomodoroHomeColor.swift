import AppKit
import CaptureCore
import SwiftUI

/// Maps an R8 hue slot to a SwiftUI color for the current appearance.
/// Unknown or missing hues use the tertiary label color (gray buckets).
enum PomodoroHomeColor {
    static func color(for hue: PomodoroHomeHue?, scheme: ColorScheme) -> Color {
        let hex: String?
        switch scheme {
        case .dark:
            hex = hue?.darkHex
        default:
            hex = hue?.lightHex
        }
        guard let hex, let parsed = Color(pomodoroHomeHex: hex) else {
            return Color(nsColor: .tertiaryLabelColor)
        }
        return parsed
    }
}

extension Color {
    init?(pomodoroHomeHex hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

/// Muted home-chip accessory: a 7pt area-hue dot plus the label.
@available(macOS 26.0, *)
struct PomodoroHomeChipView: View {
    let chip: String
    let hue: PomodoroHomeHue?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(PomodoroHomeColor.color(for: hue, scheme: colorScheme))
                .frame(width: 7, height: 7)
            Text(chip)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }
}
