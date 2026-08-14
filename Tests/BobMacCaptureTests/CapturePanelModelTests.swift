import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CapturePanelModelTests: XCTestCase {
    func testSubmitClearsDraftAndRecordsDestinationOnSuccess() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "Call bank @Cash"

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(model.lastSuccess?.routeLabel, "cash.md")
        XCTAssertNil(model.errorMessage)
    }

    func testSuccessfulSubmitDismissesPanelExactlyOnce() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "Call bank @Cash"
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testSubmitAndOpenOpensObsidianURLBuiltFromReturnedTarget() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "Call bank @Cash"
        var openedURL: URL?
        model.targetOpener = { openedURL = $0 }

        model.submit(openAfterCapture: true)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(openedURL?.scheme, "obsidian")
        XCTAssertEqual(openedURL?.host, "open")
    }

    func testSuccessfulSubmitAndOpenDismissesPanelExactlyOnceAndOpensTarget() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "Call bank @Cash"
        var openedURL: URL?
        model.targetOpener = { openedURL = $0 }
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        model.submit(openAfterCapture: true)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(dismissCount, 1)
        XCTAssertNotNil(openedURL)
    }

    func testFailedSubmitRetainsCompleteDraftAndSurfacesActionableError() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":false,"error":"clipboard command xclip exited with 1"}"#,
                "FAKE_BOB_EXIT": "1",
            ]
        )
        model.plainDraft = "private captured text"
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(model.plainDraft, "private captured text")
        XCTAssertEqual(model.errorMessage, "clipboard command xclip exited with 1")
        XCTAssertFalse(model.pendingDiscardConfirmation)
        XCTAssertEqual(dismissCount, 0)
    }

    func testTransportFailureAlsoRetainsDraftAndRedactsCapturedTextAndDoesNotDismiss() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": "{",
            ]
        )
        model.plainDraft = "private captured text"
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(model.plainDraft, "private captured text")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.errorMessage?.contains("private captured text") ?? true)
        XCTAssertEqual(dismissCount, 0)
    }

    func testSubmitWithoutResolvedBobDoesNotDismissPanel() {
        let model = CapturePanelModel()
        model.plainDraft = "Call bank @Cash"
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        model.submit(openAfterCapture: false)

        XCTAssertEqual(dismissCount, 0)
    }

    func testPrepareForPresentationAfterSuccessClearsLastSuccessAndDestinationSummary() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "Call bank @Cash"

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }
        XCTAssertNotNil(model.destinationSummary)

        model.prepareForPresentation()

        XCTAssertNil(model.lastSuccess)
        XCTAssertNil(model.destinationSummary)
        XCTAssertEqual(model.statusText, "")
    }

    func testPrepareForPresentationWithRetainedDraftAndErrorPreservesDraftErrorAndDiscardConfirmation() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":false,"error":"clipboard command xclip exited with 1"}"#,
                "FAKE_BOB_EXIT": "1",
            ]
        )
        model.plainDraft = "private captured text"
        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }
        model.pendingDiscardConfirmation = true

        model.prepareForPresentation()

        XCTAssertEqual(model.plainDraft, "private captured text")
        XCTAssertEqual(model.errorMessage, "clipboard command xclip exited with 1")
        XCTAssertTrue(model.pendingDiscardConfirmation)
    }

    func testDoubleSubmitIsSuppressedWhileOneMutationIsInFlight() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )
        model.plainDraft = "Call bank @Cash"

        model.submit(openAfterCapture: false)
        model.submit(openAfterCapture: false)
        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }

        let record = (try? String(contentsOf: recordURL)) ?? ""
        let invocationCount = record.components(separatedBy: "argv=").count - 1
        XCTAssertEqual(invocationCount, 1)
    }

    func testPreviewUsesDryRunWithoutSuppressingClipboardAndKeepsDraft() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )
        model.plainDraft = "Call bank @Cash"

        model.preview()
        await waitUntil { !model.isPreviewing }

        XCTAssertEqual(model.plainDraft, "Call bank @Cash")
        XCTAssertTrue(model.previewResult?.dryRun ?? false)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("--dry-run"))
        XCTAssertFalse(record.contains("--no-clip"))
    }

    func testSubmitWithoutResolvedBobSurfacesErrorWithoutCrashing() {
        let model = CapturePanelModel()
        model.plainDraft = "Call bank @Cash"

        model.submit(openAfterCapture: false)

        XCTAssertFalse(model.isSubmitting)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.plainDraft, "Call bank @Cash")
    }

    func testAcceptedCompletionStaysDismissedUntilNextUserEdit() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": recordURL.path,
                ]
            ),
            debounceNanoseconds: 5_000_000
        )
        model.plainDraft = "idea @ma"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil { model.completionVisible }

        model.acceptSelectedCompletion()
        XCTAssertEqual(model.plainDraft, "idea @mac_inbox")
        XCTAssertNil(model.completionResponse)

        // Mirror SwiftUI's delayed callback for the programmatic binding update.
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil {
            guard case .ready(let preview) = model.previewState else {
                return false
            }
            return preview.taskLine.contains("accepted completion")
                && model.parseDiagnostics.contains { $0.code == "accepted_fixture" }
        }

        XCTAssertNil(model.completionResponse)
        var record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-complete").count - 1, 1)
        XCTAssertTrue(
            record.contains("argv=capture-parse --format json -- idea @mac_inbox")
        )
        XCTAssertTrue(
            record.contains("argv=capture --dry-run --no-clip --format json -- idea @mac_inbox")
        )

        model.plainDraft = "idea @mac_inboxx"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil { model.completionVisible }

        XCTAssertEqual(
            model.completionResponse?.replacement,
            CaptureRange(start: 6, end: 16)
        )
        record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-complete").count - 1, 2)
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

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }
}
