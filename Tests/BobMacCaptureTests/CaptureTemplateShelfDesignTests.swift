import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Height-policy math and rendered-image review for the Control-T shelf:
/// a three-row picker with one selected armed row, light and dark, through
/// `RenderFixtureWriter`.
@MainActor
final class CaptureTemplateShelfDesignTests: XCTestCase {
    func testShelfHeightPolicyMath() {
        XCTAssertEqual(CapturePanelLayout.templateShelfRowContentMinimumHeight, 72)
        XCTAssertEqual(CapturePanelLayout.templateShelfRowHeight, 84)
        XCTAssertEqual(CapturePanelLayout.templateShelfViewportHeight, 440)
        XCTAssertEqual(CapturePanelLayout.templateShelfHintKeyHeight, 22)
        XCTAssertEqual(CapturePanelLayout.templateShelfSlotDotSize, 7)

        let three = SavedTemplateShelfPickerHeightPolicy(entryCount: 3, displayScale: 1)
        XCTAssertEqual(three.visibleRowCount, 3)
        XCTAssertEqual(three.rowViewportHeight, 268)
        XCTAssertEqual(three.actionChromeHeight, 48)
        XCTAssertEqual(three.idealHeight, 316)
        XCTAssertEqual(three.minimumVisibleHeight, 48)

        let six = SavedTemplateShelfPickerHeightPolicy(entryCount: 6, displayScale: 1)
        XCTAssertEqual(six.visibleRowCount, CapturePanelLayout.stashVisibleRows)
        XCTAssertEqual(six.rowViewportHeight, CapturePanelLayout.templateShelfViewportHeight)
        XCTAssertEqual(six.idealHeight, 488)

        let empty = SavedTemplateShelfPickerHeightPolicy(entryCount: 0, displayScale: 1)
        XCTAssertEqual(empty.visibleRowCount, 0)
        XCTAssertEqual(empty.idealHeight, empty.actionChromeHeight)
    }

    func testShelfHeightPolicyPixelRounds() {
        let integral = SavedTemplateShelfPickerHeightPolicy(entryCount: 3, displayScale: 2)
        XCTAssertEqual(integral.idealHeight, 316)

        let degenerate = SavedTemplateShelfPickerHeightPolicy(entryCount: 3, displayScale: 0)
        XCTAssertEqual(degenerate.idealHeight, integral.idealHeight)
    }

    func testRenderThreeRowShelfSelectedAndArmed() throws {
        let templates = try populatedTemplates()
        XCTAssertEqual(templates.count, 3)
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: templates, capacity: 36, saving: true)
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.presentTemplateShelf()
        model.armOrConfirmTemplateDelete()
        XCTAssertTrue(model.isTemplateShelfPresented)
        XCTAssertEqual(model.selectedTemplateIndex, 0)
        XCTAssertEqual(model.armedDeleteTemplateID, templates[0].id)

        let view = SavedTemplateShelfPicker(model: model)
        try RenderFixtureWriter.write(
            view,
            name: "capture-template-shelf-armed",
            width: 520,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            view,
            name: "capture-template-shelf-armed",
            width: 520,
            appearance: .darkAqua
        )
    }

    func testRenderSlotDotCapsAtSixPlusOverflow() throws {
        let templates = [
            CaptureSavedTemplate(index: 1, id: "one", text: "Buy {0}", fieldCount: 1, lineCount: 1),
            CaptureSavedTemplate(
                index: 2,
                id: "six",
                text: "{0} {1} {2} {3} {4} {5}",
                fieldCount: 6,
                lineCount: 1
            ),
            CaptureSavedTemplate(
                index: 3,
                id: "seven",
                text: "{0} {1} {2} {3} {4} {5} {6}",
                fieldCount: 7,
                lineCount: 1
            ),
        ]
        XCTAssertEqual(
            CaptureSavedTemplatePresentation(template: templates[0]).slotDotFields,
            [0]
        )
        XCTAssertEqual(
            CaptureSavedTemplatePresentation(template: templates[1]).slotDotFields.count,
            6
        )
        XCTAssertEqual(
            CaptureSavedTemplatePresentation(template: templates[2]).slotOverflowCount,
            1
        )

        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: templates)
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.presentTemplateShelf()
        let view = SavedTemplateShelfPicker(model: model)
        try RenderFixtureWriter.write(
            view,
            name: "capture-template-shelf-slot-dots",
            width: 520,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            view,
            name: "capture-template-shelf-slot-dots",
            width: 520,
            appearance: .darkAqua
        )
    }

    private func populatedTemplates() throws -> [CaptureSavedTemplate] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("capture-templates-list-populated.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CaptureSavedTemplatesResponse.self, from: data).templates
    }
}
