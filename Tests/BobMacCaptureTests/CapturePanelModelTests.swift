import CaptureCore
import Combine
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

    func testGlobalPreviewShowsSharedScopeSummary() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "@@foo\nFirst task\n\nSecond task"

        model.preview()
        await waitUntil { !model.isPreviewing }

        XCTAssertEqual(model.previewGlobalDestination?.scopeSummary, "foo.md")
        XCTAssertEqual(model.previewResults.map(\.text), ["First task", "Second task"])
        XCTAssertTrue(model.statusText.contains("All items \u{2192} foo.md"))
        XCTAssertTrue(model.destinationSummary?.contains("All items \u{2192} foo.md") == true)
        XCTAssertFalse(model.destinationSummary?.contains("@@") == true)
    }

    func testGlobalSubmitKeepsOverrideSummaryAndUniqueTargets() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.plainDraft = "@@foo\nFirst task\n\nSecond task @bar"
        var openedPaths: [String] = []
        model.targetOpener = { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let path = components?.queryItems?.first { $0.name == "path" }?.value
            openedPaths.append(path ?? "")
        }

        model.submit(openAfterCapture: true)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(model.lastSuccessGlobalDestination?.scopeSummary, "foo.md")
        XCTAssertEqual(model.lastSuccessResults.map(\.relativeTarget), ["foo.md", "bar.md"])
        XCTAssertTrue(model.statusText.contains("1 local override"))
        XCTAssertTrue(model.destinationSummary?.contains("1 local override") == true)
        XCTAssertEqual(openedPaths, ["/tmp/bob/foo.md", "/tmp/bob/bar.md"])
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

    func testSuccessfulBatchSubmitAndOpenStoresAllResultsAndOpensUniqueTargetsInSourceOrder() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": """
                {"ok":true,"dry_run":false,"routed":true,"route":"work","route_label":"work.md",
                 "relative_target":"work.md","target":"/tmp/bob/work.md",
                 "text":"Ship release","task_line":"- [ ] #task Ship release [created::2026-08-14]",
                 "kind":"task","created":"2026-08-14","scheduled":null,"placement":"inserted",
                 "captures":[
                   {"ok":true,"dry_run":false,"routed":true,"route":"work","route_label":"work.md",
                    "relative_target":"work.md","target":"/tmp/bob/work.md",
                    "text":"Ship release","task_line":"- [ ] #task Ship release [created::2026-08-14]",
                    "kind":"task","created":"2026-08-14","scheduled":null,"placement":"inserted"},
                   {"ok":true,"dry_run":false,"routed":true,"route":"ideas","route_label":"ideas.md",
                    "relative_target":"ideas.md","target":"/tmp/bob/ideas.md",
                    "text":"Capture follow-up","task_line":"- Capture follow-up",
                    "kind":"bullet","created":"2026-08-14","scheduled":null,"placement":"append"},
                   {"ok":true,"dry_run":false,"routed":true,"route":"work","route_label":"work.md",
                    "relative_target":"work.md","target":"/tmp/bob/work.md",
                    "text":"Backfill notes","task_line":"- Backfill notes",
                    "kind":"bullet","created":"2026-08-14","scheduled":null,"placement":"append"}
                 ]}
                """,
            ]
        )
        model.plainDraft = "Ship release @work\n\nCapture follow-up @ideas\n\nBackfill notes @work"
        var openedPaths: [String] = []
        model.targetOpener = { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let path = components?.queryItems?.first { $0.name == "path" }?.value
            openedPaths.append(path ?? "")
        }

        model.submit(openAfterCapture: true)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(openedPaths, ["/tmp/bob/work.md", "/tmp/bob/ideas.md"])
        XCTAssertEqual(model.statusText, "Captured 3 items")
        XCTAssertEqual(model.lastSuccessResults.map(\.text), [
            "Ship release",
            "Capture follow-up",
            "Backfill notes",
        ])
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

    func testClearCanceledDraftStashFromPickerClearsAllEntriesAndKeepsPanelAndEditorIntact() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        stash.push("older private draft @Cash")
        stash.push("newer private draft @Cash")
        model.presentStashPicker()
        model.selectedStashIndex = 1
        model.errorMessage = nil
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }
        let tick = model.statusAnnouncementTick
        let focusSequence = model.focusRequest.sequence

        model.clearCanceledDraftStashFromPicker()

        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(stash.capacity, 10)
        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertEqual(model.selectedStashIndex, 0)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(model.statusText, "Canceled draft stash cleared")
        XCTAssertEqual(model.statusAnnouncementTick, tick + 1)
        XCTAssertFalse(model.statusText.contains("private draft"))
        XCTAssertEqual(dismissCount, 0)
        XCTAssertEqual(model.focusRequest.target, .editor)
        XCTAssertGreaterThan(model.focusRequest.sequence, focusSequence)
    }

    func testClearCanceledDraftStashFromPickerIgnoresNonPickerCalls() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        stash.push("retained")

        model.clearCanceledDraftStashFromPicker()

        XCTAssertEqual(stash.entries.map(\.text), ["retained"])
        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertEqual(model.statusText, "")
    }

    func testStashPickerDoesNotOpenWhileTaskIDPromptIsVisible() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        stash.push("retained")
        installMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()
        let promptFocusSequence = model.focusRequest.sequence

        model.presentStashPicker()

        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertNotNil(model.taskIDPrompt)
        XCTAssertEqual(model.statusText, "Finish or cancel the block ID prompt before opening stash")
        XCTAssertEqual(model.focusRequest.target, .taskIDPromptBlockID)
        XCTAssertGreaterThan(model.focusRequest.sequence, promptFocusSequence)
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

    func testRestoreStashEntryPersistsRemainingEntriesInStoreOrder() throws {
        let store = RecordingCanceledDraftStashStore()
        let stash = CanceledDraftStash(capacity: 10, store: store)
        let oldest = try XCTUnwrap(stash.push("oldest @Cash"))
        _ = try XCTUnwrap(stash.push("middle @Cash"))
        let newest = try XCTUnwrap(stash.push("newest @Cash"))
        let model = CapturePanelModel(canceledDraftStash: stash)
        model.presentStashPicker()

        model.restoreStashEntry(id: newest.id)

        XCTAssertEqual(model.plainDraft, "newest @Cash")
        XCTAssertEqual(stash.entries.map(\.text), ["middle @Cash", "oldest @Cash"])
        XCTAssertEqual(store.snapshots.last?.map(\.text), ["middle @Cash", "oldest @Cash"])
        XCTAssertEqual(store.snapshots.last?.map(\.id), stash.entries.map(\.id))
        XCTAssertEqual(stash.entries.last?.id, oldest.id)
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

    func testBareAtAtRewriteTriggerAppliesDraftAndAnnouncesSummary() async throws {
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
        model.plainDraft = "Buy milk @dev @@"

        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil {
            model.plainDraft == "Buy milk @@dev"
                && model.statusText == "Moved @dev into @@dev"
        }

        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), "Buy milk @@dev".utf8.count)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 16 --format json -- Buy milk @dev @@"))
    }

    func testBareAtAtRewriteDropsStaleResponse() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2",
            ]
        )

        model.plainDraft = "Buy milk @dev @@"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        model.plainDraft = "Buy milk @dev @@ and keep typing"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)

        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(model.plainDraft, "Buy milk @dev @@ and keep typing")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 16 --format json -- Buy milk @dev @@"))
    }

    func testBareAtAtRewriteNoticeDoesNotMutateDraft() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        let draft = "note @notes#Ideas @@"
        model.plainDraft = draft

        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.statusText.contains("@@ cannot take a section") }

        XCTAssertEqual(model.plainDraft, draft)
    }

    func testSingleAtAndTripleAtDoNotTriggerRewrite() async throws {
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

        model.plainDraft = "Buy milk @dev @"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil {
            ((try? String(contentsOf: recordURL)) ?? "").contains("argv=capture-parse")
        }

        model.plainDraft = "Buy milk @dev @@@"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil {
            ((try? String(contentsOf: recordURL)) ?? "").contains("Buy milk @dev @@@")
        }

        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("capture-rewrite"))
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
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 11 --format json -- prefix [[AI suffix"))
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
        installTargetCache(
            on: model,
            targets: [
                CaptureTarget(
                    route: "mac_inbox",
                    name: "mac_inbox",
                    label: "mac_inbox.md",
                    kind: "inbox",
                    relativePath: "mac_inbox.md"
                ),
            ]
        )
        model.plainDraft = "idea @ma^new-id"

        model.editorTextDidChange(cursorUTF8Offset: "idea @ma".utf8.count)
        await waitUntil { self.analysisSettled(for: model, recordURL: recordURL, draft: "idea @ma^new-id") }

        XCTAssertEqual(model.completionResponse?.context, "route")
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 6, end: 8))
        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "mac_inbox")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- idea @ma^new-id"))
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- idea @ma^new-id"))
        XCTAssertFalse(record.contains("capture-complete"))
    }

    func testOrdinaryRouteSpanUsesCachedRouteCompletionWithoutBobComplete() async throws {
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
        installTargetCache(
            on: model,
            targets: [
                CaptureTarget(
                    route: "mac_inbox",
                    name: "mac_inbox",
                    label: "mac_inbox.md",
                    kind: "inbox",
                    relativePath: "mac_inbox.md"
                ),
            ]
        )
        model.plainDraft = "idea @ma"

        model.editorTextDidChange(cursorUTF8Offset: "idea @ma".utf8.count)
        await waitUntil { self.analysisSettled(for: model, recordURL: recordURL, draft: "idea @ma") }

        XCTAssertEqual(model.completionResponse?.context, "route")
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 6, end: 8))
        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "mac_inbox")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- idea @ma"))
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- idea @ma"))
        XCTAssertFalse(record.contains("capture-complete"))
    }

    func testGlobalRouteSpanUsesCachedRouteCompletionWithoutBobComplete() async throws {
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
        installTargetCache(
            on: model,
            targets: [
                CaptureTarget(
                    route: "mac_inbox",
                    name: "mac_inbox",
                    label: "mac_inbox.md",
                    kind: "inbox",
                    relativePath: "mac_inbox.md"
                ),
            ]
        )
        let draft = "@@ma\nFirst task"
        model.plainDraft = draft

        model.editorTextDidChange(cursorUTF8Offset: "@@ma".utf8.count)
        await waitUntil { self.analysisSettled(for: model, recordURL: recordURL, draft: draft) }

        XCTAssertEqual(model.completionResponse?.context, "route")
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 2, end: 4))
        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "mac_inbox")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- \(draft)"))
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- \(draft)"))
        XCTAssertFalse(record.contains("capture-complete"))
    }

    func testGlobalSubBulletTaskCompletionAndMissingIDPromptUseHeaderRange() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        let draft = "@@file+\nFirst note"
        model.plainDraft = draft

        model.editorTextDidChange(cursorUTF8Offset: "@@file+".utf8.count)
        await waitUntil { model.completionResponse?.context == "task" }

        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 7, end: 7))
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()

        XCTAssertEqual(model.taskIDPrompt?.draftSnapshot, draft)
        XCTAssertEqual(model.taskIDPrompt?.replacementRange, CaptureRange(start: 7, end: 7))

        model.updateTaskIDPromptBlockID("new-id")
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt == nil }

        XCTAssertEqual(model.plainDraft, "@@file+new-id\nFirst note")
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
        installTargetCache(
            on: model,
            targets: [
                CaptureTarget(
                    route: "file",
                    name: "file",
                    label: "file.md",
                    kind: "area",
                    relativePath: "file.md"
                ),
            ]
        )

        model.plainDraft = "Add context @file+parent-id"
        model.editorTextDidChange(cursorUTF8Offset: "Add context @file".utf8.count)
        await waitUntil { self.analysisSettled(for: model, recordURL: recordURL, draft: "Add context @file+parent-id") }
        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "file")
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 13, end: 17))

        model.plainDraft = "Follow up @file^new-id"
        model.editorTextDidChange(cursorUTF8Offset: "Follow up @file".utf8.count)
        await waitUntil { self.analysisSettled(for: model, recordURL: recordURL, draft: "Follow up @file^new-id") }
        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "file")
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 11, end: 15))

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- Add context @file+parent-id"))
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- Add context @file+parent-id"))
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- Follow up @file^new-id"))
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- Follow up @file^new-id"))
        XCTAssertFalse(record.contains("capture-complete"))
    }

    func testRouteCompletionFallsBackToBobWhenCacheHasNoMatch() async throws {
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
        installTargetCache(
            on: model,
            targets: [
                CaptureTarget(
                    route: "today",
                    name: "today",
                    label: "today.md",
                    kind: "inbox",
                    relativePath: "today.md"
                ),
            ]
        )
        model.plainDraft = "idea @ma"

        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil { model.completionResponse?.context == "route" }

        XCTAssertEqual(model.completionResponse?.candidates.first?.route, "mac_inbox")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 8 --format json -- idea @ma"))
    }

    func testInteractivePlaceholderCompletionUsesBobEvenWithMatchingCache() async throws {
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
        installTargetCache(
            on: model,
            targets: [
                CaptureTarget(
                    route: "cash",
                    name: "cash",
                    label: "cash.md",
                    kind: "area",
                    relativePath: "cash.md"
                ),
            ]
        )
        model.plainDraft = "Call bank @Cash+"

        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        await waitUntil {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return record.contains("argv=capture-complete --all-tasks --cursor 16 --format json -- Call bank @Cash+")
        }

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- Call bank @Cash+"))
        XCTAssertTrue(
            record.contains("argv=capture-complete --all-tasks --cursor 16 --format json -- Call bank @Cash+")
        )
    }

    func testPlusRightSideOffersTasksAndCaretAuthoredIdShowsNoPicker() async throws {
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
        installTargetCache(
            on: model,
            targets: [
                CaptureTarget(
                    route: "cash",
                    name: "cash",
                    label: "cash.md",
                    kind: "area",
                    relativePath: "cash.md"
                ),
            ]
        )

        model.plainDraft = "note @Cash+goog"
        model.editorTextDidChange(cursorUTF8Offset: "note @Cash+goog".utf8.count)
        await waitUntil { model.completionResponse?.context == "task" }
        XCTAssertEqual(model.completionResponse?.candidates.first?.blockID, "goog-exit")
        XCTAssertTrue(model.completionVisible)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 15 --format json -- note @Cash+goog"))

        model.plainDraft = "Do work @Dev^new-id"
        model.editorTextDidChange(cursorUTF8Offset: "Do work @Dev^new-id".utf8.count)
        await waitUntil {
            model.plainDraft == "Do work @Dev^new-id" && model.completionResponse == nil
        }
        XCTAssertFalse(model.completionVisible)
    }

    func testHashAfterResolvedSubBulletOpensTaskSectionCompletion() async throws {
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
        let draft = "Postgres 17 minimum @foo+bar#"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_section" }

        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 29, end: 29))
        XCTAssertEqual(model.completionResponse?.candidates.first?.replacement, "requirements")
        XCTAssertEqual(model.completionResponse?.candidates.first?.title, "REQUIREMENTS")
        XCTAssertEqual(model.completionResponse?.candidates.first?.text, "Parent task")
        XCTAssertEqual(model.completionResponse?.candidates.first?.blockID, "bar")
        XCTAssertEqual(model.completionResponse?.candidates.first?.childCount, 2)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains(
                "argv=capture-complete --all-tasks --cursor 29 --format json -- Postgres 17 minimum @foo+bar#"
            )
        )
    }

    func testTypedSubBulletSectionKeepsTaskSectionCompletionOpen() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        let draft = "Postgres 17 minimum @foo+bar#req"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_section" }

        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 29, end: 32))
        XCTAssertEqual(model.completionResponse?.candidates.first?.replacement, "requirements")
    }

    func testBareTrailingHashDoesNotOpenTaskSectionCompletion() async throws {
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
        let draft = "jot idea #"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil {
            guard case .ready = model.previewState else {
                return false
            }
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return record.contains("argv=capture-parse --format json -- jot idea #")
                && record.contains("argv=capture --dry-run --no-clip --format json -- jot idea #")
        }
        // Live preview is recorded before the completion request, so wait long
        // enough that a task-section complete would have been invoked.
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(model.completionResponse)
        XCTAssertFalse(model.completionVisible)
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("capture-complete"))
    }

    func testNoteBulletHashStillOpensSectionCompletion() async throws {
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
        let draft = "jot idea @foo#"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "section" }

        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(model.completionResponse?.candidates.first?.title, "Ideas")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains(
                "argv=capture-complete --all-tasks --cursor 14 --format json -- jot idea @foo#"
            )
        )
    }

    func testAcceptingTaskSectionCandidateInsertsSlugAndLandsCaret() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        let draft = "Postgres 17 minimum @foo+bar#"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_section" }

        model.acceptSelectedCompletion()

        let accepted = "Postgres 17 minimum @foo+bar#requirements"
        XCTAssertEqual(model.plainDraft, accepted)
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), accepted.utf8.count)
        XCTAssertNil(model.completionResponse)
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.taskIDPrompt)
    }

    func testMissingTaskCompletionOpensTaskIDPromptWithoutChangingDraft() {
        let model = CapturePanelModel()
        installMissingTaskCompletion(on: model)
        let initialFocusSequence = model.focusRequest.sequence

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, "note @Cash+goog")
        XCTAssertFalse(model.completionVisible)
        XCTAssertEqual(model.taskIDPrompt?.candidate.text, "Plan the handoff")
        XCTAssertEqual(model.taskIDPrompt?.candidate.route, "cash")
        XCTAssertEqual(model.taskIDPrompt?.candidate.taskRef, "8:missingidea")
        XCTAssertEqual(model.taskIDPrompt?.draftSnapshot, "note @Cash+goog")
        XCTAssertEqual(model.taskIDPrompt?.replacementRange, CaptureRange(start: 11, end: 15))
        XCTAssertEqual(model.statusText, "Add block ID")
        XCTAssertEqual(model.focusRequest.target, .taskIDPromptBlockID)
        XCTAssertGreaterThan(model.focusRequest.sequence, initialFocusSequence)
        XCTAssertTrue(model.editorInputLocked)
    }

    func testTaskIDPromptLocksEditorInPresentingTurn() async {
        let model = CapturePanelModel()
        installMissingTaskCompletion(on: model)

        model.acceptSelectedCompletion()

        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertEqual(model.focusRequest.target, .taskIDPromptBlockID)
        XCTAssertTrue(model.editorInputLocked)

        await Task.yield()

        XCTAssertTrue(model.editorInputLocked)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertEqual(model.focusRequest.target, .taskIDPromptBlockID)
    }

    func testCancelTaskIDPromptUnlocksEditorImmediately() async {
        let model = CapturePanelModel()
        installMissingTaskCompletion(on: model)

        model.acceptSelectedCompletion()
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.editorInputLocked)
        model.cancelTaskIDPrompt()

        XCTAssertNil(model.taskIDPrompt)
        XCTAssertFalse(model.editorInputLocked)
        XCTAssertEqual(model.focusRequest.target, .editor)

        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(model.taskIDPrompt)
        XCTAssertFalse(model.editorInputLocked)
        XCTAssertEqual(model.focusRequest.target, .editor)
    }

    func testPrepareForDismissalClearsTaskIDPromptAndEditorInputLock() async {
        let model = CapturePanelModel()
        installMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()
        XCTAssertTrue(model.editorInputLocked)

        model.prepareForDismissal()

        XCTAssertNil(model.taskIDPrompt)
        XCTAssertFalse(model.editorInputLocked)
    }

    func testLaterBatchTaskIDPromptSuccessSplicesGlobalRangeAndKeepsCaptureContract() async throws {
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
        let draft = laterTaskBatchDraft()
        let assignedDraft = laterTaskIDBatchDraft()
        let draftSuffix = "File follow-up @file+hand"
        let assignedSuffix = "File follow-up @file+new-id"

        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil {
            model.completionResponse?.context == "task"
                && model.completionResponse?.candidates.count == 2
        }
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 39, end: 43))
        XCTAssertEqual(model.plainDraft, draft)

        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()
        XCTAssertEqual(model.plainDraft, draft)
        XCTAssertEqual(model.taskIDPrompt?.draftSnapshot, draft)
        XCTAssertEqual(model.taskIDPrompt?.replacementRange, CaptureRange(start: 39, end: 43))
        XCTAssertEqual(model.taskIDPrompt?.candidate.text, "Plan the handoff")

        model.updateTaskIDPromptBlockID("new-id")
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt == nil && model.plainDraft == assignedDraft }

        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), assignedDraft.utf8.count)
        XCTAssertNil(model.completionResponse)
        XCTAssertFalse(model.editorInputLocked)
        await waitUntil {
            guard case .ready(let preview) = model.previewState else {
                return false
            }
            return preview.normalizedCaptures.map(\.text) == ["Plan café", "File follow-up"]
        }
        guard case .ready(let livePreview) = model.previewState else {
            return XCTFail("Expected ready live preview")
        }
        XCTAssertEqual(livePreview.normalizedCaptures.map(\.kind), ["task", "sub_bullet"])

        var record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-complete --all-tasks --cursor 43 --format json -- ")
        )
        XCTAssertTrue(record.contains(draftSuffix))
        XCTAssertEqual(
            record.components(
                separatedBy: "argv=capture-task-id --route file --task-ref 8:missingidea --block-id new-id --format json"
            ).count - 1,
            1
        )
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- "))
        XCTAssertTrue(
            record.contains("argv=capture --dry-run --no-clip --format json -- ")
        )
        XCTAssertTrue(record.contains(assignedSuffix))

        model.preview()
        await waitUntil { !model.isPreviewing }
        XCTAssertEqual(model.previewResults.map(\.text), ["Plan café", "File follow-up"])

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(model.lastSuccessResults.map(\.text), ["Plan café", "File follow-up"])

        record = try String(contentsOf: recordURL)
        XCTAssertEqual(
            record.components(separatedBy: "argv=capture --format json --dry-run -- ").count - 1,
            1
        )
        XCTAssertEqual(
            record.components(separatedBy: "argv=capture --format json -- ").count - 1,
            1
        )
        XCTAssertTrue(record.contains(assignedSuffix))
    }

    func testTaskIDPromptRejectsInvalidLocalBlockIDWithoutCallingBob() throws {
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
        installMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()
        let promptFocusSequence = model.focusRequest.sequence

        model.updateTaskIDPromptBlockID("bad_id")
        model.submitTaskIDPrompt()

        XCTAssertEqual(model.plainDraft, "note @Cash+goog")
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "bad_id")
        XCTAssertEqual(model.taskIDPrompt?.errorMessage, "Use only letters, numbers, and hyphens.")
        XCTAssertEqual(model.focusRequest.target, .taskIDPromptBlockID)
        XCTAssertGreaterThan(model.focusRequest.sequence, promptFocusSequence)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testTaskIDPromptSuccessSplicesReturnedIDAfterBobConfirms() async throws {
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
        installMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()
        var focusEvents: [(target: CapturePanelFocusTarget, draft: String, cursor: Int?)] = []
        let focusCancellable = model.$focusRequest.dropFirst().sink { request in
            focusEvents.append(
                (
                    target: request.target,
                    draft: model.plainDraft,
                    cursor: model.collapsedSelectionUTF8Offset()
                )
            )
        }

        model.updateTaskIDPromptBlockID("new-id")
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt == nil && model.plainDraft == "note @Cash+new-id" }

        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), "note @Cash+new-id".utf8.count)
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(focusEvents.last?.target, .editor)
        XCTAssertEqual(focusEvents.last?.draft, "note @Cash+new-id")
        XCTAssertEqual(focusEvents.last?.cursor, "note @Cash+new-id".utf8.count)
        XCTAssertFalse(model.editorInputLocked)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-task-id --route cash --task-ref 8:missingidea --block-id new-id --format json")
        )
        withExtendedLifetime(focusCancellable) {}
    }

    func testTaskIDPromptServerFailureRetainsDraftTaskAndAuthoredID() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":false,"error":"block ID ^duplicate-id already exists in cash.md"}"#,
                "FAKE_BOB_EXIT": "1",
            ]
        )
        installMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()
        XCTAssertTrue(model.editorInputLocked)
        let promptFocusSequence = model.focusRequest.sequence

        model.updateTaskIDPromptBlockID("duplicate-id")
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt?.isSaving == false }

        XCTAssertEqual(model.plainDraft, "note @Cash+goog")
        XCTAssertEqual(model.taskIDPrompt?.candidate.text, "Plan the handoff")
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "duplicate-id")
        XCTAssertEqual(model.taskIDPrompt?.errorMessage, "block ID ^duplicate-id already exists in cash.md")
        XCTAssertEqual(model.statusText, "Add block ID failed")
        XCTAssertEqual(model.focusRequest.target, .taskIDPromptBlockID)
        XCTAssertGreaterThan(model.focusRequest.sequence, promptFocusSequence)
        XCTAssertTrue(model.editorInputLocked)
        XCTAssertNotNil(model.taskIDPrompt)
    }

    func testLaterBatchTaskIDPromptServerFailureRetainsEntireDraftAndSelection() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":false,"error":"block ID ^duplicate-id already exists in file.md"}"#,
                "FAKE_BOB_EXIT": "1",
            ]
        )
        installLaterTaskBatchMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()

        model.updateTaskIDPromptBlockID("duplicate-id")
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt?.isSaving == false }

        XCTAssertEqual(model.plainDraft, laterTaskBatchDraft())
        XCTAssertEqual(model.taskIDPrompt?.candidate.text, "Plan the handoff")
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "duplicate-id")
        XCTAssertEqual(model.taskIDPrompt?.replacementRange, CaptureRange(start: 39, end: 43))
        XCTAssertEqual(model.taskIDPrompt?.errorMessage, "block ID ^duplicate-id already exists in file.md")
        XCTAssertEqual(model.statusText, "Add block ID failed")
    }

    func testLaterBatchTaskIDPromptTransportFailureRetainsEntireDraftAndSelection() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_EXIT": "64",
            ]
        )
        installLaterTaskBatchMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()

        model.updateTaskIDPromptBlockID("new-id")
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt?.isSaving == false }

        XCTAssertEqual(model.plainDraft, laterTaskBatchDraft())
        XCTAssertEqual(model.taskIDPrompt?.candidate.text, "Plan the handoff")
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "new-id")
        XCTAssertEqual(model.taskIDPrompt?.replacementRange, CaptureRange(start: 39, end: 43))
        XCTAssertTrue(model.taskIDPrompt?.errorMessage?.contains("bob command failed (exit 64)") == true)
        XCTAssertEqual(model.statusText, "Add block ID failed")
    }

    func testCancelTaskIDPromptRestoresChooserSelectionWithoutMutation() {
        let model = CapturePanelModel()
        installMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()
        model.updateTaskIDPromptBlockID("new-id")
        let promptFocusSequence = model.focusRequest.sequence

        model.cancelTaskIDPrompt()

        XCTAssertNil(model.taskIDPrompt)
        XCTAssertEqual(model.plainDraft, "note @Cash+goog")
        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(model.selectedCompletionIndex, 1)
        XCTAssertEqual(model.completionResponse?.candidates[1].text, "Plan the handoff")
        XCTAssertEqual(model.focusRequest.target, .editor)
        XCTAssertGreaterThan(model.focusRequest.sequence, promptFocusSequence)
    }

    func testLaterBatchCancelTaskIDPromptRestoresChooserSelectionWithoutMutation() {
        let model = CapturePanelModel()
        installLaterTaskBatchMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()
        model.updateTaskIDPromptBlockID("new-id")

        model.cancelTaskIDPrompt()

        XCTAssertNil(model.taskIDPrompt)
        XCTAssertEqual(model.plainDraft, laterTaskBatchDraft())
        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(model.selectedCompletionIndex, 1)
        XCTAssertEqual(model.completionResponse?.replacement, CaptureRange(start: 39, end: 43))
        XCTAssertEqual(model.completionResponse?.candidates[1].text, "Plan the handoff")
    }

    func testLaterBatchTaskIDPromptStaleRangeRetainsDraftAndSelectionWithoutCallingBob() throws {
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
        let draft = laterTaskBatchDraft()
        model.plainDraft = draft
        model.taskIDPrompt = CaptureTaskIDPromptState(
            candidate: laterTaskBatchMissingCandidate(),
            draftSnapshot: draft,
            replacementRange: CaptureRange(start: 200, end: 204),
            selectedCompletionIndex: 1,
            authoredID: "new-id",
            isSaving: false,
            errorMessage: nil
        )

        model.submitTaskIDPrompt()

        XCTAssertEqual(model.plainDraft, draft)
        XCTAssertEqual(model.taskIDPrompt?.candidate.text, "Plan the handoff")
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "new-id")
        XCTAssertEqual(
            model.taskIDPrompt?.errorMessage,
            "Completion range is stale. Return to the task list and choose again."
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testCanceledTaskIDPromptIgnoresLateAssignmentResponse() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_DELAY_SECONDS": "0.2",
            ]
        )
        installMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()
        model.updateTaskIDPromptBlockID("new-id")

        model.submitTaskIDPrompt()
        XCTAssertEqual(model.taskIDPrompt?.isSaving, true)
        model.cancelTaskIDPrompt()
        let canceledFocusRequest = model.focusRequest
        try await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertNil(model.taskIDPrompt)
        XCTAssertEqual(model.plainDraft, "note @Cash+goog")
        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(model.focusRequest, canceledFocusRequest)
    }

    func testAcceptingSelectablePomodoroNameSplicesSlug() {
        let model = CapturePanelModel()
        installPomodoroNameCompletion(on: model, query: "")

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, pomodoroNameDraft(query: "memory"))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), pomodoroNameDraft(query: "memory").utf8.count)
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.pomodoroNamePrompt)
    }

    func testAcceptingPomodoroCreationPreservesCanonicalMarkerWithoutNaming() async throws {
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
        installPomodoroCreationCompletion(on: model, query: "fut", replacement: "future", name: "FUTURE")
        let initialFocusSequence = model.focusRequest.sequence

        model.acceptSelectedCompletion()

        let accepted = pomodoroNameDraft(query: "future")
        XCTAssertEqual(model.plainDraft, accepted)
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), accepted.utf8.count)
        XCTAssertNil(model.completionResponse)
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.pomodoroNamePrompt)
        XCTAssertNil(model.taskIDPrompt)
        XCTAssertFalse(model.editorInputLocked)
        XCTAssertEqual(model.focusRequest.target, .editor)
        XCTAssertGreaterThan(model.focusRequest.sequence, initialFocusSequence)
        XCTAssertEqual(model.statusText, "FUTURE will be created when captured")
        await waitUntil {
            if case .ready = model.previewState {
                return true
            }
            return false
        }
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("capture-pomodoro-name"))
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- "))
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- "))
        XCTAssertTrue(record.contains(accepted))
    }

    func testAcceptingPomodoroCreationUsesGlobalRangeOnLaterNonASCIIItem() async throws {
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
        let draft = laterPomodoroCreationDraft(query: "fut")
        let accepted = laterPomodoroCreationDraft(query: "future")
        let marker = "@sase:some-id#"
        let prefix = String(draft[..<draft.range(of: marker)!.upperBound])
        installPomodoroCreationCompletion(
            on: model,
            draft: draft,
            replacementStart: prefix.utf8.count,
            replacement: "future",
            name: "FUTURE"
        )

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, accepted)
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), accepted.utf8.count)
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.pomodoroNamePrompt)
        XCTAssertEqual(model.statusText, "FUTURE will be created when captured")
        await waitUntil {
            if case .ready = model.previewState {
                return true
            }
            return false
        }
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("capture-pomodoro-name"))
        XCTAssertTrue(record.contains(accepted))
    }

    func testAcceptingNameableRowAfterCreationCandidateStillOpensNamePrompt() {
        let model = CapturePanelModel()
        installPomodoroCreationCompletion(on: model, query: "fut", replacement: "future", name: "FUTURE")
        model.selectedCompletionIndex = 1
        let initialFocusSequence = model.focusRequest.sequence

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, pomodoroNameDraft(query: "fut"))
        XCTAssertFalse(model.completionVisible)
        XCTAssertEqual(model.pomodoroNamePrompt?.candidate.taskRef, "38:0b1c2d3e")
        XCTAssertEqual(model.pomodoroNamePrompt?.authoredName, "FUT")
        XCTAssertEqual(model.statusText, "Name Pomodoro")
        XCTAssertEqual(model.focusRequest.target, .pomodoroNamePromptName)
        XCTAssertGreaterThan(model.focusRequest.sequence, initialFocusSequence)
        XCTAssertTrue(model.editorInputLocked)
        XCTAssertNil(model.taskIDPrompt)
    }

    func testAcceptingNameablePomodoroOpensPromptWithoutChangingDraft() {
        let model = CapturePanelModel()
        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        let initialFocusSequence = model.focusRequest.sequence

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, pomodoroNameDraft(query: ""))
        XCTAssertFalse(model.completionVisible)
        XCTAssertEqual(model.pomodoroNamePrompt?.candidate.taskRef, "38:0b1c2d3e")
        XCTAssertEqual(model.pomodoroNamePrompt?.authoredName, "")
        XCTAssertEqual(model.pomodoroNamePrompt?.draftSnapshot, pomodoroNameDraft(query: ""))
        XCTAssertEqual(model.pomodoroNamePrompt?.replacementRange, CaptureRange(start: 26, end: 26))
        XCTAssertEqual(model.statusText, "Name Pomodoro")
        XCTAssertEqual(model.focusRequest.target, .pomodoroNamePromptName)
        XCTAssertGreaterThan(model.focusRequest.sequence, initialFocusSequence)
        XCTAssertTrue(model.editorInputLocked)
        XCTAssertNil(model.taskIDPrompt)
    }

    func testPomodoroNamePromptPrefillsFromHyphenatedQuery() {
        let model = CapturePanelModel()
        installPomodoroNameCompletion(on: model, query: "deep-work")
        model.selectedCompletionIndex = 1

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.pomodoroNamePrompt?.authoredName, "DEEP WORK")
        XCTAssertEqual(model.plainDraft, pomodoroNameDraft(query: "deep-work"))
        XCTAssertEqual(model.pomodoroNamePromptCanonicalName, "DEEP WORK")
        XCTAssertTrue(model.pomodoroNamePromptCanSubmit)
    }

    func testDraftChangeWhilePomodoroNamePromptIsOpenCancelsIt() {
        let model = CapturePanelModel()
        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()
        XCTAssertNotNil(model.pomodoroNamePrompt)

        model.plainDraft = "changed draft"
        model.editorTextDidChange()

        XCTAssertNil(model.pomodoroNamePrompt)
        XCTAssertFalse(model.editorInputLocked)
        XCTAssertEqual(model.focusRequest.target, .editor)
        XCTAssertEqual(model.plainDraft, "changed draft")
    }

    func testPomodoroNamePromptSuccessSplicesReturnedSlugAndRestoresEditorFocus() async throws {
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
        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()
        model.updatePomodoroNamePromptName("DEEP WORK")
        var focusEvents: [(target: CapturePanelFocusTarget, draft: String, cursor: Int?)] = []
        let focusCancellable = model.$focusRequest.dropFirst().sink { request in
            focusEvents.append(
                (
                    target: request.target,
                    draft: model.plainDraft,
                    cursor: model.collapsedSelectionUTF8Offset()
                )
            )
        }

        model.submitPomodoroNamePrompt()
        let namedDraft = pomodoroNameDraft(query: "deep-work")
        await waitUntil { model.pomodoroNamePrompt == nil && model.plainDraft == namedDraft }

        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), namedDraft.utf8.count)
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(focusEvents.last?.target, .editor)
        XCTAssertEqual(focusEvents.last?.draft, namedDraft)
        XCTAssertFalse(model.editorInputLocked)
        XCTAssertEqual(model.statusText, "Named DEEP WORK in 2026/20260828.md")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains(
                "argv=capture-pomodoro-name --pomodoro-ref 38:0b1c2d3e --name DEEP WORK --format json"
            )
        )
        withExtendedLifetime(focusCancellable) {}
    }

    func testPomodoroNamePromptServerFailureRetainsDraftAndAuthoredName() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":false,"error":"Pomodoro 38:0b1c2d3e already has a selectable name"}"#,
                "FAKE_BOB_EXIT": "1",
            ]
        )
        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()
        let promptFocusSequence = model.focusRequest.sequence

        model.updatePomodoroNamePromptName("DEEP WORK")
        model.submitPomodoroNamePrompt()
        await waitUntil { model.pomodoroNamePrompt?.isSaving == false }

        XCTAssertEqual(model.plainDraft, pomodoroNameDraft(query: ""))
        XCTAssertEqual(model.pomodoroNamePrompt?.authoredName, "DEEP WORK")
        XCTAssertEqual(
            model.pomodoroNamePrompt?.errorMessage,
            "Pomodoro 38:0b1c2d3e already has a selectable name"
        )
        XCTAssertEqual(model.statusText, "Name Pomodoro failed")
        XCTAssertEqual(model.focusRequest.target, .pomodoroNamePromptName)
        XCTAssertGreaterThan(model.focusRequest.sequence, promptFocusSequence)
        XCTAssertTrue(model.editorInputLocked)
        XCTAssertNotNil(model.pomodoroNamePrompt)
    }

    func testPomodoroNamePromptTransportFailureRetainsDraft() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_EXIT": "64",
            ]
        )
        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()

        model.updatePomodoroNamePromptName("DEEP WORK")
        model.submitPomodoroNamePrompt()
        await waitUntil { model.pomodoroNamePrompt?.isSaving == false }

        XCTAssertEqual(model.plainDraft, pomodoroNameDraft(query: ""))
        XCTAssertEqual(model.pomodoroNamePrompt?.authoredName, "DEEP WORK")
        XCTAssertTrue(model.pomodoroNamePrompt?.errorMessage?.contains("bob command failed (exit 64)") == true)
        XCTAssertEqual(model.statusText, "Name Pomodoro failed")
    }

    func testPomodoroNamePromptRejectsInvalidNameWithoutCallingBob() throws {
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
        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()
        let promptFocusSequence = model.focusRequest.sequence

        model.updatePomodoroNamePromptName("snake_case")
        model.submitPomodoroNamePrompt()

        XCTAssertEqual(model.plainDraft, pomodoroNameDraft(query: ""))
        XCTAssertEqual(model.pomodoroNamePrompt?.authoredName, "snake_case")
        XCTAssertEqual(
            model.pomodoroNamePrompt?.errorMessage,
            "Use only letters, numbers, spaces, and & ' ( ) , . / -."
        )
        XCTAssertEqual(model.focusRequest.target, .pomodoroNamePromptName)
        XCTAssertGreaterThan(model.focusRequest.sequence, promptFocusSequence)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testCancelPomodoroNamePromptRestoresChooserSelectionWithoutMutation() {
        let model = CapturePanelModel()
        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()
        model.updatePomodoroNamePromptName("DEEP WORK")
        let promptFocusSequence = model.focusRequest.sequence

        model.cancelPomodoroNamePrompt()

        XCTAssertNil(model.pomodoroNamePrompt)
        XCTAssertEqual(model.plainDraft, pomodoroNameDraft(query: ""))
        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(model.selectedCompletionIndex, 1)
        XCTAssertEqual(model.completionResponse?.candidates[1].requiresName, true)
        XCTAssertEqual(model.focusRequest.target, .editor)
        XCTAssertGreaterThan(model.focusRequest.sequence, promptFocusSequence)
    }

    func testCanceledPomodoroNamePromptIgnoresLateAssignmentResponse() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_DELAY_SECONDS": "0.2",
            ]
        )
        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()
        model.updatePomodoroNamePromptName("DEEP WORK")

        model.submitPomodoroNamePrompt()
        XCTAssertEqual(model.pomodoroNamePrompt?.isSaving, true)
        model.cancelPomodoroNamePrompt()
        let canceledFocusRequest = model.focusRequest
        try await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertNil(model.pomodoroNamePrompt)
        XCTAssertEqual(model.plainDraft, pomodoroNameDraft(query: ""))
        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(model.focusRequest, canceledFocusRequest)
    }

    func testPomodoroNameAndTaskIDPromptsAreMutuallyExclusive() {
        let model = CapturePanelModel()
        installMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()
        XCTAssertNotNil(model.taskIDPrompt)
        XCTAssertNil(model.pomodoroNamePrompt)

        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()

        XCTAssertNil(model.taskIDPrompt)
        XCTAssertNotNil(model.pomodoroNamePrompt)
        XCTAssertTrue(model.editorInputLocked)
        XCTAssertEqual(model.focusRequest.target, .pomodoroNamePromptName)

        installMissingTaskCompletion(on: model)
        model.acceptSelectedCompletion()

        XCTAssertNotNil(model.taskIDPrompt)
        XCTAssertNil(model.pomodoroNamePrompt)
        XCTAssertEqual(model.focusRequest.target, .taskIDPromptBlockID)
    }

    func testStashPickerDoesNotOpenWhilePomodoroNamePromptIsVisible() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        stash.push("retained")
        installPomodoroNameCompletion(on: model, query: "")
        model.selectedCompletionIndex = 1
        model.acceptSelectedCompletion()
        let promptFocusSequence = model.focusRequest.sequence

        model.presentStashPicker()

        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertNotNil(model.pomodoroNamePrompt)
        XCTAssertEqual(model.statusText, "Finish or cancel the Pomodoro name prompt before opening stash")
        XCTAssertEqual(model.focusRequest.target, .pomodoroNamePromptName)
        XCTAssertGreaterThan(model.focusRequest.sequence, promptFocusSequence)
    }

    func testLaterBatchCaptureFailureAfterTaskIDAssignmentReportsNoPartialSuccessOrDraftClearing() async throws {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":false,"error":"capture item 2 starting on line 3: duplicate block ID"}"#,
                "FAKE_BOB_EXIT": "1",
            ]
        )
        let assignedDraft = laterTaskIDBatchDraft()
        var dismissCount = 0
        model.panelDismisser = { dismissCount += 1 }
        model.plainDraft = assignedDraft

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(model.plainDraft, assignedDraft)
        XCTAssertNil(model.lastSuccess)
        XCTAssertTrue(model.lastSuccessResults.isEmpty)
        XCTAssertEqual(model.errorMessage, "capture item 2 starting on line 3: duplicate block ID")
        XCTAssertEqual(model.statusText, "Capture failed")
        XCTAssertEqual(dismissCount, 0)
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
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 9 --format json -- prefix [[AI suffix"))
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

    private func analysisSettled(
        for model: CapturePanelModel,
        recordURL: URL,
        draft: String
    ) -> Bool {
        guard model.plainDraft == draft,
              model.completionResponse?.context == "route",
              case .ready = model.previewState
        else {
            return false
        }

        let record = (try? String(contentsOf: recordURL)) ?? ""
        return record.contains("argv=capture-parse --format json -- \(draft)")
            && record.contains("argv=capture --dry-run --no-clip --format json -- \(draft)")
    }

    private func installTargetCache(
        on model: CapturePanelModel,
        targets: [CaptureTarget]
    ) {
        model.updateTargetCacheSnapshot(
            CaptureTargetsSnapshot(
                targets: CaptureTargetsResponse(ok: true, targets: targets),
                refreshedAt: Date(),
                stale: false,
                errorDescription: nil
            )
        )
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

    private func installMissingTaskCompletion(on model: CapturePanelModel) {
        model.plainDraft = "note @Cash+goog"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 15,
            replacement: CaptureRange(start: 11, end: 15),
            context: "task",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "goog-exit",
                    route: "cash",
                    taskRef: "4:googexit",
                    blockID: "goog-exit",
                    requiresBlockID: false,
                    statusSymbol: "*",
                    statusName: "Next",
                    statusType: "ON_HOLD",
                    text: "Finish Google Exit Packet!",
                    section: "Tasks",
                    depth: 1,
                    childCount: 1
                ),
                CaptureCompletionCandidate(
                    replacement: "",
                    route: "cash",
                    taskRef: "8:missingidea",
                    blockID: nil,
                    requiresBlockID: true,
                    statusSymbol: " ",
                    statusName: "Todo",
                    statusType: "TODO",
                    text: "Plan the handoff",
                    section: "Tasks",
                    depth: 1,
                    childCount: 0
                ),
            ]
        )
        model.selectedCompletionIndex = 1
    }

    private func installLaterTaskBatchMissingTaskCompletion(on model: CapturePanelModel) {
        model.plainDraft = laterTaskBatchDraft()
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 43,
            replacement: CaptureRange(start: 39, end: 43),
            context: "task",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "hand-ready",
                    route: "file",
                    taskRef: "4:handready",
                    blockID: "hand-ready",
                    requiresBlockID: false,
                    statusSymbol: "*",
                    statusName: "Next",
                    statusType: "ON_HOLD",
                    text: "Handoff ready",
                    section: "Tasks",
                    depth: 1,
                    childCount: 0
                ),
                laterTaskBatchMissingCandidate(),
            ]
        )
        model.selectedCompletionIndex = 1
    }

    private func laterTaskBatchMissingCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            route: "file",
            taskRef: "8:missingidea",
            blockID: nil,
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Plan the handoff",
            section: "Tasks",
            depth: 1,
            childCount: 0
        )
    }

    private func laterTaskBatchDraft() -> String {
        "Plan café @Cash\n\nFile follow-up @file+hand"
    }

    private func pomodoroNameDraft(query: String) -> String {
        "Fix startup @sase:some-id#\(query)"
    }

    private func laterPomodoroCreationDraft(query: String) -> String {
        "Plan café @Cash\n\nFix startup @sase:some-id#\(query)"
    }

    private func installPomodoroCreationCompletion(
        on model: CapturePanelModel,
        query: String,
        replacement: String,
        name: String
    ) {
        let draft = pomodoroNameDraft(query: query)
        let start = pomodoroNameDraft(query: "").utf8.count
        installPomodoroCreationCompletion(
            on: model,
            draft: draft,
            replacementStart: start,
            replacement: replacement,
            name: name
        )
    }

    private func installPomodoroCreationCompletion(
        on model: CapturePanelModel,
        draft: String,
        replacementStart: Int,
        replacement: String,
        name: String
    ) {
        let end = draft.utf8.count
        model.plainDraft = draft
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: end,
            replacement: CaptureRange(start: replacementStart, end: end),
            context: "pomodoro_name",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: replacement,
                    childCount: 0,
                    name: name,
                    requiresName: false,
                    placeholder: true,
                    createsPomodoro: true
                ),
                CaptureCompletionCandidate(
                    replacement: "",
                    taskRef: "38:0b1c2d3e",
                    statusSymbol: " ",
                    childCount: 0,
                    name: nil,
                    requiresName: true,
                    line: 38,
                    state: "open",
                    timeRange: nil,
                    placeholder: true,
                    isCurrent: false,
                    matchCount: 1
                ),
            ]
        )
        model.selectedCompletionIndex = 0
    }

    private func installPomodoroNameCompletion(on model: CapturePanelModel, query: String) {
        let draft = pomodoroNameDraft(query: query)
        let start = pomodoroNameDraft(query: "").utf8.count
        let end = draft.utf8.count
        model.plainDraft = draft
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: end,
            replacement: CaptureRange(start: start, end: end),
            context: "pomodoro_name",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "memory",
                    taskRef: "31:1a2b3c4d",
                    statusSymbol: " ",
                    childCount: 5,
                    name: "MEMORY",
                    requiresName: false,
                    line: 31,
                    state: "open",
                    timeRange: "1205-1230",
                    placeholder: false,
                    isCurrent: true,
                    matchCount: 2
                ),
                CaptureCompletionCandidate(
                    replacement: "",
                    taskRef: "38:0b1c2d3e",
                    statusSymbol: " ",
                    childCount: 0,
                    name: nil,
                    requiresName: true,
                    line: 38,
                    state: "open",
                    timeRange: nil,
                    placeholder: true,
                    isCurrent: false,
                    matchCount: 1
                ),
            ]
        )
        model.selectedCompletionIndex = 0
    }

    private func laterTaskIDBatchDraft() -> String {
        "Plan café @Cash\n\nFile follow-up @file+new-id"
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
