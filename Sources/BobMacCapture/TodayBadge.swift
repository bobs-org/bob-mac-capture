import CaptureCore
import SwiftUI

@available(macOS 26.0, *)
struct TodayBadge: View {
    let presentation: TodayBadgePresentation
    var accessibilityLabel: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(presentation: TodayBadgePresentation, accessibilityLabel: String? = nil) {
        self.presentation = presentation
        self.accessibilityLabel = accessibilityLabel
    }

    private var tone: WorkBadgeTone {
        presentation.tone ?? .grey
    }

    private var accent: Color {
        let hex = colorScheme == .dark ? tone.darkHex : tone.lightHex
        return Color(pomodoroHomeHex: hex) ?? .secondary
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    private var snappy: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.15)
    }

    var body: some View {
        Text(presentation.text)
            .font(.callout.weight(.semibold).smallCaps().uppercaseSmallCaps().monospacedDigit())
            .tracking(0.5)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, 9)
            .padding(.trailing, 8.5)
            .padding(.vertical, 3.5)
            .background(accent.opacity(0.14), in: shape)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 2)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(accent.opacity(0.28), lineWidth: 1)
            }
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(snappy, value: presentation.text)
            .animation(snappy, value: presentation.tone)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel ?? presentation.spokenText)
            .help(presentation.helpText)
    }
}

@available(macOS 26.0, *)
struct TodayBadgeDeltaChip: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    private var snappy: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.15)
    }

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold).smallCaps().uppercaseSmallCaps().monospacedDigit())
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8.5)
            .padding(.vertical, 3.5)
            .background(.quaternary, in: shape)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(snappy, value: text)
    }
}
