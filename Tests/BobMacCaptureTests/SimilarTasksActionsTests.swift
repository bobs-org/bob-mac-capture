import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class SimilarTasksActionsTests: XCTestCase {
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

  private func anchoredItem(
    index: Int = 0,
    draft: String,
    routeRange: CaptureRange? = nil
  ) -> CaptureRelatedItem {
    CaptureRelatedItem(
      index: index,
      mode: "task",
      markerAt: draft.utf8.count,
      routeRange: routeRange,
      discardRange: CaptureRange(start: 0, end: draft.utf8.count)
    )
  }

  private func anchoredMatch(
    key: String = "dev.md#ups",
    defaultAction: CaptureRelatedAction? = .note
  ) -> CaptureRelatedMatch {
    CaptureRelatedMatch(
      key: key,
      band: .possibleDuplicate,
      title: "Install new UPS battery",
      kind: "task",
      statusSymbol: "?",
      statusName: "Blocked",
      route: "dev",
      locator: "dev",
      notePath: "dev.md",
      target: "/Users/test/bob/dev.md",
      line: 42,
      taskRef: "42:ab12cd34",
      blockID: "ups",
      replacements: CaptureRelatedReplacements(
        relationTo: "~dev:ups",
        parent: "@dev+ups",
        dependency: "&dev:ups",
        blockedTask: "*dev:ups"
      ),
      actions: [.relate, .note, .needs, .blocks, .open, .discard],
      defaultAction: defaultAction
    )
  }

  func testApplyDefaultUsesPreselectedNote() async throws {
    let model = CapturePanelModel(
      processClient: try client(environment: [
        "FAKE_BOB_RELATED_FIXTURE": "capture-related/recapture.json",
      ]),
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 20_000_000
    )
    model.plainDraft = "Install new UPS battery"
    model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
    await waitUntil { !model.similarTasks.pending && !model.similarTasks.rows.isEmpty }
    // Recapture fixture rows are same_title with discard default; the
    // default is bob-owned, so assert the model's preselection equals it.
    model.focusSimilarRow(number: 1)
    let row = model.focusedSimilarRow()
    XCTAssertNotNil(row)
    XCTAssertEqual(model.similarChosenAction, row?.match.defaultAction)
    XCTAssertTrue(model.isSimilarRowFocused)
  }

  private func settledIDLessModel() async throws -> CapturePanelModel {
    let model = CapturePanelModel(
      processClient: try client(environment: [
        "FAKE_BOB_RELATED_FIXTURE": "capture-related/idless.json",
      ]),
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 20_000_000
    )
    model.plainDraft = "Install new UPS battery @dev"
    model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
    await waitUntil { !model.similarTasks.pending && model.similarTasks.rows.count == 2 }
    return model
  }

  func testIDLessRowPresentsBlockIDPrompt() async throws {
    let model = try await settledIDLessModel()
    XCTAssertEqual(model.similarTasks.items.first?.overflowCount, 2)
    // Row 2 is the ID-less row: its link actions need a block ID first.
    model.focusSimilarRow(number: 2)
    XCTAssertTrue(model.isSimilarRowFocused)
    model.similarApply(.relate)
    XCTAssertTrue(model.taskIDPromptVisible)
    XCTAssertTrue(model.taskIDPromptIsSimilarTask)
    XCTAssertTrue(model.taskIDPromptCyclesSuggestions)
    XCTAssertEqual(model.taskIDPrompt?.authoredID, "ups-backup")
    XCTAssertEqual(model.taskIDPrompt?.linkSuggestions, ["ups-backup", "ups-spare"])
    XCTAssertEqual(model.statusText, "Add block ID and use task")
    // Tab cycles the suggestions; Escape keeps the band focus with no write.
    model.cycleTaskLinkSuggestion(forward: true)
    XCTAssertEqual(model.taskIDPrompt?.authoredID, "ups-spare")
    model.cancelTaskIDPrompt()
    XCTAssertFalse(model.taskIDPromptVisible)
    XCTAssertTrue(model.isSimilarRowFocused)
    XCTAssertEqual(model.similarTasks.rows.count, 2)
    XCTAssertEqual(model.plainDraft, "Install new UPS battery @dev")
  }

  func testIDLessSubmitSplicesAssignedReplacement() async throws {
    let model = try await settledIDLessModel()
    model.focusSimilarRow(number: 2)
    model.similarApply(.relate)
    XCTAssertTrue(model.taskIDPromptVisible)
    model.submitTaskIDPrompt()
    await waitUntil {
      !model.taskIDPromptVisible && model.plainDraft.contains("~dev:ups-backup")
    }
    XCTAssertEqual(model.plainDraft, "Install new UPS battery @dev ~dev:ups-backup")
    XCTAssertEqual(model.statusText, "Related to Replace the UPS battery backup")
    XCTAssertFalse(model.isSimilarRowFocused)
  }

  func testRevealNextRowAndCollapseOnUnfocus() async throws {
    let model = try await settledIDLessModel()
    XCTAssertEqual(model.similarTasks.rows.map(\.rowNumber), [1, 2])
    model.focusSimilarRow(number: 2)
    // ↓ on the last visible row reveals the next hidden match.
    model.similarSelectNextRow()
    XCTAssertEqual(model.similarTasks.rows.map(\.rowNumber), [1, 2, 3])
    XCTAssertEqual(model.focusedSimilarRow()?.rowNumber, 2)
    // ↓ moves onto the revealed row, then reveals the last hidden one.
    model.similarSelectNextRow()
    XCTAssertEqual(model.focusedSimilarRow()?.rowNumber, 3)
    model.similarSelectNextRow()
    XCTAssertEqual(model.similarTasks.rows.map(\.rowNumber), [1, 2, 3, 4])
    // Unfocusing collapses the reveal back to the capped band.
    model.unfocusSimilarRow()
    XCTAssertEqual(model.similarTasks.rows.map(\.rowNumber), [1, 2])
    XCTAssertFalse(model.isSimilarRowFocused)
  }

  func testReturnDoesNothingWithoutFocus() {
    let model = CapturePanelModel()
    model.plainDraft = "Install new UPS battery @dev"
    model.similarApplyDefault()
    XCTAssertEqual(model.plainDraft, "Install new UPS battery @dev")
    XCTAssertFalse(model.isSimilarRowFocused)
  }

  func testStaleGuardEditsNothing() async throws {
    let model = CapturePanelModel(
      processClient: try client(environment: [
        "FAKE_BOB_RELATED_FIXTURE": "capture-related/recapture.json",
      ]),
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 20_000_000
    )
    model.plainDraft = "Install new UPS battery"
    model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
    await waitUntil { !model.similarTasks.pending && !model.similarTasks.rows.isEmpty }
    model.focusSimilarRow(number: 1)
    // Simulate typing after focus without waiting for the fresh lane:
    // the pending action must wait, not splice stale anchors.
    model.plainDraft = "Install new UPS battery now"
    model.similarApply(.relate)
    XCTAssertEqual(model.plainDraft, "Install new UPS battery now")
    XCTAssertTrue(model.isSimilarRowFocused)
  }

  func testOpenKeepsDraft() async throws {
    let model = CapturePanelModel(
      processClient: try client(environment: [
        "FAKE_BOB_RELATED_FIXTURE": "capture-related/recapture.json",
      ]),
      debounceNanoseconds: 0,
      similarTasksSettleNanoseconds: 20_000_000
    )
    var opened: URL?
    var dismissed = false
    model.taskGotoOpener = { url, completion in
      opened = url
      Task { @MainActor in completion(true) }
    }
    model.panelDismisser = { dismissed = true }
    model.plainDraft = "Install new UPS battery"
    model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
    await waitUntil { !model.similarTasks.pending && !model.similarTasks.rows.isEmpty }
    model.focusSimilarRow(number: 1)
    model.similarApply(.open)
    await waitUntil { dismissed }
    XCTAssertNotNil(opened)
    XCTAssertTrue(opened?.absoluteString.contains("bob-goto-task") == true)
    XCTAssertEqual(model.plainDraft, "Install new UPS battery")
  }

  func testFocusingStaleRowFiresOneImmediateLaneCall() async throws {
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
    model.plainDraft = "Install new UPS battery"
    model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
    await waitUntil { !model.similarTasks.pending && !model.similarTasks.rows.isEmpty }
    try await Task.sleep(nanoseconds: 160_000_000)
    var record = try String(contentsOf: recordURL)
    let settledCount = record.components(separatedBy: "argv=capture-related").count - 1

    // More typing holds the rows, then focusing the held row fires at once.
    model.plainDraft = "Install new UPS battery please"
    model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
    // Focus while the settle for the edited draft is still pending.
    model.focusSimilarRow(number: 1)
    await waitUntil { !model.similarTasks.pending || model.similarTasks.focusedRowID != nil }
    try await Task.sleep(nanoseconds: 200_000_000)
    record = try String(contentsOf: recordURL)
    let total = record.components(separatedBy: "argv=capture-related").count - 1
    XCTAssertGreaterThanOrEqual(total, settledCount + 1)
    XCTAssertTrue(model.isSimilarRowFocused)
  }

  func testRelateSpliceViaFallback() {
    // Pure splice contract lives in CaptureCore; the model applies the same
    // strings through the native bridge or the fallback. Assert the fallback
    // shape here without a lane.
    let draft = "Install new UPS battery @dev"
    let item = anchoredItem(draft: draft)
    let match = anchoredMatch()
    let edited = SimilarTasksBandEdits.editedDraft(draft, item: item, match: match, action: .relate)
    XCTAssertEqual(edited?.text, draft + " ~dev:ups")
  }

  func testNoteReplacesRouteRange() {
    let draft = "Install new UPS battery @dev"
    let route = CaptureRange(start: 24, end: 28)
    let item = anchoredItem(draft: draft, routeRange: route)
    let edited = SimilarTasksBandEdits.editedDraft(
      draft,
      item: item,
      match: anchoredMatch(),
      action: .note
    )
    XCTAssertEqual(edited?.text, "Install new UPS battery @dev+ups")
  }

  func testDiscardRemovesRange() {
    let draft = "First @a\n\nSecond @b"
    let item = anchoredItem(draft: draft)
    let edited = SimilarTasksBandEdits.editedDraft(
      draft,
      item: CaptureRelatedItem(
        index: 0,
        mode: "task",
        markerAt: 8,
        discardRange: CaptureRange(start: 0, end: 9)
      ),
      match: anchoredMatch(),
      action: .discard
    )
    XCTAssertEqual(edited?.text, "\nSecond @b")
    _ = item
  }
}
