import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CapturePullInChoiceModelTests: XCTestCase {
  func testPreviewOpensChoiceAndEscapePerformsNoCaptureWrite() async throws {
    let record = temporaryRecordURL()
    let model = makeModel(record: record, stdout: successResponse())
    model.plainDraft = "complete task"
    model.preview()
    try await waitUntil { !model.isPreviewing }

    model.submit(openAfterCapture: false)
    XCTAssertTrue(model.pullInChoiceVisible)
    XCTAssertFalse(model.isSubmitting)
    XCTAssertTrue(model.pullInChoice?.markedKeys.isEmpty == true)
    XCTAssertEqual(model.pullInChoice?.effectiveSelectionKeys, ["offer#one^key"])
    XCTAssertTrue(model.editorInputLocked)
    XCTAssertEqual(try recordText(record).components(separatedBy: "argv=capture").count - 1, 1)

    model.cancelPullInChoiceFromKeyboard()
    XCTAssertFalse(model.pullInChoiceVisible)
    XCTAssertFalse(model.editorInputLocked)
    XCTAssertEqual(model.plainDraft, "complete task")
    XCTAssertEqual(model.focusRequest.target, .editor)
    XCTAssertEqual(try recordText(record).components(separatedBy: "argv=capture").count - 1, 1)
  }

  func testMarkedSubsetDispatchesOpaqueKeysOnceAndKeepsOpenAfterIntent() async throws {
    let record = temporaryRecordURL()
    let model = makeModel(record: record, stdout: successResponse())
    model.plainDraft = "complete task"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    model.submit(openAfterCapture: true)
    XCTAssertTrue(model.pullInChoiceVisible)

    model.movePullInChoiceHighlight(by: 1)
    model.toggleHighlightedPullInOffer()
    XCTAssertEqual(model.pullInChoice?.markedKeys, ["opaque:two#^suffix"])
    var opened: [URL] = []
    var dismissed = 0
    model.targetOpener = { opened.append($0) }
    model.panelDismisser = { dismissed += 1 }
    let controller = CapturePanelController(model: model)
    XCTAssertTrue(controller.perform(.confirmPullInChoice))
    try await waitUntil { !model.isSubmitting }

    XCTAssertNil(model.pullInChoice)
    XCTAssertEqual(model.plainDraft, "")
    XCTAssertEqual(opened, [URL(fileURLWithPath: "/tmp/day.md")])
    XCTAssertEqual(dismissed, 1)
    let calls = try recordText(record)
    XCTAssertEqual(calls.components(separatedBy: "argv=capture").count - 1, 2)
    XCTAssertTrue(calls.contains("argv=capture --format json --dry-run -- complete task"))
    XCTAssertTrue(
      calls.contains("argv=capture --format json --pull-in opaque:two#^suffix -- complete task"))
    XCTAssertFalse(calls.contains("--require-pull-in-choice"))
    let seeds = calls.components(separatedBy: "BOB_PRIORITY_ROLL_SEED=").dropFirst()
      .compactMap { $0.components(separatedBy: "\n").first }
    XCTAssertEqual(seeds.count, 2)
    XCTAssertEqual(seeds[0], seeds[1])
  }

  func testShiftReturnSubmitsExplicitNone() async throws {
    let record = temporaryRecordURL()
    let model = makeModel(record: record, stdout: successResponse())
    model.plainDraft = "complete task"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    model.submit(openAfterCapture: false)
    XCTAssertTrue(model.pullInChoiceVisible)

    let controller = CapturePanelController(model: model)
    XCTAssertTrue(controller.perform(.chooseNoPullInOffers))
    try await waitUntil { !model.isSubmitting }
    XCTAssertTrue(
      try recordText(record).contains("argv=capture --format json --pull-in none -- complete task"))
    XCTAssertEqual(model.plainDraft, "")
  }

  func testGuardRefusalOpensChoiceWithoutFailureOrDraftLoss() async throws {
    let record = temporaryRecordURL()
    let model = makeModel(record: record, stdout: refusalResponse(), exit: "1")
    model.plainDraft = "complete task"
    model.preview()
    try await waitUntil { !model.isPreviewing }
    XCTAssertFalse(model.pullInChoiceVisible)

    model.submit(openAfterCapture: false)
    try await waitUntil { model.pullInChoiceVisible }

    XCTAssertFalse(model.isSubmitting)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.plainDraft, "complete task")
    XCTAssertEqual(model.pullInChoice?.selectableKeys, ["refusal:key"])
    let calls = try recordText(record)
    XCTAssertEqual(calls.components(separatedBy: "argv=capture").count - 1, 2)
    XCTAssertTrue(calls.contains("--require-pull-in-choice"))
  }

  func testDraftChangeInvalidatesChoiceAndPicks() {
    let model = CapturePanelModel()
    model.installPullInChoiceForPreviews(
      offers: [testOffer(key: "one"), testOffer(key: "two", number: 2)],
      pullIn: CapturePullIn(supported: true, offerCount: 2),
      draft: "original"
    )
    model.markAllPullInOffers()
    XCTAssertTrue(model.pullInChoiceVisible)
    model.plainDraft = "edited"
    model.editorTextDidChange()

    XCTAssertFalse(model.pullInChoiceVisible)
    XCTAssertEqual(model.plainDraft, "edited")
    XCTAssertFalse(model.editorInputLocked)
  }

  private func makeModel(record: URL, stdout: String, exit: String = "0") -> CapturePanelModel {
    CapturePanelModel(
      processClient: BobProcessClient(
        executablePath: fakeBobPath(),
        environment: [
          "HOME": "/tmp",
          "PATH": "/usr/bin:/bin",
          "FAKE_BOB_RECORD_PATH": record.path,
          "FAKE_BOB_STDOUT": stdout,
          "FAKE_BOB_EXIT": exit,
        ]
      ),
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

  private func temporaryRecordURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  private func recordText(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
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

  private func testOffer(key: String, number: Int = 1) -> TaskCompleteUnblocked {
    TaskCompleteUnblocked(
      notePath: "travel.md",
      blockID: "task-\(number)",
      line: number,
      text: "Task \(number)",
      statusSymbol: " ",
      statusName: "Ready",
      notLinked: "not_selected",
      offer: TaskCompleteOffer(
        key: key,
        n: number,
        group: "hand_off",
        destination: TaskCompleteOfferDestination(dayFile: "20261013.md")
      )
    )
  }

  private func successResponse() -> String {
    #"""
    {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"day.md","target":"/tmp/day.md","text":"!task","task_line":"- [ ] #task Task","kind":"task_complete","created":"2026-10-13","placement":"updated","pull_in":{"supported":true,"offer_count":2,"choice":null,"picked_count":0,"groups":[{"group":"hand_off","project":"","folded":{"hidden":0,"already_planned":0,"sub_projects":0}}]},"task_complete":{"raw":"!travel:parent","unblocked":[{"note_path":"travel.md","block_id":"one","line":1,"text":"One task","previous_status_symbol":"?","previous_status_name":"Blocked","status_symbol":" ","status_name":"Ready","not_linked":"not_selected","offer":{"key":"offer#one^key","n":1,"group":"hand_off","project":null,"destination":{"day_file":"20261013.md","entry_name":"FOCUS","entry_role":"current","fallback":false},"selected":false,"block_id_needed":false}},{"note_path":"travel.md","block_id":"two","line":2,"text":"Two task","previous_status_symbol":"?","previous_status_name":"Blocked","status_symbol":" ","status_name":"Ready","not_linked":"not_selected","offer":{"key":"opaque:two#^suffix","n":2,"group":"hand_off","project":null,"destination":{"day_file":"20261013.md","entry_name":"FOCUS","entry_role":"current","fallback":false},"selected":false,"block_id_needed":false}}]}}
    """#
  }

  private func refusalResponse() -> String {
    #"{"ok":false,"error":"Choose successor offers","code":"pull_in_choice_required","pull_in":{"supported":true,"offer_count":1,"choice":"explicit","picked_count":0},"offers":[{"note_path":"travel.md","block_id":"one","line":1,"text":"One task","previous_status_symbol":"?","previous_status_name":"Blocked","status_symbol":" ","status_name":"Ready","not_linked":"not_selected","offer":{"key":"refusal:key","n":1,"group":"hand_off","destination":{"day_file":"20261013.md","entry_name":"FOCUS","entry_role":"current","fallback":false},"selected":false,"block_id_needed":false}}]}"#
  }
}
