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
    let fetcher = BobRefsFetcher(
      client: try client(
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
    let fetcher = BobRefsFetcher(
      client: try client(
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
    let fetcher = BobRefsFetcher(
      client: try client(
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
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_REFS_LIST_FIXTURE": goldenURL.path
      ]))

    let response = try await fetcher.list(gitDates: false)

    XCTAssertEqual(response.refs.count, 43)
    XCTAssertEqual(response.skippedRowCount, 1)
  }

  func testSchemaMismatchSurfaces() async throws {
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_PLAN_FIXTURE": "refs-plan-schema3.json"
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
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_DELAY_SECONDS": "3"
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
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_DELAY_SECONDS": "2"
      ]))

    async let listed = fetcher.list(gitDates: false)
    async let planned = fetcher.plan()
    let (list, plan) = try await (listed, planned)

    XCTAssertEqual(list.refs.count, 6)
    XCTAssertEqual(plan.todayTasks.count, 4)
  }

  func testScanRunsTheScanArgv() async throws {
    let recordURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let fetcher = BobRefsFetcher(
      client: try client(
        environment: ["FAKE_BOB_RECORD_PATH": recordURL.path]
      ))

    let response = try await fetcher.scan()

    XCTAssertEqual(response.notes.count, 3)
    XCTAssertEqual(response.notes.filter { $0.action == "create" }.count, 2)
    XCTAssertEqual(BobRefsFetcher.scanTimeout, 300)
    let record = try String(contentsOf: recordURL)
    XCTAssertTrue(record.contains("argv=ref scan -a -w -f json"))
  }

  func testScanRetriesWithoutAttendedFlagAndRemembers() async throws {
    let recordURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let client = try client(environment: [
      "FAKE_BOB_RECORD_PATH": recordURL.path,
      "FAKE_BOB_ATTENDED_FLAG_UNSUPPORTED": "1",
    ])
    let fetcher = BobRefsFetcher(client: client)

    let response = try await fetcher.scan()
    XCTAssertEqual(response.notes.count, 3)
    XCTAssertTrue(client.attendedFlagKnownUnsupported)

    _ = try await fetcher.scan()

    let record = try String(contentsOf: recordURL)
    let invocations = Array(record.components(separatedBy: "argv=ref scan").dropFirst())
    XCTAssertEqual(invocations.count, 3)
    XCTAssertTrue(invocations[0].contains(" -a "))
    XCTAssertFalse(invocations[1].contains(" -a "))
    XCTAssertFalse(invocations[2].contains(" -a "))
  }

  func testScanLaneDoesNotCancelItself() async throws {
    // The scan lane never cancels a running scan: two overlapping
    // scans both succeed because they never replace each other.
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_DELAY_SECONDS": "2"
      ]))

    async let first = fetcher.scan()
    async let second = fetcher.scan()
    let (one, two) = try await (first, second)

    XCTAssertEqual(one.notes.count, 3)
    XCTAssertEqual(two.notes.count, 3)
  }

  func testScanRejectsSchemaMismatch() async throws {
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_REFS_SCAN_FIXTURE": "refs-scan-schema2.json"
      ]))

    do {
      _ = try await fetcher.scan()
      XCTFail("expected a schema mismatch")
    } catch let error as BobClientError {
      guard case .schemaMismatch(_, let expected, let actual) = error else {
        return XCTFail("expected schemaMismatch, got \(error)")
      }
      XCTAssertEqual(expected, 1)
      XCTAssertEqual(actual, 2)
    }
  }

  func testScanReturnsPartialReportOnExitOne() async throws {
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_REFS_SCAN_FIXTURE": "refs-scan-partial.json",
        "FAKE_BOB_REFS_SCAN_EXIT": "1",
      ]))

    let response = try await fetcher.scan()

    XCTAssertFalse(response.ok)
    XCTAssertEqual(response.failures.count, 2)
  }

  func testRenameUsesExactArgvAndNonCancellingLane() async throws {
    let recordURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let fetcher = BobRefsFetcher(
      client: try client(
        environment: ["FAKE_BOB_RECORD_PATH": recordURL.path]
      ))

    let response = try await fetcher.rename(
      notePath: "ref/blogs/old.name.md",
      name: "new_name"
    )

    XCTAssertEqual(response.schemaVersion, 1)
    XCTAssertEqual(BobRefsFetcher.renameTimeout, 180)
    let record = try String(contentsOf: recordURL)
    XCTAssertTrue(
      record.contains(
        "argv=ref rename -f json -- ref/blogs/old.name.md new_name"
      ))
  }

  func testOverlappingRenamesDoNotCancelEachOther() async throws {
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_DELAY_SECONDS": "1"
      ]))

    async let first = fetcher.rename(notePath: "ref/blogs/old.md", name: "new")
    async let second = fetcher.rename(notePath: "ref/blogs/old.md", name: "new")
    let (one, two) = try await (first, second)

    XCTAssertEqual(one.to?.path, "ref/blogs/karpathy_llm_wiki.md")
    XCTAssertEqual(two.to?.path, "ref/blogs/karpathy_llm_wiki.md")
  }

  func testRenameErrorEnvelopeDecodesEvenWhenBobExitsOne() async throws {
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_REFS_RENAME_FIXTURE": "refs-rename-error.json",
        "FAKE_BOB_REFS_RENAME_EXIT": "1",
      ]))

    let response = try await fetcher.rename(notePath: "ref/blogs/old.md", name: "new")

    XCTAssertEqual(response.ok, false)
    XCTAssertEqual(response.error?.code, "unknown_reference")
    XCTAssertEqual(
      response.error?.message,
      "no reference note matches missing_ref_xyz"
    )
    XCTAssertNil(RefsRenameProblemMapping.responseProblem(response)?.hint)
  }

  func testOlderBobFailureMapsToUpdateMessage() async throws {
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_REFS_RENAME_EXIT": "2"
      ]))

    do {
      _ = try await fetcher.rename(notePath: "ref/blogs/old.md", name: "new")
      XCTFail("expected old bob process failure")
    } catch {
      XCTAssertEqual(
        RefsRenameProblemMapping.transportProblem(for: error),
        RefsRenameFailure(
          code: "bob_too_old",
          message: "This bob can't rename references yet — update bob on this Mac"
        )
      )
    }
  }

  func testRenameRejectsUnexpectedSchemaVersion() async throws {
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_REFS_RENAME_FIXTURE": "refs-rename-schema2.json"
      ]))

    do {
      _ = try await fetcher.rename(notePath: "ref/blogs/old.md", name: "new")
      XCTFail("expected a schema mismatch")
    } catch let error as BobClientError {
      guard case .schemaMismatch(_, let expected, let actual) = error else {
        return XCTFail("expected schemaMismatch, got \(error)")
      }
      XCTAssertEqual(expected, 1)
      XCTAssertEqual(actual, 2)
    }
  }

  func testTodaySelectorsAndDryRunArgv() async throws {
    let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: recordURL) }
    let fetcher = BobRefsFetcher(
      client: try client(environment: ["FAKE_BOB_RECORD_PATH": recordURL.path]))
    let selectors: [(RefsTodayLinkSelector, String)] = [
      (.automatic, ""), (.entry(ref: "2:abcd"), "-P 2:abcd "),
      (.exactName("deep work"), "-p deep work -e "),
    ]
    for (selector, args) in selectors {
      for dryRun in [true, false] {
        let response = try await fetcher.linkToToday(
          notePath: "-ref with spaces.md", selector: selector, dryRun: dryRun)
        XCTAssertEqual(response.ok, true)
        XCTAssertEqual(response.capture?.dryRun, dryRun)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
          record.contains(
            "argv=ref today -f json \(dryRun ? "-d " : "")\(args)-- -ref with spaces.md\n"))
      }
    }
    XCTAssertEqual(BobRefsFetcher.todayLinkTimeout, 30)
    XCTAssertEqual(BobProcessClient.defaultTimeout, 20)
  }

  func testTodayErrorEnvelopeExitOneAndOlderBobExitTwo() async throws {
    let fetcher = BobRefsFetcher(
      client: try client(environment: [
        "FAKE_BOB_REF_TODAY_FIXTURE": "refs-today-multiple-running.json",
        "FAKE_BOB_REF_TODAY_EXIT": "1",
      ]))
    let response = try await fetcher.linkToToday(notePath: "ref/a.md", dryRun: true)
    XCTAssertEqual(response.ok, false)
    XCTAssertEqual(response.error?.code, "multiple_running")
    XCTAssertEqual(response.pomodoros.count, 2)
    XCTAssertEqual(RefsTodayLinkProblemMapping.responseProblem(response), response.error)

    let old = BobRefsFetcher(client: try client(environment: ["FAKE_BOB_REF_TODAY_EXIT": "2"]))
    do {
      _ = try await old.linkToToday(notePath: "ref/a.md", dryRun: false)
      XCTFail("expected older bob failure")
    } catch {
      XCTAssertEqual(
        RefsTodayLinkProblemMapping.transportProblem(for: error),
        .init(
          code: "bob_too_old",
          message: "This bob can't link references to today yet — update bob on this Mac"))
    }
  }

  func testTodaySchemaMismatchAndTransportMapping() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"schema_version":2,"ok":true}"#.utf8).write(to: url)
    let fetcher = BobRefsFetcher(
      client: try client(environment: ["FAKE_BOB_REF_TODAY_FIXTURE": url.path]))
    do {
      _ = try await fetcher.linkToToday(notePath: "ref/a.md", dryRun: true)
      XCTFail("expected schema mismatch")
    } catch let error as BobClientError {
      guard case .schemaMismatch(_, let expected, let actual) = error else {
        return XCTFail("\(error)")
      }
      XCTAssertEqual(expected, 1)
      XCTAssertEqual(actual, 2)
    }
    XCTAssertEqual(
      RefsTodayLinkProblemMapping.transportProblem(for: NSError(domain: "test", code: 1)).code,
      "transport")
  }

  func testTodayTimeoutMapping() {
    let failure = RefsTodayLinkProblemMapping.transportProblem(
      for: BobClientError.timedOut(command: ["bob", "ref", "today"], seconds: 30))
    XCTAssertEqual(failure.code, "timed_out")
    XCTAssertEqual(failure.message, "Linking the reference took too long and was stopped.")
    XCTAssertEqual(failure.hint, "Check today's ledger and try again.")
  }

  func testTodayPreviewsCancelPreviousPreviewLaneOnly() async throws {
    let process = try client(environment: ["FAKE_BOB_DELAY_SECONDS": "0.5"])
    let fetcher = BobRefsFetcher(client: process)
    let first = Task {
      let response: RefsTodayLinkResponse = try await process.decodeReport(
        arguments: ["ref", "today"], expectedSchema: 1, lane: "refs-today-preview")
      return response
    }
    try await Task.sleep(nanoseconds: 200_000_000)
    let second = try await fetcher.linkToToday(notePath: "ref/a.md", dryRun: true)
    XCTAssertEqual(second.ok, true)
    do {
      _ = try await first.value
      XCTFail("expected preview cancellation")
    } catch let error as BobClientError {
      guard case .processFailed = error else { throw error }
    }
  }

  func testTodayWritesNeverCancelAndPreviewsUseSeparateLane() async throws {
    let fetcher = BobRefsFetcher(client: try client(environment: ["FAKE_BOB_DELAY_SECONDS": "0.3"]))
    async let first = fetcher.linkToToday(notePath: "ref/a.md", dryRun: false)
    async let second = fetcher.linkToToday(
      notePath: "ref/a.md", selector: .exactName("read"), dryRun: false)
    async let preview = fetcher.linkToToday(notePath: "ref/a.md", dryRun: true)
    let responses = try await [first, second, preview]
    XCTAssertEqual(responses.map(\.ok), [true, true, true])
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
    let packageRoot =
      source
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return
      packageRoot
      .appendingPathComponent("Tests/Fixtures/fake-bob")
      .path
  }
}
