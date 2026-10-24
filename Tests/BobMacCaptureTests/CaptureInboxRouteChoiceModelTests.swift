import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureInboxRouteChoiceModelTests: XCTestCase {
  func testPreviewOpensRouteCardAndReturnSubmitsOpaqueAnswer() async throws {
    let record = temporaryURL()
    let responseFile = temporaryURL()
    try write(fixture("inbox-route-moved.json"), to: responseFile)
    let model = makeModel(record: record, responseFile: responseFile)
    model.plainDraft = "@mac_inbox:route-task"
    model.preview()
    try await waitUntil { !model.isPreviewing }

    model.submit(openAfterCapture: false)

    XCTAssertTrue(model.inboxRouteChoiceVisible)
    XCTAssertFalse(model.isSubmitting)
    XCTAssertTrue(model.editorInputLocked)
    XCTAssertEqual(captureCallCount(try recordText(record)), 1)
    XCTAssertEqual(model.inboxRouteChoice?.currentCandidate?.key, "mac_inbox.md#^route-task")

    model.selectInboxRouteDestination("health.md")
    model.confirmInboxRouteChoice()
    try await waitUntil { !model.isSubmitting }

    let calls = try recordText(record)
    XCTAssertEqual(captureCallCount(calls), 2)
    XCTAssertTrue(
      calls.contains(
        "argv=capture --format json --inbox-route mac_inbox.md#^route-task=health.md "
          + "--require-inbox-route-choice --refuse-override -- @mac_inbox:route-task"
      )
    )
    XCTAssertEqual(model.plainDraft, "")
    XCTAssertTrue(model.statusText.contains("moved to health"))
  }

  func testMultipleCandidatesAreAnsweredOneAtATimeInBobOrder() async throws {
    let record = temporaryURL()
    let responseFile = temporaryURL()
    try write(fixture("inbox-route-moved.json"), to: responseFile)
    let model = makeModel(record: record, responseFile: responseFile)
    model.plainDraft = "@mac_inbox:route-task\n\n@gkeep_inbox:gkeep-task"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    model.submit(openAfterCapture: false)

    XCTAssertTrue(model.inboxRouteChoiceVisible)
    XCTAssertEqual(model.inboxRouteChoice?.candidates.map(\.n), [1, 2])
    let candidates = try XCTUnwrap(model.inboxRouteChoice?.candidates)
    let firstKey = try XCTUnwrap(model.inboxRouteChoice?.currentCandidate?.key)
    model.selectInboxRouteDestination("health.md")
    model.confirmInboxRouteChoice()
    XCTAssertEqual(model.inboxRouteChoice?.cursor, 1)
    XCTAssertEqual(model.inboxRouteChoice?.answers[firstKey], .move(destination: "health.md"))
    XCTAssertEqual(captureCallCount(try recordText(record)), 1)

    model.keepInboxRouteCandidate()
    try await waitUntil { !model.isSubmitting }

    let calls = try recordText(record)
    XCTAssertEqual(captureCallCount(calls), 2)
    let submit = try XCTUnwrap(captureBlocks(calls).last)
    let expectedAnswers = candidates.map { candidate in
      candidate.key == firstKey
        ? "--inbox-route \(candidate.key)=health.md"
        : "--inbox-route \(candidate.key)="
    }
    let expectedOrder = expectedAnswers.joined(separator: " ")
    XCTAssertTrue(submit.contains(expectedOrder))
    XCTAssertTrue(submit.contains("--require-inbox-route-choice"))
  }

  func testChoiceRequiredRefusalOpensCardWhenPreviewHadNoCandidates() async throws {
    let record = temporaryURL()
    let responseFile = temporaryURL()
    try write(fixture("inbox-route-choice-required.json"), to: responseFile)
    let model = makeModel(
      record: record,
      responseFile: responseFile,
      dryRunResponse: routeCapabilityWithoutCandidates()
    )
    model.plainDraft = "@mac_inbox:route-task"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    XCTAssertEqual(model.previewInboxRoute?.candidateCount, 0)

    model.submit(openAfterCapture: false)
    try await waitUntil { model.inboxRouteChoiceVisible }

    XCTAssertFalse(model.isSubmitting)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.plainDraft, "@mac_inbox:route-task")
    XCTAssertEqual(captureCallCount(try recordText(record)), 2)
    XCTAssertTrue(try recordText(record).contains("--require-inbox-route-choice"))
  }

  func testOldBobWithoutRouteCapabilitySeesNeitherRouteFlag() async throws {
    let record = temporaryURL()
    let responseFile = temporaryURL()
    try write(oldBobResponse(dryRun: false), to: responseFile)
    let model = makeModel(
      record: record,
      responseFile: responseFile,
      dryRunResponse: oldBobResponse(dryRun: true)
    )
    model.plainDraft = "ordinary capture"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    model.submit(openAfterCapture: false)
    try await waitUntil { !model.isSubmitting }

    let calls = try recordText(record)
    XCTAssertFalse(calls.contains("--require-inbox-route-choice"))
    XCTAssertFalse(calls.contains("--inbox-route"))
  }

  func testRefusedDestinationReopensCandidateAndRetainsAnswers() async throws {
    let record = temporaryURL()
    let responseFile = temporaryURL()
    try write(fixture("inbox-route-refused.json"), to: responseFile)
    let model = makeModel(record: record, responseFile: responseFile)
    model.plainDraft = "@mac_inbox:route-task"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    model.submit(openAfterCapture: false)
    model.selectInboxRouteDestination("health.md")
    model.confirmInboxRouteChoice()
    try await waitUntil { !model.isSubmitting }

    XCTAssertTrue(model.inboxRouteChoiceVisible)
    XCTAssertEqual(model.inboxRouteChoice?.cursor, 0)
    XCTAssertNotNil(model.inboxRouteChoice?.refusalMessage)
    XCTAssertEqual(
      model.inboxRouteChoice?.answers["mac_inbox.md#^route-task"],
      .move(destination: "health.md")
    )
    XCTAssertTrue(model.statusText.contains("inbox"))
  }

  func testStaleRouteClosesCardAndKeepsDraftForFreshChoice() async throws {
    let record = temporaryURL()
    let responseFile = temporaryURL()
    try write(fixture("inbox-route-stale.json"), to: responseFile)
    let model = makeModel(record: record, responseFile: responseFile)
    model.plainDraft = "@mac_inbox:route-task"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    model.submit(openAfterCapture: false)
    model.selectInboxRouteDestination("health.md")
    model.confirmInboxRouteChoice()
    try await waitUntil { !model.isSubmitting }

    XCTAssertFalse(model.inboxRouteChoiceVisible)
    XCTAssertEqual(model.plainDraft, "@mac_inbox:route-task")
    XCTAssertEqual(
      model.statusText,
      "Inbox tasks changed since the preview; press Return to choose again"
    )
  }

  func testPullInPrecedesRouteAndEscapeReturnsToItWithoutWriting() async throws {
    let record = temporaryURL()
    let responseFile = temporaryURL()
    try write(fixture("inbox-route-choice-required.json"), to: responseFile)
    let model = makeModel(
      record: record,
      responseFile: responseFile,
      dryRunResponse: pullInAndRoutePreview()
    )
    model.plainDraft = "!dev:prereq\n\n@mac_inbox:route-task"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    model.submit(openAfterCapture: false)

    XCTAssertTrue(model.pullInChoiceVisible)
    XCTAssertFalse(model.inboxRouteChoiceVisible)
    let selectedOffer = try XCTUnwrap(model.pullInChoice?.effectiveSelectionKeys.first)
    model.confirmPullInChoice()
    try await waitUntil { model.inboxRouteChoiceVisible }

    XCTAssertFalse(model.pullInChoiceVisible)
    XCTAssertEqual(captureCallCount(try recordText(record)), 2)
    model.backInboxRouteChoice()

    XCTAssertTrue(model.pullInChoiceVisible)
    XCTAssertFalse(model.inboxRouteChoiceVisible)
    XCTAssertEqual(model.pullInChoice?.effectiveSelectionKeys, [selectedOffer])
    XCTAssertEqual(captureCallCount(try recordText(record)), 2)
  }

  func testRouteAfterPullInResubmitsBothChoicesAndReusesSeed() async throws {
    let record = temporaryURL()
    let responseFile = temporaryURL()
    try write(fixture("inbox-route-choice-required.json"), to: responseFile)
    let model = makeModel(
      record: record,
      responseFile: responseFile,
      dryRunResponse: pullInAndRoutePreview()
    )
    model.plainDraft = "!dev:prereq\n\n@mac_inbox:route-task"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    model.submit(openAfterCapture: false)
    let selectedOffer = try XCTUnwrap(model.pullInChoice?.effectiveSelectionKeys.first)
    model.confirmPullInChoice()
    try await waitUntil { model.inboxRouteChoiceVisible }

    try write(fixture("inbox-route-moved.json"), to: responseFile)
    model.selectInboxRouteDestination("health.md")
    model.confirmInboxRouteChoice()
    try await waitUntil { !model.isSubmitting }

    let calls = try recordText(record)
    let captureCalls = captureBlocks(calls)
    XCTAssertEqual(captureCalls.count, 3)
    let routeSubmit = try XCTUnwrap(captureCalls.last)
    XCTAssertTrue(
      routeSubmit.contains(
        "--pull-in \(selectedOffer) --inbox-route mac_inbox.md#^route-task=health.md "
          + "--require-inbox-route-choice"
      )
    )
    XCTAssertLessThan(
      try XCTUnwrap(routeSubmit.range(of: "--pull-in")).lowerBound,
      try XCTUnwrap(routeSubmit.range(of: "--inbox-route")).lowerBound
    )
    let seeds = captureCalls.compactMap { block in
      block.components(separatedBy: "BOB_PRIORITY_ROLL_SEED=").dropFirst()
        .first?.components(separatedBy: "\n").first
    }
    XCTAssertEqual(seeds.count, 3)
    XCTAssertEqual(seeds[1], seeds[2])
  }

  private func makeModel(
    record: URL,
    responseFile: URL,
    dryRunResponse: String? = nil,
    writeExit: String = "0"
  ) -> CapturePanelModel {
    var environment = [
      "HOME": "/tmp",
      "PATH": "/usr/bin:/bin",
      "BOB_DIR": "/tmp/inbox-route-test-\(UUID().uuidString)",
      "FAKE_BOB_RECORD_PATH": record.path,
      "FAKE_BOB_CAPTURE_WRITE_STDOUT_FILE": responseFile.path,
      "FAKE_BOB_CAPTURE_WRITE_EXIT": writeExit,
    ]
    if let dryRunResponse {
      environment["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT"] = dryRunResponse
    }
    return CapturePanelModel(
      processClient: BobProcessClient(executablePath: fakeBobPath(), environment: environment),
      debounceNanoseconds: 0
    )
  }

  private func fakeBobPath() -> String {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Tests/Fixtures/fake-bob")
      .path
  }

  private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  private func fixture(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func write(_ text: String, to url: URL) throws {
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  private func recordText(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
  }

  private func captureCallCount(_ record: String) -> Int {
    captureBlocks(record).count
  }

  private func captureBlocks(_ record: String) -> [String] {
    record.components(separatedBy: "argv=")
      .dropFirst()
      .filter { $0.hasPrefix("capture ") }
  }

  private func waitUntil(
    timeout: TimeInterval = 3,
    condition: @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() {
        return
      }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for model state")
  }

  private func routeCapabilityWithoutCandidates() -> String {
    #"""
    {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"day.md","target":"/tmp/day.md","text":"@mac_inbox:route-task","task_line":"- [ ] #task Route me","kind":"task_complete","created":"2026-10-24","placement":"updated","inbox_route":{"supported":true,"candidate_count":0,"routed_count":0,"kept_count":0,"candidates":[]}}
    """#
  }

  private func oldBobResponse(dryRun: Bool) -> String {
    #"""
    {"ok":true,"dry_run":\#(dryRun ? "true" : "false"),"routed":true,"route_label":"cash.md","relative_target":"cash.md","target":"/tmp/bob/cash.md","text":"Task","task_line":"- [ ] #task Task","kind":"task","created":"2026-10-24","placement":"inserted"}
    """#
  }

  private func pullInAndRoutePreview() -> String {
    #"""
    {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"dev.md","target":"/tmp/dev.md","text":"!dev:prereq","task_line":"- [x] #task Prereq ^prereq","kind":"task_complete","created":"2026-10-24","placement":"updated","pull_in":{"supported":true,"offer_count":1,"choice":null,"picked_count":0},"task_complete":{"raw":"!dev:prereq","unblocked":[{"note_path":"dev.md","block_id":"dep","line":6,"text":"Dependent","previous_status_symbol":"?","previous_status_name":"Blocked","status_symbol":" ","status_name":"Ready","not_linked":"not_selected","offer":{"key":"dev.md#^dep","n":1,"group":"hand_off","destination":{"day_file":"20261024.md","entry_name":"WORK","entry_role":"current"}}}]},"inbox_route":{"supported":true,"candidate_count":1,"routed_count":0,"kept_count":0,"candidates":[{"key":"mac_inbox.md#^route-task","n":1,"note_path":"mac_inbox.md","inbox":"mac_inbox","block_id":"route-task","line":6,"text":"Route me","previous_status_symbol":" ","previous_status_name":"Ready","status_symbol":"*","status_name":"Next","outcome":"pending"}],"destinations":[{"relative_path":"health.md","route":"health","label":"health","kind":"area","blocked":false}]}}
    """#
  }
}
