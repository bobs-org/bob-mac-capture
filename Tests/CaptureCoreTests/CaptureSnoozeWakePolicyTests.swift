import XCTest

@testable import CaptureCore

final class CaptureSnoozeWakePolicyTests: XCTestCase {
    private let target = "2026-08-28T09:00:00-04:00"

    private func snapshot(
        date: String? = "2026-08-28",
        nextWakeAt: String? = "2026-08-28T09:00:00-04:00"
    ) throws -> CaptureAgendaSnapshot {
        var fields = ["\"schema_version\":1"]
        if let date {
            fields.append("\"date\":\"\(date)\"")
        }
        let wakeValue = nextWakeAt.map { "\"\($0)\"" } ?? "null"
        fields.append("\"snoozed\":{\"next_wake_at\":\(wakeValue),\"rows\":[]}")
        return try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data("{\(fields.joined(separator: ","))}".utf8)
        )
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
