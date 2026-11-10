import Foundation
import XCTest

@testable import CaptureCore

final class GcalNoteContractTests: XCTestCase {
    private var testsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: testsRoot.appendingPathComponent("Fixtures/gcal-note/\(name)"))
    }

    private func fakeBobPath() -> String {
        testsRoot.appendingPathComponent("Fixtures/fake-bob").path
    }

    private func client(_ environment: [String: String] = [:]) -> BobProcessClient {
        BobProcessClient(
            executablePath: fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"].merging(environment) {
                _, new in new
            }
        )
    }

    private func recordedArgv(_ url: URL) throws -> [[String]] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try contents.split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String])
        }
    }

    func testFullBobFixturesDecodeDistinctShowAndWriteNotes() throws {
        let list = try JSONDecoder().decode(
            GcalNoteListResponse.self, from: fixture("list_all.json"))
        XCTAssertTrue(list.ok)
        XCTAssertEqual(list.schemaVersion, 1)
        XCTAssertEqual(list.events.map(\.eventID), ["gym", "deerwood"])
        XCTAssertEqual(list.events.first?.organizer?.selfOrganized, false)

        let show = try JSONDecoder().decode(GcalNoteShowResponse.self, from: fixture("show.json"))
        XCTAssertTrue(show.ok)
        XCTAssertEqual(show.action, "show")
        XCTAssertEqual(show.event?.note?.text, "@family\n-30 Drive to Deerwood\n+15 Drive home")
        XCTAssertEqual(show.event?.note?.lines.first, "@family")
        XCTAssertEqual(show.effective?.buffer?.beforeReason, "Drive to Deerwood")

        let preview = try JSONDecoder().decode(
            GcalNoteWriteResponse.self, from: fixture("preview.json"))
        XCTAssertEqual(preview.action, "preview")
        XCTAssertEqual(preview.note?.lines.map(\.kind), ["directives", "reason", "reason"])
        XCTAssertEqual(preview.note?.lines.last?.side, "after")
        XCTAssertTrue(preview.spans.contains { $0.kind == "reason_sign" })
        XCTAssertEqual(preview.effective?.buffer?.afterReason, "Drive home")

        let invalid = try JSONDecoder().decode(
            GcalNoteWriteResponse.self, from: fixture("invalid.json"))
        XCTAssertFalse(invalid.ok)
        XCTAssertEqual(invalid.error?.kind, "invalid_note")
        XCTAssertEqual(invalid.errors.first?.kind, "route_unknown")
        XCTAssertEqual(invalid.spans.first?.start, 0)
    }

    func testFocusedFixturesCoverScopesInheritanceStatusesAndMutationOutcomes() throws {
        let bothScopes = try JSONDecoder().decode(
            GcalNoteShowResponse.self, from: fixture("both_scopes.json"))
        XCTAssertEqual(bothScopes.event?.seriesID, "gym-series")
        XCTAssertEqual(bothScopes.effective?.buffer?.beforeMinutes, 0)
        XCTAssertNil(bothScopes.effective?.buffer?.beforeReason)
        XCTAssertEqual(bothScopes.effective?.buffer?.afterReason, "Event after")

        let inherited = try JSONDecoder().decode(
            GcalNoteShowResponse.self, from: fixture("inherited_reasons.json"))
        XCTAssertEqual(inherited.effective?.buffer?.beforeReason, "Series before")
        XCTAssertEqual(inherited.effective?.buffer?.afterReason, "Series after")

        let google = try JSONDecoder().decode(
            GcalNoteShowResponse.self, from: fixture("google_reasons.json"))
        XCTAssertEqual(google.effective?.buffer?.beforeReason, "Google drive there")

        let waiting = try JSONDecoder().decode(
            GcalNoteListResponse.self, from: fixture("waiting_states.json"))
        XCTAssertEqual(waiting.events.map(\.lands), ["waiting_reply", "waiting_maybe"])

        for name in ["applied", "saved_elsewhere", "saved_sync_failed"] {
            let response = try JSONDecoder().decode(
                GcalNoteWriteResponse.self, from: fixture("\(name).json"))
            XCTAssertTrue(response.ok)
            XCTAssertNotNil(response.status?.state)
        }

        let recurring = try JSONDecoder().decode(
            GcalNoteShowResponse.self, from: fixture("series_scope.json"))
        XCTAssertEqual(recurring.scope, .series)
    }

    func testSchemaMismatchIsVisibleAndUnknownAdditiveValuesStayNeutral() throws {
        let unknownScope = try JSONDecoder().decode(
            GcalNoteScope.self, from: Data("\"future\"".utf8))
        XCTAssertEqual(unknownScope, .unknown("future"))

        let additive =
            #"{"schema_version":1,"ok":true,"events":[],"future_display":"new","future_object":{"a":1}}"#
        let decoded = try JSONDecoder().decode(GcalNoteListResponse.self, from: Data(additive.utf8))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertTrue(decoded.events.isEmpty)

        let missingIdentity = #"{"schema_version":1,"ok":true,"events":[{"event_id":"only-id"}]}"#
        XCTAssertThrowsError(
            try JSONDecoder().decode(GcalNoteListResponse.self, from: Data(missingIdentity.utf8)))
        XCTAssertThrowsError(
            try JSONDecoder().decode(GcalNoteListResponse.self, from: Data("{".utf8)))
    }

    func testOverlappingUTF8SpansValidateIndividuallyAndPaintBroadFirst() throws {
        let response = try JSONDecoder().decode(
            GcalNoteWriteResponse.self, from: fixture("preview.json"))
        let text = try XCTUnwrap(response.note?.text)
        let validated = GcalNoteSpanAdapter.validatedRanges(in: text, spans: response.spans)
        let kinds = validated.map(\.span.kind)
        XCTAssertTrue(kinds.contains("buffer"))
        XCTAssertTrue(kinds.contains("reason_sign"))
        XCTAssertEqual(kinds.last, "reason_sign")
        let unsafe = [GcalNoteSpan(start: 1, end: 2, kind: "split-scalar")]
        XCTAssertTrue(GcalNoteSpanAdapter.validatedRanges(in: "é", spans: unsafe).isEmpty)
    }

    func testClientUsesIsolatedOperationsAndPreservesWholeTextArgument() async throws {
        let argvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: argvURL) }
        let process = client(["FAKE_BOB_GCAL_NOTE_ARGV_PATH": argvURL.path])

        _ = try await process.gcalNoteList()
        let calendarURL = "https://calendar.google.com/calendar/event?eid=opaque%2Btoken"
        _ = try await process.gcalNoteShow(query: calendarURL)
        let noteText = "@family\n-30 Café 🚗\n-- leading dash"
        _ = try await process.gcalNotePreview(
            text: noteText,
            eventID: "event-123",
            calendarID: "primary",
            scope: .event
        )
        _ = try await process.gcalNoteSave(
            text: noteText, eventID: "event-123", calendarID: "primary", scope: .series)
        _ = try await process.gcalNoteClear(
            eventID: "event-123", calendarID: "primary", scope: .event)

        XCTAssertEqual(
            try recordedArgv(argvURL),
            [
                ["gcal", "note", "-l", "-a", "-f", "json"],
                ["gcal", "note", calendarURL, "-f", "json"],
                [
                    "gcal", "note", "-i", "event-123", "-C", "primary", "-s", "event", "-d", "-f",
                    "json", "--", noteText,
                ],
                [
                    "gcal", "note", "-i", "event-123", "-C", "primary", "-s", "series", "-f",
                    "json", "--", noteText,
                ],
                [
                    "gcal", "note", "-i", "event-123", "-C", "primary", "-s", "event", "-c", "-f",
                    "json",
                ],
            ])
    }

    func testMutationFixtureStoreSupportsClearAndUndoAsRestore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("note-store")
        let process = client(["FAKE_BOB_GCAL_NOTE_STORE": store.path])

        _ = try await process.gcalNoteSave(
            text: "@family\nBring the old note back", eventID: "gym", calendarID: "primary",
            scope: .event)
        _ = try await process.gcalNoteSave(
            text: "@family\nReplaced text", eventID: "gym", calendarID: "primary", scope: .event)
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "@family\nReplaced text")
        _ = try await process.gcalNoteClear(eventID: "gym", calendarID: "primary", scope: .event)
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "")
        _ = try await process.gcalNoteSave(
            text: "@family\nBring the old note back", eventID: "gym", calendarID: "primary",
            scope: .event)
        XCTAssertEqual(
            try String(contentsOf: store, encoding: .utf8), "@family\nBring the old note back")
    }

    func testExitTwoInvalidReportDecodesAndDoesNotBecomeUnsupported() async throws {
        let process = client([
            "FAKE_BOB_GCAL_NOTE_WRITE_FIXTURE": "gcal-note/invalid.json",
            "FAKE_BOB_GCAL_NOTE_EXIT": "2",
        ])
        let response = try await process.gcalNoteSave(
            text: "@unknown", eventID: "deerwood", calendarID: "primary", scope: .event)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.kind, "invalid_note")
        XCTAssertFalse(process.gcalNoteKnownUnsupported)
    }

    func testMalformedEmptySchemaAndUnrelatedErrorsStayDistinct() async throws {
        do {
            _ = try await client(["FAKE_BOB_GCAL_NOTE_STDOUT": "not JSON"]).gcalNoteList()
            XCTFail("Expected malformed JSON")
        } catch BobClientError.malformedJSON(_, _, _, _) {
        }
        do {
            _ = try await client(["FAKE_BOB_GCAL_NOTE_EMPTY": "1"]).gcalNoteList()
            XCTFail("Expected empty stdout")
        } catch BobClientError.emptyStdout(_, _, _) {
        }
        do {
            _ = try await client(["FAKE_BOB_GCAL_NOTE_STDOUT": #"{"schema_version":2,"ok":true}"#])
                .gcalNoteList()
            XCTFail("Expected schema mismatch")
        } catch BobClientError.schemaMismatch(_, let expected, let actual) {
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(actual, 2)
        }
        let process = client([
            "FAKE_BOB_GCAL_NOTE_ERROR": "authentication expired",
            "FAKE_BOB_GCAL_NOTE_EXIT": "2",
        ])
        do {
            _ = try await process.gcalNoteList()
            XCTFail("Expected ordinary process failure")
        } catch BobClientError.processFailed(_, let status, let stderr) {
            XCTAssertEqual(status, 2)
            XCTAssertTrue(stderr.contains("authentication expired"))
        }
        XCTAssertFalse(process.gcalNoteKnownUnsupported)
    }

    func testUnsupportedCapabilityIsCachedPerBobIdentity() async throws {
        let record = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: record) }
        let process = client([
            "FAKE_BOB_GCAL_NOTE_UNSUPPORTED": "1",
            "FAKE_BOB_RECORD_PATH": record.path,
        ])
        var identity = "first"
        process.identityTokenProvider = { identity }

        for _ in 0..<2 {
            do {
                _ = try await process.gcalNoteList()
                XCTFail("Expected unsupported command")
            } catch BobClientError.unsupportedCommand(let command) {
                XCTAssertEqual(command, "gcal note")
            }
        }
        XCTAssertTrue(process.gcalNoteKnownUnsupported)
        let firstCount =
            try String(contentsOf: record, encoding: .utf8)
            .components(separatedBy: "argv=gcal note").count - 1
        XCTAssertEqual(firstCount, 1)

        identity = "replacement"
        XCTAssertFalse(process.gcalNoteKnownUnsupported)
        do {
            _ = try await process.gcalNoteList()
            XCTFail("A replacement Bob should receive a fresh capability probe")
        } catch BobClientError.unsupportedCommand {
        }
        let secondCount =
            try String(contentsOf: record, encoding: .utf8)
            .components(separatedBy: "argv=gcal note").count - 1
        XCTAssertEqual(secondCount, 2)
    }

    func testPreviewReplacementAndMutationLaneIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let previewRecord = directory.appendingPathComponent("preview-record")
        let previewClient = client([
            "FAKE_BOB_RECORD_PATH": previewRecord.path,
            "FAKE_BOB_GCAL_NOTE_DELAY_SECONDS": "0.3",
        ])

        let preview = Task {
            try await previewClient.gcalNotePreview(
                text: "@family", eventID: "e1", calendarID: "primary", scope: .event)
        }
        let firstDeadline = Date().addingTimeInterval(2)
        while Date() < firstDeadline {
            if (try? String(contentsOf: previewRecord, encoding: .utf8))?.contains("argv=gcal note")
                == true
            {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let replacement = Task {
            try await previewClient.gcalNotePreview(
                text: "@family\nBring water", eventID: "e1", calendarID: "primary", scope: .event)
        }
        do {
            _ = try await preview.value
            XCTFail("A same-lane preview should be replaced by the newer request")
        } catch BobClientError.processFailed(_, _, _) {
        }
        let replacementResult = try await replacement.value
        XCTAssertTrue(replacementResult.ok)

        let isolatedRecord = directory.appendingPathComponent("isolated-record")
        let isolatedClient = client([
            "FAKE_BOB_RECORD_PATH": isolatedRecord.path,
            "FAKE_BOB_GCAL_NOTE_DELAY_SECONDS": "0.3",
        ])
        let independentPreview = Task {
            try await isolatedClient.gcalNotePreview(
                text: "@family", eventID: "e1", calendarID: "primary", scope: .event)
        }
        let isolatedDeadline = Date().addingTimeInterval(2)
        while Date() < isolatedDeadline {
            if (try? String(contentsOf: isolatedRecord, encoding: .utf8))?.contains(
                "argv=gcal note") == true
            {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let save = Task {
            try await isolatedClient.gcalNoteSave(
                text: "@family", eventID: "e1", calendarID: "primary", scope: .event)
        }
        let previewResult = try await independentPreview.value
        let saveResult = try await save.value
        XCTAssertTrue(previewResult.ok)
        XCTAssertTrue(saveResult.ok)

        let firstMutation = Task {
            try await isolatedClient.gcalNoteSave(
                text: "@family", eventID: "e1", calendarID: "primary", scope: .event)
        }
        let secondMutation = Task {
            try await isolatedClient.gcalNoteClear(
                eventID: "e1", calendarID: "primary", scope: .event)
        }
        let firstMutationResult = try await firstMutation.value
        let secondMutationResult = try await secondMutation.value
        XCTAssertTrue(firstMutationResult.ok)
        XCTAssertTrue(secondMutationResult.ok)
    }
}
