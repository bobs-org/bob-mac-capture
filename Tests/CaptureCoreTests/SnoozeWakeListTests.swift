import Foundation
import XCTest

@testable import CaptureCore

final class SnoozeWakeListTests: XCTestCase {
    private func listJSON(
        schemaVersion: Int = 1,
        wakeNoticeVersion: String = "1",
        vaultRoot: String = "\"/vault/example\"",
        eligible: String = "true",
        extraRow: String = ""
    ) -> String {
        """
        {"schema_version":\(schemaVersion),"wake_notice_version":\(wakeNoticeVersion),\
        "vault_root":\(vaultRoot),"date":"2026-10-08",\
        "now":"2026-10-08T12:00:00-04:00",\
        "rows":[{"line":4,"route":"tasks.md","block_id":"^job","title":"Email Dan",\
        "target":"1530","state":"woken","woke_at":"15:30",\
        "wake_notice_eligible":\(eligible)}\(extraRow)],\
        "next_wake_at":"2026-10-08T15:30:00-04:00",\
        "plan":{"count":3,"cap":10,"over":false}}
        """
    }

    func testDecodesSchema1ListWithCapabilities() throws {
        let response = try JSONDecoder().decode(
            SnoozeWakeListResponse.self, from: Data(listJSON().utf8))
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertTrue(response.supportsWakeNotice)
        XCTAssertEqual(response.vaultRoot, "/vault/example")
        XCTAssertEqual(response.date, "2026-10-08")
        XCTAssertEqual(response.eligibleRows.count, 1)
        XCTAssertEqual(response.eligibleRows[0].identityKey, "tasks.md#^job")
        XCTAssertEqual(response.plan.count, 3)
        XCTAssertFalse(response.plan.over)
    }

    func testOlderBobWithoutCapabilityDisablesOnlyNotice() throws {
        let json = """
            {"schema_version":1,"date":"2026-10-08",\
            "now":"2026-10-08T12:00:00-04:00","rows":[],\
            "next_wake_at":null,"plan":{"count":0,"cap":10,"over":false}}
            """
        let response = try JSONDecoder().decode(
            SnoozeWakeListResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertFalse(response.supportsWakeNotice)
        XCTAssertNil(response.wakeNoticeVersion)
        XCTAssertNil(response.vaultRoot)
        XCTAssertTrue(response.eligibleRows.isEmpty)
    }

    func testMissingEligibilityIsNotPermission() throws {
        let json = """
            {"schema_version":1,"wake_notice_version":1,\
            "vault_root":"/vault/example","date":"2026-10-08",\
            "now":"2026-10-08T12:00:00-04:00",\
            "rows":[{"line":4,"route":"tasks.md","block_id":"^job",\
            "title":"Email Dan","target":"1530","state":"woken"}],\
            "next_wake_at":null,"plan":{"count":1,"cap":10,"over":false}}
            """
        let response = try JSONDecoder().decode(
            SnoozeWakeListResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.supportsWakeNotice)
        XCTAssertTrue(response.eligibleRows.isEmpty)
        XCTAssertFalse(response.rows[0].isEligible)
    }

    func testUnknownRowFieldsDecodeTolerantly() throws {
        let json = listJSON(extraRow: ",{\"line\":9,\"state\":\"mystery\",\"future\":{}}")
        let response = try JSONDecoder().decode(
            SnoozeWakeListResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.rows.count, 2)
        XCTAssertFalse(response.rows[1].isEligible)
        XCTAssertNil(response.rows[1].identityKey)
    }

    func testIneligibleRowsStayIneligible() throws {
        let response = try JSONDecoder().decode(
            SnoozeWakeListResponse.self, from: Data(listJSON(eligible: "false").utf8))
        XCTAssertTrue(response.supportsWakeNotice)
        XCTAssertTrue(response.eligibleRows.isEmpty)
        XCTAssertFalse(response.rows[0].isEligible)
    }

    func testDecodesSuccessfulAddResponse() throws {
        let json = """
            {"schema_version":1,"date":"2026-10-08",\
            "now":"2026-10-08T12:00:00-04:00","status":"added",\
            "task":{"route":"tasks.md","block_id":"^job","title":"Email Dan"},\
            "target":{"time":"12:15","at":"2026-10-08T12:15:00-04:00"},\
            "lane":"next","daily_file":"2026/20261008.md",\
            "plan":{"count":1,"cap":10,"over":false},"dry_run":false}
            """
        let response = try JSONDecoder().decode(
            SnoozeWakeAddResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.status, .added)
        XCTAssertTrue(response.didWrite)
        XCTAssertEqual(response.snoozedUntilLabel, "12:15")
        XCTAssertEqual(response.targetAt, "2026-10-08T12:15:00-04:00")
        XCTAssertEqual(response.lane, "next")
        XCTAssertEqual(response.plan.count, 1)
        XCTAssertEqual(response.dryRun, false)
    }

    func testOnlyAddedProvesAWrite() throws {
        for (raw, writes) in [("added", true), ("planned", false), ("deferred", false)] {
            let json = """
                {"schema_version":1,"date":"2026-10-08",\
                "now":"2026-10-08T12:00:00-04:00","status":"\(raw)",\
                "daily_file":"2026/20261008.md",\
                "plan":{"count":0,"cap":10,"over":false},"dry_run":\(raw == "planned")}
                """
            let response = try JSONDecoder().decode(
                SnoozeWakeAddResponse.self, from: Data(json.utf8))
            XCTAssertEqual(response.didWrite, writes, "status=\(raw)")
        }
    }

    func testAddDecodesUnknownStatusTolerantly() throws {
        let json = """
            {"schema_version":1,"date":"2026-10-08",\
            "now":"2026-10-08T12:00:00-04:00","status":"rescheduled",\
            "plan":{"count":0,"cap":10,"over":false},"dry_run":false}
            """
        let response = try JSONDecoder().decode(
            SnoozeWakeAddResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.status, .other("rescheduled"))
        XCTAssertFalse(response.didWrite)
        XCTAssertNil(response.snoozedUntilLabel)
    }
}
