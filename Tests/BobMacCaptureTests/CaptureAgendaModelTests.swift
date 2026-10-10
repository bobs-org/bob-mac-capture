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
        agendaFixture: String? = nil
    ) throws -> CapturePanelModel {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        if let agendaFixture {
            environment["FAKE_BOB_AGENDA_FIXTURE"] = agendaFixture
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

    func testAgendaVisibleWhenPlanReady() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaStore?.snapshot != nil }
        model.refreshAgendaPlan(today: "2026-08-28")
        XCTAssertNotNil(model.agendaPlan)
        XCTAssertTrue(model.agendaVisible)
    }

    func testAgendaHiddenWhenSettingOff() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaStore?.snapshot != nil }
        model.refreshAgendaPlan(today: "2026-08-28")
        XCTAssertTrue(model.agendaVisible)
        model.agendaEnabled = false
        XCTAssertNil(model.agendaPlan)
        XCTAssertFalse(model.agendaVisible)
    }

    func testAgendaHiddenWithDraftPreviewRegionOrNoPlan() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaStore?.snapshot != nil }
        model.refreshAgendaPlan(today: "2026-08-28")
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
        bare.refreshAgendaPlan(today: "2026-08-28")
        XCTAssertNil(bare.agendaPlan)
        XCTAssertFalse(bare.agendaVisible)
    }

    func testExpansionPinsTaskAndResetsOnHide() async throws {
        let model = try refreshModel()
        await waitUntil { model.agendaStore?.snapshot != nil }
        model.agendaBudget = 100
        model.refreshAgendaPlan(today: "2026-08-28")
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
        await waitUntil { model.agendaStore?.snapshot != nil }
        model.agendaBudget = 100
        model.refreshAgendaPlan(today: "2026-08-28")
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
        var fired = false
        model.agendaPlanDidChange = {
            fired = true
        }
        model.refreshAgendaPlan(today: "2026-08-28")
        XCTAssertTrue(fired)
    }
}
