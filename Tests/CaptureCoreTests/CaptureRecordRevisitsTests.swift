import Foundation
import XCTest

@testable import CaptureCore

/// Phase 12 revisits: update cards show `before → after`, `record_target`
/// rows show status plus field values, and the Similar band accepts
/// `scope: "record"` rows with the "Add to it" action. All wire shapes are
/// additive and decode tolerantly so an older Bob keeps its presentation.
final class CaptureRecordRevisitsTests: XCTestCase {
    func testUpdateFieldDecodesBeforeAndRowShowsChange() throws {
        let field = try JSONDecoder().decode(
            CaptureRecordField.self,
            from: Data(
                """
                {"key":"status","label":"Status","kind":"choices",\
                "required":true,"list":false,"state":"set",\
                "value":"not_liked","display":"Not liked",\
                "before":"liked","before_display":"Liked"}
                """.utf8
            )
        )
        XCTAssertEqual(field.resolvedBeforeDisplay, "Liked")
        let row = CaptureRecordRow(field: field)
        XCTAssertTrue(row.isChanged)
        XCTAssertEqual(row.changeText, "Liked → Not liked")
        XCTAssertEqual(row.accessibilityLabel, "Status, Liked to Not liked")
    }

    func testUnchangedUpdateRowKeepsSingleValue() throws {
        let field = try JSONDecoder().decode(
            CaptureRecordField.self,
            from: Data(
                """
                {"key":"location","label":"Location","kind":"text",\
                "required":true,"list":false,"state":"set",\
                "value":"Clark","display":"Clark",\
                "before":"Clark","before_display":"Clark"}
                """.utf8
            )
        )
        let row = CaptureRecordRow(field: field)
        XCTAssertFalse(row.isChanged)
        XCTAssertEqual(row.changeText, "Clark")
    }

    func testUpdatePresentationNotesLabel() {
        let record = CaptureRecord(
            action: "update",
            recordType: "restaurant",
            label: "Restaurant",
            dir: "eat",
            path: "eat/ninja_sushi.md",
            title: "Ninja Sushi",
            notes: 1
        )
        let presentation = CaptureRecordPresentation(record: record)
        XCTAssertTrue(presentation.isUpdate)
        XCTAssertEqual(presentation.notesLabel, "+1 note")
        XCTAssertEqual(presentation.headerTitle, "Restaurant")
    }

    func testRecordRelatedDecodesScopeStatusFieldsAndAddTo() throws {
        let data = Data(
            """
            {"ok":true,"schema_version":1,"items":[{"index":0,\
            "mode":"record_note","matches":[{"key":"eat/ninja_sushi_bar.md",\
            "band":"possible_duplicate","title":"Ninja Sushi Bar",\
            "kind":"record","route":"eat","locator":"eat",\
            "note_path":"eat/ninja_sushi_bar.md","actions":["add_to","open","discard"],\
            "default_action":"add_to","scope":"record","record_type":"restaurant",\
            "stem":"ninja_sushi_bar","status":"Liked",\
            "fields":[{"key":"category","label":"Category","value":"Sushi"}],\
            "add_to":{"start":0,"end":17,"replacement":"@eat/ninja_sushi_bar"}}]}]}
            """.utf8
        )
        let response = try JSONDecoder().decode(
            CaptureRelatedResponse.self, from: data)
        let match = try XCTUnwrap(response.items.first?.matches.first)
        XCTAssertTrue(match.isRecord)
        XCTAssertEqual(match.recordStatus, "Liked")
        XCTAssertEqual(match.recordFields.map(\.value), ["Sushi"])
        XCTAssertEqual(match.recordDetail, "Liked · Sushi")
        XCTAssertNotNil(match.addTo)
        XCTAssertEqual(match.actions, [.addTo, .open, .discard])
        XCTAssertEqual(match.defaultAction, .addTo)
    }

    func testPolicyKeepsRecordNoteMode() {
        let response = CaptureRelatedResponse(items: [
            CaptureRelatedItem(
                index: 0, mode: "record_note",
                matches: [
                    CaptureRelatedMatch(
                        key: "eat/ninja_sushi_bar.md",
                        band: .possibleDuplicate,
                        title: "Ninja Sushi Bar",
                        actions: [.addTo, .open, .discard],
                        scope: "record"
                    ),
                ]
            ),
        ])
        let state = SimilarTasksBandPolicy.reduce(response, draft: "Ninja Sushi @eat/")
        XCTAssertEqual(state.rows.map(\.match.key), ["eat/ninja_sushi_bar.md"])
    }

    func testAddToSplicesBobsExplicitRange() throws {
        let draft = "Ninja Sushi @eat/"
        let item = CaptureRelatedItem(
            index: 0, mode: "record_note",
            range: CaptureRange(start: 0, end: draft.utf8.count),
            markerAt: draft.utf8.count,
            discardRange: CaptureRange(start: 0, end: draft.utf8.count)
        )
        let match = CaptureRelatedMatch(
            key: "eat/ninja_sushi_bar.md",
            band: .possibleDuplicate,
            title: "Ninja Sushi",
            actions: [.addTo, .open, .discard],
            defaultAction: .addTo,
            scope: "record",
            addTo: CaptureRecordAddTo(
                start: 0, end: 17, replacement: "@eat/ninja_sushi_bar")
        )
        XCTAssertEqual(SimilarTasksBandEdits.label(for: .addTo), "Add to it")
        XCTAssertEqual(SimilarTasksBandEdits.sigil(for: .addTo), "+")
        let edited = try XCTUnwrap(
            SimilarTasksBandEdits.editedDraft(
                draft, item: item, match: match, action: .addTo))
        XCTAssertEqual(edited.text, "@eat/ninja_sushi_bar")
        XCTAssertEqual(
            SimilarTasksBandEdits.announcement(for: .addTo, title: "Ninja Sushi Bar"),
            "Added to Ninja Sushi Bar")
    }

    func testRecordPresentationCopy() {
        let row = SimilarTasksBandRow(
            itemIndex: 0, rowNumber: 1,
            match: CaptureRelatedMatch(
                key: "eat/ninja_sushi_bar.md",
                band: .possibleDuplicate,
                title: "Ninja Sushi Bar",
                kind: "record",
                route: "eat", locator: "eat",
                actions: [.addTo, .open, .discard],
                scope: "record",
                recordStatus: "Liked",
                recordFields: [
                    CaptureRecordRelatedField(
                        key: "category", label: "Category", value: "Sushi"),
                ]
            )
        )
        XCTAssertEqual(
            SimilarTasksBandPresentation.locatorText(for: row), "eat · Liked · Sushi")
        XCTAssertEqual(
            SimilarTasksBandPresentation.rowAccessibilityLabel(row),
            "Ninja Sushi Bar, Possible duplicate, eat, Liked · Sushi, Record")
        let item = SimilarTasksBandItem(index: 0, mode: "record_note", rows: [row])
        XCTAssertTrue(SimilarTasksBandPresentation.isRecordItem(item))
        XCTAssertEqual(
            SimilarTasksBandPresentation.headerText(for: item), "SIMILAR RECORDS")
        XCTAssertEqual(
            SimilarTasksBandPresentation.settledAnnouncement(items: [item]),
            "Similar record: Ninja Sushi Bar")
    }

    func testRecordTargetFieldsDecodeAndRenderStatusPlusFields() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data(
                """
                {"replacement":"@eat/ninja_sushi","route":"@eat/ninja_sushi",\
                "stem":"ninja_sushi","title":"Ninja Sushi","status":"Liked",\
                "fields":[{"key":"category","label":"Category","value":"Sushi"},\
                {"key":"location","label":"Location","value":"Clark"}],\
                "cursor_after":22}
                """.utf8
            )
        )
        XCTAssertEqual(candidate.recordFields.map(\.value), ["Sushi", "Clark"])
        let content = completionRowContent(
            for: candidate, context: "record_target", query: "")
        XCTAssertEqual(content.primaryText, "Ninja Sushi")
        XCTAssertEqual(content.secondaryText, "Liked · Sushi · Clark")
    }

    func testRecordTargetWithoutFieldsKeepsStatusOnly() {
        let candidate = CaptureCompletionCandidate(
            replacement: "@eat/nagi", route: "@eat/nagi",
            status: "Liked", title: "Nagi")
        let content = completionRowContent(
            for: candidate, context: "record_target", query: "")
        XCTAssertEqual(content.secondaryText, "Liked")
    }
}
