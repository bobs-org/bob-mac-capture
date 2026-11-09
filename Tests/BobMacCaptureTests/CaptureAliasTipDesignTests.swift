import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for the completion-list typing tip at full and
/// minimum panel widths, in both appearances.
@available(macOS 26.0, *)
@MainActor
final class CaptureAliasTipDesignTests: XCTestCase {
    func testRenderRouteListWithTip() throws {
        let model = CapturePanelModel()
        model.plainDraft = "Buy milk @"
        model.completionResponse = try decodeCompletion("dot-route-complete.json")
        model.selectedCompletionIndex = 0
        model.installPresentedAliasTipForPreviews(
            CaptureSigilAliasTip(
                id: CaptureAliasLesson.routeAfterText,
                sigil: "@",
                keys: ["."],
                range: CaptureRange(start: 9, end: 10),
                positionPhrase: "after a word"
            )
        )
        let height =
            CapturePanelLayout.completionViewportHeight
            + CapturePanelLayout.aliasTipHostHeight
        for width in [760, 620] as [CGFloat] {
            let view = CompletionList(model: model)
                .frame(width: 430)
                .frame(maxHeight: height, alignment: .top)
            try RenderFixtureWriter.write(
                view,
                name: "alias-tip-route-\(Int(width))",
                width: width,
                appearance: .aqua
            )
            try RenderFixtureWriter.write(
                view,
                name: "alias-tip-route-\(Int(width))",
                width: width,
                appearance: .darkAqua
            )
        }
    }

    private func decodeCompletion(_ name: String) throws -> CaptureCompletionResponse {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        return try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)
    }
}
