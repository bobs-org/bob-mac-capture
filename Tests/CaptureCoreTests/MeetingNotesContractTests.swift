import Foundation
import XCTest

@testable import CaptureCore

final class MeetingNotesContractTests: XCTestCase {
    private var testsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: testsRoot.appendingPathComponent("Fixtures/meeting-notes/\(name)"))
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

    func testListAndPreviewDecodeTheShippedWireShape() throws {
        let list = try JSONDecoder().decode(
            MeetingNotesListResponse.self, from: fixture("list.json"))
        XCTAssertTrue(list.ok)
        XCTAssertEqual(list.schemaVersion, 1)
        XCTAssertEqual(list.meetings.count, 2)
        XCTAssertEqual(list.meetings.first?.eventRef, "20261124#^spruce-sync")
        XCTAssertNil(list.meetings.last?.eventRef)
        XCTAssertNil(list.meetings.last?.blockID)
        XCTAssertNil(list.meetings.last?.root)

        let preview = try JSONDecoder().decode(
            MeetingNotesResponse.self, from: fixture("preview.json"))
        XCTAssertEqual(preview.outcome, .wouldFile)
        XCTAssertEqual(preview.meeting?.eventRef, "20261124#^spruce-sync")
        XCTAssertEqual(preview.match?.method, "auto")
        XCTAssertEqual(preview.notes?.sha256?.count, 64)
        XCTAssertEqual(preview.notes?.outline?.nextSteps.first?.owner, "Rin")
        XCTAssertEqual(preview.filing?.task.status, "next")
    }

    func testChoiceErrorsUseMeetingCandidatesAndParentCandidatesSeparately() throws {
        let ambiguous = try JSONDecoder().decode(
            MeetingNotesResponse.self, from: fixture("ambiguous.json"))
        XCTAssertEqual(ambiguous.error?.code, "ambiguous_meeting")
        XCTAssertEqual(ambiguous.candidates.count, 2)
        XCTAssertEqual(ambiguous.candidates.first?.detail, "Juniper Systems planning")
        XCTAssertNil(ambiguous.candidates.last?.meeting.eventRef)
        XCTAssertTrue(ambiguous.parentCandidates.isEmpty)

        let parent = try JSONDecoder().decode(
            MeetingNotesResponse.self, from: fixture("needs-parent.json"))
        XCTAssertEqual(parent.error?.code, "needs_parent")
        XCTAssertEqual(parent.root, "inbox")
        XCTAssertEqual(parent.parentCandidates.map(\.route), ["team", "studio"])
        XCTAssertEqual(parent.parentCandidates.first?.aliases, ["team", "t"])

        let existing = try JSONDecoder().decode(
            MeetingNotesResponse.self, from: fixture("already-filed.json"))
        XCTAssertEqual(existing.existing?.status, "next")
        XCTAssertEqual(existing.existing?.task, "team#^juniper-notes")
    }

    func testFiledAndQueuedReceiptsKeepDistinctMetadata() throws {
        let filed = try JSONDecoder().decode(MeetingNotesResponse.self, from: fixture("filed.json"))
        XCTAssertEqual(filed.outcome, .filed)
        XCTAssertEqual(filed.commit, "ref meet: ingest meetings/261124_juniper_systems_planning")
        XCTAssertEqual(filed.pages, 2)
        XCTAssertEqual(filed.pushPending, true)
        XCTAssertEqual(filed.replaced, false)

        let queued = try JSONDecoder().decode(
            MeetingNotesResponse.self, from: fixture("queued.json"))
        XCTAssertEqual(queued.outcome, .queued)
        XCTAssertEqual(queued.queued?.reason, "lock")
        XCTAssertEqual(queued.queued?.detail, "vault is busy")
        XCTAssertNil(queued.commit)
    }

    func testAdditiveFieldsDecodeAndMalformedOrNewSchemasRefuse() throws {
        let additive =
            #"{"schema_version":1,"ok":true,"outcome":"would_file","future":{"x":1},"warnings":[]}"#
        let decoded = try JSONDecoder().decode(MeetingNotesResponse.self, from: Data(additive.utf8))
        XCTAssertNil(decoded.meeting)
        XCTAssertNil(decoded.notes)
        XCTAssertThrowsError(
            try JSONDecoder().decode(MeetingNotesResponse.self, from: fixture("malformed.json")))
        let newSchema = try JSONDecoder().decode(
            MeetingNotesResponse.self, from: fixture("schema-2.json"))
        XCTAssertEqual(newSchema.schemaVersion, 2)
    }

    func testClientUsesExactArgvAndKeepsEventAsOneOpaqueArgument() async throws {
        let argvURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: argvURL) }
        let process = client(["FAKE_BOB_MEETING_NOTES_ARGV_PATH": argvURL.path])
        let event = "20261124#^spruce sync"
        let options = MeetingNotesOptions(
            eventToken: event, parent: "studio", status: .read, overwrite: true)

        _ = try await process.meetingNotesList()
        _ = try await process.meetingNotesPreview(options)
        _ = try await process.meetingNotesFile(
            MeetingNotesFileRequest(options: options, sha256: String(repeating: "b", count: 64)))

        XCTAssertEqual(
            try recordedArgv(argvURL),
            [
                ["ref", "meet", "-l", "-f", "json"],
                [
                    "ref", "meet", event, "--parent", "studio", "--status", "read",
                    "--overwrite", "-c", "-d", "-f", "json",
                ],
                [
                    "ref", "meet", event, "--parent", "studio", "--status", "read",
                    "--overwrite", "-c", "-f", "json", "--expect-sha256",
                    String(repeating: "b", count: 64),
                ],
            ]
        )
    }

    func testStructuredExitTwoChoiceErrorDecodesButSchemaMismatchIsExplicit() async throws {
        let choiceClient = client([
            "FAKE_BOB_MEETING_NOTES_PREVIEW_FIXTURE": "meeting-notes/ambiguous.json",
            "FAKE_BOB_MEETING_NOTES_EXIT": "2",
        ])
        let choice = try await choiceClient.meetingNotesPreview(MeetingNotesOptions())
        XCTAssertEqual(choice.error?.code, "ambiguous_meeting")

        let schemaClient = client([
            "FAKE_BOB_MEETING_NOTES_PREVIEW_FIXTURE": "meeting-notes/schema-2.json"
        ])
        do {
            _ = try await schemaClient.meetingNotesPreview(MeetingNotesOptions())
            XCTFail("Expected schema mismatch")
        } catch BobClientError.schemaMismatch(_, let expected, let actual) {
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(actual, 2)
        }
    }

    func testOnlyTheExitTwoUnrecognizedMeetSignatureMeansUnsupported() {
        XCTAssertTrue(
            BobProcessClient.isUnsupportedMeetingNotesFailure(
                exitStatus: 2, stderr: "error: unrecognized subcommand 'meet'"))
        XCTAssertTrue(
            BobProcessClient.isUnsupportedMeetingNotesFailure(
                exitStatus: 2, stderr: "error: unrecognized subcommand \"meet\""))
        XCTAssertFalse(
            BobProcessClient.isUnsupportedMeetingNotesFailure(
                exitStatus: 1, stderr: "error: unrecognized subcommand 'meet'"))
        XCTAssertFalse(
            BobProcessClient.isUnsupportedMeetingNotesFailure(
                exitStatus: 2, stderr: "error: unrecognized subcommand 'scan'"))
    }

    func testUnsupportedCapabilityIsCachedByExecutableAndClearedOnRecheck() async throws {
        final class IdentityBox {
            var value = "first"
        }
        let box = IdentityBox()
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: recordURL) }
        let process = client([
            "FAKE_BOB_MEETING_NOTES_UNSUPPORTED": "1",
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ])
        process.identityTokenProvider = { box.value }

        for _ in 0..<2 {
            do {
                _ = try await process.meetingNotesList()
                XCTFail("Expected unsupported command")
            } catch BobClientError.unsupportedCommand(let command) {
                XCTAssertEqual(command, "ref meet")
            }
        }
        XCTAssertTrue(process.meetingNotesKnownUnsupported)
        let firstRecord = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertEqual(firstRecord.components(separatedBy: "argv=ref meet").count - 1, 1)

        box.value = "replacement"
        XCTAssertFalse(process.meetingNotesKnownUnsupported)
        do {
            _ = try await process.meetingNotesList()
            XCTFail("Replacement Bob is still synthetic old Bob")
        } catch BobClientError.unsupportedCommand {
        }
        process.recheckMeetingNotesCapability()
        do {
            _ = try await process.meetingNotesList()
            XCTFail("Explicit recheck should probe again")
        } catch BobClientError.unsupportedCommand {
        }
        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertEqual(record.components(separatedBy: "argv=ref meet").count - 1, 3)
    }
}
