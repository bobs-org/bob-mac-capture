import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for the whole-item `!note:block-id` completion card:
/// one PNG per task-complete fixture at full and minimum panel widths, in both
/// appearances. `BOB_MAC_CAPTURE_RENDER_DIR` points at a writable directory;
/// when set, writes the PNGs at scale 2. Inspect the PNGs with an image
/// reader and iterate on spacing, contrast, strikethrough, and fact-row
/// alignment. Follows `TaskBlockDesignTests`.
final class TaskCompleteDesignTests: XCTestCase {
    @MainActor
    func testRenderTaskCompleteStatesToPNG() throws {
        guard let renderDir = ProcessInfo.processInfo.environment["BOB_MAC_CAPTURE_RENDER_DIR"],
              !renderDir.isEmpty
        else {
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render the completion card review images.")
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fixtures = [
            "task-complete-strike.json",
            "task-complete-subtasks.json",
            "task-complete-unblocked.json",
            "task-complete-already-done.json",
        ]
        for fixture in fixtures {
            let success = try completeFixture(fixture)
            XCTAssertNotNil(
                CaptureTaskCompletePresentation(capture: success),
                "\(fixture) should carry a task_complete preview"
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
                        "task-complete-\(name)-\(Int(width))-\(appearance == .darkAqua ? "dark" : "light").png"
                    )
                    try Self.pngData(for: image).write(to: url)
                }
            }
        }
    }

    private func completeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            XCTFail("expected a successful Bob response in \(name)")
            throw NSError(domain: "TaskCompleteDesignTests", code: 1)
        }
        return success
    }

    private static func pngData(for image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "TaskCompleteDesignTests", code: 2)
        }
        return data
    }
}
