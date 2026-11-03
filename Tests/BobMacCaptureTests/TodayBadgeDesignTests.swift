import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Contact sheets for reviewing the TODAY badge ladder and pull-in pair.
/// Set `BOB_MAC_CAPTURE_RENDER_DIR` to write scale-2 PNGs in both appearances.
@available(macOS 26.0, *)
@MainActor
final class TodayBadgeDesignTests: XCTestCase {
    func testRenderTodayBadgeLadderToPNG() throws {
        guard
            let renderDir = ProcessInfo.processInfo.environment[
                "BOB_MAC_CAPTURE_RENDER_DIR"
            ], !renderDir.isEmpty
        else {
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render the TODAY badge review images.")
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let sheet = VStack(alignment: .leading, spacing: 9) {
                badgeRow("Grey · 0/10", count: 0, cap: 10)
                badgeRow("Blue · 3/10", count: 3, cap: 10)
                badgeRow("Green · 4/10", count: 4, cap: 10)
                badgeRow("Yellow · 6/10", count: 6, cap: 10)
                badgeRow("Orange · 8/10", count: 8, cap: 10)
                badgeRow("Magenta · 10/10", count: 10, cap: 10)
                badgeRow("Red · 11/10", count: 11, cap: 10)
                badgeRow("Unavailable", count: 0, cap: 0)
                Divider()
                HStack(spacing: 8) {
                    Text("Pull-in pair")
                        .frame(width: 100, alignment: .leading)
                    TodayBadge(presentation: TodayBadgePresentation(count: 6, cap: 10))
                    TodayBadgeDeltaChip(text: "+2")
                }
            }
            .font(.caption)
            .padding(18)
            .frame(width: 390, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)

            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 2
            guard let image = renderer.nsImage else {
                XCTFail("Could not render the TODAY badge ladder in \(name) appearance")
                continue
            }
            let url = directory.appendingPathComponent("today-badge-ladder-\(name).png")
            try Self.pngData(for: image).write(to: url)
        }
    }

    private func badgeRow(_ label: String, count: Int, cap: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 100, alignment: .leading)
            TodayBadge(presentation: TodayBadgePresentation(count: count, cap: cap))
        }
    }

    private static func pngData(for image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "TodayBadgeDesignTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode TODAY badge render as PNG."]
            )
        }
        return png
    }
}
