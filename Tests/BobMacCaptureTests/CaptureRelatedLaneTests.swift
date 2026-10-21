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
    model.prepareForPresentation()

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
    model.prepareForPresentation()

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
    model.prepareForPresentation()

    typeDraft(model, "Install UPS battery")
    await waitUntil { !model.similarTasks.pending && processClient.captureRelatedKnownUnsupported }
    typeDraft(model, "Install a UPS battery")
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertTrue(model.similarTasks.rows.isEmpty)
    XCTAssertNil(model.errorMessage)
    let record = try String(contentsOf: recordURL)
    XCTAssertEqual(record.components(separatedBy: "argv=capture-related").count - 1, 1)
  }

  func testPreviewLaneUntouchedBySimilarTasksSetting() async throws {
    func previewLines(enabled: Bool) async throws -> [String] {
      let recordURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      let model = CapturePanelModel(
        processClient: try client(environment: [
          "FAKE_BOB_RECORD_PATH": recordURL.path,
          "FAKE_BOB_RELATED_FIXTURE": "capture-related/recapture.json",
        ]),
        debounceNanoseconds: 0,
        similarTasksSettleNanoseconds: 20_000_000
      )
      model.prepareForPresentation()
      model.similarTasksEnabled = enabled
      typeDraft(model, "Install new UPS battery")
      await waitUntil {
        if case .ready = model.previewState { return true }
        return false
      }
      typeDraft(model, "Install new UPS battery backup")
      await waitUntil {
        if case .ready = model.previewState { return true }
        return false
      }
      try await Task.sleep(nanoseconds: 200_000_000)
      let record = (try? String(contentsOf: recordURL)) ?? ""
      return record
        .components(separatedBy: "\n")
        .filter { $0.contains("argv=capture-parse") || $0.contains("argv=capture --dry-run") }
    }
    let on = try await previewLines(enabled: true)
    let off = try await previewLines(enabled: false)
    XCTAssertFalse(on.isEmpty)
    XCTAssertEqual(on, off)
  }

  func testReturnNeverWaitsForSlowRelatedLane() async throws {
    let recordURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let model = CapturePanelModel(
      processClient: try client(environment: [
        "FAKE_BOB_RECORD_PATH": recordURL.path,
        "FAKE_BOB_RELATED_FIXTURE": "capture-related/recapture.json",
        "FAKE_BOB_RELATED_DELAY_SECONDS": "5",
      ]),
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 20_000_000
    )
    model.prepareForPresentation()
    typeDraft(model, "Call bank @Cash")
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertTrue(model.similarTasks.pending)
    let start = Date()
    model.submit(openAfterCapture: false)
    await waitUntil { !model.isSubmitting }
    let elapsed = Date().timeIntervalSince(start)
    XCTAssertLessThan(elapsed, 2.0, "submit waited for the slow related lane")
    XCTAssertEqual(model.plainDraft, "")
    XCTAssertNotNil(model.lastSuccess)
  }

  func testNoSpawnsWhileHiddenAndImmediateFireOnRetainedShow() async throws {
    let recordURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let model = CapturePanelModel(
      processClient: try client(environment: [
        "FAKE_BOB_RECORD_PATH": recordURL.path,
        "FAKE_BOB_RELATED_FIXTURE": "capture-related/recapture.json",
      ]),
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 10_000_000_000
    )
    model.prepareForPresentation()
    typeDraft(model, "Install new UPS battery")
    XCTAssertTrue(model.similarTasks.pending)
    model.prepareForRetainedClose()
    typeDraft(model, "Install new UPS battery edited")
    try await Task.sleep(nanoseconds: 300_000_000)
    let hiddenRecord = (try? String(contentsOf: recordURL)) ?? ""
    XCTAssertEqual(hiddenRecord.components(separatedBy: "argv=capture-related").count - 1, 0)
    model.prepareForPresentation()
    await waitUntil { !model.similarTasks.pending && !model.similarTasks.rows.isEmpty }
    let shownRecord = (try? String(contentsOf: recordURL)) ?? ""
    XCTAssertEqual(shownRecord.components(separatedBy: "argv=capture-related").count - 1, 1)
    XCTAssertEqual(model.similarTasks.draft, "Install new UPS battery edited")
  }

  func testNoSpawnWhileModalOwnsPanel() async throws {
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
    model.prepareForPresentation()
    typeDraft(model, "Install new UPS battery")
    await waitUntil { !model.similarTasks.pending && !model.similarTasks.rows.isEmpty }
    let before = (try? String(contentsOf: recordURL)) ?? ""
    XCTAssertEqual(before.components(separatedBy: "argv=capture-related").count - 1, 1)
    let heldIDs = model.similarTasks.rows.map(\.id)
    let heldDraft = model.similarTasks.draft
    model.installDependencyPickerForPreviews(candidates: [], draft: model.plainDraft)
    XCTAssertTrue(model.pickerVisible)
    typeDraft(model, "Install new UPS battery plus cable")
    try await Task.sleep(nanoseconds: 250_000_000)
    let after = (try? String(contentsOf: recordURL)) ?? ""
    XCTAssertEqual(after.components(separatedBy: "argv=capture-related").count - 1, 1)
    XCTAssertEqual(model.similarTasks.rows.map(\.id), heldIDs)
    XCTAssertEqual(model.similarTasks.draft, heldDraft)
    XCTAssertFalse(model.similarTasks.pending)
  }

  func testStaleResultsNeverPaint() async throws {
    let recordURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let model = CapturePanelModel(
      processClient: try client(environment: [
        "FAKE_BOB_RECORD_PATH": recordURL.path,
        "FAKE_BOB_RELATED_FIXTURE": "capture-related/recapture.json",
        "FAKE_BOB_RELATED_DELAY_SECONDS": "0.3",
      ]),
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 20_000_000
    )
    model.prepareForPresentation()
    typeDraft(model, "Install new UPS battery")
    try await Task.sleep(nanoseconds: 50_000_000)
    typeDraft(model, "Water the plants backup")
    let deadline = Date().addingTimeInterval(3)
    var publishedB = false
    while Date() < deadline {
      if model.similarTasks.draft == "Install new UPS battery" {
        XCTFail("stale response for draft A painted after draft B was typed")
        return
      }
      if model.similarTasks.draft == "Water the plants backup"
        && !model.similarTasks.pending && !model.similarTasks.rows.isEmpty
      {
        publishedB = true
        break
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertTrue(publishedB, "draft B response never published")
    XCTAssertEqual(model.similarTasks.draft, "Water the plants backup")
  }
}
