import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class WalkAttentionStoreTests: XCTestCase {
    private func fakeBobPath() throws -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func makeStore(
        environment: [String: String] = [:],
        recordURL: URL? = nil,
        today: String = "2026-11-17",
        debounce: TimeInterval = 0.03
    ) throws -> WalkAttentionStore {
        var full = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        for (key, value) in environment {
            full[key] = value
        }
        if let recordURL {
            full["FAKE_BOB_RECORD_PATH"] = recordURL.path
        }
        let client = BobProcessClient(executablePath: try fakeBobPath(), environment: full)
        return WalkAttentionStore(
            processClient: client,
            vaultRootPath: "/vault",
            today: { today },
            debounceInterval: { _ in debounce },
            workspaceCenter: NotificationCenter(),
            defaultCenter: NotificationCenter()
        )
    }

    private func recordedInvocations(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url) else {
            return []
        }
        return text.split(separator: "\n").map(String.init).filter {
            $0.hasPrefix("argv=")
        }
    }

    func testLaunchPublishesTodayAndShowUsesFreshCache() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = try makeStore(recordURL: recordURL)

        store.refresh(reason: .launch)
        await waitUntil { store.status == .ready }

        XCTAssertEqual(store.snapshot?.date, "2026-11-17")
        XCTAssertEqual(store.snapshot?.walks.map(\.family.letter), ["s", "w", "b"])
        XCTAssertEqual(store.snapshot?.walks.first?.count, 18)
        XCTAssertNotNil(store.lastRefreshedAt)
        XCTAssertEqual(recordedInvocations(recordURL).count, 1)

        store.panelVisibilityDidChange(true)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(recordedInvocations(recordURL).count, 1)
    }

    func testRelevantVaultChangesTrailAndIrrelevantChangesDoNothing() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = try makeStore(recordURL: recordURL, debounce: 0.3)
        store.refresh(reason: .launch)
        await waitUntil { store.status == .ready }

        store.vaultDidChange(VaultChangeBatch(paths: ["/vault/.git/index"]))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(recordedInvocations(recordURL).count, 1)

        store.vaultDidChange(VaultChangeBatch(paths: ["/vault/Projects/a.md"]))
        try? await Task.sleep(nanoseconds: 15_000_000)
        store.vaultDidChange(VaultChangeBatch(paths: ["/vault/Projects/b.md"]))
        await waitUntil { self.recordedInvocations(recordURL).count == 2 }
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(recordedInvocations(recordURL).count, 2)
    }

    func testFailureKeepsLastGoodSameDaySnapshot() async throws {
        let store = try makeStore()
        store.refresh(reason: .launch)
        await waitUntil { store.status == .ready }
        let previous = store.snapshot

        store.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_WALKS_FAIL": "1",
            ]
        )
        store.refresh(reason: .submit)
        await waitUntil {
            if case .stale = store.status { return true }
            return false
        }

        XCTAssertEqual(store.snapshot, previous)
        XCTAssertTrue(store.diagnosticLine().hasPrefix("Walk marks couldn't refresh:"))
    }

    func testUnsupportedAndOtherDayReportsNeverShowMarks() async throws {
        let unsupported = try makeStore(environment: ["FAKE_BOB_WALKS_UNSUPPORTED": "1"])
        unsupported.refresh(reason: .launch)
        await waitUntil { unsupported.status == .unsupported }
        XCTAssertNil(unsupported.snapshot)
        XCTAssertEqual(unsupported.diagnosticLine(), "Upgrade bob for walk marks")

        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let otherDay = try makeStore(recordURL: recordURL, today: "2026-11-18")
        otherDay.refresh(reason: .launch)
        await waitUntil { otherDay.lastRefreshedAt != nil }
        XCTAssertNil(otherDay.snapshot)
        XCTAssertNotNil(otherDay.lastRefreshedAt)

        otherDay.panelVisibilityDidChange(true)
        await waitUntil { self.recordedInvocations(recordURL).count == 2 }
        XCTAssertNil(otherDay.snapshot)
    }
}
