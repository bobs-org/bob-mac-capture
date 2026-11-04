import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for move, merge, consequence, offer, and unchanged
/// transfer cards at panel and minimum widths in light and dark appearances.
final class CaptureTransferCardDesignTests: XCTestCase {
    @MainActor
    func testRenderTransferCardsToPNG() throws {
        guard let renderDir = ProcessInfo.processInfo.environment["BOB_MAC_CAPTURE_RENDER_DIR"],
              !renderDir.isEmpty
        else {
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render transfer card review images.")
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fixtures = [
            "capture-transfer-merge.json",
            "capture-transfer-consequences-offers.json",
            "capture-transfer-drawer-merge.json",
            "capture-transfer-section-merge.json",
            "capture-transfer-move.json",
            "capture-transfer-unchanged-merge.json",
        ]
        for fixture in fixtures {
            let success = try transferFixture(fixture)
            XCTAssertNotNil(CaptureTransferPresentation(capture: success), fixture)
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
                    let style = appearance == .darkAqua ? "dark" : "light"
                    let url = directory.appendingPathComponent(
                        "transfer-card-\(name)-\(Int(width))-\(style).png"
                    )
                    try Self.pngData(for: image).write(to: url)
                }
            }
        }
    }

    private func transferFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            XCTFail("expected a successful Bob response in \(name)")
            throw NSError(domain: "CaptureTransferCardDesignTests", code: 1)
        }
        return success
    }

    private static func pngData(for image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "CaptureTransferCardDesignTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode transfer render as PNG."]
            )
        }
        return png
    }
}
