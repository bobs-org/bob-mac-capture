import Foundation
import XCTest

@testable import CaptureCore

final class SnoozeWakeNoticePresentationTests: XCTestCase {
    private func batch(
        wakeID: String = "w1",
        wokenAt: String = "2026-10-08T15:32:00-04:00",
        rows: [SnoozeWakeListRow]? = nil
    ) throws -> SnoozeWakeNoticeBatch {
        let woken = try XCTUnwrap(CaptureRFC3339Date.date(from: wokenAt))
        return SnoozeWakeNoticeBatch(
            wakeID: wakeID,
            wokenAt: woken,
            date: "2026-10-08",
            rows: rows ?? [
                SnoozeWakeListRow(
                    line: 4, route: "tasks.md", blockID: "^job", title: "Email Dan",
                    target: "1532", state: "woken", wokeAt: "15:32",
                    wakeNoticeEligible: true)
            ],
            vaultRoot: "/vault/example")
    }

    private func row(title: String, blockID: String) -> SnoozeWakeListRow {
        SnoozeWakeListRow(
            line: 4, route: "tasks.md", blockID: blockID, title: title,
            target: "1532", state: "woken", wokeAt: "15:32",
            wakeNoticeEligible: true)
    }

    func testSingleTaskCopyNamesTitle() throws {
        let presentation = SnoozeWakeNoticePresentation(batch: try batch())
        XCTAssertEqual(presentation.headline, "Ready now · Email Dan")
        XCTAssertEqual(presentation.visibleTitles, ["Email Dan"])
        XCTAssertEqual(presentation.remainingCount, 0)
        XCTAssertFalse(presentation.isOverCap)
    }

    func testBatchCopyShowsThreeTitlesPlusCount() throws {
        let rows = [
            row(title: "One", blockID: "^a"), row(title: "Two", blockID: "^b"),
            row(title: "Three", blockID: "^c"), row(title: "Four", blockID: "^d"),
            row(title: "Five", blockID: "^e"),
        ]
        let presentation = SnoozeWakeNoticePresentation(batch: try batch(rows: rows))
        XCTAssertEqual(presentation.headline, "5 snoozed tasks are ready")
        XCTAssertEqual(presentation.visibleTitles, ["One", "Two", "Three"])
        XCTAssertEqual(presentation.remainingCount, 2)
    }

    func testOverCapUsesListBudgetNotReceiptTotals() throws {
        let over = SnoozeWakeLinkPlan(count: 12, cap: 10, over: true)
        let presentation = SnoozeWakeNoticePresentation(
            batch: try batch(), listBudget: over)
        XCTAssertTrue(presentation.isOverCap)

        let under = SnoozeWakeNoticePresentation(
            batch: try batch(), listBudget: SnoozeWakeLinkPlan(count: 1, cap: 10, over: false))
        XCTAssertFalse(under.isOverCap)
    }

    func testStableRecordIDs() throws {
        let presentation = SnoozeWakeNoticePresentation(batch: try batch(wakeID: "abc"))
        XCTAssertEqual(presentation.recordID, "snooze-woken-abc")
        XCTAssertEqual(SnoozeWakeNoticePresentation.recordID(wakeID: "abc"), "snooze-woken-abc")
        XCTAssertEqual(SnoozeWakeNoticePresentation.recordThread, "snooze")
    }

    func testActionTargetsFollowReceiptOrder() throws {
        let rows = [row(title: "One", blockID: "^a"), row(title: "Two", blockID: "^b")]
        let presentation = SnoozeWakeNoticePresentation(batch: try batch(rows: rows))
        XCTAssertEqual(
            presentation.actionTargets.map { $0.locator },
            ["tasks.md:^a", "tasks.md:^b"])
        XCTAssertEqual(presentation.taskCount, 2)
    }

    func testIdentityLessRowsHaveNoActionTarget() throws {
        let rows = [
            SnoozeWakeListRow(
                line: 4, route: nil, blockID: nil, title: "Orphan",
                target: "1532", state: "woken", wakeNoticeEligible: true)
        ]
        let presentation = SnoozeWakeNoticePresentation(batch: try batch(rows: rows))
        XCTAssertTrue(presentation.actionTargets.isEmpty)
        XCTAssertEqual(presentation.taskCount, 0)
    }

    func testPerBatchExpiryAndBeaconWindows() throws {
        let presentation = SnoozeWakeNoticePresentation(batch: try batch())
        let woken = try XCTUnwrap(CaptureRFC3339Date.date(from: "2026-10-08T15:32:00-04:00"))
        XCTAssertEqual(
            presentation.expiresAt(), woken.addingTimeInterval(4 * 60 * 60))
        let delivered = try XCTUnwrap(
            CaptureRFC3339Date.date(from: "2026-10-08T15:33:00-04:00"))
        XCTAssertEqual(
            presentation.beaconClearsAt(deliveredAt: delivered),
            delivered.addingTimeInterval(60 * 60))
        XCTAssertEqual(
            presentation.hudDismissesAt(presentedAt: delivered),
            delivered.addingTimeInterval(12))
    }

    func testEveryAcknowledgementTrigger() throws {
        let keys = ["tasks.md#^a", "tasks.md#^b"]
        XCTAssertTrue(SnoozeWakeAcknowledgementStore.remainingKeys(
            visibleKeys: keys, trigger: .panelOpened).isEmpty)
        XCTAssertTrue(SnoozeWakeAcknowledgementStore.remainingKeys(
            visibleKeys: keys, trigger: .openAction).isEmpty)
        XCTAssertTrue(SnoozeWakeAcknowledgementStore.remainingKeys(
            visibleKeys: keys, trigger: .sixtyMinutesElapsed).isEmpty)
        XCTAssertTrue(SnoozeWakeAcknowledgementStore.remainingKeys(
            visibleKeys: keys, trigger: .dayRollover).isEmpty)

        XCTAssertEqual(
            SnoozeWakeAcknowledgementStore.remainingKeys(
                visibleKeys: keys, trigger: .addSucceeded(removedKeys: ["tasks.md#^a"])),
            ["tasks.md#^b"])
        XCTAssertTrue(
            SnoozeWakeAcknowledgementStore.remainingKeys(
                visibleKeys: keys,
                trigger: .addSucceeded(removedKeys: keys)).isEmpty)
    }

    func testAcknowledgementStoreIsBoundedAndDayScoped() throws {
        var store = SnoozeWakeAcknowledgementStore()
        store.acknowledge("w1", day: "2026-10-08")
        XCTAssertTrue(store.contains("w1", day: "2026-10-08"))
        XCTAssertFalse(store.contains("w1", day: "2026-10-09"))

        var bounded = SnoozeWakeAcknowledgementStore()
        for index in 0..<(SnoozeWakeAcknowledgementStore.maxEntries + 10) {
            bounded.acknowledge("w\(index)", day: "2026-10-08")
        }
        XCTAssertLessThanOrEqual(
            bounded.count, SnoozeWakeAcknowledgementStore.maxEntries)

        var rolled = SnoozeWakeAcknowledgementStore()
        rolled.acknowledge("w1", day: "2026-10-08")
        rolled.purge(day: "2026-10-09")
        XCTAssertFalse(rolled.contains("w1", day: "2026-10-09"))
    }
}
