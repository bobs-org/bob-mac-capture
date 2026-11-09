import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureRecordPanelTests: XCTestCase {
    private let incompleteDraft = "Ramen Nagi @eat/"
    private let completeDraft = "Ramen Nagi @eat/\n- status:: liked\n- category:: Ramen\n- location:: Clark"

    private func fakeBobPath() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func makeModel(
        parseFixture: String,
        completionFixture: String,
        draft: String,
        recordPath: URL,
        completionDelay: String? = nil
    ) -> CapturePanelModel {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_PARSE_FIXTURE": parseFixture,
            "FAKE_BOB_CAPTURE_COMPLETE_FIXTURE": completionFixture,
            "FAKE_BOB_RECORD_PATH": recordPath.path,
        ]
        if let completionDelay {
            environment["FAKE_BOB_CAPTURE_COMPLETE_DELAY_SECONDS"] = completionDelay
        }
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: fakeBobPath(),
            environment: environment
        )
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        return model
    }

    private func recordLog(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () -> Bool
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

    private func recordURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeHostedTextView(_ text: String) -> (NSTextView, NSPanel) {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let textView = NSTextView(frame: .zero)
        textView.isEditable = true
        textView.allowsUndo = true
        textView.string = text
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return (textView, window)
    }

    private func mutationCaptureCalls(in log: String) -> [String] {
        log.split(separator: "\n").map(String.init).filter { line in
            line.hasPrefix("argv=capture --") && !line.contains("--dry-run")
        }
    }

    func testTabAcceptsBobSuggestionAndRunsItsNextMissingContinuation() async {
        let logURL = recordURL()
        let model = makeModel(
            parseFixture: "record-parse-incomplete.json",
            completionFixture: "record-complete-next-missing-first.json",
            draft: incompleteDraft,
            recordPath: logURL
        )

        await waitUntil { model.recordCompletionListVisible }
        XCTAssertTrue(model.recordCardActive)
        XCTAssertEqual(model.selectedCompletionIndex, 0)

        model.recordTab()

        XCTAssertEqual(model.plainDraft, "Ramen Nagi @eat/\n- status:: to_try")
        await waitUntil { self.recordLog(logURL).contains("--next-missing-field") }
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)
    }

    func testNamedFieldEditUsesBobsExactTextWithoutSubmitting() async {
        let logURL = recordURL()
        let (textView, window) = makeHostedTextView(incompleteDraft)
        defer { window.close() }
        let model = makeModel(
            parseFixture: "record-parse-incomplete.json",
            completionFixture: "record-complete-named-status.json",
            draft: incompleteDraft,
            recordPath: logURL
        )
        model.applyNativeRewriteEdit = { edit in
            CapturePanelController.applyNativeRewriteToDraftEditor(
                edit,
                panel: window,
                cachedEditor: textView
            )
        }

        await waitUntil { model.recordAssistAvailable }
        XCTAssertTrue(model.requestRecordField("status"))
        await waitUntil { model.recordEditAvailable }
        XCTAssertTrue(recordLog(logURL).contains("--record-field status"))

        XCTAssertTrue(model.editRecordField())
        XCTAssertEqual(model.plainDraft, "Ramen Nagi @eat/\n- status:: ")
        XCTAssertEqual(textView.string, "Ramen Nagi @eat/\n- status:: ")
        XCTAssertFalse(model.isSubmitting)
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, incompleteDraft)
        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "Ramen Nagi @eat/\n- status:: ")
    }

    func testReturnBlocksOnLaterIncompleteRecordInMixedDraft() async {
        let logURL = recordURL()
        let draft = "Ramen Nagi @eat/\n- status:: liked\n- category:: Ramen\n- location:: Clark\n\nRamen Nagi @eat/"
        let model = makeModel(
            parseFixture: "record-parse-mixed-incomplete.json",
            completionFixture: "record-complete-empty-value.json",
            draft: draft,
            recordPath: logURL
        )

        await waitUntil { model.recordAssistAvailable }
        model.recordReturn()
        await waitUntil { self.recordLog(logURL).contains("--record-field status") }

        XCTAssertEqual(model.statusText, "Needs Status")
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)
    }

    func testValidRecordReturnRunsOneAggregateCapture() async {
        let logURL = recordURL()
        let model = makeModel(
            parseFixture: "record-parse-complete.json",
            completionFixture: "record-complete-empty-value.json",
            draft: completeDraft,
            recordPath: logURL
        )

        await waitUntil { model.recordAssistAvailable }
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)

        model.recordReturn()

        await waitUntil { model.lastSuccess != nil }
        let calls = mutationCaptureCalls(in: recordLog(logURL))
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testLateNamedResponseCannotReopenDismissedRecordCard() async {
        let logURL = recordURL()
        let model = makeModel(
            parseFixture: "record-parse-incomplete.json",
            completionFixture: "record-complete-named-status.json",
            draft: incompleteDraft,
            recordPath: logURL,
            completionDelay: "0.2"
        )

        await waitUntil { model.recordCompletionListVisible }
        XCTAssertTrue(model.requestRecordField("status"))
        model.dismissRecordCard()
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertFalse(model.recordCardActive)
        XCTAssertFalse(model.completionVisible)
        XCTAssertEqual(model.plainDraft, incompleteDraft)
    }

    func testMoreDisclosureRevealsHiddenOptionalFieldsWithoutSubmitting() async throws {
        let logURL = recordURL()
        let model = makeModel(
            parseFixture: "record-parse-incomplete.json",
            completionFixture: "record-complete-next-missing-first.json",
            draft: incompleteDraft,
            recordPath: logURL
        )

        await waitUntil { model.recordAssistAvailable }
        let before = try XCTUnwrap(model.recordPresentation)
        XCTAssertTrue(before.hiddenOptionalRows.contains(where: { $0.key == "url" }))
        XCTAssertFalse(before.displayedRows.contains(where: { $0.key == "url" }))
        XCTAssertEqual(before.moreLabel, "More (visited, url)")

        model.setRecordMoreExpanded(true)
        let expanded = try XCTUnwrap(model.recordPresentation)
        XCTAssertTrue(expanded.showsMore)
        XCTAssertTrue(expanded.displayedRows.contains(where: { $0.key == "url" }))
        XCTAssertTrue(expanded.displayedRows.contains(where: { $0.key == "visited" }))
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)

        model.setRecordMoreExpanded(false)
        let collapsed = try XCTUnwrap(model.recordPresentation)
        XCTAssertFalse(collapsed.showsMore)
        XCTAssertFalse(collapsed.displayedRows.contains(where: { $0.key == "url" }))
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)
    }

    private func makeAssistModel(draft: String, recordPath: URL) -> CapturePanelModel {
        let model = CapturePanelModel()
        model.processClient = BobProcessClient(
            executablePath: fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_ASSIST": "1",
                "FAKE_BOB_RECORD_PATH": recordPath.path,
            ]
        )
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        return model
    }

    func testAssistChainAcceptsStatusCategoryLocationThenSubmitsOnce() async {
        let logURL = recordURL()
        let model = makeAssistModel(draft: incompleteDraft, recordPath: logURL)

        await waitUntil { model.recordShowsGenericCompletionFallback }
        XCTAssertFalse(model.recordCompletionListVisible)
        XCTAssertEqual(model.plainDraft, incompleteDraft)

        model.recordTab()
        await waitUntil {
            model.recordCompletionListVisible
                && model.completionResponse?.record?.field == "status"
        }
        XCTAssertEqual(model.plainDraft, incompleteDraft)
        XCTAssertFalse(model.plainDraft.contains("burger_joint"))

        model.selectNextCompletion()
        XCTAssertEqual(model.selectedCompletion?.recordValue, "liked")
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "Ramen Nagi @eat/\n- status:: liked")

        await waitUntil {
            model.recordCompletionListVisible
                && model.completionResponse?.record?.field == "category"
        }
        XCTAssertEqual(model.selectedCompletion?.recordValue, "Ramen")
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(
            model.plainDraft,
            "Ramen Nagi @eat/\n- status:: liked\n- category:: Ramen"
        )

        await waitUntil {
            model.recordCompletionListVisible
                && model.completionResponse?.record?.field == "location"
        }
        XCTAssertEqual(model.selectedCompletion?.recordValue, "Clark")
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, completeDraft)

        await waitUntil {
            model.latestParse?.record?.missing.isEmpty == true
                && !model.recordCompletionListVisible
        }
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)

        model.recordReturn()
        await waitUntil { model.lastSuccess != nil }
        XCTAssertEqual(mutationCaptureCalls(in: recordLog(logURL)).count, 1)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testFieldNameMenuAcceptsBobsInsertionAndShiftTabStaysAtFirstMissing() async {
        let logURL = recordURL()
        let fieldDraft = "Ramen Nagi @eat/\n- "
        let model = makeAssistModel(draft: fieldDraft, recordPath: logURL)

        await waitUntil {
            model.recordCompletionListVisible
                && model.completionResponse?.context == "record_field"
        }
        XCTAssertEqual(model.selectedCompletionIndex, 0)
        XCTAssertEqual(model.selectedCompletion?.key, "status")
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "Ramen Nagi @eat/\n- status:: ")
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)

        await waitUntil { model.recordAssistAvailable }
        model.recordShiftTab()
        await waitUntil {
            model.completionResponse?.record?.field == "status"
                || model.recordCompletionListVisible
        }
        XCTAssertTrue(model.plainDraft.hasPrefix("Ramen Nagi @eat/"))
        XCTAssertFalse(model.plainDraft.contains("@eat/burger_joint"))
    }

    func testSevenValueSuggestionsKeepTheSelectedRowVisibleAndAccepted() async {
        let logURL = recordURL()
        let draft = "Ramen Nagi @eat/\n- status:: liked\n- category:: "
        let model = makeAssistModel(draft: draft, recordPath: logURL)

        await waitUntil {
            model.recordCompletionListVisible
                && (model.completionResponse?.candidates.count ?? 0) >= 7
        }
        XCTAssertEqual(model.completionResponse?.record?.field, "category")
        for _ in 0..<6 {
            model.selectNextCompletion()
        }
        XCTAssertEqual(model.selectedCompletionIndex, 6)
        XCTAssertEqual(model.selectedCompletion?.recordValue, "Tacos")
        XCTAssertEqual(model.selectedCompletion?.display, "Tacos")
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(
            model.plainDraft,
            "Ramen Nagi @eat/\n- status:: liked\n- category:: Tacos"
        )
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)
    }

    func testCreateRouteTargetFallbackTabKeepsCreateIntentAndReturnUpdates() async {
        let logURL = recordURL()
        let model = makeAssistModel(draft: incompleteDraft, recordPath: logURL)

        await waitUntil { model.recordShowsGenericCompletionFallback }
        XCTAssertTrue(model.completionVisible)
        XCTAssertFalse(model.recordCompletionListVisible)
        XCTAssertEqual(model.completionResponse?.context, "record_target")

        model.recordTab()
        await waitUntil {
            model.recordCompletionListVisible
                && model.completionResponse?.context == "record_value"
        }
        XCTAssertEqual(model.plainDraft, incompleteDraft)
        XCTAssertFalse(model.plainDraft.contains("burger_joint"))
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)

        let acceptURL = recordURL()
        let accepting = makeAssistModel(draft: incompleteDraft, recordPath: acceptURL)
        await waitUntil { accepting.recordShowsGenericCompletionFallback }
        XCTAssertEqual(accepting.selectedCompletion?.title, "Burger Joint")
        XCTAssertTrue(accepting.acceptSelectedCompletion())
        XCTAssertTrue(accepting.plainDraft.contains("@eat/burger_joint"))
        XCTAssertNotEqual(accepting.plainDraft, incompleteDraft)
    }

    func testCurrentValueNamedEditKeepsTypedSpellingWithoutSubmitting() async {
        let logURL = recordURL()
        let (textView, window) = makeHostedTextView(completeDraft)
        defer { window.close() }
        let model = makeAssistModel(draft: completeDraft, recordPath: logURL)
        model.applyNativeRewriteEdit = { edit in
            CapturePanelController.applyNativeRewriteToDraftEditor(
                edit,
                panel: window,
                cachedEditor: textView
            )
        }

        await waitUntil { model.recordAssistAvailable }
        XCTAssertTrue(model.requestRecordField("status"))
        await waitUntil { model.recordEditAvailable }
        XCTAssertEqual(model.completionResponse?.record?.edit?.replacement, "liked")
        XCTAssertTrue(model.editRecordField())
        XCTAssertEqual(model.plainDraft, completeDraft)
        XCTAssertEqual(textView.string, completeDraft)
        XCTAssertFalse(model.isSubmitting)
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)
    }

    func testEscapeDismissesCompletionThenRecordCard() async {
        let logURL = recordURL()
        let model = makeAssistModel(draft: incompleteDraft, recordPath: logURL)

        await waitUntil { model.recordShowsGenericCompletionFallback }
        XCTAssertTrue(model.completionVisible)
        XCTAssertTrue(model.recordCardActive)

        model.dismissCompletion()
        XCTAssertFalse(model.completionVisible)
        XCTAssertFalse(model.recordShowsGenericCompletionFallback)
        XCTAssertTrue(model.recordCardActive)
        XCTAssertEqual(model.plainDraft, incompleteDraft)

        model.dismissRecordCard()
        XCTAssertFalse(model.recordCardActive)
        XCTAssertEqual(model.plainDraft, incompleteDraft)
        XCTAssertTrue(mutationCaptureCalls(in: recordLog(logURL)).isEmpty)
    }

    func testOldBobWithoutAssistVersionLeavesTheRecordCardInactive() async {
        let logURL = recordURL()
        let model = makeModel(
            parseFixture: "record-parse-old-bob.json",
            completionFixture: "record-complete-old-bob.json",
            draft: incompleteDraft,
            recordPath: logURL
        )

        await waitUntil { model.latestParse != nil }
        XCTAssertFalse(model.recordAssistAvailable)
        XCTAssertFalse(model.recordCardActive)
        XCTAssertFalse(model.recordCompletionListVisible)
        XCTAssertFalse(model.recordShowsGenericCompletionFallback)
    }
}
