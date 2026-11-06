import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureGmailPeekLaneTests: XCTestCase {
    private let gmailDraft =
        "Follow up https://mail.google.com/mail/u/0/#inbox/FMfcgzQhWTsNRgxMhQNwhZDfgqwXpPsx"
    private var gmailURL: String { String(gmailDraft.dropFirst("Follow up ".count)) }
    private let peekMessage =
        "✉️ Lease renewal for 14 Elm St · Dana Whitfield · 3 messages · Nov 3"

    private func fakeBobPath() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/fake-bob").path
    }

    private func client(environment extra: [String: String] = [:]) throws -> BobProcessClient {
        var environment = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        environment.merge(extra) { _, override in override }
        return BobProcessClient(executablePath: try fakeBobPath(), environment: environment)
    }

    private func typeDraft(_ model: CapturePanelModel, _ draft: String) {
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition was not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testSettledPeekReplacesTheOfflineLineAfterTheDraftPause() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(
            processClient: try client(environment: [
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_PARSE_FIXTURE": "capture-parse-gmail.json",
                "FAKE_BOB_GMAIL_PEEK_FIXTURE": "gmail-peek-resolved.json",
            ]),
            debounceNanoseconds: 0,
            gmailPeekSettleNanoseconds: 80_000_000
        )
        model.prepareForPresentation()

        typeDraft(model, gmailDraft)
        await waitUntil { model.gmailPeekDraft == self.gmailDraft }

        XCTAssertEqual(model.gmailPeekMessages[gmailURL], peekMessage)
        XCTAssertEqual(model.gmailPeekMessage(for: gmailURL), peekMessage)
        XCTAssertNil(model.gmailPeekMessage(for: "https://mail.google.com/mail/u/0/#all/other"))
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=gmail peek \(gmailURL) -f json"))
    }

    func testRapidEditsPeekOnceForTheLatestDraft() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(
            processClient: try client(environment: [
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_PARSE_FIXTURE": "capture-parse-gmail.json",
                "FAKE_BOB_GMAIL_PEEK_FIXTURE": "gmail-peek-resolved.json",
            ]),
            debounceNanoseconds: 0,
            gmailPeekSettleNanoseconds: 100_000_000
        )
        model.prepareForPresentation()

        typeDraft(model, gmailDraft)
        try await Task.sleep(nanoseconds: 35_000_000)
        let later = gmailDraft + "!"
        typeDraft(model, later)
        await waitUntil { model.gmailPeekDraft == later }
        try await Task.sleep(nanoseconds: 160_000_000)

        XCTAssertEqual(model.gmailPeekMessages[gmailURL], peekMessage)
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=gmail peek").count - 1, 1)
    }

    func testUnresolvedPeekKeepsTheOfflineLine() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(
            processClient: try client(environment: [
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_PARSE_FIXTURE": "capture-parse-gmail.json",
                "FAKE_BOB_GMAIL_PEEK_FIXTURE": "gmail-peek-unresolvable.json",
            ]),
            debounceNanoseconds: 0,
            gmailPeekSettleNanoseconds: 20_000_000
        )
        model.prepareForPresentation()

        typeDraft(model, gmailDraft)
        await waitUntil { model.gmailPeekDraft == self.gmailDraft }

        XCTAssertTrue(model.gmailPeekMessages.isEmpty)
        XCTAssertNil(model.gmailPeekMessage(for: gmailURL))
        XCTAssertNil(model.errorMessage)
    }

    func testOlderBobHidesPeekQuietlyAfterOneCapabilityCheck() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let processClient = try client(environment: [
            "FAKE_BOB_RECORD_PATH": recordURL.path,
            "FAKE_BOB_PARSE_FIXTURE": "capture-parse-gmail.json",
            "FAKE_BOB_GMAIL_PEEK_UNSUPPORTED": "1",
        ])
        let model = CapturePanelModel(
            processClient: processClient,
            debounceNanoseconds: 0,
            gmailPeekSettleNanoseconds: 20_000_000
        )
        model.prepareForPresentation()

        typeDraft(model, gmailDraft)
        await waitUntil { processClient.gmailPeekKnownUnsupported }
        typeDraft(model, gmailDraft + "!")
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(model.gmailPeekMessages.isEmpty)
        XCTAssertNil(model.errorMessage)
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=gmail peek").count - 1, 1)
    }
}
