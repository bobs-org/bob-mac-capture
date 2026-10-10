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
        agendaEnvironment: [String: String] = [:]
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
        let model = CapturePanelModel()
        model.agendaStore = store
        store.refresh(reason: .show)
        return model
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
        guard let task = model.agendaPresentation?.groups.first?.tasks.first else {
            XCTFail("expected a task in the default fixture")
            return
        }
        var fired = false
        model.agendaPlanDidChange = {
            fired = true
        }
        model.expandAgendaUnit(task.id)
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
}
