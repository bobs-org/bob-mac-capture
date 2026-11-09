import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Design-phase tests for the new-record preview and inline refusal:
/// pairing order, disclosure identity, accessibility copy, and the gated
/// rendered-image review at panel widths.
@MainActor
final class CaptureRecordPreviewDesignTests: XCTestCase {
    private func decodeSuccess(_ name: String) throws -> CaptureCommandSuccess {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self, from: Data(contentsOf: url))
        guard case .success(let success) = response else {
            throw NSError(domain: "CaptureRecordPreviewDesignTests", code: 1)
        }
        return success
    }

    private func decodeFailure(_ name: String) throws -> CaptureCommandFailure {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        return try JSONDecoder().decode(
            CaptureCommandFailure.self, from: Data(contentsOf: url))
    }

    func testRestaurantPreviewPairsFileWithItem() throws {
        let success = try decodeSuccess("record-capture-restaurant.json")
        let items = success.normalizedCaptures
        let map = CaptureRecordPreviewPresentation.pairIndexed(
            files: success.noteFiles, items: items)
        XCTAssertEqual(map.count, 1)
        let file = try XCTUnwrap(map[0])
        XCTAssertTrue(file.isUsable)
        XCTAssertEqual(file.markdown, success.noteFiles[0].markdown)
    }

    func testTwoRecordPreviewKeepsBothFilesReachable() throws {
        let success = try decodeSuccess("record-capture-two-records.json")
        let map = CaptureRecordPreviewPresentation.pairIndexed(
            files: success.noteFiles, items: success.normalizedCaptures)
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map[0]?.path, "eat/ramen_nagi.md")
        XCTAssertEqual(map[1]?.path, "podcasts/talk_python.md")
    }

    func testRefusalCardExposesDraftWithoutApplying() throws {
        let failure = try decodeFailure("record-capture-missing.json")
        let presentation = try XCTUnwrap(
            CaptureRecordRefusalPresentation(failure: failure))
        XCTAssertEqual(presentation.missing, ["category", "location"])
        let draft = try XCTUnwrap(presentation.draft)
        XCTAssertTrue(draft.contains("category::"))
    }

    func testRecordPreviewRendersAtPanelWidths() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Record note preview requires macOS 26.")
        }
        let success = try decodeSuccess("record-capture-restaurant.json")
        let item = try XCTUnwrap(success.normalizedCaptures.first)
        let file = try XCTUnwrap(success.noteFiles.first)
        let collapsed = RecordNotePreviewView(item: item, file: file)
            .padding(18)
        let expanded = RecordNotePreviewView(item: item, file: file, expanded: true)
            .padding(18)

        for (name, width) in [
            ("capture-record-note-wide", CGFloat(760)),
            (
                "capture-record-note-minimum",
                CGFloat(CapturePanelLayout.panelMinimumContentWidth)
            ),
        ] {
            for (view, stem) in [
                (AnyView(collapsed), "\(name)-collapsed"),
                (AnyView(expanded), "\(name)-expanded"),
            ] {
                try RenderFixtureWriter.write(
                    view, name: stem, width: width, appearance: .aqua)
                try RenderFixtureWriter.write(
                    view, name: stem, width: width, appearance: .darkAqua)
            }
        }
    }

    func testRecordPreviewRendersMultipleFilesAndRefusal() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Record note preview requires macOS 26.")
        }
        let two = try decodeSuccess("record-capture-two-records.json")
        let map = CaptureRecordPreviewPresentation.pairIndexed(
            files: two.noteFiles, items: two.normalizedCaptures)
        let both = VStack(alignment: .leading, spacing: 10) {
            ForEach([0, 1], id: \.self) { index in
                if let file = map[index] {
                    RecordNotePreviewView(item: two.normalizedCaptures[index], file: file)
                }
            }
        }
        .padding(18)
        try RenderFixtureWriter.write(
            both, name: "capture-record-note-multiple", width: 760, appearance: .aqua)
        try RenderFixtureWriter.write(
            both, name: "capture-record-note-multiple", width: 760, appearance: .darkAqua)

        let failure = try decodeFailure("record-capture-missing.json")
        let refusal = try XCTUnwrap(CaptureRecordRefusalPresentation(failure: failure))
        let card = RecordRefusalCardView(presentation: refusal)
            .padding(18)
        try RenderFixtureWriter.write(
            card, name: "capture-record-refusal", width: 760, appearance: .aqua)
        try RenderFixtureWriter.write(
            card, name: "capture-record-refusal", width: 760, appearance: .darkAqua)
        try RenderFixtureWriter.write(
            card,
            name: "capture-record-refusal-minimum",
            width: CGFloat(CapturePanelLayout.panelMinimumContentWidth),
            appearance: .aqua)
    }
}
