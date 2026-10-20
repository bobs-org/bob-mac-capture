import CaptureCore
import Combine
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureSavedTemplateShelfTests: XCTestCase {
    func testRefreshLoadsPopulatedListAndKeepsLastGoodOnFailure() async throws {
        let shelf = SavedTemplateShelf(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
            )
        )

        shelf.refresh(reason: .launch)
        await waitUntil { shelf.availability == .available }

        XCTAssertEqual(shelf.count, 3)
        XCTAssertEqual(shelf.capacity, 36)
        XCTAssertTrue(shelf.saving)
        XCTAssertEqual(shelf.templates[0].fieldCount, 3)

        shelf.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": "{",
            ]
        )
        shelf.refresh(reason: .show)
        await waitUntil { shelf.lastRefreshedAt != nil && shelf.count == 3 }

        XCTAssertEqual(shelf.templates[0].id, "6cd8000f52eb")
        XCTAssertEqual(shelf.availability, .available)
    }

    func testRefreshMapsUnsupportedCommandAndHidesFeature() async throws {
        let shelf = SavedTemplateShelf(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_TEMPLATES_UNSUPPORTED": "1",
                ]
            )
        )

        shelf.refresh(reason: .launch)
        await waitUntil { shelf.isUnsupported }

        XCTAssertTrue(shelf.isEmpty)
        XCTAssertTrue(shelf.isUnsupported)
    }

    func testRefreshCoalescesConcurrentCallsIntoOneFollowUp() async throws {
        let shelf = SavedTemplateShelf(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_DELAY_SECONDS": "0.15",
                ]
            )
        )

        shelf.refresh(reason: .launch)
        shelf.refresh(reason: .show)
        shelf.refresh(reason: .submit)
        await waitUntil(timeout: .seconds(4)) { shelf.availability == .available }

        XCTAssertEqual(shelf.count, 3)
    }

    func testShowRefreshSkipsInsideWindowAndRunsOutside() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        var current = Date(timeIntervalSince1970: 1_000)
        let shelf = SavedTemplateShelf(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": recordURL.path,
                ]
            ),
            now: { current }
        )

        shelf.refresh(reason: .launch)
        await waitUntil { shelf.availability == .available }
        XCTAssertEqual(recordArgvCount(recordURL), 1)

        current = Date(timeIntervalSince1970: 1_003)
        shelf.refresh(reason: .show)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(recordArgvCount(recordURL), 1)

        current = Date(timeIntervalSince1970: 1_000 + CaptureShowRefreshWindow.pullThrottleInterval + 0.01)
        shelf.refresh(reason: .show)
        await waitUntil { self.recordArgvCount(recordURL) == 2 }
        XCTAssertEqual(recordArgvCount(recordURL), 2)
    }

    func testNonShowRefreshReasonsAreNeverSkipped() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        var current = Date(timeIntervalSince1970: 1_000)
        let shelf = SavedTemplateShelf(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": recordURL.path,
                ]
            ),
            now: { current }
        )

        shelf.refresh(reason: .launch)
        await waitUntil { shelf.availability == .available }
        current = Date(timeIntervalSince1970: 1_001)
        for reason in [
            SavedTemplateShelfRefreshReason.submit,
            .mutation,
            .recheck,
        ] {
            let before = recordArgvCount(recordURL)
            shelf.refresh(reason: reason)
            await waitUntil { self.recordArgvCount(recordURL) == before + 1 }
            current = current.addingTimeInterval(0.5)
        }
    }

    func testIdenticalListDoesNotRepublishTemplates() async throws {
        let shelf = SavedTemplateShelf(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
            )
        )
        shelf.refresh(reason: .launch)
        await waitUntil { shelf.availability == .available }

        var published = 0
        let cancellable = shelf.$templates.sink { _ in published += 1 }
        XCTAssertEqual(published, 1)
        let firstRefresh = shelf.lastRefreshedAt
        shelf.refresh(reason: .submit)
        await waitUntil { shelf.lastRefreshedAt != firstRefresh }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(published, 1)
        XCTAssertNotNil(cancellable)
    }

    func testReplaceCacheForTestsSeedsEntriesWithoutBob() {
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: [
            CaptureSavedTemplate(index: 1, id: "one", text: "Buy {0}", fieldCount: 1, lineCount: 1)
        ])
        XCTAssertEqual(shelf.count, 1)
        XCTAssertEqual(shelf.availability, .available)
        XCTAssertEqual(shelf.removeLocally(id: "one"), [])
        shelf.restoreLocally([
            CaptureSavedTemplate(index: 1, id: "one", text: "Buy {0}", fieldCount: 1, lineCount: 1)
        ])
        XCTAssertEqual(shelf.template(id: "one")?.text, "Buy {0}")
    }

    private func recordArgvCount(_ url: URL) -> Int {
        guard let text = try? String(contentsOf: url) else {
            return 0
        }
        return text.split(separator: "\n").filter { $0.hasPrefix("argv=") }.count
    }

    private func fakeBobPath() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("fake-bob")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw NSError(domain: "CaptureSavedTemplateShelfTests", code: 1)
        }
        return url.path
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        predicate: @escaping () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !predicate(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        if !predicate() {
            XCTFail("Condition not met before timeout")
        }
    }
}
