import Foundation
import XCTest

@testable import CaptureCore

final class SnoozeWakeReceiptTests: XCTestCase {
    private func receiptJSON(
        schemaVersion: Int = 1,
        wakeID: String = "abc123-0-42",
        date: String = "2026-10-08",
        wokenAt: String = "2026-10-08T15:32:00-04:00",
        channel: String? = "mac_capture",
        vaultRoot: String? = "/vault/example",
        extra: String = ""
    ) -> String {
        let channelValue = channel.map { "\"\($0)\"" } ?? "null"
        let vaultValue = vaultRoot.map { "\"\($0)\"" } ?? "null"
        return """
            {"schema_version":\(schemaVersion),"wake_id":"\(wakeID)",\
            "date":"\(date)","woken_at":"\(wokenAt)","host":"mac",\
            "notification_channel":\(channelValue),"vault_root":\(vaultValue),\
            "daily_file":"2026/20261008.md",\
            "tasks":[{"title":"Email Dan","route":"tasks.md","block_id":"^job",\
            "target":"1532","woke_at":"15:32","destination":"WRITE","line":3}],\
            "plan":{"count":3,"cap":10,"over":false}\(extra)}
            """
    }

    private func writeReceipt(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try Data(text.utf8).write(to: url)
        return url
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    func testDecodesRustShapedReceipt() throws {
        let receipt = try JSONDecoder().decode(
            SnoozeWakeReceipt.self, from: Data(receiptJSON().utf8))
        XCTAssertEqual(receipt.schemaVersion, 1)
        XCTAssertEqual(receipt.wakeID, "abc123-0-42")
        XCTAssertEqual(receipt.date, "2026-10-08")
        XCTAssertEqual(receipt.wokenAt, "2026-10-08T15:32:00-04:00")
        XCTAssertEqual(receipt.notificationChannel, .macCapture)
        XCTAssertTrue(receipt.notificationChannel.permitsMacNotice)
        XCTAssertEqual(receipt.vaultRoot, "/vault/example")
        XCTAssertEqual(receipt.dailyFile, "2026/20261008.md")
        XCTAssertEqual(receipt.tasks.count, 1)
        XCTAssertEqual(receipt.tasks[0].identityKey, "tasks.md#^job")
        XCTAssertEqual(receipt.tasks[0].destination, "WRITE")
        XCTAssertEqual(receipt.tasks[0].line, 3)
        XCTAssertEqual(receipt.plan.count, 3)
        XCTAssertEqual(receipt.plan.over, false)
    }

    func testDesktopAndOffChannelsDoNotPermitMacNotice() throws {
        for (raw, expected) in [("desktop", SnoozeWakeNotificationChannel.desktop),
                                ("off", SnoozeWakeNotificationChannel.off)] {
            let receipt = try JSONDecoder().decode(
                SnoozeWakeReceipt.self, from: Data(receiptJSON(channel: raw).utf8))
            XCTAssertEqual(receipt.notificationChannel, expected)
            XCTAssertFalse(receipt.notificationChannel.permitsMacNotice)
        }
    }

    func testMissingOrUnknownOwnershipIsNotPermission() throws {
        let missing = try JSONDecoder().decode(
            SnoozeWakeReceipt.self,
            from: Data(receiptJSON(channel: nil).utf8))
        XCTAssertFalse(missing.notificationChannel.permitsMacNotice)

        let unknown = try JSONDecoder().decode(
            SnoozeWakeReceipt.self,
            from: Data(receiptJSON(channel: "carrier_pigeon").utf8))
        XCTAssertEqual(unknown.notificationChannel, .unknown("carrier_pigeon"))
        XCTAssertFalse(unknown.notificationChannel.permitsMacNotice)
    }

    func testUnknownKeysAndNullTasksDecodeTolerantly() throws {
        let json = receiptJSON(extra: ",\"future_field\":true")
        let receipt = try JSONDecoder().decode(SnoozeWakeReceipt.self, from: Data(json.utf8))
        XCTAssertEqual(receipt.tasks.count, 1)
        XCTAssertEqual(receipt.tasks[0].identityKey, "tasks.md#^job")

        let nullTask = """
            {"schema_version":1,"wake_id":"n1","date":"2026-10-08",\
            "woken_at":"2026-10-08T15:32:00-04:00","host":"mac",\
            "notification_channel":"mac_capture","vault_root":"/vault/example",\
            "daily_file":"2026/20261008.md","tasks":[{}],\
            "plan":{"count":0,"cap":10,"over":false}}
            """
        let sparse = try JSONDecoder().decode(
            SnoozeWakeReceipt.self, from: Data(nullTask.utf8))
        XCTAssertEqual(sparse.tasks.count, 1)
        XCTAssertNil(sparse.tasks[0].identityKey)
        XCTAssertNil(sparse.tasks[0].title)
    }

    func testReaderResolvesXDGStateHomeFirst() {
        let xdg = URL(fileURLWithPath: "/xdg/state", isDirectory: true)
        let url = SnoozeWakeReceiptReader.receiptURL(
            environment: ["XDG_STATE_HOME": "/xdg/state", "HOME": "/home/user"])
        XCTAssertEqual(
            url.path, xdg.appendingPathComponent("bob-cli/snooze/last-wake.json").path)
    }

    func testReaderFallsBackToHomeLocalState() {
        let url = SnoozeWakeReceiptReader.receiptURL(
            environment: ["HOME": "/home/user"],
            homeDirectoryURL: URL(fileURLWithPath: "/fallback", isDirectory: true))
        XCTAssertEqual(
            url.path, "/home/user/.local/state/bob-cli/snooze/last-wake.json")
    }

    func testReaderIgnoresEmptyXDGStateHome() {
        let url = SnoozeWakeReceiptReader.receiptURL(
            environment: ["XDG_STATE_HOME": "", "HOME": "/home/user"])
        XCTAssertEqual(
            url.path, "/home/user/.local/state/bob-cli/snooze/last-wake.json")
    }

    func testReaderParityWithRustFields() throws {
        let url = try writeReceipt(receiptJSON())
        let receipt = try SnoozeWakeReceiptReader().read(at: url)
        XCTAssertEqual(receipt?.wakeID, "abc123-0-42")
        XCTAssertEqual(receipt?.dailyFile, "2026/20261008.md")
        XCTAssertEqual(receipt?.notificationChannel, .macCapture)
        XCTAssertEqual(receipt?.vaultRoot, "/vault/example")
    }

    func testReaderIgnoresSchemaMismatch() throws {
        let url = try writeReceipt(receiptJSON(schemaVersion: 2))
        XCTAssertNil(try SnoozeWakeReceiptReader().read(at: url))
    }

    func testReaderDoesNotAssumeMissingSchemaVersionIsOne() throws {
        let json = receiptJSON().replacingOccurrences(of: "\"schema_version\":1,", with: "")
        let url = try writeReceipt(json)
        do {
            _ = try SnoozeWakeReceiptReader().read(at: url)
            XCTFail("Expected an explicit schema version")
        } catch let error as SnoozeWakeReceiptError {
            guard case .malformed = error else {
                XCTFail("Expected .malformed, got \(error)")
                return
            }
        }
    }

    func testReadsFractionalRFC3339WakeTimeFixture() throws {
        let receipt = try XCTUnwrap(
            SnoozeWakeReceiptReader().read(at: fixtureURL("snooze-wake-fractional.json")))
        XCTAssertEqual(receipt.wokenAt, "2026-11-26T15:32:00.123456789-05:00")
        XCTAssertNotNil(CaptureRFC3339Date.date(from: receipt.wokenAt))
    }

    func testReaderReportsMalformedJSONAsDiagnostic() throws {
        let url = try writeReceipt("{not json")
        do {
            _ = try SnoozeWakeReceiptReader().read(at: url)
            XCTFail("Expected malformed diagnostic")
        } catch let error as SnoozeWakeReceiptError {
            guard case .malformed = error else {
                XCTFail("Expected .malformed, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReaderReportsUnreadableInputAsDiagnostic() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        do {
            _ = try SnoozeWakeReceiptReader().read(at: missing)
            XCTFail("Expected unreadable diagnostic")
        } catch let error as SnoozeWakeReceiptError {
            guard case .unreadable = error else {
                XCTFail("Expected .unreadable, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReaderRejectsOversizedReceipt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        let prefix = Data("{\"schema_version\":1,\"wake_id\":\"x\",".utf8)
        let padding = Data(
            repeating: 0x20, count: SnoozeWakeReceiptReader.maximumBytes)
        try (prefix + padding).write(to: url)
        do {
            _ = try SnoozeWakeReceiptReader().read(at: url)
            XCTFail("Expected tooLarge diagnostic")
        } catch let error as SnoozeWakeReceiptError {
            guard case .tooLarge(let maximumBytes) = error else {
                XCTFail("Expected .tooLarge, got \(error)")
                return
            }
            XCTAssertEqual(maximumBytes, SnoozeWakeReceiptReader.maximumBytes)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
