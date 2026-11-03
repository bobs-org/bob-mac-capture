import XCTest

@testable import CaptureCore

/// Unit tests for the muted relation held and uncertainty lines.
/// Copy matches Bob's `relation_successors/copy.rs` held and uncertainty
/// notices (`docs/task-dependencies.md` §12.18, vectors SU-P12–SU-P16,
/// SU-P20–SU-P21). Already-planned rows are JSON-only and never render.
final class CaptureRelationHeldPresentationTests: XCTestCase {
    private func held(
        reason: String,
        text: String = "Write rollout notes",
        label: String = "starts after",
        target: String = "Send implementation prompt",
        waitsOn: [CaptureRelationTarget]? = nil,
        scheduled: String? = nil,
        project: String? = nil,
        waitsFor: [CaptureRelationTarget]? = nil
    ) -> CaptureRelationHeld {
        CaptureRelationHeld(
            notePath: "agents.md",
            blockID: "write",
            text: text,
            statusSymbol: " ",
            statusName: "Ready",
            reason: reason,
            waitsOn: waitsOn,
            scheduled: scheduled,
            project: project,
            waitsFor: waitsFor,
            relation: CaptureRelationMetadata(
                label: label,
                key: label,
                event: "parked",
                after: [CaptureRelationTarget(text: target)]
            )
        )
    }

    func testAlreadyPlannedIsSuppressed() throws {
        XCTAssertNil(CaptureRelationHeldPresentation.heldNotice(for: held(reason: "already_planned")))
        XCTAssertTrue(
            CaptureRelationHeldPresentation.heldNotices(for: [held(reason: "already_planned")]).isEmpty
        )
    }

    func testHeldNoticesCoverEveryReportedReason() throws {
        XCTAssertEqual(
            CaptureRelationHeldPresentation.heldNotice(
                for: held(reason: "already_started", text: "Prepare evaluation prompt")
            ),
            "🪢 “Prepare evaluation prompt” starts after “Send implementation prompt” · not offered: already started"
        )
        XCTAssertEqual(
            CaptureRelationHeldPresentation.heldNotice(
                for: held(
                    reason: "waits_for",
                    waitsFor: [CaptureRelationTarget(text: "Ship schema change")]
                )
            ),
            "🪢 “Write rollout notes” starts after “Send implementation prompt” · not offered: waits for “Ship schema change”"
        )
        XCTAssertEqual(
            CaptureRelationHeldPresentation.heldNotice(
                for: held(
                    reason: "blocked",
                    waitsOn: [
                        CaptureRelationTarget(text: "One"),
                        CaptureRelationTarget(text: "Two"),
                    ]
                )
            ),
            "🪢 “Write rollout notes” starts after “Send implementation prompt” · not offered: blocked (waits on 2)"
        )
        XCTAssertEqual(
            CaptureRelationHeldPresentation.heldNotice(
                for: held(reason: "scheduled", scheduled: "2026-11-03")
            ),
            "🪢 “Write rollout notes” starts after “Send implementation prompt” · not offered: scheduled Nov 3"
        )
        XCTAssertEqual(
            CaptureRelationHeldPresentation.heldNotice(for: held(reason: "project")),
            "🪢 “Write rollout notes” starts after “Send implementation prompt” · not offered: blocked by its project"
        )
        XCTAssertEqual(
            CaptureRelationHeldPresentation.heldNotice(for: held(reason: "hidden")),
            "🪢 “Write rollout notes” starts after “Send implementation prompt” · not offered: hidden"
        )
    }

    func testWaitsForWithSeveralTargetsNamesFirstAndCount() throws {
        XCTAssertEqual(
            CaptureRelationHeldPresentation.heldNotice(
                for: held(
                    reason: "waits_for",
                    waitsFor: [
                        CaptureRelationTarget(text: "Ship schema change"),
                        CaptureRelationTarget(text: "Second"),
                        CaptureRelationTarget(text: "Third"),
                    ]
                )
            ),
            "🪢 “Write rollout notes” starts after “Send implementation prompt” · not offered: waits for “Ship schema change” and 2 more"
        )
    }

    func testEmptyWaitsForCarriesNoNotice() throws {
        XCTAssertNil(
            CaptureRelationHeldPresentation.heldNotice(for: held(reason: "waits_for", waitsFor: []))
        )
    }

    func testUncertaintyNamesSingleLabelOrFallsBackToRelationLinks() throws {
        XCTAssertEqual(
            CaptureRelationHeldPresentation.uncertaintyNotice(
                check: "unavailable",
                held: [held(reason: "hidden")]
            ),
            "🪢 Couldn't check starts after links · nothing offered"
        )
        XCTAssertEqual(
            CaptureRelationHeldPresentation.uncertaintyNotice(
                check: "unavailable",
                held: [held(reason: "hidden"), held(reason: "hidden", label: "blocked by")]
            ),
            "🪢 Couldn't check relation links · nothing offered"
        )
        XCTAssertEqual(
            CaptureRelationHeldPresentation.uncertaintyNotice(check: "unavailable", held: []),
            "🪢 Couldn't check relation links · nothing offered"
        )
        XCTAssertNil(CaptureRelationHeldPresentation.uncertaintyNotice(check: "checked"))
        XCTAssertNil(CaptureRelationHeldPresentation.uncertaintyNotice(check: nil))
    }
}
