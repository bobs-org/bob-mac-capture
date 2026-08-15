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

    func testSubmitRetainsAggregateBatchSuccessAndCountAwareStatus() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "First item @Cash\n\nSecond item @notes#Ideas"

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(model.lastSuccess?.text, "First item")
        XCTAssertEqual(model.lastSuccessResults.map(\.text), ["First item", "Second item"])
        XCTAssertEqual(model.statusText, "Captured 2 items")
        XCTAssertTrue(model.destinationSummary?.contains("2 captures, 2 destinations") == true)
        XCTAssertNil(model.errorMessage)
    }

    func testPreviewRetainsAggregateBatchResultAndKeepsDraft() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "First item @Cash\n\nSecond item @notes#Ideas"

        model.preview()
        await waitUntil { !model.isPreviewing }

        XCTAssertEqual(model.plainDraft, "First item @Cash\n\nSecond item @notes#Ideas")
        XCTAssertEqual(model.previewResult?.text, "First item")
        XCTAssertEqual(model.previewResults.map(\.relativeTarget), ["cash.md", "notes.md"])
        XCTAssertEqual(model.statusText, "Preview 2 items")
        XCTAssertTrue(model.destinationSummary?.contains("First item; Second item") == true)
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

    func testSubmitAndOpenBatchOpensUniqueTargetsInSourceOrder() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "First item @Cash\n\nSecond item @notes#Ideas"
        var openedPaths: [String] = []
        model.targetOpener = { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let path = components?.queryItems?.first { $0.name == "path" }?.value
            openedPaths.append(path ?? "")
        }

        model.submit(openAfterCapture: true)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(openedPaths, ["/tmp/bob/cash.md", "/tmp/bob/notes.md"])
    }

    func testSubmitAndOpenBatchDeduplicatesTargets() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": sameTargetBatchSuccessJSON,
            ]
        )
        model.plainDraft = "First @cash\n\nSecond @cash"
        var openedPaths: [String] = []
        model.targetOpener = { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let path = components?.queryItems?.first { $0.name == "path" }?.value
            openedPaths.append(path ?? "")
        }

        model.submit(openAfterCapture: true)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(model.lastSuccessResults.map(\.text), ["First", "Second"])
        XCTAssertEqual(openedPaths, ["/tmp/bob/cash.md"])
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

    func testDefaultConstructionCreatesUsableCanceledDraftStash() {
        let model = CapturePanelModel()
        model.plainDraft = "Call bank @Cash"

        model.stashDraftAndClose()

        XCTAssertEqual(model.stashEntries.map(\.text), ["Call bank @Cash"])
        XCTAssertEqual(model.stashCount, 1)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(model.statusText, "Canceled draft stashed")
    }

    func testStashDraftAndCloseStoresExactNonemptyDraftClearsStateAndDismisses() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        let draft = "  café task @Cash\n- keep whitespace  "
        model.plainDraft = draft
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

        model.stashDraftAndClose()

        XCTAssertEqual(stash.entries.map(\.text), [draft])
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.previewResult)
        XCTAssertEqual(model.parseDiagnostics, [])
        XCTAssertEqual(model.previewState, .idle)
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(model.statusText, "Canceled draft stashed")
        XCTAssertEqual(dismissCount, 1)
    }

    func testStashDraftAndCloseWhitespaceOnlyDraftDoesNotStoreAndClearsEditor() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        model.plainDraft = " \n\t "
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        model.stashDraftAndClose()

        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(model.statusText, "")
        XCTAssertEqual(dismissCount, 1)
    }

    func testDiscardDraftAndCloseDoesNotAddToStash() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        model.plainDraft = "Call bank @Cash"
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }

        model.discardDraftAndClose()

        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(dismissCount, 1)
    }

    func testStashPickerOpeningReportsEmptyAndRefusesLiveDraft() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)

        model.presentStashPicker()
        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertEqual(model.statusText, "No canceled drafts yet")

        stash.push("retained")
        model.plainDraft = "live draft"
        model.presentStashPicker()

        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertEqual(model.statusText, "Capture, retain, or cancel the current draft before opening stash")
        XCTAssertEqual(model.plainDraft, "live draft")
        XCTAssertEqual(stash.entries.map(\.text), ["retained"])
    }

    func testStashPickerSelectionWrapsAndClampsWhenStoreChanges() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        stash.push("old")
        stash.push("middle")
        stash.push("new")

        model.presentStashPicker()
        XCTAssertTrue(model.isStashPickerPresented)
        XCTAssertEqual(model.selectedStashIndex, 0)

        model.selectPreviousStashEntry()
        XCTAssertEqual(model.selectedStashIndex, 2)

        model.selectNextStashEntry()
        XCTAssertEqual(model.selectedStashIndex, 0)

        model.selectedStashIndex = 2
        stash.updateCapacity(1)
        XCTAssertEqual(stash.entries.map(\.text), ["new"])
        XCTAssertEqual(model.selectedStashIndex, 0)
        XCTAssertTrue(model.isStashPickerPresented)

        stash.clear()
        XCTAssertEqual(model.selectedStashIndex, 0)
        XCTAssertFalse(model.isStashPickerPresented)
    }

    func testRestoreStashEntryInstallsExactTextAtEndSchedulesFreshAnalysisAndPopsOnlyThatEntry() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": recordURL.path,
                ]
            ),
            debounceNanoseconds: 0,
            canceledDraftStash: stash
        )
        let older = try XCTUnwrap(stash.push("older @Cash"))
        let chosen = try XCTUnwrap(stash.push("Restored café @Cash\n- child"))
        _ = older
        model.presentStashPicker()

        model.restoreStashEntry(id: chosen.id)

        XCTAssertEqual(model.plainDraft, "Restored café @Cash\n- child")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), model.plainDraft.utf8.count)
        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertEqual(stash.entries.map(\.text), ["older @Cash"])
        XCTAssertEqual(model.statusText, "Restored canceled draft")

        await waitUntil {
            guard case .ready(let preview) = model.previewState else {
                return false
            }
            return preview.routeLabel == "cash.md"
        }

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- Restored café @Cash\n- child"))
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- Restored café @Cash\n- child"))
    }

    func testRestoreStashEntryRefusesToOverwriteLiveDraftAndLeavesEntry() throws {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        let entry = try XCTUnwrap(stash.push("retained"))
        model.plainDraft = "live"

        model.restoreStashEntry(id: entry.id)

        XCTAssertEqual(model.plainDraft, "live")
        XCTAssertEqual(stash.entries, [entry])
        XCTAssertEqual(model.statusText, "Capture, retain, or cancel the current draft before opening stash")
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
        model.plainDraft = "idea @ma^new-id"

        model.editorTextDidChange(cursorUTF8Offset: "idea @ma".utf8.count)
        await waitUntil { model.completionVisible }

        XCTAssertEqual(model.completionResponse?.context, "route")
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 6, end: 8))
        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "mac_inbox")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- idea @ma^new-id"))
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
        model.plainDraft = "idea @mac_inbox^new-id"

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
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- idea @mac_inbox^new-id"))
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

    func testPlusSubBulletAndCaretIdOnlySubmitThroughDirectArgv() async throws {
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

        model.plainDraft = "Follow up @file^new-id"
        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }
        XCTAssertEqual(model.lastSuccess?.kind, "task")
        XCTAssertEqual(model.lastSuccess?.blockID, "new-id")
        XCTAssertNil(model.lastSuccess?.dayFile)
        XCTAssertNil(model.lastSuccess?.blockLink)
        XCTAssertNil(model.lastSuccess?.pomodoroLinkPlacement)

        model.plainDraft = "Add context @file+parent-id"
        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }
        XCTAssertEqual(model.lastSuccess?.kind, "sub_bullet")
        XCTAssertEqual(model.lastSuccess?.blockID, "parent-id")

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture --format json -- Follow up @file^new-id"))
        XCTAssertTrue(record.contains("argv=capture --format json -- Add context @file+parent-id"))
    }

    func testPreviewDecodesAuthoredIdOnlyTaskWithoutPomodoroFields() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "Follow up @file^new-id"

        model.preview()
        await waitUntil { !model.isPreviewing }

        XCTAssertEqual(model.previewResult?.kind, "task")
        XCTAssertEqual(model.previewResult?.blockID, "new-id")
        XCTAssertEqual(
            model.previewResult?.taskLine,
            "- [ ] #task Follow up [created::2026-08-14] ^new-id"
        )
        XCTAssertNil(model.previewResult?.dayFile)
        XCTAssertNil(model.previewResult?.blockLink)
        XCTAssertNil(model.previewResult?.pomodoroLinkPlacement)
    }

    func testCachedRouteCompletionWorksOnPlusAndCaretRouteSpans() async throws {
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
        model.updateTargetCacheSnapshot(
            CaptureTargetsSnapshot(
                targets: CaptureTargetsResponse(
                    ok: true,
                    targets: [
                        CaptureTarget(
                            route: "file",
                            name: "file",
                            label: "file.md",
                            kind: "area",
                            relativePath: "file.md"
                        )
                    ]
                ),
                refreshedAt: Date(),
                stale: false,
                errorDescription: nil
            )
        )

        model.plainDraft = "Add context @file+parent-id"
        model.editorTextDidChange(cursorUTF8Offset: "Add context @file".utf8.count)
        await waitUntil { model.completionResponse?.context == "route" }
        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "file")

        model.plainDraft = "Follow up @file^new-id"
        model.editorTextDidChange(cursorUTF8Offset: "Follow up @file".utf8.count)
        await waitUntil {
            model.completionResponse?.context == "route"
                && model.plainDraft == "Follow up @file^new-id"
        }
        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "file")
    }

    func testPlusRightSideOffersTasksAndCaretAuthoredIdShowsNoPicker() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )

        model.plainDraft = "note @Cash+goog"
        model.editorTextDidChange(cursorUTF8Offset: "note @Cash+goog".utf8.count)
        await waitUntil { model.completionResponse?.context == "task" }
        XCTAssertEqual(model.completionResponse?.candidates.first?.blockID, "goog-exit")
        XCTAssertTrue(model.completionVisible)

        model.plainDraft = "Do work @Dev^new-id"
        model.editorTextDidChange(cursorUTF8Offset: "Do work @Dev^new-id".utf8.count)
        await waitUntil {
            model.plainDraft == "Do work @Dev^new-id" && model.completionResponse == nil
        }
        XCTAssertFalse(model.completionVisible)
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

    private var sameTargetBatchSuccessJSON: String {
        """
        {
          "ok": true,
          "dry_run": false,
          "routed": true,
          "route": "cash",
          "route_label": "cash.md",
          "relative_target": "cash.md",
          "target": "/tmp/bob/cash.md",
          "text": "First",
          "task_line": "- [ ] #task First [created::2026-08-14]",
          "kind": "task",
          "created": "2026-08-14",
          "scheduled": null,
          "placement": "inserted",
          "captures": [
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": "cash",
              "route_label": "cash.md",
              "relative_target": "cash.md",
              "target": "/tmp/bob/cash.md",
              "text": "First",
              "task_line": "- [ ] #task First [created::2026-08-14]",
              "kind": "task",
              "created": "2026-08-14",
              "scheduled": null,
              "placement": "inserted"
            },
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": "cash",
              "route_label": "cash.md",
              "relative_target": "cash.md",
              "target": "/tmp/bob/cash.md",
              "text": "Second",
              "task_line": "- [ ] #task Second [created::2026-08-14]",
              "kind": "task",
              "created": "2026-08-14",
              "scheduled": null,
              "placement": "inserted"
            }
          ]
        }
        """
    }
}
