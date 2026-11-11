import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Design-phase tests for the Record Card: fixed-height sizing, accessibility
/// identities, and the gated rendered-image review at panel widths.
@MainActor
final class CaptureRecordCardDesignTests: XCTestCase {
    func testRecordCardHeightPolicyUsesVisibleRowsAndMoreControl() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: parse, cursor: parse.input.utf8.count)
        )
        XCTAssertEqual(presentation.displayedRows.count, 4)
        XCTAssertFalse(presentation.hiddenOptionalRows.isEmpty)

        let policy = RecordCardHeightPolicy(presentation: presentation, displayScale: 1)
        XCTAssertTrue(policy.showsMoreControl)
        XCTAssertEqual(policy.clampedRows, 4)
        XCTAssertEqual(policy.listViewportHeight, 128)
        XCTAssertEqual(policy.idealHeight, 246)
        XCTAssertEqual(policy.minimumVisibleHeight, 214)
        XCTAssertEqual(policy.auxiliaryHeight.idealHeight, 246)
        XCTAssertEqual(policy.auxiliaryHeight.minimumVisibleHeight, 214)
    }

    func testRecordCardHeightPolicyClampsToEightRowsAndKeepsAReadableFloor() {
        let many = RecordCardHeightPolicy(rowCount: 20, showsMoreControl: true, displayScale: 1)
        XCTAssertEqual(many.clampedRows, CapturePanelLayout.recordCardMaxRows)
        XCTAssertEqual(many.listViewportHeight, 256)
        XCTAssertEqual(many.idealHeight, 374)
        XCTAssertEqual(many.minimumRowCount, CapturePanelLayout.recordCardMinRows)
        XCTAssertEqual(many.minimumVisibleHeight, 214)
        XCTAssertLessThan(many.minimumVisibleHeight, many.idealHeight)

        let empty = RecordCardHeightPolicy(rowCount: 0, showsMoreControl: false, displayScale: 1)
        XCTAssertEqual(empty.clampedRows, 1)
        XCTAssertEqual(empty.minimumRowCount, 1)
        XCTAssertEqual(empty.idealHeight, empty.minimumVisibleHeight)
    }

    func testRecordCardHeightPolicyPixelRounds() {
        let integral = RecordCardHeightPolicy(
            rowCount: 4,
            showsMoreControl: true,
            displayScale: 2
        )
        XCTAssertEqual(integral.listViewportHeight, 128)
        XCTAssertEqual(integral.idealHeight, 246)

        let degenerate = RecordCardHeightPolicy(
            rowCount: 4,
            showsMoreControl: true,
            displayScale: 0
        )
        XCTAssertEqual(degenerate.idealHeight, integral.idealHeight)
    }

    func testRecordCardLayoutConstants() {
        XCTAssertEqual(CapturePanelLayout.recordCardHeaderHeight, 36)
        XCTAssertEqual(CapturePanelLayout.recordCardRowHeight, 32)
        XCTAssertEqual(CapturePanelLayout.recordCardMoreHeight, 26)
        XCTAssertEqual(CapturePanelLayout.recordCardFooterHeight, 34)
        XCTAssertEqual(CapturePanelLayout.recordCardPadding, 10)
        XCTAssertEqual(CapturePanelLayout.recordCardMaxRows, 8)
        XCTAssertEqual(CapturePanelLayout.recordCardMinRows, 3)
        XCTAssertEqual(CapturePanelLayout.recordCardChangesHeaderHeight, 16)
        XCTAssertEqual(CapturePanelLayout.recordCardChangeRowHeight, 18)
        XCTAssertEqual(CapturePanelLayout.recordCardChangesMoreHeight, 16)
        XCTAssertEqual(CapturePanelLayout.recordCardChangesMaxRows, 3)
        XCTAssertEqual(CapturePanelLayout.panelMinimumContentWidth, 620)
        XCTAssertEqual(CapturePanelLayout.panelInitialContentWidth, 760)
    }

    func testRecordCardHeightPolicyAddsChangeLinesWithoutChangingTheZeroCase() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: parse, cursor: parse.input.utf8.count)
        )
        let unchanged = RecordCardHeightPolicy(presentation: presentation, displayScale: 1)
        XCTAssertEqual(unchanged.changeLineCount, 0)
        XCTAssertEqual(unchanged.changesHeight, 0)
        XCTAssertEqual(unchanged.idealHeight, 246)

        let three = RecordCardHeightPolicy(
            presentation: presentation,
            displayScale: 1,
            changeLineCount: 3
        )
        XCTAssertEqual(three.visibleChangeRows, 3)
        XCTAssertFalse(three.showsChangesMore)
        XCTAssertEqual(three.changesHeight, 70)
        XCTAssertEqual(three.idealHeight, unchanged.idealHeight + 70)

        let five = RecordCardHeightPolicy(
            presentation: presentation,
            displayScale: 1,
            changeLineCount: 5
        )
        XCTAssertEqual(five.visibleChangeRows, 3)
        XCTAssertTrue(five.showsChangesMore)
        XCTAssertEqual(five.changesHeight, 86)
        XCTAssertEqual(five.idealHeight, unchanged.idealHeight + 86)
    }

    func testRecordCardAccessibilityIdentitiesMatchPersistentState() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: parse, cursor: parse.input.utf8.count)
        )
        XCTAssertEqual(presentation.headerTitle, "New restaurant")
        XCTAssertEqual(presentation.headerPath, "eat/ramen_nagi.md")
        XCTAssertEqual(presentation.notesLabel, "0 notes")
        XCTAssertEqual(presentation.moreLabel, "More (visited, url)")
        XCTAssertEqual(
            presentation.footerHint,
            "⇥ next field · ⏎ Needs Status · Esc back to draft"
        )
        let status = try XCTUnwrap(presentation.rows.first { $0.key == "status" })
        XCTAssertEqual(status.accessibilityLabel, "Status, required, missing")
        XCTAssertEqual(status.stateSymbolName, "circle.inset.filled")
        let companions = try XCTUnwrap(presentation.rows.first { $0.key == "companions" })
        XCTAssertEqual(companions.accessibilityLabel, "Companions, kelly, optional, default")
        XCTAssertEqual(companions.stateSymbolName, "checkmark.circle")
        let url = try XCTUnwrap(presentation.rows.first { $0.key == "url" })
        XCTAssertEqual(url.accessibilityLabel, "Url, optional, none")
        XCTAssertEqual(url.stateSymbolName, "circle.dashed")
    }

    func testRenderRecordCardAtSupportedWidthsAppearancesAndContrast() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Record Card rendering requires macOS 26.")
        }
        let incomplete = try decodeParse("record-parse-incomplete.json")
        let completion = try decodeComplete("record-complete-next-missing-first.json")
        let incompletePresentation = try XCTUnwrap(
            CaptureRecordPresentation.make(
                parse: incomplete,
                cursor: incomplete.input.utf8.count
            )
        )
        let incompleteModel = CapturePanelModel()
        incompleteModel.installRecordCardForPreviews(
            presentation: incompletePresentation,
            parse: incomplete,
            completion: completion
        )
        let incompleteCard = RecordCardView(
            model: incompleteModel,
            presentation: incompletePresentation,
            previewMode: true
        )
        .padding(18)

        for (name, width) in [
            ("capture-record-card-wide", CGFloat(760)),
            (
                "capture-record-card-minimum",
                CGFloat(CapturePanelLayout.panelMinimumContentWidth)
            ),
        ] {
            try RenderFixtureWriter.write(
                incompleteCard,
                name: name,
                width: width,
                appearance: .aqua
            )
            try RenderFixtureWriter.write(
                incompleteCard,
                name: name,
                width: width,
                appearance: .darkAqua
            )
        }

        let contrastCard = incompleteCard.environment(\._colorSchemeContrast, .increased)
        try RenderFixtureWriter.write(
            contrastCard,
            name: "capture-record-card-contrast",
            width: 760,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            contrastCard,
            name: "capture-record-card-contrast",
            width: 760,
            appearance: .darkAqua
        )

        let complete = try decodeParse("record-parse-complete.json")
        let completePresentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: complete, cursor: complete.input.utf8.count)
        )
        let completeModel = CapturePanelModel()
        completeModel.installRecordCardForPreviews(
            presentation: completePresentation,
            parse: complete
        )
        let completeCard = RecordCardView(
            model: completeModel,
            presentation: completePresentation,
            previewMode: true
        )
        .padding(18)
        try RenderFixtureWriter.write(
            completeCard,
            name: "capture-record-card-complete",
            width: 760,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            completeCard,
            name: "capture-record-card-complete",
            width: 760,
            appearance: .darkAqua
        )

        let morePresentation = CaptureRecordPresentation(
            record: incompletePresentation.record,
            itemIndex: incompletePresentation.itemIndex,
            rows: incompletePresentation.rows,
            activeFieldKey: incompletePresentation.activeFieldKey,
            selectedRowKey: incompletePresentation.selectedRowKey,
            showsMore: true
        )
        let moreModel = CapturePanelModel()
        moreModel.installRecordCardForPreviews(
            presentation: morePresentation,
            parse: incomplete
        )
        let moreCard = RecordCardView(
            model: moreModel,
            presentation: morePresentation,
            previewMode: true
        )
        .padding(18)
        try RenderFixtureWriter.write(
            moreCard,
            name: "capture-record-card-more",
            width: CapturePanelLayout.panelMinimumContentWidth,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            moreCard,
            name: "capture-record-card-more",
            width: CapturePanelLayout.panelMinimumContentWidth,
            appearance: .darkAqua
        )

        let productionCard = RecordCardView(
            model: moreModel,
            presentation: morePresentation,
            previewMode: false
        )
        .padding(18)
        try RenderFixtureWriter.write(
            productionCard,
            name: "capture-record-card-more-production",
            width: CapturePanelLayout.panelMinimumContentWidth,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            productionCard,
            name: "capture-record-card-more-production",
            width: CapturePanelLayout.panelMinimumContentWidth,
            appearance: .darkAqua
        )
    }

    func testRecordCardHeightPolicyUsesFieldCandidateCount() throws {
        let fields = try decodeComplete("record-complete-field.json")
        XCTAssertEqual(fields.candidates.count, 6)
        let policy = RecordCardHeightPolicy(
            rowCount: fields.candidates.count,
            showsMoreControl: false,
            displayScale: 1
        )
        XCTAssertFalse(policy.showsMoreControl)
        XCTAssertEqual(policy.clampedRows, 6)
        XCTAssertEqual(policy.listViewportHeight, 192)
    }

    func testRenderRecordCardSelectedOverflowFieldListReadyFooterAndOverlay() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Record Card rendering requires macOS 26.")
        }
        let incomplete = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(
                parse: incomplete,
                cursor: incomplete.input.utf8.count
            )
        )

        let many = try decodeComplete("record-complete-category-many.json")
        let manyModel = CapturePanelModel()
        manyModel.installRecordCardForPreviews(
            presentation: presentation,
            parse: incomplete,
            completion: many,
            statusText: "Ready"
        )
        manyModel.selectedCompletionIndex = 6
        let manyCard = RecordCardView(
            model: manyModel,
            presentation: presentation,
            previewMode: true
        )
        .padding(18)
        try RenderFixtureWriter.write(
            manyCard,
            name: "capture-record-card-values-overflow",
            width: 760,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            manyCard,
            name: "capture-record-card-values-overflow",
            width: 760,
            appearance: .darkAqua
        )

        let fields = try decodeComplete("record-complete-field.json")
        let fieldModel = CapturePanelModel()
        fieldModel.installRecordCardForPreviews(
            presentation: presentation,
            parse: incomplete,
            completion: fields
        )
        let fieldCard = RecordCardView(
            model: fieldModel,
            presentation: presentation,
            previewMode: true
        )
        .padding(18)
        try RenderFixtureWriter.write(
            fieldCard,
            name: "capture-record-card-fields",
            width: 760,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            fieldCard,
            name: "capture-record-card-fields",
            width: 760,
            appearance: .darkAqua
        )

        let readyModel = CapturePanelModel()
        readyModel.installRecordCardForPreviews(
            presentation: presentation,
            parse: incomplete,
            statusText: "Ready"
        )
        let readyCard = RecordCardView(
            model: readyModel,
            presentation: presentation,
            previewMode: true
        )
        .padding(18)
        try RenderFixtureWriter.write(
            readyCard,
            name: "capture-record-card-ready-footer",
            width: 760,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            readyCard,
            name: "capture-record-card-ready-footer",
            width: 760,
            appearance: .darkAqua
        )

        let errorModel = CapturePanelModel()
        errorModel.installRecordCardForPreviews(
            presentation: presentation,
            parse: incomplete,
            statusText: "Needs Status",
            statusIsRefusal: true
        )
        let errorCard = RecordCardView(
            model: errorModel,
            presentation: presentation,
            previewMode: true
        )
        .padding(18)
        try RenderFixtureWriter.write(
            errorCard,
            name: "capture-record-card-error-footer",
            width: 760,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            errorCard,
            name: "capture-record-card-error-footer",
            width: 760,
            appearance: .darkAqua
        )

        let target = try decodeComplete("record-complete-target-create.json")
        let targetModel = CapturePanelModel()
        targetModel.installRecordCardForPreviews(
            presentation: presentation,
            parse: incomplete,
            completion: target
        )
        let fallback = CompletionList(model: targetModel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: CapturePanelLayout.completionViewportHeight, alignment: .top)
            .padding(18)
        try RenderFixtureWriter.write(
            fallback,
            name: "capture-record-target-fallback",
            width: 760,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            fallback,
            name: "capture-record-target-fallback",
            width: 760,
            appearance: .darkAqua
        )

        let liked = try decodeParse("record-parse-status-liked.json")
        let likedPresentation = try XCTUnwrap(
            CaptureRecordPresentation.make(
                parse: liked,
                cursor: liked.input.utf8.count
            )
        )
        let likedModel = CapturePanelModel()
        likedModel.installRecordCardForPreviews(
            presentation: likedPresentation,
            parse: liked,
            statusText: "Restored canceled draft"
        )
        let likedCard = RecordCardView(
            model: likedModel,
            presentation: likedPresentation,
            previewMode: true
        )
        .padding(18)
        try RenderFixtureWriter.write(
            likedCard,
            name: "capture-record-card-set-status",
            width: 760,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            likedCard,
            name: "capture-record-card-set-status",
            width: 760,
            appearance: .darkAqua
        )

        let two = try decodeParse("record-parse-two-records.json")
        let overlay = ZStack(alignment: .topLeading) {
            Text(two.input)
                .font(.system(.body, design: .monospaced))
                .frame(width: 760, alignment: .topLeading)
            RecordRouteEmojiOverlay(
                draft: two.input,
                adornments: CaptureRecordRouteAdornment.all(in: two),
                wrapWidth: 760,
                monoCharWidth: 8,
                lineHeight: 18
            )
        }
        .frame(width: 760, height: 48, alignment: .topLeading)
        .padding(18)
        try RenderFixtureWriter.write(
            overlay,
            name: "capture-record-route-emoji",
            width: 760,
            appearance: .aqua
        )
        try RenderFixtureWriter.write(
            overlay,
            name: "capture-record-route-emoji",
            width: 760,
            appearance: .darkAqua
        )
    }

    private func decodeParse(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(contentsOf: fixtureURL(name))
        )
    }

    private func decodeComplete(_ name: String) throws -> CaptureCompletionResponse {
        try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtureURL(name))
        )
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }
}
