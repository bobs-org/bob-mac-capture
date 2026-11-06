import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Grammar ≥ 15 gate: missing/1–14 block capture and keep the draft; 15+
/// submit; a pending parse stays quiet; Recheck Bob invalidates evidence.
@MainActor
final class CaptureGrammarGateHostedTests: XCTestCase {
    func testMissingGrammarBlocksSubmitAndKeepsTheDraft() throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try makeModel(recordURL: recordURL)
        model.plainDraft = "Inbox task"
        model.installCaptureGrammarForTests(nil)

        XCTAssertEqual(model.captureGrammarWarning, CaptureGrammarGate.blockedMessage)
        XCTAssertFalse(model.primaryActionEnabled)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(model.plainDraft, "Inbox task")
        XCTAssertEqual(model.statusText, CaptureGrammarGate.blockedMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testGrammarOneBlocksSubmitAndKeepsTheDraft() throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try makeModel(recordURL: recordURL)
        model.plainDraft = "Inbox task"
        model.installCaptureGrammarForTests(1)

        XCTAssertEqual(model.captureGrammarWarning, CaptureGrammarGate.blockedMessage)
        XCTAssertFalse(model.primaryActionEnabled)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(model.plainDraft, "Inbox task")
        XCTAssertEqual(model.statusText, CaptureGrammarGate.blockedMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testGrammarTwoBlocksSubmitAndKeepsTheDraft() throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try makeModel(recordURL: recordURL)
        model.plainDraft = "Inbox task"
        model.installCaptureGrammarForTests(2)

        XCTAssertEqual(model.captureGrammarWarning, CaptureGrammarGate.blockedMessage)
        XCTAssertFalse(model.primaryActionEnabled)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(model.plainDraft, "Inbox task")
        XCTAssertEqual(model.statusText, CaptureGrammarGate.blockedMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testMinimumGrammarAllowsSubmit() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try makeModel(recordURL: recordURL)
        model.plainDraft = "Inbox task"
        model.installCompatibleCaptureGrammarForTests()

        XCTAssertTrue(model.primaryActionEnabled)
        XCTAssertNil(model.captureGrammarWarning)
        var dismissed = 0
        model.panelDismisser = { dismissed += 1 }
        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(dismissed, 1)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture "), record)
    }

    func testGrammarFourteenBlocksSubmitAndKeepsTheDraft() throws {
        let model = try makeModel()
        model.plainDraft = "Inbox task"
        model.installCaptureGrammarForTests(14)

        XCTAssertFalse(model.captureGrammarAllowsSubmit)
        XCTAssertFalse(model.primaryActionEnabled)
        XCTAssertEqual(model.captureGrammarWarning, CaptureGrammarGate.blockedMessage)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(model.plainDraft, "Inbox task")
    }

    func testGrammarFiveBlocksSubmitAndKeepsTheDraft() throws {
        let model = try makeModel()
        model.plainDraft = "Inbox task"
        model.installCaptureGrammarForTests(5)

        XCTAssertFalse(model.captureGrammarAllowsSubmit)
        XCTAssertFalse(model.primaryActionEnabled)
        XCTAssertEqual(model.captureGrammarWarning, CaptureGrammarGate.blockedMessage)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(model.plainDraft, "Inbox task")
    }

    func testGrammarFifteenAllowsSubmit() async throws {
        let model = try makeModel()
        model.plainDraft = "Inbox task"
        model.installCaptureGrammarForTests(15)

        XCTAssertTrue(model.captureGrammarAllowsSubmit)
        XCTAssertTrue(model.primaryActionEnabled)
        XCTAssertNil(model.captureGrammarWarning)
        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }
        XCTAssertEqual(model.plainDraft, "")
    }

    func testPendingParseDisablesCaptureWithoutTheUpdateMessage() throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try makeModel(recordURL: recordURL)
        model.plainDraft = "Inbox task"

        XCTAssertFalse(model.captureGrammarAllowsSubmit)
        XCTAssertNil(model.captureGrammarWarning)
        XCTAssertFalse(model.primaryActionEnabled)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(model.plainDraft, "Inbox task")
        XCTAssertNotEqual(model.statusText, CaptureGrammarGate.blockedMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testRecheckBobInvalidatesCompatibleGrammar() throws {
        let model = try makeModel()
        model.plainDraft = "Inbox task"
        model.installCompatibleCaptureGrammarForTests()
        XCTAssertTrue(model.captureGrammarAllowsSubmit)

        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_PARSE_GRAMMAR": "2",
            ]
        )

        XCTAssertFalse(model.captureGrammarAllowsSubmit)
        XCTAssertNil(model.captureGrammarWarning)
        XCTAssertFalse(model.primaryActionEnabled)
        XCTAssertEqual(model.plainDraft, "Inbox task")
    }

    func testLandedIncompatibleParseShowsTheUpdateMessage() async throws {
        let model = try makeModel(
            environment: ["FAKE_BOB_PARSE_GRAMMAR": "omit"]
        )
        let draft = "Inbox task"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.latestParse?.input == draft }

        XCTAssertNil(model.latestParse?.grammar)
        XCTAssertEqual(model.captureGrammarWarning, CaptureGrammarGate.blockedMessage)
        XCTAssertFalse(model.primaryActionEnabled)
        XCTAssertEqual(model.plainDraft, draft)
    }

    func testDelayedIncompatibleParseDoesNotOverwriteANewerCompatibleState() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        let draft = "Inbox task"
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_DELAY_SECONDS": "0.25",
                "FAKE_BOB_PARSE_GRAMMAR": "2",
            ]
        )
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)

        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_PARSE_GRAMMAR": "15",
            ]
        )
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.latestParse?.grammar == 15 }
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(model.latestParse?.grammar, 15)
        XCTAssertTrue(model.captureGrammarAllowsSubmit)
        XCTAssertNil(model.captureGrammarWarning)
        XCTAssertEqual(model.plainDraft, draft)
    }

    private func makeModel(
        recordURL: URL? = nil,
        environment: [String: String] = [:]
    ) throws -> CapturePanelModel {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        var env = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        if let recordURL {
            env["FAKE_BOB_RECORD_PATH"] = recordURL.path
        }
        for (key, value) in environment {
            env[key] = value
        }
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: env
        )
        return model
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot =
            source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return
            packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
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
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
