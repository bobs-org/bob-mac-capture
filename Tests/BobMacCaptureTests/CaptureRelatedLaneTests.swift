import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureRelatedLaneTests: XCTestCase {
  private func fakeBobPath() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return root.appendingPathComponent("Tests/Fixtures/fake-bob").path
  }

  private func client(environment extra: [String: String] = [:]) throws -> BobProcessClient {
    var environment = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
    environment.merge(extra) { _, override in override }
    return BobProcessClient(executablePath: try fakeBobPath(), environment: environment)
  }

  private func typeDraft(_ model: CapturePanelModel, _ draft: String) {
    model.plainDraft = draft
    model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
  }

  private func waitUntil(
    timeout: TimeInterval = 3,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      if Date() > deadline {
        XCTFail("Condition was not met before timeout", file: file, line: line)
        return
      }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
  }

  func testSettledRelatedLanePublishesBobRowsAfterTheDraftPause() async throws {
    let recordURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let model = CapturePanelModel(
      processClient: try client(environment: [
        "FAKE_BOB_RECORD_PATH": recordURL.path,
        "FAKE_BOB_RELATED_FIXTURE": "capture-related/recapture.json",
      ]),
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 80_000_000
    )

    typeDraft(model, "Install new UPS battery")
    XCTAssertTrue(model.similarTasks.pending)
    await waitUntil { !model.similarTasks.pending && !model.similarTasks.rows.isEmpty }

    XCTAssertEqual(model.similarTasks.rows.map(\.match.key), ["dev.md#ups", "health.md#ups-health"])
    XCTAssertEqual(model.similarTasks.items.first?.overflowCount, 2)
    XCTAssertEqual(model.similarTasks.draft, "Install new UPS battery")
    let record = try String(contentsOf: recordURL)
    XCTAssertTrue(record.contains("argv=capture-related --format json -- Install new UPS battery"))
  }

  func testRapidEditsAreDebouncedAndTheSettingSuppressesTheLane() async throws {
    let recordURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let model = CapturePanelModel(
      processClient: try client(environment: [
        "FAKE_BOB_RECORD_PATH": recordURL.path,
        "FAKE_BOB_RELATED_FIXTURE": "capture-related/recapture.json",
      ]),
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 100_000_000
    )

    typeDraft(model, "Install")
    try await Task.sleep(nanoseconds: 35_000_000)
    typeDraft(model, "Install new UPS battery")
    await waitUntil { !model.similarTasks.pending && !model.similarTasks.rows.isEmpty }
    try await Task.sleep(nanoseconds: 160_000_000)

    var record = try String(contentsOf: recordURL)
    XCTAssertEqual(record.components(separatedBy: "argv=capture-related").count - 1, 1)

    model.similarTasksEnabled = false
    typeDraft(model, "Buy another UPS battery")
    try await Task.sleep(nanoseconds: 180_000_000)
    record = try String(contentsOf: recordURL)
    XCTAssertEqual(record.components(separatedBy: "argv=capture-related").count - 1, 1)
    XCTAssertTrue(model.similarTasks.rows.isEmpty)
  }

  func testOlderBobHidesTheFeatureQuietlyAfterOneCapabilityCheck() async throws {
    let recordURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let processClient = try client(environment: [
      "FAKE_BOB_RECORD_PATH": recordURL.path,
      "FAKE_BOB_RELATED_UNSUPPORTED": "1",
    ])
    let model = CapturePanelModel(
      processClient: processClient,
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 20_000_000
    )

    typeDraft(model, "Install UPS battery")
    await waitUntil { !model.similarTasks.pending && processClient.captureRelatedKnownUnsupported }
    typeDraft(model, "Install a UPS battery")
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertTrue(model.similarTasks.rows.isEmpty)
    XCTAssertNil(model.errorMessage)
    let record = try String(contentsOf: recordURL)
    XCTAssertEqual(record.components(separatedBy: "argv=capture-related").count - 1, 1)
  }
}
