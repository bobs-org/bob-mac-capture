import Foundation
import XCTest

@testable import CaptureCore

final class CaptureSavedTemplatesTests: XCTestCase {
  func testRecordedListFixtureDecodesShelfAndPresentationFields() throws {
    let response = try JSONDecoder().decode(
      CaptureSavedTemplatesResponse.self,
      from: fixture("capture-templates-list-populated.json")
    )

    XCTAssertEqual(response.schemaVersion, 1)
    XCTAssertEqual(response.capacity, 36)
    XCTAssertTrue(response.saving)
    XCTAssertEqual(response.templates.count, 3)
    XCTAssertEqual(response.templates[0].fieldCount, 3)
    XCTAssertEqual(response.templates[0].lineCount, 2)
    XCTAssertEqual(response.templates[0].route, "job")
    XCTAssertEqual(
      response.templates[0].spans.map(\.kind),
      [
        "template_placeholder", "task_block_id_route", "task_block_id", "template_placeholder",
        "template_placeholder",
      ]
    )
    XCTAssertFalse(response.templates[0].id.isEmpty)
    XCTAssertEqual(response.templates[1].fieldCount, 2)
    XCTAssertEqual(response.templates[2].fieldCount, 1)

    let empty = try JSONDecoder().decode(
      CaptureSavedTemplatesResponse.self,
      from: fixture("capture-templates-list-empty.json")
    )
    XCTAssertTrue(empty.templates.isEmpty)

    let savingOff = try JSONDecoder().decode(
      CaptureSavedTemplatesResponse.self,
      from: fixture("capture-templates-list-saving-off.json")
    )
    XCTAssertFalse(savingOff.saving)
    XCTAssertEqual(savingOff.capacity, 0)
  }

  func testModelsTolerateOlderAndMalformedAdditiveFields() throws {
    let response = try JSONDecoder().decode(
      CaptureSavedTemplatesResponse.self,
      from: Data(
        """
        {"schema_version":1,"capacity":8,"saving":true,"file":"/tmp/templates.json","templates":[{"id":"old","text":"Task {0}","draft":"@@template:\\nTask {0}\\n\\n","cursor":30}],"warnings":[]}
        """.utf8)
    )
    XCTAssertEqual(response.templates.first?.index, 0)
    XCTAssertEqual(response.templates.first?.fieldCount, 0)
    XCTAssertTrue(response.templates.first?.spans.isEmpty == true)
    XCTAssertNil(response.templates.first?.lastUsedAt)

    let malformed = try JSONDecoder().decode(
      CaptureSavedTemplate.self,
      from: Data(#"{"id":42,"field_count":"three","spans":"bad","use_count":-1}"#.utf8)
    )
    XCTAssertEqual(malformed.id, "")
    XCTAssertEqual(malformed.fieldCount, 0)
    XCTAssertTrue(malformed.spans.isEmpty)
    XCTAssertEqual(malformed.useCount, 0)

    let missingSchema = try JSONDecoder().decode(
      CaptureSavedTemplatesResponse.self,
      from: Data("{}".utf8)
    )
    XCTAssertEqual(missingSchema.schemaVersion, 0)
  }

  func testRecordedSaveDeleteAndClearFixturesDecode() throws {
    let new = try JSONDecoder().decode(
      CaptureTemplateSaveResponse.self,
      from: fixture("capture-templates-save-new.json")
    )
    XCTAssertTrue(new.ok)
    XCTAssertEqual(new.saved?.status, .new)
    XCTAssertEqual(new.saved?.id, new.template?.id)

    let replaced = try JSONDecoder().decode(
      CaptureTemplateSaveResponse.self,
      from: fixture("capture-templates-save-replaced.json")
    )
    XCTAssertEqual(replaced.saved?.status, .replaced)

    let delete = try JSONDecoder().decode(
      CaptureTemplateDeleteResponse.self,
      from: fixture("capture-templates-delete.json")
    )
    XCTAssertEqual(delete.deleted.count, 1)
    XCTAssertEqual(delete.missing.count, 1)

    let clear = try JSONDecoder().decode(
      CaptureTemplateClearResponse.self,
      from: fixture("capture-templates-clear.json")
    )
    XCTAssertEqual(clear.cleared, 2)

    let invalid = try JSONDecoder().decode(
      CaptureTemplateSaveResponse.self,
      from: fixture("capture-templates-save-invalid.json")
    )
    XCTAssertFalse(invalid.ok)
    XCTAssertEqual(invalid.code, "template_missing_placeholder")
    XCTAssertEqual(invalid.error, "template line 2: add at least one placeholder such as {0}")
  }

  func testCaptureTemplateSummaryDecodesSaveOutcomesAndOlderPayloads() throws {
    let old = try JSONDecoder().decode(
      CaptureTemplateSummary.self,
      from: Data(#"{"line":2,"field_count":3,"row_count":1}"#.utf8)
    )
    XCTAssertEqual(old.fieldCount, 3)
    XCTAssertNil(old.saved)
    XCTAssertNil(old.notSaved)

    let saved = try JSONDecoder().decode(
      CaptureTemplateSummary.self,
      from: Data(
        #"{"line":2,"field_count":3,"row_count":1,"saved":{"id":"abc","status":"replaced"}}"#.utf8)
    )
    XCTAssertEqual(saved.saved?.status, .replaced)

    let unknown = try JSONDecoder().decode(
      CaptureTemplateSavedSummary.self,
      from: Data(#"{"id":"abc","status":"future-status"}"#.utf8)
    )
    XCTAssertEqual(unknown.status, .unknown)

    let notSaved = try JSONDecoder().decode(
      CaptureTemplateSummary.self,
      from: Data(#"{"not_saved":"disk full"}"#.utf8)
    )
    XCTAssertEqual(notSaved.notSaved, "disk full")
  }

  func testRecordedCaptureSuccessFixturesCarrySavedAndNotSavedOutcomes() throws {
    let new = try decodeCaptureFixture("capture-template-saved-new.json")
    XCTAssertEqual(captureTemplate(from: new)?.saved?.status, .new)

    let replaced = try decodeCaptureFixture("capture-template-saved-replaced.json")
    XCTAssertEqual(captureTemplate(from: replaced)?.saved?.status, .replaced)

    let notSaved = try decodeCaptureFixture("capture-template-not-saved.json")
    XCTAssertEqual(
      captureTemplate(from: notSaved)?.notSaved,
      "write shelf: File exists (os error 17)"
    )
  }

  func testPresentationBuildsSpanSegmentsMetadataDotsAndAccessibility() throws {
    let text = "Apply to {0}! @job^apply-{1}\n- **URL**: {2}\nNote {3}"
    let template = CaptureSavedTemplate(
      index: 1,
      id: "template-id",
      text: text,
      fieldCount: 4,
      lineCount: 3,
      route: "job",
      spans: [
        span("{0}", kind: "template_placeholder", field: 0, in: text),
        span("@job", kind: "pomodoro_route", in: text),
        span("^apply-", kind: "task_block_id", in: text),
        span("{1}", kind: "template_placeholder", field: 1, in: text),
        span("{2}", kind: "template_placeholder", field: 2, in: text),
      ],
      firstSavedAt: "2026-10-16T12:58:00Z"
    )

    let row = CaptureSavedTemplatePresentation(
      template: template,
      now: ISO8601DateFormatter().date(from: "2026-10-16T13:00:00Z")!
    )

    XCTAssertEqual(row.parentText, "Apply to {0}! @job^apply-{1}")
    XCTAssertEqual(row.firstChildText, "- **URL**: {2}")
    XCTAssertEqual(
      row.parentLine.map(\.category),
      [.neutral, .templateSlot(0), .neutral, .route, .blockID, .templateSlot(1)]
    )
    XCTAssertEqual(row.firstChildLine?.map(\.category), [.neutral, .templateSlot(2)])
    XCTAssertEqual(row.moreLinesCount, 1)
    XCTAssertEqual(row.slotDotFields, [0, 1, 2, 3])
    XCTAssertEqual(row.slotOverflowCount, 0)
    XCTAssertEqual(row.metadataText, "4 fields · job · saved 2m ago")
    XCTAssertEqual(
      row.accessibilityLabel,
      "Template 1, Apply to {0}! @job^apply-{1}, 4 fields, job, saved 2 minutes ago")
    XCTAssertEqual(
      row.accessibilityHint,
      "Press 1 or Return to use this template. Press Delete twice to delete it.")
  }

  func testPresentationUsesSingularAndPluralUseCountsAndCapsDots() throws {
    let now = ISO8601DateFormatter().date(from: "2026-10-16T13:00:00Z")!
    let usedOnce = CaptureSavedTemplatePresentation(
      template: CaptureSavedTemplate(
        index: 2,
        id: "one",
        text: "Buy {0} @grocery",
        fieldCount: 1,
        lineCount: 1,
        route: "grocery",
        spans: [span("{0}", kind: "template_placeholder", field: 0, in: "Buy {0} @grocery")],
        firstSavedAt: "2026-10-16T10:00:00Z",
        lastUsedAt: "2026-10-16T12:00:00Z",
        useCount: 1
      ),
      now: now
    )
    XCTAssertEqual(usedOnce.metadataText, "1 field · grocery · used 1× · 1h ago")
    XCTAssertEqual(
      usedOnce.accessibilityLabel,
      "Template 2, Buy {0} @grocery, 1 field, grocery, used 1 time, 1 hour ago")
    XCTAssertEqual(
      usedOnce.accessibilityHint,
      "Press 2 or Return to use this template. Press Delete twice to delete it.")

    let usedMany = CaptureSavedTemplatePresentation(
      template: CaptureSavedTemplate(
        index: 7,
        id: "many",
        text: "{0} {1} {2} {3} {4} {5} {6} {7}",
        fieldCount: 8,
        lineCount: 1,
        firstSavedAt: "2026-10-15T13:00:00Z",
        lastUsedAt: "2026-10-16T12:00:00Z",
        useCount: 14
      ),
      now: now
    )
    XCTAssertEqual(usedMany.slotDotFields, [0, 1, 2, 3, 4, 5])
    XCTAssertEqual(usedMany.slotOverflowCount, 2)
    XCTAssertEqual(usedMany.metadataText, "8 fields · used 14× · 1h ago")
    XCTAssertEqual(
      usedMany.accessibilityLabel,
      "Template 7, {0} {1} {2} {3} {4} {5} {6} {7}, 8 fields, used 14 times, 1 hour ago")
  }

  func testBobProcessClientListsSavesDeletesAndClearsOnIndependentLanes() async throws {
    let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let client = BobProcessClient(
      executablePath: try fakeBobPath(),
      environment: [
        "HOME": "/tmp",
        "PATH": "/usr/bin:/bin",
        "FAKE_BOB_RECORD_PATH": recordURL.path,
        "FAKE_BOB_TEMPLATES_LIST_FIXTURE": "capture-templates-list-populated.json",
        "FAKE_BOB_TEMPLATES_SAVE_FIXTURE": "capture-templates-save-new.json",
        "FAKE_BOB_TEMPLATES_DELETE_FIXTURE": "capture-templates-delete.json",
        "FAKE_BOB_TEMPLATES_CLEAR_FIXTURE": "capture-templates-clear.json",
      ]
    )

    let list = try await client.savedTemplates()
    let save = try await client.saveTemplate("@@template:\nBuy {0}\n\n", origin: "origin123")
    let delete = try await client.deleteSavedTemplates(ids: ["one", "two"])
    let clear = try await client.clearSavedTemplates()

    XCTAssertEqual(list.templates.count, 3)
    XCTAssertEqual(save.saved?.status, .new)
    XCTAssertEqual(delete.deleted, ["d55d6407f700"])
    XCTAssertEqual(clear.cleared, 2)

    let record = try String(contentsOf: recordURL)
    XCTAssertTrue(record.contains("argv=capture-templates --format json"))
    XCTAssertTrue(
      record.contains(
        "argv=capture-templates save --format json --template-origin origin123 -- @@template:"))
    XCTAssertTrue(record.contains("argv=capture-templates delete one two --format json"))
    XCTAssertTrue(record.contains("argv=capture-templates clear --format json"))
  }

  func testUnknownCaptureTemplatesCommandMapsToUnsupported() async throws {
    let client = BobProcessClient(
      executablePath: try fakeBobPath(),
      environment: [
        "HOME": "/tmp",
        "PATH": "/usr/bin:/bin",
        "FAKE_BOB_TEMPLATES_UNSUPPORTED": "1",
      ]
    )

    do {
      _ = try await client.savedTemplates()
      XCTFail("Expected an unsupported command error")
    } catch BobClientError.unsupportedCommand(let command) {
      XCTAssertEqual(command, "capture-templates")
    }
  }

  func testSavedTemplatesRequiresSchemaVersionOne() async throws {
    let client = BobProcessClient(
      executablePath: try fakeBobPath(),
      environment: [
        "HOME": "/tmp",
        "PATH": "/usr/bin:/bin",
        "FAKE_BOB_STDOUT": "{\"ok\":true,\"schema_version\":2}",
      ]
    )

    do {
      _ = try await client.savedTemplates()
      XCTFail("Expected a schema mismatch")
    } catch BobClientError.schemaMismatch(_, let expected, let actual) {
      XCTAssertEqual(expected, 1)
      XCTAssertEqual(actual, 2)
    }
  }

  func testSaveReturnsBobDefinitionRefusalFromJSONEvenWithNonzeroExit() async throws {
    let client = BobProcessClient(
      executablePath: try fakeBobPath(),
      environment: [
        "HOME": "/tmp",
        "PATH": "/usr/bin:/bin",
        "FAKE_BOB_TEMPLATES_SAVE_FIXTURE": "capture-templates-save-invalid.json",
        "FAKE_BOB_TEMPLATES_EXIT": "2",
      ]
    )

    let response = try await client.saveTemplate("@@template:\nNo fields\n\n")
    XCTAssertFalse(response.ok)
    XCTAssertEqual(response.code, "template_missing_placeholder")
    XCTAssertEqual(response.error, "template line 2: add at least one placeholder such as {0}")
  }

  func testTemplateOriginIsIdentityGatedBySuccessfulList() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let executable = root.appendingPathComponent("bob")
    let sourceFakeBobPath = try fakeBobPath()
    try FileManager.default.copyItem(atPath: sourceFakeBobPath, toPath: executable.path)
    let sourceFixtures = URL(fileURLWithPath: sourceFakeBobPath).deletingLastPathComponent()
    let listFixture = sourceFixtures.appendingPathComponent("capture-templates-list-populated.json")
    try FileManager.default.copyItem(
      at: listFixture,
      to: root.appendingPathComponent(listFixture.lastPathComponent)
    )
    let captureFixture = sourceFixtures.appendingPathComponent("capture-template-example.json")
    try FileManager.default.copyItem(
      at: captureFixture,
      to: root.appendingPathComponent(captureFixture.lastPathComponent)
    )
    let recordURL = root.appendingPathComponent("argv.log")
    let client = BobProcessClient(
      executablePath: executable.path,
      environment: [
        "HOME": "/tmp",
        "PATH": "/usr/bin:/bin",
        "FAKE_BOB_RECORD_PATH": recordURL.path,
      ]
    )

    _ = try await client.capture("Buy milk", readClipboard: false, templateOrigin: "origin123")
    _ = try await client.savedTemplates()
    let exampleDraft = [
      "@@template:",
      "Apply to {0}! @job_2026_apply_29:{1}",
      "- **URL**: {2}",
      "",
      "Foobar foo http://foobar.com/career/some_foo_job",
      "Bazbuz baz http://bazbuz.com/career/some_baz_job",
      "\"Two Sigma\" two-sigma https://www.twosigma.com/careers/some_role",
    ].joined(separator: "\n")
    let listedCapture = try await client.capture(
      exampleDraft,
      readClipboard: false,
      templateOrigin: "origin123"
    )
    XCTAssertEqual(captureTemplate(from: listedCapture)?.rowCount, 3)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_900_000_000)],
      ofItemAtPath: executable.path
    )
    _ = try await client.capture("Buy milk", readClipboard: false, templateOrigin: "origin123")

    let calls = try String(contentsOf: recordURL)
      .components(separatedBy: "argv=")
      .filter { $0.hasPrefix("capture") }
    let captures = calls.filter { $0.hasPrefix("capture --") }
    XCTAssertEqual(captures.count, 3)
    XCTAssertFalse(captures[0].contains("--template-origin"))
    XCTAssertTrue(captures[1].contains("--template-origin origin123"))
    XCTAssertFalse(captures[2].contains("--template-origin"))
  }

  func testFakeBobRoutesRecordedTemplateCaptureOutcomes() async throws {
    let cases: [(String, CaptureTemplateSavedStatus?, String?)] = [
      ("capture-template-saved-new.json", .new, nil),
      ("capture-template-saved-replaced.json", .replaced, nil),
      ("capture-template-not-saved.json", nil, "write shelf: File exists (os error 17)"),
    ]

    for (fixture, status, notSaved) in cases {
      let client = BobProcessClient(
        executablePath: try fakeBobPath(),
        environment: [
          "HOME": "/tmp",
          "PATH": "/usr/bin:/bin",
          "FAKE_BOB_CAPTURE_TEMPLATE_FIXTURE": fixture,
        ]
      )
      let response = try await client.capture("template draft", readClipboard: false)
      XCTAssertEqual(captureTemplate(from: response)?.saved?.status, status, fixture)
      XCTAssertEqual(captureTemplate(from: response)?.notSaved, notSaved, fixture)
    }
  }

  func testTemplateCommandsDoNotCancelSubmitOrPreviewLanes() async throws {
    let client = BobProcessClient(
      executablePath: try fakeBobPath(),
      environment: [
        "HOME": "/tmp",
        "PATH": "/usr/bin:/bin",
        "FAKE_BOB_DELAY_SECONDS": "0.2",
      ]
    )

    async let submit = client.capture("Buy milk", readClipboard: false)
    async let preview = client.captureLivePreview("Buy milk", priorityRollSeed: "seed")
    async let templates = client.savedTemplates()
    let (_, _, list) = try await (submit, preview, templates)
    XCTAssertEqual(list.schemaVersion, 1)
  }

  private func span(_ token: String, kind: String, field: Int? = nil, in text: String)
    -> CaptureSpan
  {
    let bytes = Array(text.utf8)
    let needle = Array(token.utf8)
    let start = bytes.firstRange(of: needle)!.lowerBound
    return CaptureSpan(start: start, end: start + needle.count, kind: kind, field: field)
  }

  private func fixture(_ name: String) throws -> Data {
    let testFile = URL(fileURLWithPath: #filePath)
    let fixtures =
      testFile
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures", isDirectory: true)
    return try Data(contentsOf: fixtures.appendingPathComponent(name))
  }

  private func decodeCaptureFixture(_ name: String) throws -> CaptureCommandResponse {
    try JSONDecoder().decode(CaptureCommandResponse.self, from: fixture(name))
  }

  private func captureTemplate(from response: CaptureCommandResponse) -> CaptureTemplateSummary? {
    guard case let .success(success) = response else { return nil }
    return success.template
  }

  private func fakeBobPath() throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    return
      testFile
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Tests/Fixtures/fake-bob")
      .path
  }
}

extension Array where Element: Equatable {
  fileprivate func firstRange(of elements: [Element]) -> Range<Int>? {
    guard !elements.isEmpty, elements.count <= count else { return nil }
    for start in 0...(count - elements.count)
    where Array(self[start..<(start + elements.count)]) == elements {
      return start..<(start + elements.count)
    }
    return nil
  }
}

final class CapturePickerHelpersTests: XCTestCase {
  func testAcceleratorsMatchTheStashAlphabetAndRespectEntryCount() {
    XCTAssertEqual(CapturePickerHelpers.accelerator(for: 0), "1")
    XCTAssertEqual(CapturePickerHelpers.accelerator(for: 10), "A")
    XCTAssertEqual(CapturePickerHelpers.accelerator(for: 12), "C")
    XCTAssertEqual(CapturePickerHelpers.accelerator(for: 13), "-")
    XCTAssertEqual(CapturePickerHelpers.accelerator(for: 35), "Z")
    XCTAssertNil(CapturePickerHelpers.accelerator(for: 36))
    XCTAssertEqual(CapturePickerHelpers.acceleratorIndex(for: "c", entryCount: 20), 12)
    XCTAssertNil(CapturePickerHelpers.acceleratorIndex(for: "Z", entryCount: 20))
    XCTAssertNil(CapturePickerHelpers.acceleratorIndex(for: "12", entryCount: 20))
  }

  func testSelectionClampsAndWrapsInBothDirections() {
    XCTAssertEqual(CapturePickerHelpers.clampedSelectionIndex(8, entryCount: 3), 2)
    XCTAssertEqual(CapturePickerHelpers.clampedSelectionIndex(-1, entryCount: 3), 0)
    XCTAssertEqual(CapturePickerHelpers.nextSelectionIndex(after: 2, entryCount: 3), 0)
    XCTAssertEqual(CapturePickerHelpers.previousSelectionIndex(before: 0, entryCount: 3), 2)
    XCTAssertEqual(CapturePickerHelpers.nextSelectionIndex(after: 0, entryCount: 0), 0)
  }

  func testRelativeAgeUsesStashWordingAndVoiceOverExpansion() {
    let now = Date(timeIntervalSince1970: 10_000)
    XCTAssertEqual(
      CapturePickerHelpers.relativeAgeDescription(from: now.addingTimeInterval(-30), to: now),
      "just now")
    XCTAssertEqual(
      CapturePickerHelpers.relativeAgeDescription(from: now.addingTimeInterval(-180), to: now),
      "3m ago")
    XCTAssertEqual(
      CapturePickerHelpers.relativeAgeDescription(from: now.addingTimeInterval(-7_200), to: now),
      "2h ago")
    XCTAssertEqual(
      CapturePickerHelpers.relativeAgeDescription(from: now.addingTimeInterval(-172_800), to: now),
      "2d ago")
    XCTAssertEqual(
      CapturePickerHelpers.spokenRelativeAgeDescription(
        from: now.addingTimeInterval(-7_200), to: now), "2 hours ago")
  }
}
