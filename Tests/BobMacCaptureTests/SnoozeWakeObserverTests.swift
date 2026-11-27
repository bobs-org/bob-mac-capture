import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class SnoozeWakeObserverTests: XCTestCase {
    private func receipt(wakeID: String) -> SnoozeWakeReceipt {
        SnoozeWakeReceipt(
            wakeID: wakeID,
            date: "2026-11-26",
            wokenAt: "2026-11-26T15:32:00-05:00",
            notificationChannel: .macCapture,
            dailyFile: "2026/20261126.md"
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testStartRegistersAndReadsMissedPingOnce() async {
        var registered = 0
        var cancelled: [Int32] = []
        let expected = receipt(wakeID: "w1")
        let observer = SnoozeWakeObserver(
            readReceipt: { expected },
            register: { _ in
                registered += 1
                return 7
            },
            cancel: { cancelled.append($0) }
        )
        var delivered: [String] = []
        observer.onReceipt = { delivered.append($0.wakeID) }

        observer.start()
        XCTAssertTrue(observer.isRegistered)
        await waitUntil { delivered == ["w1"] }
        XCTAssertEqual(registered, 1)

        observer.stop()
        XCTAssertEqual(cancelled, [7])
    }

    func testDuplicateWakeIDIsDropped() {
        let observer = SnoozeWakeObserver(
            readReceipt: { nil },
            register: { _ in nil },
            cancel: { _ in }
        )
        var delivered: [String] = []
        observer.onReceipt = { delivered.append($0.wakeID) }

        observer.processForTests(receipt(wakeID: "w1"))
        observer.processForTests(receipt(wakeID: "w1"))
        observer.processForTests(receipt(wakeID: "w2"))

        XCTAssertEqual(delivered, ["w1", "w2"])
    }

    func testFailedRegistrationLeavesFallbackWithoutReading() async {
        var reads = 0
        let observer = SnoozeWakeObserver(
            readReceipt: {
                reads += 1
                return nil
            },
            register: { _ in nil },
            cancel: { _ in }
        )
        var diagnostics: [String] = []
        observer.onDiagnostic = { diagnostics.append($0) }

        observer.start()
        // The registration failure is reported synchronously; no
        // startup read follows a nil token.
        XCTAssertFalse(observer.isRegistered)
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(diagnostics.count, 1)
        observer.stop()
    }

    func testFailedReadReportsDiagnostic() async {
        struct Boom: Error {}
        let observer = SnoozeWakeObserver(
            readReceipt: { throw Boom() },
            register: { handler in
                handler()
                return 3
            },
            cancel: { _ in }
        )
        var diagnostics: [String] = []
        observer.onDiagnostic = { diagnostics.append($0) }

        observer.start()
        await waitUntil { !diagnostics.isEmpty }
        XCTAssertTrue(diagnostics[0].contains("read failed"))
        observer.stop()
    }

    func testOverlappingReadsCoalesce() async {
        var reads = 0
        var release: (() -> Void)?
        var handler: (@Sendable () -> Void)?
        let observer = SnoozeWakeObserver(
            readReceipt: {
                reads += 1
                // Block the first read until the test releases it so a
                // second event arrives mid-read.
                if reads == 1 {
                    await withCheckedContinuation { continuation in
                        release = { continuation.resume() }
                    }
                }
                return nil
            },
            register: { captured in
                handler = captured
                captured()
                return 9
            },
            cancel: { _ in }
        )
        observer.start()
        await waitUntil { reads == 1 }
        // Second Darwin event while the first read is still off-main:
        // it coalesces into one follow-up read instead of racing it.
        handler?()
        release?()
        await waitUntil(timeout: 5) { reads == 2 }
        observer.stop()
    }
}
