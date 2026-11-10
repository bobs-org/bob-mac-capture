import CaptureCore
import SwiftUI

/// Shared meeting-and-buffer rail drawing for the agenda day rail and
/// the event-note rail. Bob owns every time fact; these views convert
/// only normalized positions to pixels and never parse note text.
///
/// The buffer-wing fill is a clipped diagonal hatch drawn with
/// `Canvas`, not a raster image or a character string, so it stays
/// crisp at any width and visible in both appearances and increased
/// contrast.
@available(macOS 26.0, *)
enum EventTimeRailMetrics {
    /// Event-note meeting capsule height (the agenda uses 5).
    static let capsuleHeight: CGFloat = 8
    static let capsuleRadius: CGFloat = 4
    /// Event-note wing height (the agenda uses 3).
    static let wingHeight: CGFloat = 5
    static let wingRadius: CGFloat = 2.5
    /// Height of the event-note rail strip.
    static let stripHeight: CGFloat = 14
    /// Narrowest painted span, matching the agenda rail.
    static let minimumSpan: CGFloat = 2
    /// Normalized spans at or below this read as zero-width.
    static let zeroSpanEpsilon = 0.004
}

/// A meeting capsule shared by the agenda rail and the event-note
/// rail: solid in the event hue, hollow and dashed for off-clock and
/// Maybe/free rows, with a stronger outline in increased contrast.
@available(macOS 26.0, *)
struct SharedRailCapsule: View {
    let hue: PomodoroHomeHue?
    let offClock: Bool
    let maybe: Bool
    var height: CGFloat = 5
    var cornerRadius: CGFloat = 2
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let color = PomodoroHomeColor.color(for: hue, scheme: colorScheme)
        let strokeWidth: CGFloat = contrast == .increased ? 1.5 : 1
        let fill: Color =
            offClock || maybe ? .clear : color.opacity(0.9)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        dash: maybe ? [1, 2] : offClock ? [3, 2] : []
                    )
                )
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// Diagonal hatch clipped to a wing-sized rounded rectangle. The
/// translucent base keeps the wing readable on any background while
/// the solid diagonal strokes keep it visible in both appearances and
/// increased contrast.
@available(macOS 26.0, *)
struct HatchedWingFill: View {
    let color: Color
    var cornerRadius: CGFloat = 1.5
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else {
                return
            }
            let rect = CGRect(origin: .zero, size: size)
            let clip = Path(
                roundedRect: rect,
                cornerRadius: cornerRadius
            )
            context.clip(to: clip)
            context.fill(
                clip,
                with: .color(
                    color.opacity(contrast == .increased ? 0.30 : 0.18)
                )
            )
            var strokes = Path()
            let spacing: CGFloat = 4
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                strokes.move(to: CGPoint(x: x, y: size.height))
                strokes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(
                strokes,
                with: .color(
                    color.opacity(contrast == .increased ? 1 : 0.85)
                ),
                lineWidth: contrast == .increased ? 1.25 : 1
            )
        }
        .accessibilityHidden(true)
    }
}

/// A buffer wing fused to a rail capsule, shared by the agenda rail
/// and the event-note rail: thinner than the capsule, hatched in the
/// event's home hue, dashed when the event is off-clock or
/// Maybe/free, and outlined in the hue while the buffer is in
/// progress.
@available(macOS 26.0, *)
struct SharedRailWing: View {
    let hue: PomodoroHomeHue?
    let offClock: Bool
    let maybe: Bool
    let active: Bool
    var height: CGFloat = 3
    var cornerRadius: CGFloat = 1.5
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let color = PomodoroHomeColor.color(for: hue, scheme: colorScheme)
        let dashed = offClock || maybe
        HatchedWingFill(color: color, cornerRadius: cornerRadius)
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(
                    active ? color : color.opacity(0.55),
                    style: StrokeStyle(
                        lineWidth: active ? 1.5 : 1,
                        dash: dashed ? [2, 2] : []
                    )
                )
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// The event-note rail: a larger solid meeting capsule with
/// proportionate hatched wings, driven only by Bob's structured
/// `effective` times, hue, and reasons. Decorative geometry is hidden
/// from VoiceOver; the whole rail reports one spoken summary.
@available(macOS 26.0, *)
struct EventNoteRailView: View {
    let geometry: EventTimeRailGeometry?
    let content: EventTimeRailContent
    @Environment(\.colorScheme) private var colorScheme

    init(
        effective: GcalNoteEffective?,
        answer: String? = nil,
        nowMinutes: Double? = nil
    ) {
        content = EventTimeRailContent(effective: effective, answer: answer)
        geometry = EventTimeRailGeometry(
            meeting: effective?.meeting,
            occupied: effective?.occupied,
            nowMinutes: nowMinutes
        )
    }

    init(
        geometry: EventTimeRailGeometry?,
        content: EventTimeRailContent
    ) {
        self.geometry = geometry
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let geometry {
                railStrip(geometry)
            }
            timeSentence
            if let leading = content.leadingReasonLabel {
                Text(leading)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityHidden(true)
            }
            if let trailing = content.trailingReasonLabel {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.voiceOverSummary)
    }

    private func railStrip(_ geometry: EventTimeRailGeometry) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 2)
                    .offset(y: EventTimeRailMetrics.stripHeight / 2 - 1)
                if let leading = geometry.leadingWing,
                    leading.end - leading.start
                        > EventTimeRailMetrics.zeroSpanEpsilon
                {
                    SharedRailWing(
                        hue: content.hue,
                        offClock: content.offClock,
                        maybe: content.maybe,
                        active: leading.active,
                        height: EventTimeRailMetrics.wingHeight,
                        cornerRadius: EventTimeRailMetrics.wingRadius
                    )
                    .frame(
                        width: wingWidth(
                            start: leading.start,
                            end: leading.end,
                            width: width
                        ),
                        height: EventTimeRailMetrics.wingHeight
                    )
                    .position(
                        x: EventTimeRailGeometry.x(
                            (leading.start + leading.end) / 2,
                            totalWidth: width
                        ),
                        y: EventTimeRailMetrics.stripHeight / 2
                    )
                }
                SharedRailCapsule(
                    hue: content.hue,
                    offClock: content.offClock,
                    maybe: content.maybe,
                    height: EventTimeRailMetrics.capsuleHeight,
                    cornerRadius: EventTimeRailMetrics.capsuleRadius
                )
                .frame(
                    width: capsuleWidth(geometry, width: width),
                    height: EventTimeRailMetrics.capsuleHeight
                )
                .position(
                    x: EventTimeRailGeometry.x(
                        (geometry.meetingStart + geometry.meetingEnd) / 2
                            / EventTimeRailGeometry.minutesPerDay,
                        totalWidth: width
                    ),
                    y: EventTimeRailMetrics.stripHeight / 2
                )
                if let trailing = geometry.trailingWing,
                    trailing.end - trailing.start
                        > EventTimeRailMetrics.zeroSpanEpsilon
                {
                    SharedRailWing(
                        hue: content.hue,
                        offClock: content.offClock,
                        maybe: content.maybe,
                        active: trailing.active,
                        height: EventTimeRailMetrics.wingHeight,
                        cornerRadius: EventTimeRailMetrics.wingRadius
                    )
                    .frame(
                        width: wingWidth(
                            start: trailing.start,
                            end: trailing.end,
                            width: width
                        ),
                        height: EventTimeRailMetrics.wingHeight
                    )
                    .position(
                        x: EventTimeRailGeometry.x(
                            (trailing.start + trailing.end) / 2,
                            totalWidth: width
                        ),
                        y: EventTimeRailMetrics.stripHeight / 2
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .clipped()
        }
        .frame(height: EventTimeRailMetrics.stripHeight)
        .accessibilityHidden(true)
    }

    private var timeSentence: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(
                    PomodoroHomeColor.color(
                        for: content.hue,
                        scheme: colorScheme
                    )
                )
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(content.timeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let clipping = content.clippingText {
                Text(clipping)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityHidden(true)
    }

    private func capsuleWidth(
        _ geometry: EventTimeRailGeometry,
        width: CGFloat
    ) -> CGFloat {
        max(
            EventTimeRailMetrics.minimumSpan,
            EventTimeRailGeometry.spanWidth(
                start: geometry.meetingStart
                    / EventTimeRailGeometry.minutesPerDay,
                end: geometry.meetingEnd
                    / EventTimeRailGeometry.minutesPerDay,
                totalWidth: Double(width)
            )
        )
    }

    private func wingWidth(
        start: Double,
        end: Double,
        width: CGFloat
    ) -> CGFloat {
        max(
            EventTimeRailMetrics.minimumSpan,
            EventTimeRailGeometry.spanWidth(
                start: start,
                end: end,
                totalWidth: Double(width)
            )
        )
    }
}
