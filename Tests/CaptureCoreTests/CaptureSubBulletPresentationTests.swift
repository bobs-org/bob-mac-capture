import XCTest

@testable import CaptureCore

/// Wording coverage for sub-bullet items whose parent renders as a
/// batch-level task card: the compact header detail, the parent label
/// for status and summary strings, and the accessibility phrase.
/// Fixture provenance is documented on `CaptureModelTests`.
final class CaptureSubBulletPresentationTests: XCTestCase {
    private func successFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(
            contentsOf: fixtures.appendingPathComponent(name),
            encoding: .utf8
        )
        let decoded = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(text.utf8)
        )
        guard case .success(let success) = decoded else {
            throw SubBulletPresentationFixtureError.expectedSuccess
        }
        return success
    }

    private func subBullet(
        blockID: String? = "capture",
        parentSection: String? = nil,
        kind: String = "sub_bullet"
    ) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: true,
            route: "sase",
            routeLabel: "sase.md",
            relativeTarget: "sase.md",
            target: "/tmp/vault/sase.md",
            text: "note",
            taskLine: "- note",
            kind: kind,
            created: "2026-10-02",
            placement: "appended",
            blockID: blockID,
            parentSection: parentSection
        )
    }

    func testPlainSubBulletNamesItsParent() throws {
        let success = try successFixture("sub-bullet-task-block.json")
        let presented = try XCTUnwrap(CaptureSubBulletPresentation(capture: success))

        XCTAssertEqual(presented.parentLabel, "^capture")
        XCTAssertEqual(presented.headerDetail, "under ^capture")
        XCTAssertEqual(presented.accessibilityText, "Sub-bullet under ^capture")
    }

    func testSectionSubBulletNamesItsSection() throws {
        let success = try successFixture("sub-bullet-section-task-block.json")
        let presented = try XCTUnwrap(CaptureSubBulletPresentation(capture: success))

        XCTAssertEqual(presented.parentLabel, "^bar")
        XCTAssertEqual(presented.headerDetail, "under ^bar › REQUIREMENTS")
        XCTAssertEqual(
            presented.accessibilityText,
            "Sub-bullet under ^bar, in REQUIREMENTS"
        )
    }

    func testRealBobDrawerCaptureNamesTheDrawerFromTheLegacyMirror() throws {
        let existing = try XCTUnwrap(
            CaptureSubBulletPresentation(
                capture: try successFixture("drawer-capture-existing.json")))
        XCTAssertEqual(existing.drawerTitle, "REQUIREMENTS")
        XCTAssertFalse(existing.createsDrawer)
        XCTAssertEqual(existing.headerDetail, "under ^bar › REQUIREMENTS")

        // This Bob names a created drawer only through `parent_section`, so no
        // capsule appears until it sends the `drawer` object.
        let created = try XCTUnwrap(
            CaptureSubBulletPresentation(
                capture: try successFixture("drawer-capture-new.json")))
        XCTAssertEqual(created.drawerTitle, "PERF BUDGET")
        XCTAssertFalse(created.createsDrawer)
    }

    func testNewDrawerObjectAddsTheCapsuleAndTheRetypeRowTravelsWithIt() throws {
        let success = try successFixture("drawer-contract-capture-new-retype.json")
        let presented = try XCTUnwrap(CaptureSubBulletPresentation(capture: success))

        XCTAssertEqual(presented.drawerTitle, "PERF BUDGET")
        XCTAssertTrue(presented.createsDrawer)
        XCTAssertEqual(presented.headerDetail, "under ^bar › PERF BUDGET")
        XCTAssertEqual(CaptureSubBulletPresentation.newDrawerBadge, "new drawer")
        XCTAssertEqual(
            presented.accessibilityText,
            "Sub-bullet under ^bar, in new drawer PERF BUDGET"
        )
        // The same item carries the `Type` row the preview renders beneath the header.
        let change = try XCTUnwrap(success.taskTheme)
        XCTAssertEqual(change.action, "set")
        XCTAssertEqual(change.theme?.name, "FIX")
        XCTAssertNotNil(CaptureTaskThemePresentation.line(for: change, isDryRun: success.dryRun))
    }

    func testDrawerObjectWinsOverTheLegacyMirror() {
        let success = CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: true,
            route: "foo",
            routeLabel: "foo.md",
            relativeTarget: "foo.md",
            target: "/tmp/vault/foo.md",
            text: "note",
            taskLine: "- note",
            kind: "sub_bullet",
            created: "2026-10-30",
            placement: "inserted",
            blockID: "bar",
            parentSection: "OLD NAME",
            drawer: CaptureDrawerSummary(title: "Q&A", key: "Q&A", created: true)
        )
        let presented = CaptureSubBulletPresentation(capture: success)

        XCTAssertEqual(presented?.drawerTitle, "Q&A")
        XCTAssertEqual(presented?.createsDrawer, true)
    }

    func testParentWithoutBlockIDFallsBackToTask() throws {
        let presented = try XCTUnwrap(
            CaptureSubBulletPresentation(capture: subBullet(blockID: nil))
        )

        XCTAssertEqual(presented.parentLabel, "task")
        XCTAssertEqual(presented.headerDetail, "under task")
        XCTAssertEqual(presented.accessibilityText, "Sub-bullet under task")
    }

    func testOtherKindsYieldNil() throws {
        for kind in ["task", "pomodoro_start", "task_toggle", "sub-bullet-x"] {
            XCTAssertNil(
                CaptureSubBulletPresentation(capture: subBullet(kind: kind)),
                "kind \(kind) is not a sub-bullet"
            )
        }
    }
}

private enum SubBulletPresentationFixtureError: Error {
    case expectedSuccess
}
