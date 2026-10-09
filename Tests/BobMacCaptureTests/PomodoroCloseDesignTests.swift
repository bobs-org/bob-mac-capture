import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for the Pomodoro close card with successor links:
/// one PNG per close-successors fixture at full and minimum panel widths, in
/// both appearances. `BOB_MAC_CAPTURE_RENDER_DIR` points at a writable
/// directory; when set, writes the PNGs at scale 2. Inspect the PNGs with an
/// image reader and iterate on the Unblocked section, destination capsules,
/// and badge alignment. Follows `TaskCompleteDesignTests`.
///
/// Fixtures (`Tests/Fixtures/pomodoro-close-successors.json`,
/// `pomodoro-close-carried.json`) are real `bob capture --dry-run -f json`
/// responses from bob-cli master with the successor-link capture phases,
/// against sandbox vaults (see `Tests/Fixtures/fake-bob` routes `=x!1` and
/// `=x!2` for the true drafts).
final class PomodoroCloseDesignTests: XCTestCase {
    @MainActor
    func testRenderCloseSuccessorStatesToPNG() throws {
        guard let renderDir = ProcessInfo.processInfo.environment["BOB_MAC_CAPTURE_RENDER_DIR"],
              !renderDir.isEmpty
        else {
            throw XCTSkip("Set BOB_MAC_CAPTURE_RENDER_DIR to render the close card review images.")
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fixtures = [
            "pomodoro-close-successors.json",
            "pomodoro-close-carried.json",
        ]
        for fixture in fixtures {
            let success = try closeFixture(fixture)
            XCTAssertNotNil(
                CapturePomodoroClosePresentation(capture: success),
                "\(fixture) should carry a pomodoro_close preview"
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
                    let style = appearance == .darkAqua ? "dark" : "light"
                    let url = directory.appendingPathComponent(
                        "close-\(name)-\(Int(width))-\(style).png"
                    )
                    try Self.pngData(for: image).write(to: url)
                }
            }
        }
    }

    private func closeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            XCTFail("expected a successful Bob response in \(name)")
            throw NSError(domain: "PomodoroCloseDesignTests", code: 1)
        }
        return success
    }

    private static func pngData(for image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "PomodoroCloseDesignTests", code: 2)
        }
        return data
    }
}
