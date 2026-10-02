import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for the batch-level parent-task block view: one PNG
/// per task-block fixture at full and minimum panel widths, in both
/// appearances. `BOB_MAC_CAPTURE_RENDER_DIR` points at a writable directory;
/// when set, writes the PNGs at scale 2. Inspect the PNGs with an image
/// reader and iterate on spacing, contrast, wrapping, fold rows, and guide
/// alignment. Follows `PomodoroBlockDesignTests`.
final class TaskBlockDesignTests: XCTestCase {
    /// `BOB_MAC_CAPTURE_RENDER_DIR` points at a writable directory; when set,
    /// writes light/dark PNGs at 760pt and 620pt widths for the task-block
    /// fixtures. Inspect the PNGs with an image reader and iterate on
    /// spacing, contrast, wrapping, fold rows, and guide alignment.
    @MainActor
    func testRenderTaskBlockStatesToPNG() throws {
        guard let renderDir = ProcessInfo.processInfo.environment["BOB_MAC_CAPTURE_RENDER_DIR"],
              !renderDir.isEmpty
        else {
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render the task block review images.")
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fixtures = [
            "sub-bullet-task-block.json",
            "sub-bullet-section-task-block.json",
            "sub-bullet-children-task-block.json",
            "sub-bullet-global-task-block.json",
            "sub-bullet-long-task-block.json",
        ]
        for fixture in fixtures {
            let success = try blockFixture(fixture)
            XCTAssertFalse(
                success.taskBlocks.isEmpty,
                "\(fixture) should carry task blocks to render"
            )
            let name = fixture.replacingOccurrences(of: ".json", with: "")
            for width in [760, 620] as [CGFloat] {
                for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
                    let model = CapturePanelModel()
                    model.previewResult = success
                    model.previewResults = [success]
                    model.previewState = .ready(success)
                    let pane = PreviewPane(model: model)
                        .frame(width: width)
                        .environment(
                            \.colorScheme,
                            appearance == .darkAqua ? .dark : .light
                        )
                    let renderer = ImageRenderer(content: pane)
                    renderer.scale = 2
                    guard let image = renderer.nsImage else {
                        XCTFail("Could not render \(name) (\(appearance.rawValue))")
                        continue
                    }
                    let url = directory.appendingPathComponent(
                        "task-block-\(name)-\(Int(width))-\(appearance == .darkAqua ? "dark" : "light").png"
                    )
                    try Self.pngData(for: image).write(to: url)
                }
            }
        }
    }

    private func blockFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            XCTFail("expected a successful Bob response in \(name)")
            throw NSError(domain: "TaskBlockDesignTests", code: 1)
        }
        return success
    }

    private static func pngData(for image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "TaskBlockDesignTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode task block render as PNG."]
            )
        }
        return png
    }
}
