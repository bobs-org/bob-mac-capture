import AppKit
import XCTest

@testable import BobMacCapture

/// Rendered-image review for the menu-bar bullet-b glyph: one PNG per state at
/// 1x, 2x, and 3x on light, dark, and accent (highlighted) backgrounds, an 8x
/// enlargement of each state, and the landed-pulse filmstrip.
/// `BOB_MAC_CAPTURE_RENDER_DIR` points at a writable directory; when set,
/// writes the PNGs. Inspect the PNGs with an image reader and iterate on
/// weight, balance, and the alert "!" legibility. Follows
/// `PomodoroBlockDesignTests`.
final class StatusItemGlyphDesignTests: XCTestCase {
    /// `BOB_MAC_CAPTURE_RENDER_DIR` points at a writable directory; when set,
    /// writes each state's 1x/2x/3x renders on light, dark, and accent
    /// backgrounds, 8x enlargements, and the pulse filmstrip. Inspect the PNGs
    /// with an image reader to eyeball the real AppKit rendering.
    @MainActor
    func testRenderStatusItemGlyphsToPNG() throws {
        guard let renderDir = ProcessInfo.processInfo.environment[
            "BOB_MAC_CAPTURE_RENDER_DIR"
        ], !renderDir.isEmpty else {
            throw XCTSkip(
                "Set BOB_MAC_CAPTURE_RENDER_DIR to render the glyph review images."
            )
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let states: [StatusItemGlyph.State] = [.ready, .bobUnresolved]
        let backdrops: [Backdrop] = [.light, .dark, .accent]
        let resting = StatusItemGlyph.Metrics.bulletRadius
        for state in states {
            let name = state == .ready ? "ready" : "bob-unresolved"
            for scale in [1, 2, 3] {
                for backdrop in backdrops {
                    let rep = renderGlyph(
                        state: state,
                        bulletRadius: resting,
                        pixelsWide: 18 * scale,
                        pixelsHigh: 18 * scale,
                        background: backdrop.color
                    )
                    let url = directory.appendingPathComponent(
                        "status-item-glyph-\(name)-\(scale)x-\(backdrop.name).png"
                    )
                    try Self.pngData(for: rep).write(to: url)
                }
            }
            for backdrop in [Backdrop.light, .dark] {
                let rep = renderGlyph(
                    state: state,
                    bulletRadius: resting,
                    pixelsWide: 144,
                    pixelsHigh: 144,
                    background: backdrop.color
                )
                let url = directory.appendingPathComponent(
                    "status-item-glyph-\(name)-8x-\(backdrop.name).png"
                )
                try Self.pngData(for: rep).write(to: url)
            }
        }

        // Landed-pulse filmstrip: one 2x cell per pulse sample on light.
        let cell = 36
        let radii = StatusItemPulse.bulletRadii
        let strip = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: cell * radii.count,
            pixelsHigh: cell,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: strip)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: cell * radii.count, height: cell).fill()
        for (index, radius) in radii.enumerated() {
            StatusItemGlyph.image(for: .ready, bulletRadius: radius).draw(
                in: NSRect(x: index * cell, y: 0, width: cell, height: cell)
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        try Self.pngData(for: strip).write(
            to: directory.appendingPathComponent(
                "status-item-glyph-pulse-filmstrip-light.png"
            )
        )
    }

    private enum Backdrop {
        case light
        case dark
        case accent

        var color: NSColor {
            switch self {
            case .light: return .white
            case .dark: return .black
            case .accent: return .systemBlue
            }
        }

        var name: String {
            switch self {
            case .light: return "light"
            case .dark: return "dark"
            case .accent: return "accent"
            }
        }
    }

    @MainActor
    private func renderGlyph(
        state: StatusItemGlyph.State,
        bulletRadius: CGFloat,
        pixelsWide: Int,
        pixelsHigh: Int,
        background: NSColor
    ) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
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
        background.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        StatusItemGlyph.image(for: state, bulletRadius: bulletRadius).draw(
            in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh)
        )
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func pngData(for rep: NSBitmapImageRep) throws -> Data {
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "StatusItemGlyphDesignTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not encode glyph render."
                ]
            )
        }
        return png
    }
}
