import Foundation
import XCTest

@testable import CaptureCore

final class SnoozeWakeNoticePolicyTests: XCTestCase {
    private let today = "2026-10-08"
    private let vault = "/vault/example"
    private let bobNow = "2026-10-08T15:32:10-04:00"

    private func date(_ rfc3339: String) throws -> Date {
        try XCTUnwrap(CaptureRFC3339Date.date(from: rfc3339))
    }

    private func receipt(
        wakeID: String = "w1",
        date: String = "2026-10-08",
        wokenAt: String = "2026-10-08T15:32:00-04:00",
        channel: SnoozeWakeNotificationChannel = .macCapture,
        vaultRoot: String? = "/vault/example"
    ) -> SnoozeWakeReceipt {
        SnoozeWakeReceipt(
            wakeID: wakeID,
            date: date,
            wokenAt: wokenAt,
            host: "mac",
            notificationChannel: channel,
            vaultRoot: vaultRoot,
            dailyFile: "2026/20261008.md",
            tasks: [
                SnoozeWakeReceiptTask(
                    title: "Email Dan",
                    route: "tasks.md",
                    blockID: "^job",
                    target: "1532",
                    wokeAt: "15:32",
                    destination: "WRITE",
                    line: 3)
            ],
            plan: SnoozeWakeReceiptPlan(count: 1, cap: 10, over: false))
    }

    private func eligibleRow() -> SnoozeWakeListRow {
        SnoozeWakeListRow(
            line: 4,
            route: "tasks.md",
            blockID: "^job",
            title: "Email Dan",
            target: "1532",
            state: "woken",
            wokeAt: "15:32",
            wakeNoticeEligible: true)
    }

    private func meetingRow(
        startsAt: String?,
        endsAt: String?,
        kind: CaptureAgendaEventKind = .task,
        statusSymbol: String? = "*",
        statusType: String? = "ON_HOLD",
        phase: CaptureAgendaEventPhase? = nil
    ) -> CaptureAgendaEventRow {
        CaptureAgendaEventRow(
            line: 7,
            blockID: "standup",
            kind: kind,
            title: "Standup",
            startsAt: startsAt,
            endsAt: endsAt,
            phase: phase,
            statusSymbol: statusSymbol,
            statusType: statusType)
    }

    private func events(_ rows: [CaptureAgendaEventRow]) -> CaptureAgendaEvents {
        CaptureAgendaEvents(rows: rows)
    }

    private func activeSettings() -> SnoozeWakeNoticeSettings {
        SnoozeWakeNoticeSettings(
            announceWakes: true, holdWhileAway: true, holdDuringMeetings: true)
    }

    func testImmediateActiveDeliveryShows() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let decision = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show(let batch) = decision else {
            XCTFail("Expected .show, got \(decision)")
            return
        }
        XCTAssertEqual(batch.wakeID, "w1")
        XCTAssertEqual(batch.rows.count, 1)
    }

    func testUnheldUnverifiedWorkVerifiesImmediately() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let decision = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .unverified,
            now: now)
        guard case .verify(let recheckAt) = decision else {
            XCTFail("Expected .verify, got \(decision)")
            return
        }
        XCTAssertEqual(
            recheckAt.timeIntervalSince1970, now.timeIntervalSince1970,
            accuracy: 0.001)
    }

    func testIdleThresholdBoundary() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        for (idle, expectHold) in [(179.9, false), (180.0, true)] as [(TimeInterval, Bool)] {
            var policy = SnoozeWakeNoticePolicy()
            let decision = policy.decide(
                receipt: receipt(),
                today: today,
                bobNow: bobNow,
                configuredVaultRoot: vault,
                presence: SnoozeWakePresence(idleSeconds: idle),
                events: nil,
                settings: activeSettings(),
                verification: .verified(eligible: [eligibleRow()]),
                now: now)
            switch decision {
            case .hold(let reason, _):
                XCTAssertTrue(expectHold, "idle=\(idle) should not hold")
                guard case .away(let signals) = reason else {
                    XCTFail("Expected away hold")
                    return
                }
                XCTAssertTrue(signals.contains(.idleTimeout))
            case .show:
                XCTAssertFalse(expectHold, "idle=\(idle) should hold")
            default:
                XCTFail("Unexpected \(decision) for idle=\(idle)")
            }
        }
    }

    func testEachAwaySignalHoldsIndependently() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        let presences: [(SnoozeWakePresence, SnoozeWakeAwaySignal)] = [
            (SnoozeWakePresence(screenLocked: true), .screenLocked),
            (SnoozeWakePresence(displaysAsleep: true), .displaysAsleep),
            (SnoozeWakePresence(sessionInactive: true), .sessionInactive),
        ]
        for (presence, signal) in presences {
            var policy = SnoozeWakeNoticePolicy()
            let decision = policy.decide(
                receipt: receipt(),
                today: today,
                bobNow: bobNow,
                configuredVaultRoot: vault,
                presence: presence,
                events: nil,
                settings: activeSettings(),
                verification: .verified(eligible: [eligibleRow()]),
                now: now)
            guard case .hold(let reason, _) = decision,
                case .away(let signals) = reason
            else {
                XCTFail("Expected away hold for \(signal)")
                return
            }
            XCTAssertTrue(signals.contains(signal))
        }
    }

    func testCombinedAwaySignalsReportAll() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let decision = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(
                screenLocked: true, displaysAsleep: true,
                sessionInactive: true, idleSeconds: 300),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .hold(let reason, _) = decision,
            case .away(let signals) = reason
        else {
            XCTFail("Expected combined away hold")
            return
        }
        XCTAssertEqual(Set(signals),
                       [.screenLocked, .displaysAsleep, .sessionInactive, .idleTimeout])
    }

    func testHoldTogglesApplyIndependently() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        var awayPolicy = SnoozeWakeNoticePolicy()
        let awayOff = SnoozeWakeNoticeSettings(
            announceWakes: true, holdWhileAway: false, holdDuringMeetings: true)
        let awayDecision = awayPolicy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(screenLocked: true),
            events: nil,
            settings: awayOff,
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show = awayDecision else {
            XCTFail("Disabling hold-while-away must deliver, got \(awayDecision)")
            return
        }

        var meetingPolicy = SnoozeWakeNoticePolicy()
        let meetingOff = SnoozeWakeNoticeSettings(
            announceWakes: true, holdWhileAway: true, holdDuringMeetings: false)
        let meetingDecision = meetingPolicy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: events([meetingRow(
                startsAt: "2026-10-08T15:00:00-04:00",
                endsAt: "2026-10-08T16:00:00-04:00")]),
            settings: meetingOff,
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show = meetingDecision else {
            XCTFail("Disabling hold-during-meetings must deliver, got \(meetingDecision)")
            return
        }
    }

    func testSecondHoldDuringVerificationSupersedesTimer() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let first = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .unverified,
            now: now)
        guard case .verify = first else {
            XCTFail("Expected initial verify")
            return
        }
        let second = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(screenLocked: true),
            events: nil,
            settings: activeSettings(),
            verification: .unverified,
            now: now.addingTimeInterval(0.5))
        guard case .hold(let reason, _) = second,
            case .away = reason
        else {
            XCTFail("A new hold must invalidate the settle timer, got \(second)")
            return
        }
    }

    func testOverlappingMeetingsHoldUntilEarliestEnd() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let decision = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: events([
                meetingRow(
                    startsAt: "2026-10-08T15:00:00-04:00",
                    endsAt: "2026-10-08T16:00:00-04:00"),
                meetingRow(
                    startsAt: "2026-10-08T15:30:00-04:00",
                    endsAt: "2026-10-08T15:45:00-04:00"),
            ]),
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .hold(let reason, let nextCheck) = decision,
            case .meeting(let until) = reason
        else {
            XCTFail("Expected meeting hold, got \(decision)")
            return
        }
        XCTAssertEqual(until, try date("2026-10-08T15:45:00-04:00"))
        XCTAssertEqual(nextCheck, try date("2026-10-08T15:45:00-04:00"))
    }

    func testMeetingEndBoundaryIsExclusive() throws {
        var policy = SnoozeWakeNoticePolicy()
        let end = try date("2026-10-08T16:00:00-04:00")
        let atEnd = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: events([meetingRow(
                startsAt: "2026-10-08T15:00:00-04:00",
                endsAt: "2026-10-08T16:00:00-04:00")]),
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: end)
        guard case .show = atEnd else {
            XCTFail("now == endsAt must not hold, got \(atEnd)")
            return
        }

        var startPolicy = SnoozeWakeNoticePolicy()
        let atStart = startPolicy.decide(
            receipt: receipt(wokenAt: "2026-10-08T14:59:00-04:00"),
            today: today,
            bobNow: "2026-10-08T15:00:00-04:00",
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: events([meetingRow(
                startsAt: "2026-10-08T15:00:00-04:00",
                endsAt: "2026-10-08T16:00:00-04:00")]),
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: try date("2026-10-08T15:00:00-04:00"))
        guard case .hold = atStart else {
            XCTFail("now == startsAt must hold, got \(atStart)")
            return
        }
    }

    func testBufferedSpanNeverHoldsOutsideActualSpan() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T10:10:00-04:00")
        let row = meetingRow(
            startsAt: "2026-10-08T09:40:00-04:00",
            endsAt: "2026-10-08T10:00:00-04:00")
        let decision = policy.decide(
            receipt: receipt(
                wokenAt: "2026-10-08T10:09:00-04:00"),
            today: today,
            bobNow: "2026-10-08T10:10:00-04:00",
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: events([row]),
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show = decision else {
            XCTFail("A buffer-only overlap must not hold, got \(decision)")
            return
        }
    }

    func testCancelledRowsNeverHold() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        let cancelled: [CaptureAgendaEventRow] = [
            meetingRow(
                startsAt: "2026-10-08T15:00:00-04:00",
                endsAt: "2026-10-08T16:00:00-04:00",
                statusSymbol: "-", statusType: "TODO"),
            meetingRow(
                startsAt: "2026-10-08T15:00:00-04:00",
                endsAt: "2026-10-08T16:00:00-04:00",
                statusSymbol: "*", statusType: "cancelled"),
            meetingRow(
                startsAt: "2026-10-08T15:00:00-04:00",
                endsAt: "2026-10-08T16:00:00-04:00",
                kind: .timedContext),
        ]
        for row in cancelled {
            var policy = SnoozeWakeNoticePolicy()
            let decision = policy.decide(
                receipt: receipt(),
                today: today,
                bobNow: bobNow,
                configuredVaultRoot: vault,
                presence: SnoozeWakePresence(),
                events: events([row]),
                settings: activeSettings(),
                verification: .verified(eligible: [eligibleRow()]),
                now: now)
            guard case .show = decision else {
                XCTFail("Cancelled/non-meeting rows must not hold, got \(decision)")
                return
            }
        }
    }

    func testStalePhaseLabelIsNeverTrusted() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        var staleRunning = SnoozeWakeNoticePolicy()
        let notRunning = staleRunning.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: events([meetingRow(
                startsAt: "2026-10-08T14:00:00-04:00",
                endsAt: "2026-10-08T14:30:00-04:00",
                phase: .running)]),
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show = notRunning else {
            XCTFail("A stale running label must not hold, got \(notRunning)")
            return
        }

        var staleUpcoming = SnoozeWakeNoticePolicy()
        let running = staleUpcoming.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: events([meetingRow(
                startsAt: "2026-10-08T15:00:00-04:00",
                endsAt: "2026-10-08T16:00:00-04:00",
                phase: .upcoming)]),
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .hold = running else {
            XCTFail("A live span must hold despite an upcoming label, got \(running)")
            return
        }
    }

    func testAbsentAgendaFieldsDoNotHold() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        var policy = SnoozeWakeNoticePolicy()
        let decision = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: events([meetingRow(startsAt: nil, endsAt: nil)]),
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show = decision else {
            XCTFail("Rows without spans must not hold, got \(decision)")
            return
        }

        var nilEvents = SnoozeWakeNoticePolicy()
        let nilDecision = nilEvents.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show = nilDecision else {
            XCTFail("Missing events must not hold, got \(nilDecision)")
            return
        }
    }

    func testStaleReceiptDateNeverCombinesWithNewClock() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-09T08:00:00-04:00")
        let decision = policy.decide(
            receipt: receipt(),
            today: "2026-10-09",
            bobNow: "2026-10-09T08:00:00-04:00",
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .drop(let reason) = decision else {
            XCTFail("Expected day-mismatch drop, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .dayMismatch)
    }

    func testFutureDatedReceiptsNeverReplay() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let decision = policy.decide(
            receipt: receipt(wokenAt: "2026-10-08T16:00:00-04:00"),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .drop(let reason) = decision else {
            XCTFail("Expected future-dated drop, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .futureDated)
    }

    func testFourHourCutoff() throws {
        let woken = try date("2026-10-08T11:32:00-04:00")
        var fresh = SnoozeWakeNoticePolicy()
        let justInside = fresh.decide(
            receipt: receipt(wokenAt: "2026-10-08T11:32:00-04:00"),
            today: today,
            bobNow: "2026-10-08T15:31:59-04:00",
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: woken.addingTimeInterval(4 * 60 * 60 - 1))
        guard case .show = justInside else {
            XCTFail("A receipt just inside four hours must show, got \(justInside)")
            return
        }

        var stale = SnoozeWakeNoticePolicy()
        let outside = stale.decide(
            receipt: receipt(wokenAt: "2026-10-08T11:32:00-04:00"),
            today: today,
            bobNow: "2026-10-08T15:32:01-04:00",
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: woken.addingTimeInterval(4 * 60 * 60 + 1))
        guard case .drop(let reason) = outside else {
            XCTFail("A receipt past four hours must expire, got \(outside)")
            return
        }
        XCTAssertEqual(reason, .expired)
    }

    func testInvalidTimestampsDrop() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let decision = policy.decide(
            receipt: receipt(wokenAt: "not-an-instant"),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .drop(let reason) = decision else {
            XCTFail("Expected invalid-timestamp drop, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .invalidTimestamp)
    }

    func testVaultMismatchDrops() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        var mismatch = SnoozeWakeNoticePolicy()
        let decision = mismatch.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: "/vault/other",
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .drop(let reason) = decision else {
            XCTFail("Expected vault-mismatch drop, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .vaultMismatch)

        var missing = SnoozeWakeNoticePolicy()
        let missingDecision = missing.decide(
            receipt: receipt(vaultRoot: nil),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .drop(let missingReason) = missingDecision else {
            XCTFail("A receipt without vault identity must not announce")
            return
        }
        XCTAssertEqual(missingReason, .vaultMismatch)
    }

    func testDuplicateIDsNeverReplay() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        var policy = SnoozeWakeNoticePolicy()
        let decision = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            handledIDs: ["w1"],
            handledIDsDay: today,
            now: now)
        guard case .drop(let reason) = decision else {
            XCTFail("Expected duplicate drop, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .duplicate)
    }

    func testDistinctIDsQueueWithoutReplacing() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let first = policy.decide(
            receipt: receipt(wakeID: "w1"),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show = first else {
            XCTFail("Expected first batch to show, got \(first)")
            return
        }
        let second = policy.decide(
            receipt: receipt(wakeID: "w2"),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show(let batch) = second else {
            XCTFail("Expected distinct batch to show, got \(second)")
            return
        }
        XCTAssertEqual(batch.wakeID, "w2")
    }

    func testEmptyAndFailedVerificationDrop() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        var emptyPolicy = SnoozeWakeNoticePolicy()
        let empty = emptyPolicy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .empty,
            now: now)
        guard case .drop(let emptyReason) = empty else {
            XCTFail("Expected empty-verification drop, got \(empty)")
            return
        }
        XCTAssertEqual(emptyReason, .emptyVerification)

        var failedPolicy = SnoozeWakeNoticePolicy()
        let failed = failedPolicy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .failed(reason: "timeout"),
            now: now)
        guard case .drop(let failedReason) = failed else {
            XCTFail("Expected failed-verification drop, got \(failed)")
            return
        }
        XCTAssertEqual(failedReason, .verificationFailed(reason: "timeout"))
    }

    func testPartialVerificationShowsMatchingRows() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let decision = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .show(let batch) = decision else {
            XCTFail("Expected partial verification to show, got \(decision)")
            return
        }
        XCTAssertEqual(batch.identityKeys, ["tasks.md#^job"])
    }

    func testVerificationWithNoActionableRowsDrops() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let decision = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: []),
            now: now)
        guard case .drop(let reason) = decision else {
            XCTFail("Expected no-eligible-tasks drop, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .noEligibleTasks)
    }

    func testWrongChannelAndUnsupportedBobDrop() throws {
        let now = try date("2026-10-08T15:32:10-04:00")
        for channel in [SnoozeWakeNotificationChannel.desktop, .off, .unknown("x")] {
            var policy = SnoozeWakeNoticePolicy()
            let decision = policy.decide(
                receipt: receipt(channel: channel),
                today: today,
                bobNow: bobNow,
                configuredVaultRoot: vault,
                presence: SnoozeWakePresence(),
                events: nil,
                settings: activeSettings(),
                verification: .verified(eligible: [eligibleRow()]),
                now: now)
            guard case .drop(let reason) = decision else {
                XCTFail("Expected wrong-channel drop for \(channel)")
                return
            }
            XCTAssertEqual(reason, .wrongChannel)
        }

        var oldBob = SnoozeWakeNoticePolicy()
        var legacy = receipt()
        legacy = SnoozeWakeReceipt(
            schemaVersion: 2,
            wakeID: legacy.wakeID,
            date: legacy.date,
            wokenAt: legacy.wokenAt,
            host: legacy.host,
            notificationChannel: legacy.notificationChannel,
            vaultRoot: legacy.vaultRoot,
            dailyFile: legacy.dailyFile,
            tasks: legacy.tasks,
            plan: legacy.plan)
        let legacyDecision = oldBob.decide(
            receipt: legacy,
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .drop(let legacyReason) = legacyDecision else {
            XCTFail("Expected unsupported-bob drop")
            return
        }
        XCTAssertEqual(legacyReason, .unsupportedBob)
    }

    func testAnnouncementsDisabledDiscards() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try date("2026-10-08T15:32:10-04:00")
        let decision = policy.decide(
            receipt: receipt(),
            today: today,
            bobNow: bobNow,
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: nil,
            settings: SnoozeWakeNoticeSettings(
                announceWakes: false, holdWhileAway: true, holdDuringMeetings: true),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .drop(let reason) = decision else {
            XCTFail("Expected announcements-disabled drop, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .announcementsDisabled)
    }

    func testDifferingSystemZoneUsesBobOffset() throws {
        var policy = SnoozeWakeNoticePolicy()
        let now = try XCTUnwrap(CaptureRFC3339Date.date(from: "2026-10-08T06:45:00Z"))
        let decision = policy.decide(
            receipt: receipt(wokenAt: "2026-10-08T06:30:00Z"),
            today: today,
            bobNow: "2026-10-08T12:00:00+05:30",
            configuredVaultRoot: vault,
            presence: SnoozeWakePresence(),
            events: events([meetingRow(
                startsAt: "2026-10-08T12:00",
                endsAt: "2026-10-08T13:00")]),
            settings: activeSettings(),
            verification: .verified(eligible: [eligibleRow()]),
            now: now)
        guard case .hold = decision else {
            XCTFail("Wall times must resolve in bob's +05:30 zone, got \(decision)")
            return
        }
    }

    func testOffsetAndDSTInstantsMatchAcrossZones() throws {
        let eastern = try date("2026-10-08T15:32:00-04:00")
        let utc = try date("2026-10-08T19:32:00Z")
        XCTAssertEqual(eastern, utc)
    }
}
