import RefsCore
import SwiftUI

@available(macOS 26.0, *)
struct RefsPickerScopeLine: View {
    let scope: RefsPickerScope
    var previewMode = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animatesSelection: Bool { !previewMode && !reduceMotion }

    var body: some View {
        HStack(spacing: 0) {
            Text(scope.noun.ordinalWord + " ")
                .foregroundStyle(.secondary)
            Text("\(scope.selectedOrdinal)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(animatesSelection ? .numericText() : .identity)
            Text(" of \(scope.total)")
                .foregroundStyle(.secondary)
            if let label = scope.scopeLabel {
                Text(" · \(label)")
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .frame(height: RefsVisualTokens.copyCardPickerScopeLineHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scope.accessibilityLabel)
        .animation(
            animatesSelection ? .smooth(duration: 0.18) : nil,
            value: scope.selectedOrdinal
        )
    }
}

@available(macOS 26.0, *)
struct RefsPickerScopeRail: View {
    let scope: RefsPickerScope
    var previewMode = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var animatesScope: Bool { !previewMode && !reduceMotion }
    private var trackOpacity: Double {
        contrast == .increased
            ? RefsVisualTokens.copyCardPickerRailTrackOpacityIncreased
            : RefsVisualTokens.copyCardPickerRailTrackOpacity
    }
    private var thumbOpacity: Double {
        contrast == .increased
            ? RefsVisualTokens.copyCardPickerRailThumbOpacityIncreased
            : RefsVisualTokens.copyCardPickerRailThumbOpacity
    }
    private var tickOpacity: Double {
        contrast == .increased
            ? RefsVisualTokens.copyCardPickerRailTickOpacityIncreased
            : RefsVisualTokens.copyCardPickerRailTickOpacity
    }

    var body: some View {
        GeometryReader { proxy in
            if let geometry = RefsPickerRailGeometry.make(
                scope: scope,
                trackHeight: Double(proxy.size.height),
                minimumThumbHeight: Double(RefsVisualTokens.copyCardPickerRailMinimumThumbHeight),
                tickHalfHeight: 1
            ) {
                ZStack(alignment: .top) {
                    railCapsule(
                        color: Color.primary.opacity(trackOpacity),
                        height: geometry.trackHeight
                    )
                    railCapsule(
                        color: Color.primary.opacity(thumbOpacity),
                        height: geometry.thumb.upperBound - geometry.thumb.lowerBound
                    )
                    .offset(y: geometry.thumb.lowerBound)
                    ForEach(Array(geometry.ticks.enumerated()), id: \.offset) { _, tick in
                        railCapsule(
                            color: Color.accentColor.opacity(tickOpacity),
                            height: tick.upperBound - tick.lowerBound
                        )
                        .offset(y: tick.lowerBound)
                    }
                    railCapsule(
                        color: Color.accentColor,
                        width: RefsVisualTokens.copyCardPickerRailNotchWidth,
                        height: RefsVisualTokens.copyCardPickerRailNotchHeight
                    )
                    .offset(
                        y: geometry.selectedY - RefsVisualTokens.copyCardPickerRailNotchHeight / 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(
                    animatesScope ? .smooth(duration: 0.18) : nil,
                    value: scope
                )
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func railCapsule(
        color: Color,
        width: CGFloat = RefsVisualTokens.copyCardPickerRailTrackWidth,
        height: Double
    ) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: CGFloat(max(0, height)))
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
