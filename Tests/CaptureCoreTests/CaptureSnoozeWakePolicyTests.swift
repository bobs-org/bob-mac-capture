import XCTest

@testable import CaptureCore

final class CaptureSnoozeWakePolicyTests: XCTestCase {
    private let target = "2026-08-28T09:00:00-04:00"

    private func snapshot(
        date: String? = "2026-08-28",
        nextWakeAt: String? = "2026-08-28T09:00:00-04:00",
        rows: [String] = [],
        headline: String? = nil
    ) throws -> CaptureAgendaSnapshot {
        var fields = ["\"schema_version\":1"]
        if let date {
            fields.append("\"date\":\"\(date)\"")
        }
        if let headline {
            fields.append("\"headline\":\"\(headline)\"")
        }
        let wakeValue = nextWakeAt.map { "\"\($0)\"" } ?? "null"
        fields.append(
            "\"snoozed\":{\"next_wake_at\":\(wakeValue),\"rows\":[\(rows.joined(separator: ","))]}"
        )
        return try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data("{\(fields.joined(separator: ","))}".utf8)
        )
    }

    private static func row(blockID: String) -> String {
        "{\"title\":\"Task \(blockID)\",\"route\":\"tasks.md\",\"block_id\":\"\(blockID)\",\"target\":\"0900\",\"wake_at\":\"2026-08-28T09:00:00-04:00\",\"state\":\"due\",\"notes\":[]}"
    }

    func testArmsFiveSecondsAfterOffsetBearingBobInstant() throws {
        var policy = CaptureSnoozeWakePolicy()
        let now = Date(timeIntervalSince1970: 1_787_921_994)  // 08:59:54 at -04:00

        let fireAt = policy.update(
            snapshot: try snapshot(),
            today: "2026-08-28",
            now: now
        )

        XCTAssertEqual(fireAt?.timeIntervalSince1970, 1_787_922_005)
        XCTAssertEqual(
            CaptureRFC3339Date.date(from: "2026-08-28T09:00:00-04:00"),
            CaptureRFC3339Date.date(from: "2026-08-28T13:00:00Z")
        )
    }

    func testOverdueTargetOnLaunchIsImmediatelyEligible() throws {
        var policy = CaptureSnoozeWakePolicy()
        let now = Date(timeIntervalSince1970: 1_787_922_060)
        let fireAt = policy.update(
            snapshot: try snapshot(),
            today: "2026-08-28",
            now: now
        )

        XCTAssertLessThanOrEqual(try XCTUnwrap(fireAt), now)
        XCTAssertTrue(policy.beginAttempt(at: now))
    }

    func testDuplicateSnapshotsKeepSameTargetOnSixtySecondRetryDeadline() throws {
        var policy = CaptureSnoozeWakePolicy()
        let snapshot = try snapshot()
        let now = Date(timeIntervalSince1970: 1_787_922_060)
        _ = policy.update(snapshot: snapshot, today: "2026-08-28", now: now)
        XCTAssertTrue(policy.beginAttempt(at: now))

        let duplicateDeadline = policy.update(
            snapshot: snapshot,
            today: "2026-08-28",
            now: now.addingTimeInterval(10)
        )
        XCTAssertEqual(duplicateDeadline, now.addingTimeInterval(60))
        XCTAssertFalse(policy.beginAttempt(at: now.addingTimeInterval(59)))
        XCTAssertTrue(policy.beginAttempt(at: now.addingTimeInterval(60)))
    }

    func testRetimeAndDropReplacePendingDeadline() throws {
        var policy = CaptureSnoozeWakePolicy()
        let now = Date(timeIntervalSince1970: 1_787_918_400)
        let first = try snapshot(nextWakeAt: "2026-08-28T09:00:00-04:00")
        let retimed = try snapshot(nextWakeAt: "2026-08-28T10:00:00-04:00")

        XCTAssertEqual(
            policy.update(snapshot: first, today: "2026-08-28", now: now),
            Date(timeIntervalSince1970: 1_787_922_005)
        )
        XCTAssertEqual(
            policy.update(snapshot: retimed, today: "2026-08-28", now: now),
            Date(timeIntervalSince1970: 1_787_925_605)
        )
        XCTAssertNil(
            policy.update(
                snapshot: try snapshot(nextWakeAt: nil),
                today: "2026-08-28",
                now: now
            )
        )
        XCTAssertNil(policy.advertisedTarget)
    }

    func testOldDayNullAndInvalidInstantsDisarm() throws {
        var policy = CaptureSnoozeWakePolicy()
        let now = Date(timeIntervalSince1970: 1_787_918_400)

        XCTAssertNil(
            policy.update(
                snapshot: try snapshot(date: "2026-08-27"),
                today: "2026-08-28",
                now: now
            )
        )
        XCTAssertNil(
            policy.update(
                snapshot: try snapshot(nextWakeAt: nil),
                today: "2026-08-28",
                now: now
            )
        )
        XCTAssertNil(
            policy.update(
                snapshot: try snapshot(nextWakeAt: "not-an-instant"),
                today: "2026-08-28",
                now: now
            )
        )
    }

    func testNullWakeSettlementDisarmsUntilAgendaAdvertisesAnotherTarget() throws {
        var policy = CaptureSnoozeWakePolicy()
        let now = Date(timeIntervalSince1970: 1_787_922_060)
        _ = policy.update(snapshot: try snapshot(), today: "2026-08-28", now: now)
        XCTAssertTrue(policy.beginAttempt(at: now))
        XCTAssertNil(policy.settle(nextWakeAt: nil, now: now.addingTimeInterval(2)))
        XCTAssertNil(policy.nextAttemptDate(now: now.addingTimeInterval(3)))

        let future = try snapshot(nextWakeAt: "2026-08-28T15:30:00-04:00")
        XCTAssertEqual(
            policy.update(snapshot: future, today: "2026-08-28", now: now),
            Date(timeIntervalSince1970: 1_787_945_405)
        )
    }

    func testUnsupportedCapabilityResetsForRecheck() throws {
        var policy = CaptureSnoozeWakePolicy()
        let now = Date(timeIntervalSince1970: 1_787_918_400)
        _ = policy.update(snapshot: try snapshot(), today: "2026-08-28", now: now)
        policy.markUnsupported()

        XCTAssertTrue(policy.isDisabled)
        XCTAssertNil(policy.update(snapshot: try snapshot(), today: "2026-08-28", now: now))

        policy.reset()
        XCTAssertFalse(policy.isDisabled)
        XCTAssertNotNil(policy.update(snapshot: try snapshot(), today: "2026-08-28", now: now))
    }

    func testSettledNullSurvivesReappliedSnapshot() throws {
        // The exact two-second reproduction: update, begin, settle null,
        // then re-apply the retained old snapshot. The retired target must
        // stay retired instead of re-arming.
        var policy = CaptureSnoozeWakePolicy()
        let snapshot = try snapshot()
        let attemptAt = Date(timeIntervalSince1970: 1_787_922_005)
        _ = policy.update(snapshot: snapshot, today: "2026-08-28", now: attemptAt)
        XCTAssertTrue(policy.beginAttempt(at: attemptAt))
        XCTAssertNil(
            policy.settle(nextWakeAt: nil, now: attemptAt.addingTimeInterval(1))
        )
        XCTAssertNil(
            policy.update(
                snapshot: snapshot,
                today: "2026-08-28",
                now: attemptAt.addingTimeInterval(2)
            )
        )
        XCTAssertFalse(policy.beginAttempt(at: attemptAt.addingTimeInterval(2)))
    }

    func testSettledFutureSurvivesReappliedSnapshot() throws {
        // Same reproduction with a returned future target: it stays
        // scheduled through the re-applied old snapshot.
        var policy = CaptureSnoozeWakePolicy()
        let snapshot = try snapshot()
        let attemptAt = Date(timeIntervalSince1970: 1_787_922_005)
        _ = policy.update(snapshot: snapshot, today: "2026-08-28", now: attemptAt)
        XCTAssertTrue(policy.beginAttempt(at: attemptAt))
        let fireAt = policy.settle(
            nextWakeAt: "2026-08-28T19:00:00-04:00",
            now: attemptAt.addingTimeInterval(1)
        )
        XCTAssertEqual(fireAt?.timeIntervalSince1970, 1_787_958_005)
        XCTAssertEqual(
            policy.update(
                snapshot: snapshot,
                today: "2026-08-28",
                now: attemptAt.addingTimeInterval(2)
            )?.timeIntervalSince1970,
            1_787_958_005
        )
        XCTAssertFalse(policy.beginAttempt(at: attemptAt.addingTimeInterval(2)))
    }

    func testLifecycleCallbacksBeforeSixtySecondsKeepRetryFloor() throws {
        var policy = CaptureSnoozeWakePolicy()
        let snapshot = try snapshot()
        let attemptAt = Date(timeIntervalSince1970: 1_787_922_005)
        _ = policy.update(snapshot: snapshot, today: "2026-08-28", now: attemptAt)
        XCTAssertTrue(policy.beginAttempt(at: attemptAt))

        // Timer and lifecycle callbacks re-apply the retained snapshot;
        // none of them may buy an early second attempt.
        for offset in [10, 30, 59] as [TimeInterval] {
            let tick = attemptAt.addingTimeInterval(offset)
            XCTAssertEqual(
                policy.update(snapshot: snapshot, today: "2026-08-28", now: tick),
                attemptAt.addingTimeInterval(60)
            )
            XCTAssertFalse(policy.beginAttempt(at: tick))
        }
        XCTAssertTrue(policy.beginAttempt(at: attemptAt.addingTimeInterval(60)))
    }

    func testChangedAgendaWithoutDueWorkCancelsRetry() throws {
        var policy = CaptureSnoozeWakePolicy()
        let attemptAt = Date(timeIntervalSince1970: 1_787_922_005)
        _ = policy.update(
            snapshot: try snapshot(),
            today: "2026-08-28",
            now: attemptAt
        )
        XCTAssertTrue(policy.beginAttempt(at: attemptAt))

        // Fresh facts with no due work retire the reserved retry.
        let cleared = try snapshot(nextWakeAt: nil)
        XCTAssertNil(
            policy.update(snapshot: cleared, today: "2026-08-28", now: attemptAt)
        )
        XCTAssertFalse(policy.beginAttempt(at: attemptAt.addingTimeInterval(60)))
    }

    func testFreshSameTargetWorkRearmsAfterRetirement() throws {
        // A new task at an already-settled clock target re-arms: only
        // remembering the timestamp would suppress it forever.
        var policy = CaptureSnoozeWakePolicy()
        let attemptAt = Date(timeIntervalSince1970: 1_787_922_005)
        _ = policy.update(
            snapshot: try snapshot(rows: [Self.row(blockID: "old")]),
            today: "2026-08-28",
            now: attemptAt
        )
        XCTAssertTrue(policy.beginAttempt(at: attemptAt))
        XCTAssertNil(
            policy.settle(nextWakeAt: nil, now: attemptAt.addingTimeInterval(1))
        )

        let fresh = try snapshot(rows: [Self.row(blockID: "new")])
        let fireAt = policy.update(
            snapshot: fresh,
            today: "2026-08-28",
            now: attemptAt.addingTimeInterval(2)
        )
        XCTAssertEqual(fireAt?.timeIntervalSince1970, 1_787_922_005)
        XCTAssertTrue(policy.beginAttempt(at: attemptAt.addingTimeInterval(2)))
    }

    func testSameTargetRowChangePreservesRetryFloor() throws {
        // A mid-retry row change at the same target is related work, but
        // the 60-second floor for repeated attempts on that target holds.
        var policy = CaptureSnoozeWakePolicy()
        let attemptAt = Date(timeIntervalSince1970: 1_787_922_005)
        _ = policy.update(
            snapshot: try snapshot(rows: [Self.row(blockID: "old")]),
            today: "2026-08-28",
            now: attemptAt
        )
        XCTAssertTrue(policy.beginAttempt(at: attemptAt))

        let changed = try snapshot(rows: [Self.row(blockID: "new")])
        XCTAssertEqual(
            policy.update(
                snapshot: changed,
                today: "2026-08-28",
                now: attemptAt.addingTimeInterval(10)
            ),
            attemptAt.addingTimeInterval(60)
        )
        XCTAssertFalse(policy.beginAttempt(at: attemptAt.addingTimeInterval(10)))
        XCTAssertTrue(policy.beginAttempt(at: attemptAt.addingTimeInterval(60)))
    }

    func testUnrelatedAgendaChangePreservesRetryDeadline() throws {
        // Ledger/headline edits leave the `snoozed` block equal, so the
        // reserved retry deadline survives them.
        var policy = CaptureSnoozeWakePolicy()
        let attemptAt = Date(timeIntervalSince1970: 1_787_922_005)
        _ = policy.update(
            snapshot: try snapshot(headline: "Morning"),
            today: "2026-08-28",
            now: attemptAt
        )
        XCTAssertTrue(policy.beginAttempt(at: attemptAt))

        XCTAssertEqual(
            policy.update(
                snapshot: try snapshot(headline: "Evening"),
                today: "2026-08-28",
                now: attemptAt.addingTimeInterval(10)
            ),
            attemptAt.addingTimeInterval(60)
        )
        XCTAssertFalse(policy.beginAttempt(at: attemptAt.addingTimeInterval(10)))
    }

    func testForwardClockJumpHonorsExpiredRetry() throws {
        var policy = CaptureSnoozeWakePolicy()
        let attemptAt = Date(timeIntervalSince1970: 1_787_922_005)
        _ = policy.update(
            snapshot: try snapshot(),
            today: "2026-08-28",
            now: attemptAt
        )
        XCTAssertTrue(policy.beginAttempt(at: attemptAt))
        XCTAssertTrue(policy.beginAttempt(at: attemptAt.addingTimeInterval(120)))
    }

    func testDayRolloverClearsAttemptDeadlineAndRejectsYesterdaySnapshot() throws {
        var policy = CaptureSnoozeWakePolicy()
        let now = Date(timeIntervalSince1970: 1_787_922_060)
        _ = policy.update(snapshot: try snapshot(), today: "2026-08-28", now: now)
        XCTAssertTrue(policy.beginAttempt(at: now))

        XCTAssertNil(
            policy.update(
                snapshot: try snapshot(),
                today: "2026-08-29",
                now: now.addingTimeInterval(1)
            )
        )
        XCTAssertNil(policy.advertisedTarget)
    }
}
