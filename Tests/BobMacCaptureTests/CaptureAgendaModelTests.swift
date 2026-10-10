import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Model wiring for the idle agenda: the visibility conditions, the
/// settle-while-hidden hook, expansion pinning and resets, and the
/// height-cap fold. Drives a real store through fake-bob, exactly as
/// the panel show path does. The agenda fixtures are dated
/// 2026-08-28, so plans pin that day.
@MainActor
final class CaptureAgendaModelTests: XCTestCase {
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

    private func waitUntil(
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail(
                    "Condition not met before timeout",
                    file: file,
                    line: line
                )
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func refreshModel(
        agendaFixture: String? = nil,
        agendaEnvironment: [String: String] = [:],
        debounceNanoseconds: UInt64 = 0
    ) throws -> CapturePanelModel {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        if let agendaFixture {
            environment["FAKE_BOB_AGENDA_FIXTURE"] = agendaFixture
        }
        for (key, value) in agendaEnvironment {
            environment[key] = value
        }
        let store = CaptureAgendaStore(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: environment
            ),
            vaultRootPath: "/tmp",
            today: { "2026-08-28" }
        )
        let model = CapturePanelModel(debounceNanoseconds: debounceNanoseconds)
        model.agendaStore = store
        store.refresh(reason: .show)
        return model
    }

    private func attachCaptureClient(
        _ model: CapturePanelModel,
        environment extra: [String: String] = [:]
    ) throws {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        for (key, value) in extra {
            environment[key] = value
        }
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: environment
        )
    }

    private func readyLiveModel(
        captureEnvironment: [String: String] = [:],
        agendaEnvironment: [String: String] = [:]
    ) async throws -> CapturePanelModel {
        let model = try refreshModel(agendaEnvironment: agendaEnvironment)
        try attachCaptureClient(model, environment: captureEnvironment)
        await waitUntil { model.agendaStore?.snapshot != nil }
        XCTAssertTrue(model.agendaVisible)
        return model
    }

    private func typeDraft(_ model: CapturePanelModel, _ text: String) {
        model.plainDraft = text
        model.editorTextDidChange(cursorUTF8Offset: text.utf8.count)
    }

    private func waitForReadyPreview(_ model: CapturePanelModel) async {
        await waitUntil {
            if case .ready = model.previewState { return true }
            return false
        }
    }

    private func assertIdleAgendaVisible(
        _ model: CapturePanelModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(model.agendaVisible, file: file, line: line)
        XCTAssertFalse(model.agendaDimmed, file: file, line: line)
        XCTAssertEqual(model.previewState, .idle, file: file, line: line)
        XCTAssertNil(model.previewResult, file: file, line: line)
        XCTAssertTrue(model.previewResults.isEmpty, file: file, line: line)
        XCTAssertNil(model.previewGlobalDestination, file: file, line: line)
        XCTAssertNil(model.destinationSummary, file: file, line: line)
        XCTAssertNil(model.errorMessage, file: file, line: line)
        XCTAssertNil(model.errorCode, file: file, line: line)
        XCTAssertNil(model.closePendingText, file: file, line: line)
        XCTAssertFalse(model.isClosePending, file: file, line: line)
        XCTAssertFalse(model.isPreviewing, file: file, line: line)
        XCTAssertNil(model.pickerChip, file: file, line: line)
        XCTAssertFalse(model.pickerVisible, file: file, line: line)
        XCTAssertFalse(model.editorInputLocked, file: file, line: line)
        XCTAssertEqual(model.primaryActionTitle, "Capture", file: file, line: line)
    }

    /// Points the model's store at a new fake-bob and refreshes, so
    /// the model's presentation follows the store's emissions, never
    /// a hand-called re-plan.
    private func swapAgendaClient(
        _ model: CapturePanelModel,
        environment: [String: String]
    ) throws {
        var full = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        for (key, value) in environment {
            full[key] = value
        }
        model.agendaStore?.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: full
        )
        model.agendaStore?.refresh(reason: .show)
    }

    func testAgendaVisibleWhenPlanReady() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaPlan != nil }
        XCTAssertTrue(model.agendaVisible)
    }

    func testAgendaHiddenWhenSettingOff() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaPlan != nil }
        XCTAssertTrue(model.agendaVisible)
        model.agendaEnabled = false
        XCTAssertNil(model.agendaPlan)
        XCTAssertFalse(model.agendaVisible)
    }

    func testAgendaHiddenWithDraftPreviewRegionOrNoPlan() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaPlan != nil }
        XCTAssertTrue(model.agendaVisible)

        model.plainDraft = "068"
        XCTAssertFalse(model.agendaVisible)
        model.plainDraft = ""

        model.previewState = .loading
        XCTAssertFalse(model.agendaVisible)
        model.previewState = .idle

        model.errorMessage = "boom"
        XCTAssertFalse(model.agendaVisible)
        model.errorMessage = nil

        XCTAssertTrue(model.agendaVisible)

        let bare = CapturePanelModel()
        XCTAssertNil(bare.agendaPlan)
        XCTAssertFalse(bare.agendaVisible)
    }

    func testExpansionPinsTaskAndResetsOnHide() async throws {
        let model = try refreshModel()
        // The loading plan publishes synchronously on subscribe, so a
        // `plan != nil` wait passes before the fetch lands: content
        // tests must wait for the store's snapshot instead.
        await waitUntil { model.agendaStore?.snapshot != nil }
        model.agendaBudget = 100
        guard let task = model.agendaPresentation?.groups.first?.tasks.first else {
            XCTFail("expected a task in the default fixture")
            return
        }
        model.expandAgendaUnit(task.id)
        XCTAssertTrue(model.agendaExpanded.contains(task.id))
        XCTAssertEqual(model.agendaPlan?.taskStates[task.id], .full)

        model.prepareForDismissal()
        XCTAssertTrue(model.agendaExpanded.isEmpty)

        model.expandAgendaUnit(task.id)
        model.prepareForRetainedClose()
        XCTAssertTrue(model.agendaExpanded.isEmpty)
    }

    func testTinyBudgetFoldsToOverflow() async throws {
        let model = try refreshModel(agendaFixture: "agenda-heavy.json")
        model.agendaBudget = 100
        await waitUntil { model.agendaPlan?.overflows == true }
        guard let plan = model.agendaPlan else {
            XCTFail("expected a plan for the heavy fixture")
            return
        }
        XCTAssertTrue(plan.overflows)
        XCTAssertGreaterThan(plan.totalHeight, plan.budget)
    }

    func testSettleHookFiresOnPublish() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaStore?.snapshot != nil }
        let first = model.agendaPresentation
        XCTAssertNotNil(first)
        // Expanding an already-full task re-publishes an identical
        // plan, which correctly stays silent: the hook fires only when
        // a new plan publishes. Drive a publish that changes the plan
        // (a new snapshot through the store) instead.
        var fired = false
        model.agendaPlanDidChange = {
            fired = true
        }
        try swapAgendaClient(
            model,
            environment: ["FAKE_BOB_AGENDA_FIXTURE": "agenda-heavy.json"]
        )
        await waitUntil { model.agendaPresentation != first }
        XCTAssertTrue(fired)
    }

    func testPresentationFollowsLatestSnapshot() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaStore?.snapshot != nil }
        let first = model.agendaPresentation
        XCTAssertNotNil(first)
        XCTAssertEqual(model.agendaStore?.snapshot?.pomodoros.count, 4)
        try swapAgendaClient(
            model,
            environment: ["FAKE_BOB_AGENDA_FIXTURE": "agenda-heavy.json"]
        )
        await waitUntil {
            model.agendaStore?.snapshot?.pomodoros.count == 25
        }
        await waitUntil { model.agendaPresentation != first }
        XCTAssertNotNil(model.agendaPlan)
        XCTAssertTrue(model.agendaVisible)
    }

    func testStaleRecoversOnNextSuccess() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaStore?.snapshot != nil }
        XCTAssertEqual(model.agendaPresentation?.isStale, false)
        try swapAgendaClient(
            model,
            environment: ["FAKE_BOB_AGENDA_FAIL": "1"]
        )
        await waitUntil { model.agendaPresentation?.isStale == true }
        // The same bytes come back, so the store takes the
        // `.unchanged` branch; the status emission still re-plans and
        // clears the stale marker.
        try swapAgendaClient(model, environment: [:])
        await waitUntil { model.agendaPresentation?.isStale == false }
        XCTAssertEqual(model.agendaStore?.status, .ready)
        XCTAssertTrue(model.agendaVisible)
    }

    // MARK: - Dim-hold and states (mac-agenda-polish)

    private func readyModel() async throws -> CapturePanelModel {
        let model = try refreshModel()
        await waitUntil { model.agendaStore?.snapshot != nil }
        XCTAssertTrue(model.agendaVisible)
        return model
    }

    private func beginHold(_ model: CapturePanelModel) {
        model.plainDraft = "068"
        model.noteAgendaFirstKeystroke()
        XCTAssertTrue(model.agendaDimmed)
    }

    func testFirstKeystrokeDimsAndKeepsAgendaMounted() async throws {
        let model = try await readyModel()
        beginHold(model)
        // The agenda stays mounted (dimmed) with a non-blank draft.
        XCTAssertTrue(model.agendaVisible)
        model.releaseAgendaHoldForTests(event: .previewSettled)
        XCTAssertFalse(model.agendaDimmed)
        XCTAssertFalse(model.agendaVisible)
    }

    func testHoldReleasesOnEveryPath() async throws {
        let model = try await readyModel()

        beginHold(model)
        model.releaseAgendaHoldForTests(event: .regionTaken)
        XCTAssertFalse(model.agendaDimmed)

        beginHold(model)
        model.noteAgendaDraftCleared()
        XCTAssertFalse(model.agendaDimmed)

        beginHold(model)
        model.noteAgendaStoppedShowing()
        XCTAssertFalse(model.agendaDimmed)

        beginHold(model)
        model.previewState = .failed("preview failed")
        XCTAssertFalse(model.agendaDimmed)
        model.previewState = .idle

        beginHold(model)
        await waitUntil(timeout: 5) { !model.agendaDimmed }
        XCTAssertFalse(model.agendaVisible)
    }

    func testHoldIgnoresKeystrokeWhenAgendaHidden() async throws {
        let model = try await readyModel()
        model.agendaEnabled = false
        model.plainDraft = "068"
        model.noteAgendaFirstKeystroke()
        XCTAssertFalse(model.agendaDimmed)
    }

    func testStaleSnapshotMarksTitleRow() async throws {
        let model = try await readyModel()
        XCTAssertEqual(model.agendaPresentation?.isStale, false)
        try swapAgendaClient(
            model,
            environment: ["FAKE_BOB_AGENDA_FAIL": "1"]
        )
        await waitUntil { model.agendaPresentation?.isStale == true }
        XCTAssertEqual(model.agendaPresentation?.isStale, true)
        XCTAssertTrue(
            model.agendaPresentation?.titleRow.accessoryText?.contains(
                CaptureAgendaPresentation.staleSuffix
            ) == true
        )
        XCTAssertTrue(model.agendaVisible)
        XCTAssertTrue(
            model.agendaStore?.diagnosticLine().hasPrefix("Couldn't refresh") == true
        )
    }

    func testNoSnapshotShowsLoadingLine() async throws {
        let model = try refreshModel(agendaEnvironment: ["FAKE_BOB_AGENDA_FAIL": "1"])
        await waitUntil { model.agendaPresentation?.state == .loading }
        XCTAssertEqual(model.agendaPresentation?.state, .loading)
        XCTAssertEqual(model.agendaPresentation?.stateRow?.text, "Loading today…")
        XCTAssertTrue(model.agendaVisible)
    }

    func testUnsupportedBobHidesAgenda() async throws {
        let model = try refreshModel(
            agendaEnvironment: ["FAKE_BOB_AGENDA_UNSUPPORTED": "1"]
        )
        await waitUntil { model.agendaStore?.status == .unsupported }
        await waitUntil { model.agendaPlan == nil && model.agendaPresentation == nil }
        XCTAssertNil(model.agendaPlan)
        XCTAssertFalse(model.agendaVisible)
        XCTAssertEqual(
            model.agendaStore?.diagnosticLine(),
            "Update bob to show the agenda (needs `capture-pomodoros --tasks`)"
        )
    }

    func testReadyStoreReportsLastRefreshed() async throws {
        let model = try await readyModel()
        XCTAssertTrue(
            model.agendaStore?.diagnosticLine().hasPrefix("Last refreshed") == true
        )
    }

    // MARK: - Restore idle agenda after clearing the draft

    func testClearingSettledStartPreviewRestoresCachedAgendaImmediately() async throws {
        let model = try await readyLiveModel()
        typeDraft(model, "=")
        await waitForReadyPreview(model)
        XCTAssertEqual(model.primaryActionTitle, "Start")
        XCTAssertNotNil(model.destinationSummary)
        XCTAssertFalse(model.agendaVisible)

        typeDraft(model, "")

        assertIdleAgendaVisible(model)
        XCTAssertEqual(model.plainDraft, "")

        typeDraft(model, "=")
        await waitForReadyPreview(model)
        XCTAssertEqual(model.primaryActionTitle, "Start")
        XCTAssertFalse(model.agendaVisible)

        let whitespace = " \n"
        typeDraft(model, whitespace)
        XCTAssertEqual(model.plainDraft, whitespace)
        assertIdleAgendaVisible(model)
    }

    func testClearingFailedPreviewRestoresAgendaAndDropsError() async throws {
        let model = try await readyLiveModel()
        typeDraft(model, "=*abc")
        await waitUntil {
            if case .failed = model.previewState { return true }
            return false
        }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.agendaVisible)

        typeDraft(model, "")

        assertIdleAgendaVisible(model)
    }

    func testClearingPendingClosePreviewRestoresAgendaAndAllowsNextDraft() async throws {
        let model = try await readyLiveModel()
        typeDraft(model, "=x1,")
        await waitUntil { model.closePendingText != nil }
        XCTAssertTrue(model.isClosePending)
        XCTAssertEqual(model.closePendingAction, "Close")
        XCTAssertFalse(model.agendaVisible)

        typeDraft(model, "")
        assertIdleAgendaVisible(model)

        typeDraft(model, "=")
        await waitForReadyPreview(model)
        XCTAssertFalse(model.isClosePending)
        XCTAssertEqual(model.primaryActionTitle, "Start")
        XCTAssertFalse(model.agendaVisible)
    }

    func testClearingDismissedPickerChipRestoresAgendaAndUnlocksEditor() async throws {
        let model = try await readyLiveModel()
        typeDraft(model, "^")
        await waitUntil { model.pickerVisible }
        XCTAssertTrue(model.editorInputLocked)
        XCTAssertFalse(model.agendaVisible)

        model.escapePicker()
        await waitUntil { model.pickerChipVisible }
        XCTAssertFalse(model.pickerVisible)
        XCTAssertFalse(model.editorInputLocked)
        XCTAssertFalse(model.agendaVisible)

        typeDraft(model, "")
        assertIdleAgendaVisible(model)
    }

    func testLateLivePreviewCannotRefillAfterClear() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let termURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try await readyLiveModel(
            captureEnvironment: [
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_TERM_PATH": termURL.path,
                "FAKE_BOB_DELAY_SECONDS": "0.4",
            ]
        )
        typeDraft(model, "=")
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains("argv=") == true
        }

        typeDraft(model, "")
        assertIdleAgendaVisible(model)

        await waitUntil { FileManager.default.fileExists(atPath: termURL.path) }
        assertIdleAgendaVisible(model)
        XCTAssertNil(model.sessionStartPresentation)
    }

    func testLateRewriteCannotMutateClearedDraft() async throws {
        let model = try await readyLiveModel(
            captureEnvironment: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.3"]
        )
        let rewriteDraft = "Buy milk @dev @@"
        typeDraft(model, rewriteDraft)
        XCTAssertEqual(model.plainDraft, rewriteDraft)

        typeDraft(model, "")
        assertIdleAgendaVisible(model)

        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(model.plainDraft, "")
        assertIdleAgendaVisible(model)
    }

    func testLateExplicitPreviewSuccessCannotRefillAfterClear() async throws {
        let model = try await readyLiveModel()
        typeDraft(model, "=")
        await waitForReadyPreview(model)
        XCTAssertEqual(model.primaryActionTitle, "Start")

        try attachCaptureClient(
            model,
            environment: ["FAKE_BOB_DELAY_SECONDS": "0.4"]
        )
        model.preview()
        XCTAssertTrue(model.isPreviewing)

        typeDraft(model, "")
        assertIdleAgendaVisible(model)

        try await Task.sleep(nanoseconds: 550_000_000)
        assertIdleAgendaVisible(model)
        XCTAssertNil(model.sessionStartPresentation)
    }

    func testLateExplicitPreviewFailureCannotRefillAfterClear() async throws {
        let model = try await readyLiveModel()
        typeDraft(model, "=")
        await waitForReadyPreview(model)

        try attachCaptureClient(
            model,
            environment: [
                "FAKE_BOB_DELAY_SECONDS": "0.4",
                "FAKE_BOB_STDOUT": "{",
                "FAKE_BOB_EXIT": "1",
            ]
        )
        model.preview()
        XCTAssertTrue(model.isPreviewing)

        typeDraft(model, "")
        assertIdleAgendaVisible(model)

        try await Task.sleep(nanoseconds: 550_000_000)
        assertIdleAgendaVisible(model)
        XCTAssertNil(model.errorMessage)
    }

    func testClearingKeepsCachedAgendaWhenRefreshIsUnchangedOrStale() async throws {
        let model = try await readyLiveModel()
        let pomodoroCount = model.agendaStore?.snapshot?.pomodoros.count
        typeDraft(model, "=")
        await waitForReadyPreview(model)

        typeDraft(model, "")
        assertIdleAgendaVisible(model)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(model.agendaVisible)
        XCTAssertEqual(model.agendaStore?.snapshot?.pomodoros.count, pomodoroCount)

        try swapAgendaClient(
            model,
            environment: ["FAKE_BOB_AGENDA_FAIL": "1"]
        )
        await waitUntil { model.agendaPresentation?.isStale == true }
        typeDraft(model, "=")
        await waitForReadyPreview(model)
        typeDraft(model, "")
        assertIdleAgendaVisible(model)
        XCTAssertEqual(model.agendaPresentation?.isStale, true)
    }

    func testClearingCleansDraftUIWhenAgendaCannotShow() async throws {
        let disabled = try await readyLiveModel()
        disabled.agendaEnabled = false
        XCTAssertFalse(disabled.agendaVisible)
        typeDraft(disabled, "=")
        await waitForReadyPreview(disabled)
        XCTAssertEqual(disabled.primaryActionTitle, "Start")
        typeDraft(disabled, "")
        XCTAssertFalse(disabled.agendaVisible)
        XCTAssertEqual(disabled.previewState, .idle)
        XCTAssertNil(disabled.previewResult)
        XCTAssertTrue(disabled.previewResults.isEmpty)
        XCTAssertNil(disabled.destinationSummary)
        XCTAssertNil(disabled.errorMessage)
        XCTAssertEqual(disabled.primaryActionTitle, "Capture")

        let unsupported = try refreshModel(
            agendaEnvironment: ["FAKE_BOB_AGENDA_UNSUPPORTED": "1"]
        )
        try attachCaptureClient(unsupported)
        await waitUntil { unsupported.agendaStore?.status == .unsupported }
        await waitUntil { unsupported.agendaPlan == nil }
        XCTAssertFalse(unsupported.agendaVisible)
        typeDraft(unsupported, "=")
        await waitForReadyPreview(unsupported)
        typeDraft(unsupported, "")
        XCTAssertFalse(unsupported.agendaVisible)
        XCTAssertEqual(unsupported.previewState, .idle)
        XCTAssertNil(unsupported.previewResult)
        XCTAssertTrue(unsupported.previewResults.isEmpty)
        XCTAssertEqual(unsupported.primaryActionTitle, "Capture")
    }

    func testClearingNeverCapturesAndEmptyReturnIsInert() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try await readyLiveModel(
            captureEnvironment: ["FAKE_BOB_RECORD_PATH": recordURL.path]
        )
        typeDraft(model, "=")
        await waitForReadyPreview(model)

        typeDraft(model, "")
        assertIdleAgendaVisible(model)
        model.submit(openAfterCapture: false)
        XCTAssertFalse(model.isSubmitting)
        assertIdleAgendaVisible(model)

        let record = try String(contentsOf: recordURL)
        let mutating = record.split(whereSeparator: \.isNewline).filter { line in
            line.hasPrefix("argv=capture ") && !line.contains("--dry-run")
        }
        XCTAssertTrue(mutating.isEmpty, record)
    }

    func testClearingDoesNotRetireInFlightSubmit() async throws {
        let model = try await readyLiveModel()
        typeDraft(model, "=")
        await waitForReadyPreview(model)

        try attachCaptureClient(
            model,
            environment: ["FAKE_BOB_DELAY_SECONDS": "0.3"]
        )
        var dismissed = 0
        model.panelDismisser = { dismissed += 1 }
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.isSubmitting)

        typeDraft(model, "")
        XCTAssertTrue(model.isSubmitting)

        await waitUntil { !model.isSubmitting }
        XCTAssertNotNil(model.lastSuccess)
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(model.plainDraft, "")
    }
}
