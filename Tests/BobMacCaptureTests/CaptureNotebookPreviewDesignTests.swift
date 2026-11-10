import Foundation
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureNotebookPreviewDesignTests: XCTestCase {
    private func successFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(contentsOf: fixtures.appendingPathComponent(name))
        )
        guard case .success(let success) = response else {
            throw NSError(domain: "CaptureNotebookPreviewDesignTests", code: 1)
        }
        return success
    }

    func testNotebookCreationPreviewKeepsExactMarkdownAndPairsInBatchOrder() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Notebook preview requires macOS 26.")
        }
        let success = try successFixture("notebook-capture-create-then-use.json")
        let items = success.normalizedCaptures
        let files = CaptureNotebookPresentation.pairIndexed(
            files: success.noteFiles,
            items: items
        )
        let item = try XCTUnwrap(items.first)
        let file = try XCTUnwrap(files[0])

        XCTAssertEqual(item.kind, "notebook_create")
        XCTAssertEqual(file.action, "create")
        XCTAssertTrue(file.markdown.contains("## Mappings"))
        XCTAssertFalse(file.markdown.contains("[ ]"))

        let preview = CaptureNotebookPreviewView(item: item, file: file)
            .padding(18)
        for (name, width) in [
            ("capture-notebook-create-wide", CGFloat(760)),
            (
                "capture-notebook-create-minimum",
                CGFloat(CapturePanelLayout.panelMinimumContentWidth)
            ),
        ] {
            try RenderFixtureWriter.write(preview, name: name, width: width, appearance: .aqua)
            try RenderFixtureWriter.write(preview, name: name, width: width, appearance: .darkAqua)
        }
    }

    func testNotebookNoteAndSubNoteMetadataStaysInCaptureOrder() throws {
        let success = try successFixture("notebook-capture-existing-notes.json")
        let items = success.normalizedCaptures
        XCTAssertEqual(items.map(\.kind), [
            "notebook_note",
            "notebook_note",
            "notebook_sub_note",
            "notebook_sub_note",
        ])
        XCTAssertEqual(
            CaptureNotebookPresentation.headline(for: items[2]),
            "📓 Note → Neovim › ^existing-guide"
        )
    }
}
