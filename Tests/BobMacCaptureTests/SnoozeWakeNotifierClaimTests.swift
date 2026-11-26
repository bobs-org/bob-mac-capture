import Foundation
import XCTest

@testable import BobMacCapture

final class SnoozeWakeNotifierClaimTests: XCTestCase {
    private func temporaryClaimURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("notifier.json")
    }

    private func claim(
        at url: URL, pid: Int32 = 4242, startedAt: String = "2026-11-26T10:00:00-05:00",
        pidIsAlive: (@Sendable (Int32) -> Bool)? = nil
    ) -> SnoozeWakeNotifierClaim {
        SnoozeWakeNotifierClaim(
            claimURL: url,
            pid: pid,
            app: "org.bobs.bob-mac-capture",
            version: "9.9",
            startedAt: startedAt,
            pidIsAlive: pidIsAlive
        )
    }

    func testDefaultClaimURLResolvesUnderXDGStateHome() {
        let url = SnoozeWakeNotifierClaim.defaultClaimURL(
            environment: ["XDG_STATE_HOME": "/tmp/xdg"],
            homeDirectoryURL: URL(fileURLWithPath: "/home/user"))
        XCTAssertEqual(url.path, "/tmp/xdg/bob-cli/snooze/notifier.json")
    }

    func testDefaultClaimURLFallsBackToHomeLocalState() {
        let url = SnoozeWakeNotifierClaim.defaultClaimURL(
            environment: ["HOME": "/home/user"],
            homeDirectoryURL: URL(fileURLWithPath: "/fallback"))
        XCTAssertEqual(url.path, "/home/user/.local/state/bob-cli/snooze/notifier.json")
    }

    func testPublishWritesWellFormedClaimWith0600() throws {
        let url = try temporaryClaimURL()
        let writer = claim(at: url)
        try writer.publish()

        XCTAssertTrue(writer.isOwned)
        let record = SnoozeWakeNotifierClaim.readRecord(at: url)
        XCTAssertEqual(record?.schemaVersion, 1)
        XCTAssertEqual(record?.pid, 4242)
        XCTAssertEqual(record?.app, "org.bobs.bob-mac-capture")
        XCTAssertEqual(record?.version, "9.9")
        XCTAssertEqual(record?.startedAt, "2026-11-26T10:00:00-05:00")
        let permissions =
            try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
            as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testRelinquishRemovesOnlyOwnedClaim() throws {
        let url = try temporaryClaimURL()
        let writer = claim(at: url)
        try writer.publish()
        writer.relinquish()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(writer.isOwned)
    }

    func testRelinquishLeavesRivalClaimAlone() throws {
        let url = try temporaryClaimURL()
        let first = claim(at: url, pid: 1001, startedAt: "2026-11-26T10:00:00-05:00")
        let second = claim(at: url, pid: 1002, startedAt: "2026-11-26T10:00:01-05:00")
        try first.publish()
        try second.publish()

        XCTAssertTrue(second.isOwned)
        XCTAssertFalse(first.isOwned)
        // The first instance no longer owns the file: relinquishing it
        // must not delete the rival's claim.
        first.relinquish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(second.isOwned)
        second.relinquish()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSamePIDStartTokenDistinguishesRelaunch() throws {
        let url = try temporaryClaimURL()
        let before = claim(at: url, pid: 555, startedAt: "2026-11-26T10:00:00-05:00")
        let after = claim(at: url, pid: 555, startedAt: "2026-11-26T11:00:00-05:00")
        try before.publish()
        XCTAssertFalse(after.isOwned)
        after.relinquish()
        // A relaunched process with a recycled pid must not delete the
        // previous launch's claim with its own relinquish.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testLiveClaimRequiresSchemaPIDAndMetadata() throws {
        let url = try temporaryClaimURL()
        let writer = claim(at: url, pid: 4242, pidIsAlive: { _ in true })
        XCTAssertFalse(writer.isLiveClaim())
        try writer.publish()
        XCTAssertTrue(writer.isLiveClaim())

        let dead = claim(at: url, pid: 4242, pidIsAlive: { _ in false })
        XCTAssertFalse(dead.isLiveClaim())
    }

    func testCorruptClaimIsNotLive() throws {
        let url = try temporaryClaimURL()
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let writer = claim(at: url, pidIsAlive: { _ in true })
        XCTAssertFalse(writer.isLiveClaim())
        XCTAssertFalse(writer.isOwned)
    }
}
