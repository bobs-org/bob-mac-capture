import AppKit
import XCTest

@testable import BobMacCapture

/// Geometry, presentation, menu-row, and pulse coverage for the menu-bar
/// bullet-b glyph. Raster checks draw each state image at 2x into a 36x36
/// bitmap; row 0 is the top row, so 2x pixel (col, row) backs the y-down
/// point (col / 2, row / 2).
final class StatusItemGlyphTests: XCTestCase {
    @MainActor
    func testGlyphImagesAreTemplateSizedAndLabeled() {
        let states: [StatusItemGlyph.State] = [.ready, .bobUnresolved]
        for state in states {
            let image = StatusItemGlyph.image(for: state)
            XCTAssertTrue(image.isTemplate, "\(state) must be a template image")
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertFalse(
                image.accessibilityDescription?.isEmpty ?? true,
                "\(state) needs an accessibility description"
            )
        }
        XCTAssertNotEqual(
            StatusItemGlyph.image(for: .ready).accessibilityDescription,
            StatusItemGlyph.image(for: .bobUnresolved).accessibilityDescription
        )
    }

    @MainActor
    func testRasterizedInkStaysInsideInkBounds() {
        let states: [StatusItemGlyph.State] = [.ready, .bobUnresolved]
        // 1px tolerance at 2x is 0.5pt.
        let allowed = StatusItemGlyph.Metrics.inkBounds.insetBy(dx: -0.5, dy: -0.5)
        for state in states {
            let rep = rasterizeAt2X(StatusItemGlyph.image(for: state))
            for row in 0..<36 {
                for col in 0..<36 {
                    guard alpha(rep, x: col, y: row) > 0 else {
                        continue
                    }
                    let point = NSPoint(x: CGFloat(col) / 2, y: CGFloat(row) / 2)
                    XCTAssertTrue(
                        allowed.contains(point),
                        "\(state) has ink at 2x pixel (\(col), \(row))"
                    )
                }
            }
        }
    }

    @MainActor
    func testStateBitmapsDifferOnlyInsideCounter() {
        let ready = rasterizeAt2X(StatusItemGlyph.image(for: .ready))
        let alert = rasterizeAt2X(StatusItemGlyph.image(for: .bobUnresolved))
        let center = StatusItemGlyph.Metrics.bowlCenter
        let limit = StatusItemGlyph.Metrics.counterRadius + 0.5
        var differing = 0
        for row in 0..<36 {
            for col in 0..<36 {
                if alpha(ready, x: col, y: row) != alpha(alert, x: col, y: row) {
                    differing += 1
                    let point = NSPoint(x: CGFloat(col) / 2, y: CGFloat(row) / 2)
                    let distance = hypot(point.x - center.x, point.y - center.y)
                    XCTAssertLessThanOrEqual(
                        distance,
                        limit,
                        "states differ at 2x pixel (\(col), \(row))"
                    )
                }
            }
        }
        XCTAssertGreaterThan(differing, 0, "the two states must differ")
    }

    @MainActor
    func testCanvasCenterColumnHasInkInBothStates() {
        let states: [StatusItemGlyph.State] = [.ready, .bobUnresolved]
        for state in states {
            let rep = rasterizeAt2X(StatusItemGlyph.image(for: state))
            let hasInk = (0..<36).contains { alpha(rep, x: 18, y: $0) > 0 }
            XCTAssertTrue(hasInk, "\(state) has no ink in the center column")
        }
    }

    func testPulseRadiiShape() {
        let radii = StatusItemPulse.bulletRadii
        let resting = StatusItemGlyph.Metrics.bulletRadius
        XCTAssertEqual(radii.count, StatusItemPulse.frameCount + 1)
        XCTAssertEqual(radii.first, resting)
        XCTAssertEqual(radii.last, resting)
        let peak = radii.max()!
        XCTAssertEqual(peak, StatusItemPulse.peakBulletRadius, accuracy: 0.01)
        let ceiling = StatusItemGlyph.Metrics.counterRadius - 1.0
        XCTAssertTrue(
            radii.allSatisfy { $0 <= ceiling },
            "pulse must keep a 1pt gap to the counter"
        )
        let peakIndex = radii.firstIndex(of: peak)!
        let rising = radii[...peakIndex]
        let falling = radii[peakIndex...]
        XCTAssertTrue(
            zip(rising, rising.dropFirst()).allSatisfy { $0 <= $1 },
            "pulse must rise monotonically to the peak"
        )
        XCTAssertTrue(
            zip(falling, falling.dropFirst()).allSatisfy { $0 >= $1 },
            "pulse must fall monotonically after the peak"
        )
    }

    func testPresentationStrings() {
        let ready = StatusItemPresentation(isBobResolved: true)
        XCTAssertEqual(ready.glyphState, .ready)
        XCTAssertEqual(ready.toolTip, "Bob Mac Capture")
        XCTAssertEqual(ready.accessibilityLabel, "Bob Mac Capture")
        XCTAssertNil(ready.issueMenuTitle)

        let unresolved = StatusItemPresentation(isBobResolved: false)
        XCTAssertEqual(unresolved.glyphState, .bobUnresolved)
        XCTAssertEqual(
            unresolved.toolTip,
            "Bob Mac Capture — bob is not resolved. Check Settings."
        )
        XCTAssertEqual(
            unresolved.accessibilityLabel,
            "Bob Mac Capture, bob not resolved"
        )
        XCTAssertEqual(
            unresolved.issueMenuTitle,
            "bob Not Resolved — Open Settings…"
        )
    }

    @MainActor
    func testApplyIssueInsertsActionableRowAheadOfHealthyMenu() {
        let menu = AppDelegate.makeStatusMenu()
        StatusItemController.applyIssue(
            title: "bob Not Resolved — Open Settings…",
            to: menu
        )

        XCTAssertEqual(menu.items.count, 8)
        XCTAssertEqual(menu.items[0].title, "bob Not Resolved — Open Settings…")
        XCTAssertEqual(menu.items[0].action.map(NSStringFromSelector), "openSettings")
        XCTAssertNotNil(menu.items[0].image)
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(
            menu.items.dropFirst(2).map(\.title),
            [
                "Capture", "Settings", "Recheck Bob", "",
                "Restart Bob Mac Capture", "Quit Bob Mac Capture",
            ]
        )
    }

    @MainActor
    func testApplyIssueIsIdempotentAndNilRestoresHealthyMenu() {
        let menu = AppDelegate.makeStatusMenu()
        let title = "bob Not Resolved — Open Settings…"
        let healthy = menu.items.map(\.title)

        StatusItemController.applyIssue(title: title, to: menu)
        StatusItemController.applyIssue(title: title, to: menu)
        XCTAssertEqual(menu.items.count, healthy.count + 2)
        XCTAssertEqual(menu.items[0].title, title)

        StatusItemController.applyIssue(title: nil, to: menu)
        XCTAssertEqual(menu.items.map(\.title), healthy)
    }

    @MainActor
    func testPulseRendersTwentyFourFramesEndingOnRestingReady() async {
        let box = FrameBox()
        let controller = makeController(box: box)
        controller.update(isBobResolved: true)
        box.frames.removeAll()

        controller.playCaptureLandedPulse()
        await controller.pulseTask?.value

        XCTAssertEqual(box.frames.count, StatusItemPulse.frameCount)
        XCTAssertTrue(box.frames.allSatisfy { $0.glyphState == .ready })
        XCTAssertEqual(
            box.frames.last?.bulletRadius,
            StatusItemGlyph.Metrics.bulletRadius
        )
        XCTAssertEqual(box.frames.last?.toolTip, "Bob Mac Capture")
    }

    @MainActor
    func testPulseSkippedUnderReduceMotion() async {
        let box = FrameBox()
        let controller = makeController(box: box, reduceMotion: true)
        controller.update(isBobResolved: true)

        controller.playCaptureLandedPulse()
        await controller.pulseTask?.value

        XCTAssertEqual(box.frames.count, 1)
    }

    @MainActor
    func testUnresolvedStateNeverPulses() async {
        let box = FrameBox()
        let controller = makeController(box: box)
        controller.update(isBobResolved: false)

        controller.playCaptureLandedPulse()
        await controller.pulseTask?.value

        XCTAssertEqual(box.frames.count, 1)
        XCTAssertEqual(box.frames.first?.glyphState, .bobUnresolved)
    }

    @MainActor
    func testStateChangeDuringPulseLeavesAlertRestingLast() async {
        let box = FrameBox()
        let controller = makeController(box: box)
        controller.update(isBobResolved: true)
        controller.playCaptureLandedPulse()
        let inFlight = controller.pulseTask

        controller.update(isBobResolved: false)
        await inFlight?.value

        XCTAssertEqual(box.frames.count, 2)
        XCTAssertEqual(box.frames.last?.glyphState, .bobUnresolved)
        XCTAssertEqual(
            box.frames.last?.bulletRadius,
            StatusItemGlyph.Metrics.bulletRadius
        )
        XCTAssertFalse(
            box.frames.dropFirst(2).contains { $0.glyphState == .ready },
            "no Ready frames may follow the alert resting frame"
        )
    }

    private final class FrameBox {
        var frames: [StatusItemFrame] = []
    }

    @MainActor
    private func makeController(box: FrameBox, reduceMotion: Bool = false) -> StatusItemController {
        StatusItemController(
            render: { box.frames.append($0) },
            menu: AppDelegate.makeStatusMenu(),
            reduceMotion: { reduceMotion },
            sleep: { _ in await Task.yield() }
        )
    }

    @MainActor
    private func rasterizeAt2X(_ image: NSImage) -> NSBitmapImageRep {
        let pixels = 36
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Alpha of the pixel at column `x`, row `y`; row 0 is the top row.
    private func alpha(_ rep: NSBitmapImageRep, x: Int, y: Int) -> UInt8 {
        let data = rep.bitmapData!
        let offset = y * rep.bytesPerRow + x * rep.samplesPerPixel
        let alphaIndex = rep.bitmapFormat.contains(.alphaFirst) ? 0 : 3
        return data[offset + alphaIndex]
    }
}
