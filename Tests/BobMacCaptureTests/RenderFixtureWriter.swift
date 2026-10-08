import AppKit
import SwiftUI
import XCTest

/// Shared PNG render helper for design tests: every design-test render goes
/// through here so CI uploads one uniform set of fixtures.
///
/// Renders `view` at the given width with `ImageRenderer` at scale 2 onto an
/// opaque `windowBackgroundColor` base, then writes
/// `<name>-<light|dark>.png` to `BOB_MAC_CAPTURE_RENDER_DIR`. Throws `XCTSkip`
/// when that variable is unset, like the design tests that predate it.
enum RenderFixtureWriter {
    static func write<V: View>(
        _ view: V,
        name: String,
        width: CGFloat,
        appearance: NSAppearance.Name
    ) throws {
        guard let renderDir = ProcessInfo.processInfo.environment[
            "BOB_MAC_CAPTURE_RENDER_DIR"
        ], !renderDir.isEmpty else {
            throw XCTSkip(
                "Set BOB_MAC_CAPTURE_RENDER_DIR to render the \(name) images."
            )
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let dark = appearance == .darkAqua
        let composed = ZStack {
            Color(nsColor: .windowBackgroundColor)
            view
        }
        .frame(width: width)
        .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: composed)
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            throw NSError(
                domain: "RenderFixtureWriter",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not render \(name) (\(appearance.rawValue))."
                ]
            )
        }
        let url = directory.appendingPathComponent(
            "\(name)-\(dark ? "dark" : "light").png"
        )
        try pngData(for: image, name: name).write(to: url)
    }

    private static func pngData(for image: NSImage, name: String) throws
        -> Data
    {
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "RenderFixtureWriter",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not encode \(name) render as PNG."
                ]
            )
        }
        return png
    }
}
