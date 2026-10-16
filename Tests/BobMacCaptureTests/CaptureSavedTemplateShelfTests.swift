import CaptureCore
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
