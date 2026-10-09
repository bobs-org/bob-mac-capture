import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Fetcher tests against fake-bob: exact argv, lane separation, schema
/// rejection, and the golden list through the real client.
final class RefsFetchingTests: XCTestCase {
    func testListRunsTheSnapshotArgv() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let fetcher = BobRefsFetcher(client: try client(
            environment: ["FAKE_BOB_RECORD_PATH": recordURL.path]
        ))

        let response = try await fetcher.list(gitDates: false)

        XCTAssertEqual(response.refs.count, 6)
        XCTAssertEqual(response.skippedRowCount, 0)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=ref list -R all -A -f json"))
        XCTAssertFalse(record.contains("-g"))
    }

    func testListWithGitDatesAddsTheGitFlag() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let fetcher = BobRefsFetcher(client: try client(
            environment: ["FAKE_BOB_RECORD_PATH": recordURL.path]
        ))

        let response = try await fetcher.list(gitDates: true)

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=ref list -R all -A -f json -g"))
        let gitRows = response.refs.filter { $0.addedSource == "git" }
        XCTAssertEqual(gitRows.count, 2)
    }

    func testPlanRunsThePlanArgv() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let fetcher = BobRefsFetcher(client: try client(
            environment: ["FAKE_BOB_RECORD_PATH": recordURL.path]
        ))

        let response = try await fetcher.plan()

        XCTAssertEqual(response.todayTasks.count, 4)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=plan -f json"))
    }

    func testGoldenListDecodesThroughTheFetcher() async throws {
        let golden = try RefsModelTests.fixtureData("refs-list-golden.json")
        let goldenURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try golden.write(to: goldenURL)
        let fetcher = BobRefsFetcher(client: try client(environment: [
            "FAKE_BOB_REFS_LIST_FIXTURE": goldenURL.path,
        ]))

        let response = try await fetcher.list(gitDates: false)

        XCTAssertEqual(response.refs.count, 43)
        XCTAssertEqual(response.skippedRowCount, 1)
    }

    func testSchemaMismatchSurfaces() async throws {
        let fetcher = BobRefsFetcher(client: try client(environment: [
            "FAKE_BOB_PLAN_FIXTURE": "refs-plan-schema3.json",
        ]))

        do {
            _ = try await fetcher.plan()
            XCTFail("expected a schema mismatch")
        } catch let error as BobClientError {
            guard case .schemaMismatch(_, let expected, let actual) = error else {
                return XCTFail("expected schemaMismatch, got \(error)")
            }
            XCTAssertEqual(expected, 2)
            XCTAssertEqual(actual, 3)
        }
    }

    func testSameLaneReplacementCancelsTheFirstFetch() async throws {
        // Lanes live on the client: two `list` calls on one client share
        // `refs-list`, so the second terminates the delayed first.
        let fetcher = BobRefsFetcher(client: try client(environment: [
            "FAKE_BOB_DELAY_SECONDS": "3",
        ]))

        let slow = Task { try await fetcher.list(gitDates: false) }
        try await Task.sleep(nanoseconds: 500_000_000)
        let fast = try await fetcher.list(gitDates: false)

        XCTAssertEqual(fast.refs.count, 6)
        do {
            _ = try await slow.value
            XCTFail("expected the first fetch to be cancelled")
        } catch let error as BobClientError {
            guard case .processFailed = error else {
                throw error
            }
        }
    }

    func testPlanLaneDoesNotCancelTheListLane() async throws {
        // `plan` runs on `refs-plan`: a delayed list plus an immediate plan
        // both succeed because they never share a lane.
        let fetcher = BobRefsFetcher(client: try client(environment: [
            "FAKE_BOB_DELAY_SECONDS": "2",
        ]))

        async let listed = fetcher.list(gitDates: false)
        async let planned = fetcher.plan()
        let (list, plan) = try await (listed, planned)

        XCTAssertEqual(list.refs.count, 6)
        XCTAssertEqual(plan.todayTasks.count, 4)
    }

    private func client(environment: [String: String]) throws -> BobProcessClient {
        BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
                .merging(environment) { _, override in override }
        )
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }
}
