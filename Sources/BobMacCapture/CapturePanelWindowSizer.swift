import AppKit

/// Pure window-geometry math for the capture panel. Touches no live `NSWindow`; the
/// controller supplies live values (current frame, chrome height, visible frame) and
/// applies the result.
struct CapturePanelWindowSizer: Equatable {
    var minimumContentHeight: CGFloat = CapturePanelLayout.panelMinimumContentHeight
    var maximumContentHeight: CGFloat = CapturePanelLayout.panelMaximumContentHeight
    var screenMargin: CGFloat = CapturePanelLayout.panelScreenMargin
    var displayScale: CGFloat = 1

    /// Clamps a SwiftUI-measured ideal content height into the panel's allowed range,
    /// further bounding it to the given screen height (minus margins) when known.
    func contentHeight(
        forIdealContentHeight idealContentHeight: CGFloat,
        availableScreenHeight: CGFloat?
    ) -> CGFloat {
        var clamped = min(max(idealContentHeight, minimumContentHeight), maximumContentHeight)
        if let availableScreenHeight {
            let screenLimit = max(minimumContentHeight, availableScreenHeight - 2 * screenMargin)
            clamped = min(clamped, screenLimit)
        }
        return roundedToPixel(clamped)
    }

    /// Converts a target content height into a frame rect that preserves the window's
    /// top edge (`maxY`), origin.x, and width, nudging the result back inside
    /// `visibleFrame` if growing would cross the screen's top or bottom edge.
    func frame(
        forCurrentFrame currentFrame: NSRect,
        contentHeight: CGFloat,
        chromeHeight: CGFloat,
        visibleFrame: NSRect
    ) -> NSRect {
        let frameHeight = contentHeight + chromeHeight
        var rect = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.maxY - frameHeight,
            width: currentFrame.width,
            height: frameHeight
        )

        if rect.minY < visibleFrame.minY {
            rect.origin.y = visibleFrame.minY
        }
        if rect.maxY > visibleFrame.maxY {
            rect.origin.y = visibleFrame.maxY - frameHeight
        }

        return rect
    }

    private func roundedToPixel(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded(.up) / scale
    }
}
