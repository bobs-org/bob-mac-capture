import Foundation

/// Fixed eye line for show-time panel placement: every show, with or
/// without the agenda or a retained draft, puts the input line in the
/// same place.
///
/// The eye line is the top edge `center()` gives the _compact_ panel
/// (editor + footer, no auxiliary region). Shows place the panel at
/// that top with the target height, so the agenda grows downward from
/// the same input line instead of re-centring. Typed previews keep
/// today's clamp and slide-up rule on top of it.
///
/// The top is cached per screen visible frame: if the screen at show
/// time differs from the one planned for, only the budget changes and
/// re-planning is arithmetic on cached heights.
public struct CapturePanelPlacement: Equatable, Sendable {
    /// A screen's visible frame, in screen coordinates.
    public struct VisibleFrame: Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var width: Double
        public var height: Double

        public init(minX: Double, minY: Double, width: Double, height: Double) {
            self.minX = minX
            self.minY = minY
            self.width = width
            self.height = height
        }

        public var maxY: Double { minY + height }
    }

    private var cachedFrame: VisibleFrame?
    private var cachedTop: Double?

    public init() {}

    /// The eye-line top for a screen: where `center()` puts the top of
    /// the compact panel. Compact means the one-line editor plus the
    /// footer and chrome, with no auxiliary region.
    public mutating func eyeLineTop(
        compactContentHeight: Double,
        chromeHeight: Double,
        visibleFrame: VisibleFrame
    ) -> Double {
        if let cachedFrame, let cachedTop, cachedFrame == visibleFrame {
            return cachedTop
        }
        let frameHeight = compactContentHeight + chromeHeight
        let top = visibleFrame.minY + (visibleFrame.height - frameHeight) / 2 + frameHeight
        cachedFrame = visibleFrame
        cachedTop = top
        return top
    }

    /// The last cached top without computing, so callers can tell a
    /// first show (nothing cached) from a repeat.
    public var lastCachedTop: Double? { cachedTop }

    /// Forgets the cached top, forcing the next show to re-derive it
    /// from the compact panel.
    public mutating func invalidate() {
        cachedFrame = nil
        cachedTop = nil
    }

    /// The panel origin's y for a target content height that preserves
    /// the top edge: the window grows downward from the eye line.
    public static func originY(
        topEdge: Double,
        contentHeight: Double,
        chromeHeight: Double
    ) -> Double {
        topEdge - (contentHeight + chromeHeight)
    }
}
