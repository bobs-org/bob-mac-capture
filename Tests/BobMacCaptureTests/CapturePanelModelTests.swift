import CaptureCore
import Foundation
import SwiftUI
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

    func testSubmitDecodesRenderedNestedSubBulletsForMultilineDraft() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = nestedMultilineDraft()

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(model.lastSuccess?.subBullets, renderedNestedSubBullets())
    }

    func testPreviewDecodesRenderedNestedSubBulletsForMultilineDraft() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = nestedMultilineDraft()

        model.preview()
        await waitUntil { !model.isPreviewing }

        XCTAssertEqual(model.previewResult?.subBullets, renderedNestedSubBullets())
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

    func testPrepareForPresentationWithRetainedDraftAndErrorPreservesDraftAndError() async throws {
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

        model.prepareForPresentation()

        XCTAssertEqual(model.plainDraft, "private captured text")
        XCTAssertEqual(model.errorMessage, "clipboard command xclip exited with 1")
    }

    func testDiscardDraftAndCloseClearsDraftAnalysisStateAndDismisses() {
        let model = CapturePanelModel()
        model.plainDraft = "Call bank @Cash"
        model.errorMessage = "Capture failed"
        model.previewResult = sampleSuccess()
        model.parseDiagnostics = [
            CaptureDiagnostic(severity: "error", code: "bad_route", message: "Unknown route")
        ]
        model.previewState = .failed("Preview failed")
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 15,
            replacement: CaptureRange(start: 11, end: 15),
            context: "route",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "Cash",
                    route: "Cash",
                    label: "Cash.md",
                    kind: "cash"
                )
            ]
        )
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        model.discardDraftAndClose()

        XCTAssertEqual(model.plainDraft, "")
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.previewResult)
        XCTAssertEqual(model.parseDiagnostics, [])
        XCTAssertEqual(model.previewState, .idle)
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(dismissCount, 1)
    }

    func testCloseRetainingEmptyDraftDismissesWithoutDraftRetainedStatus() {
        let model = CapturePanelModel()
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        model.closeRetainingDraft()

        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(model.statusText, "")
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

    func testEditorAnalysisUsesRealCaretForWikilinkCompletion() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )
        model.plainDraft = "prefix [[AI suffix"
        let insertion = try XCTUnwrap(attributedStringIndex(
            in: model.attributedDraft,
            utf8Offset: "prefix [[AI".utf8.count
        ))
        model.editorSelection = AttributedTextSelection(insertionPoint: insertion)

        model.editorTextDidChange(cursorUTF8Offset: "prefix [[AI".utf8.count)
        await waitUntil { model.completionResponse?.context == "wikilink_note" }

        XCTAssertEqual(model.completionResponse?.warnings, ["skipped unreadable note"])
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), "prefix [[AI".utf8.count)
        XCTAssertEqual(model.statusText, "Link completion warning: skipped unreadable note")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete --cursor 11 --format json -- prefix [[AI suffix"))
    }

    func testRowContentDerivesQueryFromDraftReplacementAndCursorForWikilinkNote() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "prefix [[AI suffix"
        let insertion = try XCTUnwrap(attributedStringIndex(
            in: model.attributedDraft,
            utf8Offset: "prefix [[AI".utf8.count
        ))
        model.editorSelection = AttributedTextSelection(insertionPoint: insertion)

        model.editorTextDidChange(cursorUTF8Offset: "prefix [[AI".utf8.count)
        await waitUntil { model.completionResponse?.context == "wikilink_note" }

        let candidate = try XCTUnwrap(model.completionResponse?.candidates.first)
        let content = model.rowContent(for: candidate)

        XCTAssertEqual(content.contextLabel, "Note")
        XCTAssertEqual(content.primaryText, "AI")
        XCTAssertEqual(content.secondaryText, "Artificial Intelligence.md")
        XCTAssertEqual(content.badges, ["Alias"])
        XCTAssertEqual(content.primaryMatchRange, 0..<2)
    }

    func testRowContentDerivesQueryFromDraftReplacementAndCursorForRoute() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "idea @ma"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil { model.completionVisible }

        let candidate = try XCTUnwrap(model.completionResponse?.candidates.first)
        let content = model.rowContent(for: candidate)

        XCTAssertEqual(content.contextLabel, "Destination")
        XCTAssertEqual(content.primaryText, "mac_inbox")
        XCTAssertEqual(content.secondaryText, "mac_inbox.md")
        XCTAssertEqual(content.badges, ["inbox"])
        XCTAssertEqual(content.primaryMatchRange, 0..<2)
    }

    func testTaskBlockIDRouteSpanUsesCachedRouteCompletion() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )
        model.updateTargetCacheSnapshot(CaptureTargetsSnapshot(
            targets: CaptureTargetsResponse(
                ok: true,
                targets: [
                    CaptureTarget(
                        route: "mac_inbox",
                        name: "mac_inbox",
                        label: "mac_inbox.md",
                        kind: "inbox",
                        relativePath: "mac_inbox.md"
                    ),
                ]
            ),
            refreshedAt: Date(),
            stale: false,
            errorDescription: nil
        ))
        model.plainDraft = "idea @ma::new-id"

        model.editorTextDidChange(cursorUTF8Offset: "idea @ma".utf8.count)
        await waitUntil { model.completionVisible }

        XCTAssertEqual(model.completionResponse?.context, "route")
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 6, end: 8))
        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "mac_inbox")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- idea @ma::new-id"))
        XCTAssertFalse(record.contains("capture-complete"))
    }

    func testTaskBlockIDAuthoredIDSideDoesNotCompleteButLivePreviewShowsBlockID() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )
        model.plainDraft = "idea @mac_inbox::new-id"

        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil {
            guard case .ready(let preview) = model.previewState else {
                return false
            }
            return preview.taskLine == "- [ ] #task idea [created::2026-08-14] ^new-id"
        }

        XCTAssertNil(model.completionResponse)
        guard case .ready(let preview) = model.previewState else {
            return XCTFail("Expected ready preview")
        }
        XCTAssertEqual(preview.kind, "task")
        XCTAssertEqual(preview.blockID, "new-id")
        XCTAssertNil(preview.dayFile)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- idea @mac_inbox::new-id"))
        XCTAssertFalse(record.contains("capture-complete"))
    }

    func testRangeSelectionSuppressesCompletionButKeepsPreviewAnalysis() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )
        model.plainDraft = "prefix [[AI suffix"

        model.editorSelectionDidChange(cursorUTF8Offset: nil)
        await waitUntil {
            if case .ready = model.previewState {
                return true
            }
            return false
        }

        XCTAssertNil(model.completionResponse)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- prefix [[AI suffix"))
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- prefix [[AI suffix"))
        XCTAssertFalse(record.contains("capture-complete"))
    }

    func testCaretOnlyMoveRequeriesCompletionAtNewOffset() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )
        model.plainDraft = "prefix [[AI suffix"

        model.editorSelectionDidChange(cursorUTF8Offset: "prefix [[".utf8.count)
        await waitUntil { model.completionResponse?.context == "wikilink_note" }

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete --cursor 9 --format json -- prefix [[AI suffix"))
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

    private func sampleSuccess() -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: true,
            route: "Cash",
            routeLabel: "Cash.md",
            relativeTarget: "Cash.md",
            target: "/tmp/Cash.md",
            text: "Call bank",
            taskLine: "- [ ] Call bank",
            kind: "task",
            created: "2026-08-14",
            placement: "append"
        )
    }

    private func nestedMultilineDraft() -> String {
        [
            "Prepare launch",
            "- confirm owner",
            "  - text owner",
            "- attach checklist",
            "  - verify links",
        ].joined(separator: "\n")
    }

    private func renderedNestedSubBullets() -> [String] {
        [
            "  - confirm owner",
            "    - text owner",
            "  - attach checklist",
            "    - verify links",
        ]
    }
}
