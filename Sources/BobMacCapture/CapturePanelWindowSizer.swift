import AppKit

/// Pure window-geometry math for the capture panel. Touches no live `NSWindow`; the
/// controller supplies live values (current frame, chrome height, visible frame) and
/// applies the result.
struct CapturePanelWindowSizer: Equatable {
    var minimumContentHeight: CGFloat = CapturePanelLayout.panelMinimumContentHeight
    /// Artificial content-height cap. `nil` (the default) means no cap beyond the
    /// screen limit. Tests and the no-screen controller path pass a value; a live
    /// panel with a known screen does not.
    var maximumContentHeight: CGFloat? = nil
    var screenMargin: CGFloat = CapturePanelLayout.panelScreenMargin
    var displayScale: CGFloat = 1

    /// Clamps SwiftUI-measured content metrics into the panel's allowed range, further
    /// bounding them to the given screen height (minus margins) when known.
    func contentHeight(
        for metrics: CapturePanelContentMetrics,
        availableScreenHeight: CGFloat?
    ) -> CGFloat {
        let persistentMinimum = max(metrics.minimumVisibleContentHeight, minimumContentHeight)
        var clamped = max(metrics.idealContentHeight, persistentMinimum)
        if let maximumContentHeight {
            clamped = min(clamped, maximumContentHeight)
            clamped = max(clamped, persistentMinimum)
        }

        if let availableScreenHeight {
            // Round the screen limit down to the pixel grid *before* clamping so the
            // subsequent round-up cannot return a value a fraction of a point above
            // the visible frame.
            let screenLimit = max(1, roundedDownToPixel(availableScreenHeight - 2 * screenMargin))
            if screenLimit < persistentMinimum {
                return screenLimit
            }
            clamped = min(clamped, screenLimit)
            clamped = max(clamped, persistentMinimum)
            return min(roundedToPixel(clamped), screenLimit)
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

    private func roundedDownToPixel(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded(.down) / scale
    }
}
