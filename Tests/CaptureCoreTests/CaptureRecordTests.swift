import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRecordTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func decodeParse(_ name: String) throws -> CaptureParseResponse {
        let data = try Data(contentsOf: fixtureURL(name))
        return try JSONDecoder().decode(CaptureParseResponse.self, from: data)
    }

    private func decodeComplete(_ name: String) throws -> CaptureCompletionResponse {
        let data = try Data(contentsOf: fixtureURL(name))
        return try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)
    }

    private func decodeTargets(_ name: String) throws -> CaptureTargetsResponse {
        let data = try Data(contentsOf: fixtureURL(name))
        return try JSONDecoder().decode(CaptureTargetsResponse.self, from: data)
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let root =
            source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/fake-bob").path
    }

    func testParseIncompleteDecodesRecord() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        XCTAssertEqual(parse.mode, "record_note")
        XCTAssertEqual(parse.needs, ["record_value"])
        let record = try XCTUnwrap(parse.record)
        XCTAssertEqual(record.recordType, "restaurant")
        XCTAssertEqual(record.label, "Restaurant")
        XCTAssertEqual(record.dir, "eat")
        XCTAssertEqual(record.missing, ["status", "category", "location"])
        XCTAssertEqual(record.assistVersion, 1)
        XCTAssertEqual(record.fields.map(\.key).prefix(3), ["status", "category", "location"])
        XCTAssertEqual(record.fields[0].state, "missing")
        let companions = try XCTUnwrap(record.fields.first(where: { $0.key == "companions" }))
        XCTAssertEqual(companions.state, "default")
        XCTAssertEqual(companions.source, "default")
    }

    func testParseCompleteHasNoMissing() throws {
        let parse = try decodeParse("record-parse-complete.json")
        let record = try XCTUnwrap(parse.record)
        XCTAssertEqual(record.missing, [])
        XCTAssertTrue(record.fields.contains(where: { $0.state == "set" }))
    }

    func testParseRecordCarriesAlbumIdentity() throws {
        let parse = try decodeParse("record-parse-complete.json")
        let album = try XCTUnwrap(parse.record?.album)
        XCTAssertEqual(album.stem, "eat")
        XCTAssertEqual(album.title, "Restaurants")
        XCTAssertEqual(album.owner, "body")
        XCTAssertEqual(album.breadcrumb, ["body", "Restaurants"])
        XCTAssertEqual(album.ownerTrail, ["body"])
    }

    func testBareAlbumRefusalCarriesOneKeyRewrite() throws {
        let parse = try decodeParse("record-parse-bare-album.json")
        XCTAssertNil(parse.record, "a bare album route plans no record")
        let diagnostic = try XCTUnwrap(
            parse.diagnostics.first(where: { $0.code == "album_holds_no_tasks" }))
        XCTAssertEqual(diagnostic.severity, "error")
        XCTAssertTrue(diagnostic.message.contains("@eat/"), diagnostic.message)
        let rewrite = try XCTUnwrap(
            CaptureBareAlbumRefusal.rewrite(in: parse))
        XCTAssertEqual(rewrite.replacement, "@eat/")
        XCTAssertEqual(rewrite.start, 6)
        XCTAssertEqual(rewrite.end, 10)
        XCTAssertFalse(rewrite.label.isEmpty)
    }

    func testBareAlbumRefusalIgnoresOtherDiagnostics() throws {
        let parse = try decodeParse("record-parse-invalid.json")
        XCTAssertNil(CaptureBareAlbumRefusal.rewrite(in: parse))
        XCTAssertNil(CaptureBareAlbumRefusal.rewrite(in: nil))
    }

    func testParseInvalidMarksField() throws {
        let parse = try decodeParse("record-parse-invalid.json")
        let record = try XCTUnwrap(parse.record)
        let status = try XCTUnwrap(record.fields.first(where: { $0.key == "status" }))
        XCTAssertEqual(status.state, "invalid")
        XCTAssertTrue(parse.diagnostics.contains(where: { $0.code == "record_invalid_value" }))
    }

    func testParseOptionalEmptyIsNone() throws {
        let parse = try decodeParse("record-parse-optional-empty.json")
        let record = try XCTUnwrap(parse.record)
        let companions = try XCTUnwrap(record.fields.first(where: { $0.key == "companions" }))
        XCTAssertEqual(companions.state, "none")
        XCTAssertNil(companions.value)
    }

    func testParseExplicitStem() throws {
        let parse = try decodeParse("record-parse-explicit-stem.json")
        let record = try XCTUnwrap(parse.record)
        XCTAssertEqual(record.stem, "custom-stem")
        XCTAssertEqual(record.stemSource, "explicit")
    }

    func testParseUnicodePreservesOffsets() throws {
        let parse = try decodeParse("record-parse-unicode.json")
        let record = try XCTUnwrap(parse.record)
        XCTAssertEqual(record.title, "Café Møø")
        XCTAssertTrue(parse.spans.contains(where: { $0.kind == "record_route" }))
    }

    func testParseMixedItems() throws {
        let parse = try decodeParse("record-parse-mixed.json")
        XCTAssertGreaterThanOrEqual(parse.items.count, 2)
        XCTAssertTrue(parse.items.contains(where: { $0.record != nil }))
    }

    func testMixedIncompleteFixtureKeepsEachRecordScopedToItsItem() throws {
        let parse = try decodeParse("record-parse-mixed-incomplete.json")
        XCTAssertEqual(parse.input.utf8.count, 89)
        XCTAssertEqual(parse.items.count, 2)
        XCTAssertEqual(parse.items[0].record?.missing, [])
        XCTAssertEqual(parse.items[1].range.start, 73)
        XCTAssertEqual(parse.items[1].record?.missing, ["status", "category", "location"])
    }

    func testParseOldBobDecodesWithoutRecord() throws {
        let parse = try decodeParse("record-parse-old-bob.json")
        XCTAssertNil(parse.record)
        XCTAssertEqual(parse.schemaVersion, 1)
    }

    func testGeneratedRecordParseFixturesHaveDisjointSpans() throws {
        let fixtures = fixtureURL(".").deletingLastPathComponent()
        let names = try FileManager.default.contentsOfDirectory(
            at: fixtures,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .filter { $0.hasPrefix("record-parse-") && $0.hasSuffix(".json") }
        .sorted()
        var checked = 0
        for name in names {
            if name.contains("old-bob") {
                continue
            }
            if name == "record-parse-mixed-incomplete.json" {
                continue
            }
            let parse = try decodeParse(name)
            XCTAssertNotNil(
                validatedSpanRanges(in: parse.input, spans: parse.spans),
                "\(name) spans must be sorted and disjoint"
            )
            checked += 1
        }
        XCTAssertGreaterThan(checked, 10, "expected generated record-parse fixtures")
    }

    func testRecordValuePreservesScalars() throws {
        let data = Data(
            """
            {
              "key": "vis",
              "label": "Visited",
              "kind": "date",
              "required": false,
              "list": false,
              "state": "set",
              "value": "2026-10-30",
              "display": "2026-10-30",
              "source": "typed",
              "range": {"start": 10, "end": 20}
            }
            """.utf8
        )
        let field = try JSONDecoder().decode(CaptureRecordField.self, from: data)
        XCTAssertEqual(field.value, .string("2026-10-30"))

        let numberField = try JSONDecoder().decode(
            CaptureRecordField.self,
            from: Data(
                """
                {"key":"y","label":"Y","kind":"number","required":false,
                 "list":false,"state":"set","value":0}
                """.utf8
            )
        )
        XCTAssertEqual(numberField.value, .number(0))

        let falseField = try JSONDecoder().decode(
            CaptureRecordField.self,
            from: Data(
                """
                {"key":"f","label":"F","kind":"text","required":false,
                 "list":false,"state":"set","value":false}
                """.utf8
            )
        )
        XCTAssertEqual(falseField.value, .bool(false))

        let listField = try JSONDecoder().decode(
            CaptureRecordField.self,
            from: Data(
                """
                {"key":"c","label":"C","kind":"link","required":false,
                 "list":true,"state":"set","value":["[[kelly]]","[[sam]]"]}
                """.utf8
            )
        )
        XCTAssertEqual(
            listField.value,
            .list([.string("[[kelly]]"), .string("[[sam]]")])
        )

        let nullField = try JSONDecoder().decode(
            CaptureRecordField.self,
            from: Data(
                """
                {"key":"u","label":"U","kind":"url","required":false,
                 "list":false,"state":"none","value":null}
                """.utf8
            )
        )
        XCTAssertNil(nullField.value)
    }

    func testRecordUnknownStateAndKindStayNeutral() throws {
        let field = try JSONDecoder().decode(
            CaptureRecordField.self,
            from: Data(
                """
                {"key":"x","label":"X","kind":"future_kind","required":false,
                 "list":false,"state":"future_state"}
                """.utf8
            )
        )
        XCTAssertEqual(field.kind, "future_kind")
        XCTAssertEqual(field.state, "future_state")
        let row = CaptureRecordRow(field: field)
        XCTAssertEqual(row.stateLabel, "none")
        XCTAssertFalse(row.isOptionalHidden)
    }

    func testRecordMalformedOptionalMetadataDegrades() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "Ramen Nagi @eat/",
              "body": "Ramen Nagi",
              "mode": "record_note",
              "needs": [],
              "spans": [],
              "diagnostics": [],
              "record": {
                "type": 42,
                "missing": "nope",
                "fields": "nope"
              }
            }
            """.utf8
        )
        let parse = try JSONDecoder().decode(CaptureParseResponse.self, from: data)
        XCTAssertNotNil(parse.record)
        XCTAssertEqual(parse.record?.recordType, "")
        XCTAssertEqual(parse.record?.missing, [])
        XCTAssertEqual(parse.record?.fields, [])
    }

    func testCompletionNamedFieldDecodesMetaAndEdit() throws {
        let response = try decodeComplete("record-complete-named-visited.json")
        XCTAssertEqual(response.context, "record_value")
        let meta = try XCTUnwrap(response.record)
        XCTAssertEqual(meta.recordType, "restaurant")
        XCTAssertEqual(meta.field, "visited")
        XCTAssertEqual(meta.assistVersion, 1)
        let edit = try XCTUnwrap(meta.edit)
        XCTAssertEqual(edit.replacement, "\n- visited:: ")
        XCTAssertFalse(edit.continuation.nextMissingField)
        XCTAssertFalse(response.candidates.isEmpty)
        for row in response.candidates {
            XCTAssertNotNil(row.recordContinuation)
        }
    }

    func testCompletionValueCaretRows() throws {
        let response = try decodeComplete("record-complete-value-caret.json")
        XCTAssertEqual(response.context, "record_value")
        let first = try XCTUnwrap(response.candidates.first)
        XCTAssertNotNil(first.recordValue)
        XCTAssertNotNil(first.display)
        XCTAssertNotNil(first.cursorAfter)
        XCTAssertNotNil(first.recordContinuation)
    }

    func testCompletionFieldRowsCarryFlags() throws {
        let response = try decodeComplete("record-complete-field.json")
        XCTAssertEqual(response.context, "record_field")
        let status = try XCTUnwrap(response.candidates.first(where: { $0.key == "status" }))
        XCTAssertTrue(status.recordRequired)
        XCTAssertFalse(status.recordList)
        let companions = try XCTUnwrap(
            response.candidates.first(where: { $0.key == "companions" }))
        XCTAssertTrue(companions.recordList)
        XCTAssertTrue(companions.recordDefaulted)
        XCTAssertNotNil(status.recordContinuation)
    }

    func testCompletionRouteRecordRow() throws {
        let response = try decodeComplete("record-complete-route.json")
        let eat = try XCTUnwrap(response.candidates.first(where: { $0.kind == "record" }))
        XCTAssertEqual(eat.route, "eat/")
        XCTAssertEqual(eat.replacement, "eat/ ")
        XCTAssertEqual(eat.recordType, "restaurant")
        XCTAssertEqual(eat.emoji, "🍽️")
        XCTAssertEqual(eat.count, 8)
        XCTAssertEqual(eat.title, "Restaurants")
        XCTAssertEqual(eat.summary, "Restaurants we have tried or want to try.")
        XCTAssertEqual(eat.owner, "body")
        XCTAssertEqual(eat.breadcrumb, ["body", "Restaurants"])
        let continuation = try XCTUnwrap(eat.recordContinuation)
        XCTAssertTrue(continuation.nextMissingField)
    }

    func testCompletionSectionCreateRow() throws {
        let response = try decodeComplete("record-complete-section-create.json")
        let create = try XCTUnwrap(response.candidates.first(where: { $0.kind == "record_create" }))
        XCTAssertEqual(create.recordType, "restaurant")
        XCTAssertNotNil(create.recordContinuation)
    }

    func testCompletionOldBobDecodesWithoutRecord() throws {
        let response = try decodeComplete("record-complete-old-bob.json")
        XCTAssertNil(response.record)
        XCTAssertEqual(response.candidates.count, 1)
        XCTAssertNil(response.candidates.first?.recordContinuation)
    }

    func testTargetsDecodeRecordMetadata() throws {
        let targets = try decodeTargets("record-targets.json")
        let eat = try XCTUnwrap(targets.targets.first(where: { $0.kind == "record" }))
        XCTAssertEqual(eat.recordType, "restaurant")
        XCTAssertEqual(eat.emoji, "🍽️")
        XCTAssertNotNil(eat.count)
        XCTAssertEqual(eat.title, "Restaurants")
        XCTAssertEqual(eat.summary, "Restaurants we have tried or want to try.")
        XCTAssertEqual(eat.owner, "body")
        XCTAssertEqual(eat.breadcrumb, ["body", "Restaurants"])
    }

    func testTargetsOldBobDecodesWithoutRecord() throws {
        let targets = try decodeTargets("record-targets-old-bob.json")
        XCTAssertTrue(targets.targets.allSatisfy { $0.recordType == nil })
    }

    func testPresentationVisibleAndMore() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: parse, cursor: parse.input.utf8.count))
        XCTAssertEqual(presentation.firstMissingFieldKey, "status")
        XCTAssertTrue(presentation.visibleRows.contains(where: { $0.key == "status" }))
        XCTAssertTrue(presentation.hiddenOptionalRows.contains(where: { $0.key == "url" }))
        XCTAssertFalse(presentation.displayedRows.contains(where: { $0.key == "url" }))
        let more = CaptureRecordPresentation(
            record: presentation.record,
            itemIndex: presentation.itemIndex,
            rows: presentation.rows,
            activeFieldKey: presentation.activeFieldKey,
            selectedRowKey: presentation.selectedRowKey,
            showsMore: true
        )
        XCTAssertTrue(more.displayedRows.contains(where: { $0.key == "url" }))
    }

    func testPresentationFirstMiddleLastIntents() throws {
        let first = try decodeComplete("record-complete-next-missing-first.json")
        let firstValue = try XCTUnwrap(first.candidates.first?.recordValue)
        XCTAssertEqual(first.record?.field, "status")
        XCTAssertTrue(firstValue == "to_try" || firstValue == "liked")

        let middle = try decodeComplete("record-complete-next-missing-middle.json")
        XCTAssertEqual(middle.record?.field, "category")

        let last = try decodeComplete("record-complete-next-missing-last.json")
        XCTAssertEqual(last.record?.field, "location")
        XCTAssertNil(last.candidates.first?.recordContinuation)
    }

    func testPresentationTabAndReturnIntents() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: parse, cursor: parse.input.utf8.count))
        let tab = try XCTUnwrap(presentation.tabIntent)
        if case .requestField(let key, let nextMissing, _) = tab {
            XCTAssertEqual(key, "status")
            XCTAssertTrue(nextMissing)
        } else {
            XCTFail("Expected tab request")
        }
        let ret = presentation.returnIntent
        if case .requestField(let key, _, let needs) = ret {
            XCTAssertEqual(key, "status")
            XCTAssertNotNil(needs)
        } else {
            XCTFail("Expected return request")
        }
    }

    func testFocusStableAcrossRefresh() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: parse, cursor: parse.input.utf8.count))
        let state = CaptureRecordFocusState(
            draft: "Ramen Nagi @eat/",
            generation: 1,
            sequence: 1,
            clientIdentity: "bob",
            itemIndex: presentation.itemIndex,
            fieldKey: "category",
            showsMore: false,
            selectedRowKey: "category"
        )
        let refreshed = try XCTUnwrap(
            state.refreshed(
                with: presentation,
                draft: "Ramen Nagi @eat/",
                generation: 2,
                sequence: 2,
                clientIdentity: "bob"
            ))
        XCTAssertEqual(refreshed.fieldKey, "category")
        XCTAssertEqual(refreshed.selectedRowKey, "category")
    }

    func testFocusFieldRemovalClearsKey() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: parse, cursor: parse.input.utf8.count))
        let state = CaptureRecordFocusState(
            draft: "Ramen Nagi @eat/",
            generation: 1,
            sequence: 1,
            clientIdentity: "bob",
            fieldKey: "gone",
            selectedRowKey: "gone"
        )
        let refreshed = try XCTUnwrap(
            state.refreshed(
                with: presentation,
                draft: "Ramen Nagi @eat/",
                generation: 2,
                sequence: 2,
                clientIdentity: "bob"
            ))
        XCTAssertNotEqual(refreshed.fieldKey, "gone")
    }

    func testFocusDoesNotCarryAcrossItemsOfTheSameRecordType() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        let base = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: parse, cursor: parse.input.utf8.count))
        let firstItem = CaptureRecordPresentation(
            record: base.record,
            itemIndex: 0,
            rows: base.rows,
            activeFieldKey: "category",
            selectedRowKey: "category"
        )
        let secondItem = CaptureRecordPresentation(
            record: base.record,
            itemIndex: 1,
            rows: base.rows,
            activeFieldKey: "status",
            selectedRowKey: "status"
        )
        let state = CaptureRecordFocusState(
            draft: "two restaurant items",
            generation: 1,
            sequence: 1,
            clientIdentity: "bob",
            itemIndex: firstItem.itemIndex,
            fieldKey: "category",
            showsMore: true,
            selectedRowKey: "category"
        )

        let refreshed = try XCTUnwrap(
            state.refreshed(
                with: secondItem,
                draft: "two restaurant items",
                generation: 2,
                sequence: 2,
                clientIdentity: "bob"
            ))

        XCTAssertEqual(refreshed.fieldKey, "status")
        XCTAssertEqual(refreshed.selectedRowKey, "status")
        XCTAssertFalse(refreshed.showsMore)
    }

    func testFocusRejectsStaleSequence() throws {
        let parse = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: parse, cursor: parse.input.utf8.count))
        let state = CaptureRecordFocusState(
            draft: "Ramen Nagi @eat/",
            generation: 2,
            sequence: 5,
            clientIdentity: "bob"
        )
        XCTAssertNil(
            state.refreshed(
                with: presentation,
                draft: "Ramen Nagi @eat/",
                generation: 1,
                sequence: 6,
                clientIdentity: "bob"
            ))
        XCTAssertNil(
            state.refreshed(
                with: presentation,
                draft: "Ramen Nagi @eat/",
                generation: 2,
                sequence: 4,
                clientIdentity: "bob"
            ))
        XCTAssertNil(
            state.refreshed(
                with: presentation,
                draft: "Ramen Nagi @eat/",
                generation: 2,
                sequence: 6,
                clientIdentity: "other"
            ))
    }

    func testCaptureCompletePassesNextMissingArgv() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_CAPTURE_COMPLETE_FIXTURE": "record-complete-next-missing-first.json",
            ]
        )
        let draft = "Ramen Nagi @eat/"
        let response = try await client.captureComplete(
            draft,
            cursor: draft.utf8.count,
            nextMissingField: true
        )
        XCTAssertEqual(response.context, "record_value")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("--next-missing-field"))
        XCTAssertFalse(record.contains("--record-field"))
    }

    func testCaptureCompletePassesNamedFieldArgv() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_CAPTURE_COMPLETE_FIXTURE": "record-complete-named-visited.json",
            ]
        )
        let draft = "Ramen Nagi @eat/"
        let response = try await client.captureComplete(
            draft,
            cursor: draft.utf8.count,
            recordField: "visited"
        )
        XCTAssertEqual(response.record?.field, "visited")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("--record-field visited"))
    }

    func testCaptureCompleteUnsupportedRecordFieldMapsOldBob() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDERR": "error: unexpected argument '--record-field' found",
                "FAKE_BOB_EXIT": "2",
            ]
        )
        do {
            _ = try await client.captureComplete(
                "Ramen Nagi @eat/",
                cursor: 16,
                recordField: "visited"
            )
            XCTFail("Expected unsupportedOption")
        } catch BobClientError.unsupportedOption(let option) {
            XCTAssertEqual(option, "--record-field")
        } catch {
            XCTFail("Expected unsupportedOption, got \(error)")
        }
    }

    func testCaptureCompleteUnsupportedNextMissingMapsOldBob() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDERR": "error: unexpected argument '--next-missing-field' found",
                "FAKE_BOB_EXIT": "2",
            ]
        )
        do {
            _ = try await client.captureComplete(
                "Ramen Nagi @eat/",
                cursor: 16,
                nextMissingField: true
            )
            XCTFail("Expected unsupportedOption")
        } catch BobClientError.unsupportedOption(let option) {
            XCTAssertEqual(option, "--next-missing-field")
        } catch {
            XCTFail("Expected unsupportedOption, got \(error)")
        }
    }

    func testRouteCachePreservesRecordRow() throws {
        let targets = try decodeTargets("record-targets.json")
        let eat = try XCTUnwrap(targets.targets.first(where: { $0.kind == "record" }))
        XCTAssertEqual(CaptureRecordRouteCache.insertion(for: eat), "eat/ ")
        XCTAssertEqual(
            CaptureRecordRouteCache.label(for: eat),
            "🍽️ New restaurant · 9"
        )
        let continuation = try XCTUnwrap(
            CaptureRecordRouteCache.continuation(for: eat, replacementStart: 1))
        XCTAssertTrue(continuation.nextMissingField)
        XCTAssertEqual(continuation.cursor, 1 + "eat/ ".utf8.count)

        let inbox = try XCTUnwrap(targets.targets.first(where: { $0.kind == "inbox" }))
        XCTAssertEqual(CaptureRecordRouteCache.insertion(for: inbox), "mac_inbox")
        XCTAssertEqual(CaptureRecordRouteCache.label(for: inbox), inbox.label)
        XCTAssertNil(CaptureRecordRouteCache.continuation(for: inbox, replacementStart: 1))
    }

    func testRowAccessibilityLabelAndStateSymbols() throws {
        let missing = CaptureRecordRow(
            key: "status",
            label: "Status",
            kind: "choices",
            required: true,
            state: "missing"
        )
        XCTAssertEqual(missing.accessibilityLabel, "Status, required, missing")
        XCTAssertEqual(missing.stateSymbolName, "circle.inset.filled")

        let optionalMissing = CaptureRecordRow(
            key: "note",
            label: "Note",
            required: false,
            state: "missing"
        )
        XCTAssertEqual(optionalMissing.accessibilityLabel, "Note, optional, missing")
        XCTAssertEqual(optionalMissing.stateSymbolName, "circle")

        let set = CaptureRecordRow(
            key: "category",
            label: "Category",
            required: true,
            state: "set"
        )
        XCTAssertEqual(set.accessibilityLabel, "Category, required, set")
        XCTAssertEqual(set.stateSymbolName, "checkmark.circle.fill")

        let invalid = CaptureRecordRow(
            key: "status",
            label: "Status",
            required: true,
            state: "invalid"
        )
        XCTAssertEqual(invalid.accessibilityLabel, "Status, required, invalid")
        XCTAssertEqual(invalid.stateSymbolName, "exclamationmark.circle.fill")

        let defaulted = CaptureRecordRow(
            key: "companions",
            label: "Companions",
            required: false,
            state: "default",
            source: "default"
        )
        XCTAssertEqual(defaulted.accessibilityLabel, "Companions, optional, default")
        XCTAssertEqual(defaulted.stateSymbolName, "checkmark.circle")

        let none = CaptureRecordRow(
            key: "url",
            label: "Url",
            required: false,
            state: "none"
        )
        XCTAssertEqual(none.accessibilityLabel, "Url, optional, none")
        XCTAssertEqual(none.stateSymbolName, "circle.dashed")

        let unknown = CaptureRecordRow(
            key: "x",
            label: "X",
            required: false,
            state: "future_state"
        )
        XCTAssertEqual(unknown.accessibilityLabel, "X, optional, none")
        XCTAssertEqual(unknown.stateSymbolName, "circle.dashed")
    }

    func testPresentationHeaderPathNotesAndFooterComeFromBob() throws {
        let incomplete = try decodeParse("record-parse-incomplete.json")
        let presentation = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: incomplete, cursor: incomplete.input.utf8.count)
        )
        XCTAssertEqual(presentation.headerTitle, "New restaurant")
        XCTAssertEqual(presentation.headerPath, "eat/ramen_nagi.md")
        XCTAssertEqual(presentation.notesLabel, "0 notes")
        XCTAssertEqual(presentation.moreLabel, "More (visited, url)")
        XCTAssertEqual(
            presentation.footerHint,
            "⇥ next field · ⏎ Needs Status · Esc back to draft"
        )

        let complete = try decodeParse("record-parse-complete.json")
        let ready = try XCTUnwrap(
            CaptureRecordPresentation.make(parse: complete, cursor: complete.input.utf8.count)
        )
        XCTAssertEqual(ready.headerTitle, "New restaurant")
        XCTAssertEqual(ready.footerHint, "⇥ next field · ⏎ create · Esc back to draft")
        XCTAssertTrue(ready.hiddenOptionalRows.contains(where: { $0.key == "url" }))

        let untitled = CaptureRecord(
            action: "update",
            label: "Restaurant",
            path: nil,
            notes: 1,
            fields: []
        )
        let update = CaptureRecordPresentation(record: untitled)
        XCTAssertEqual(update.headerTitle, "Restaurant")
        XCTAssertNil(update.headerPath)
        XCTAssertEqual(update.notesLabel, "+1 note")
        XCTAssertEqual(update.moreLabel, "More")
        XCTAssertEqual(update.footerHint, "⇥ next field · ⏎ accept · Esc back to draft")
    }

    func testRecordMatchingUsesTheOwningItemNeverTheFirstRecordGlobally() throws {
        let parse = try decodeParse("record-parse-mixed-incomplete.json")
        let firstValue = try XCTUnwrap(
            parse.spans.first { $0.kind == "record_field_value" && $0.key == "status" }
        )
        let first = try XCTUnwrap(CaptureRecordPresentation.record(matching: firstValue, in: parse))
        XCTAssertEqual(first.missing, [])
        XCTAssertEqual(first.fields.first { $0.key == "status" }?.state, "set")
        XCTAssertEqual(
            CaptureRecordPresentation.field(matching: firstValue, in: first)?.state,
            "set"
        )

        let secondRoute = CaptureSpan(start: 84, end: 89, kind: "record_route")
        let second = try XCTUnwrap(
            CaptureRecordPresentation.record(matching: secondRoute, in: parse)
        )
        XCTAssertEqual(second.missing, ["status", "category", "location"])
        XCTAssertEqual(parse.record?.missing, [])

        let outside = CaptureSpan(start: 200, end: 210, kind: "record_field_value", key: "status")
        XCTAssertNil(CaptureRecordPresentation.record(matching: outside, in: parse))
    }

    func testFieldMatchingFallsBackToRangeWhenSpanKeyIsAbsent() throws {
        let parse = try decodeParse("record-parse-complete.json")
        let record = try XCTUnwrap(parse.record)
        let keyed = CaptureSpan(start: 28, end: 33, kind: "record_field_value", key: "status")
        XCTAssertEqual(CaptureRecordPresentation.field(matching: keyed, in: record)?.key, "status")

        let unkeyed = CaptureSpan(start: 47, end: 52, kind: "record_field_value")
        XCTAssertEqual(
            CaptureRecordPresentation.field(matching: unkeyed, in: record)?.key,
            "category"
        )
    }

    func testCompletionSurfaceAgreesWithRenderedContexts() throws {
        let value = try decodeComplete("record-complete-next-missing-first.json")
        XCTAssertEqual(
            CaptureRecordCompletionSurface.make(
                context: value.context,
                candidateCount: value.candidates.count,
                snapshotCurrent: true,
                isRecordCompletion: true
            ),
            .cardValue
        )
        let field = try decodeComplete("record-complete-field.json")
        XCTAssertEqual(
            CaptureRecordCompletionSurface.make(
                context: field.context,
                candidateCount: field.candidates.count,
                snapshotCurrent: true,
                isRecordCompletion: true
            ),
            .cardField
        )
        let target = try decodeComplete("record-complete-target-create.json")
        XCTAssertEqual(target.context, "record_target")
        XCTAssertFalse(target.candidates.isEmpty)
        XCTAssertEqual(
            CaptureRecordCompletionSurface.make(
                context: target.context,
                candidateCount: target.candidates.count,
                snapshotCurrent: true,
                isRecordCompletion: true
            ),
            .genericFallback
        )
        XCTAssertEqual(
            CaptureRecordCompletionSurface.make(
                context: target.context,
                candidateCount: target.candidates.count,
                snapshotCurrent: false,
                isRecordCompletion: true
            ),
            .none
        )
        XCTAssertTrue(
            CaptureRecordCompletionSurface.make(
                context: value.context,
                candidateCount: value.candidates.count,
                snapshotCurrent: true,
                isRecordCompletion: true
            ).listVisibleOnCard
        )
        XCTAssertTrue(
            CaptureRecordCompletionSurface.make(
                context: target.context,
                candidateCount: target.candidates.count,
                snapshotCurrent: true,
                isRecordCompletion: true
            ).showsGenericFallback
        )
    }

    func testFooterMessageTreatsReadyAsOrdinaryHint() {
        let hint = "⇥ next field · ⏎ Needs Status · Esc back to draft"
        let ready = CaptureRecordFooterMessage.copy(
            statusText: "Ready",
            statusIsRefusal: false,
            errorDiagnostic: nil,
            footerHint: hint
        )
        XCTAssertEqual(ready.text, hint)
        XCTAssertFalse(ready.isRefusal)
        XCTAssertTrue(CaptureRecordFooterMessage.isOrdinaryStatus("Target cache stale"))
        XCTAssertTrue(CaptureRecordFooterMessage.isOrdinaryStatus("Capturing\u{2026}"))
        XCTAssertTrue(CaptureRecordFooterMessage.isSupersedable("Needs Status"))

        for status in ["Restored canceled draft", "Inserted ✅ Watched", "Similar tasks changed"] {
            let informational = CaptureRecordFooterMessage.copy(
                statusText: status,
                statusIsRefusal: false,
                errorDiagnostic: nil,
                footerHint: hint
            )
            XCTAssertEqual(informational.text, hint, status)
            XCTAssertFalse(informational.isRefusal, status)
        }

        let needs = CaptureRecordFooterMessage.copy(
            statusText: "Needs Status",
            statusIsRefusal: true,
            errorDiagnostic: nil,
            footerHint: hint
        )
        XCTAssertEqual(needs.text, "Needs Status")
        XCTAssertTrue(needs.isRefusal)

        let diagnosticOverInfo = CaptureRecordFooterMessage.copy(
            statusText: "Restored canceled draft",
            statusIsRefusal: false,
            errorDiagnostic: "status is not a valid value",
            footerHint: hint
        )
        XCTAssertEqual(diagnosticOverInfo.text, "status is not a valid value")
        XCTAssertTrue(diagnosticOverInfo.isRefusal)
    }

    func testValueModePrefersDisplayOverChoiceCapsules() throws {
        let liked = try decodeParse("record-parse-status-liked.json")
        let likedStatus = try XCTUnwrap(
            liked.record?.fields.first { $0.key == "status" }.map(CaptureRecordRow.init(field:))
        )
        XCTAssertEqual(likedStatus.state, "set")
        XCTAssertEqual(likedStatus.display, "Liked")
        XCTAssertEqual(likedStatus.choices.count, 2)
        XCTAssertEqual(
            likedStatus.valueMode(hasCandidates: false, hasDiagnostic: false),
            .display
        )
        XCTAssertEqual(
            likedStatus.valueMode(hasCandidates: true, hasDiagnostic: false),
            .candidates
        )

        let missing = try decodeParse("record-parse-incomplete.json")
        let missingStatus = try XCTUnwrap(
            missing.record?.fields.first { $0.key == "status" }.map(CaptureRecordRow.init(field:))
        )
        XCTAssertEqual(missingStatus.state, "missing")
        XCTAssertNil(missingStatus.display)
        XCTAssertEqual(
            missingStatus.valueMode(hasCandidates: false, hasDiagnostic: false),
            .choices
        )

        let invalid = try decodeParse("record-parse-invalid.json")
        let invalidStatus = try XCTUnwrap(
            invalid.record?.fields.first { $0.key == "status" }.map(CaptureRecordRow.init(field:))
        )
        XCTAssertEqual(invalidStatus.state, "invalid")
        XCTAssertNil(invalidStatus.display)
        XCTAssertEqual(
            invalidStatus.valueMode(hasCandidates: false, hasDiagnostic: true),
            .choices
        )

        let defaultLink = CaptureRecordRow(
            key: "wiki",
            label: "Wiki",
            kind: "link",
            state: "default",
            display: "[[abby]]",
            source: "default"
        )
        XCTAssertEqual(
            defaultLink.valueMode(hasCandidates: false, hasDiagnostic: false),
            .display
        )

        let changed = CaptureRecordRow(
            key: "status",
            label: "Status",
            kind: "choices",
            state: "set",
            display: "✅ Watched",
            beforeDisplay: "🔖 To watch",
            choices: [
                CaptureRecordChoice(value: "to_watch", label: "To watch"),
                CaptureRecordChoice(value: "watched", label: "Watched"),
            ]
        )
        XCTAssertEqual(
            changed.valueMode(hasCandidates: false, hasDiagnostic: false),
            .changed
        )
        XCTAssertEqual(
            changed.valueMode(hasCandidates: true, hasDiagnostic: true),
            .candidates
        )
    }

    func testRouteAdornmentsUseOwningItemEmojiAndSkipMissingMetadata() throws {
        let two = try decodeParse("record-parse-two-records.json")
        let adornments = CaptureRecordRouteAdornment.all(in: two)
        XCTAssertEqual(adornments.map(\.emoji), ["🍽️", "🎙️"])
        XCTAssertEqual(adornments.count, 2)

        let unicode = try decodeParse("record-parse-unicode.json")
        let cafe = try XCTUnwrap(CaptureRecordRouteAdornment.all(in: unicode).first)
        XCTAssertEqual(cafe.start, ("Café Møø " as String).utf8.count)
        XCTAssertEqual(cafe.emoji, "🍽️")
        let origin = try XCTUnwrap(
            CaptureMonospaceGlyphOrigin.wrappingOrigin(
                utf8Offset: cafe.start,
                in: unicode.input,
                charsPerLine: 80
            )
        )
        XCTAssertEqual(origin.line, 0)
        XCTAssertEqual(origin.column, ("Café Møø " as String).count)

        var noEmoji = try decodeParse("record-parse-incomplete.json")
        noEmoji = CaptureParseResponse(
            ok: noEmoji.ok,
            schemaVersion: noEmoji.schemaVersion,
            input: noEmoji.input,
            body: noEmoji.body,
            mode: noEmoji.mode,
            spans: noEmoji.spans,
            record: CaptureRecord(
                action: noEmoji.record?.action ?? "create",
                recordType: noEmoji.record?.recordType ?? "",
                label: noEmoji.record?.label ?? "",
                emoji: nil,
                dir: noEmoji.record?.dir ?? "",
                fields: noEmoji.record?.fields ?? []
            )
        )
        XCTAssertTrue(CaptureRecordRouteAdornment.all(in: noEmoji).isEmpty)
    }

    func testWrappingOriginRejectsMidCharacterAndWrapsLines() {
        let cafe = "Café Møø @eat/"
        // é occupies UTF-8 bytes 3-4; offset 4 is mid-character.
        XCTAssertNil(
            CaptureMonospaceGlyphOrigin.wrappingOrigin(
                utf8Offset: 4,
                in: cafe,
                charsPerLine: 80
            )
        )
        let origin = CaptureMonospaceGlyphOrigin.wrappingOrigin(
            utf8Offset: 11,
            in: "Ramen Nagi @eat/",
            charsPerLine: 8
        )
        XCTAssertEqual(origin, CaptureMonospaceGlyphOrigin(line: 1, column: 3))
        let newline = CaptureMonospaceGlyphOrigin.wrappingOrigin(
            utf8Offset: 17,
            in: "Ramen Nagi @eat/\n- ",
            charsPerLine: 80
        )
        XCTAssertEqual(newline, CaptureMonospaceGlyphOrigin(line: 1, column: 0))
    }

    func testCurrentValueNamedEditKeepsTheTypedSpelling() throws {
        let response = try decodeComplete("record-complete-named-status-current.json")
        XCTAssertEqual(response.context, "record_value")
        XCTAssertEqual(response.record?.field, "status")
        let edit = try XCTUnwrap(response.record?.edit)
        XCTAssertEqual(edit.replacement, "liked")
        XCTAssertFalse(edit.continuation.nextMissingField)
    }

    func testCategoryManyHasAtLeastSevenValues() throws {
        let response = try decodeComplete("record-complete-category-many.json")
        XCTAssertEqual(response.context, "record_value")
        XCTAssertGreaterThanOrEqual(response.candidates.count, 7)
        XCTAssertEqual(response.record?.field, "category")
        XCTAssertTrue(
            response.candidates.contains { $0.recordValue == "Cafe" },
            "category suggestions still include Cafe")
    }

    func testRecordAssistMapsCreateRouteWithoutNextMissingToTarget() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_ASSIST": "1",
            ]
        )
        let draft = "Ramen Nagi @eat/"
        let target = try await client.captureComplete(draft, cursor: draft.utf8.count)
        XCTAssertEqual(target.context, "record_target")
        XCTAssertFalse(target.candidates.isEmpty)
        let firstMissing = try await client.captureComplete(
            draft,
            cursor: draft.utf8.count,
            nextMissingField: true
        )
        XCTAssertEqual(firstMissing.context, "record_value")
        XCTAssertEqual(firstMissing.record?.field, "status")
        let fieldDraft = "Ramen Nagi @eat/\n- "
        let fields = try await client.captureComplete(
            fieldDraft,
            cursor: fieldDraft.utf8.count
        )
        XCTAssertEqual(fields.context, "record_field")
    }
}
