import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Hosted record-preview model flows: explicit and live previews, the
/// committed summary after the draft clears, mixed batches, inline
/// refusals with the draft intact, and stale delayed replies. Bob authors
/// every parse and preview below; fake-bob serves them from real-bob
/// fixtures. All waits are bounded.
@MainActor
final class CaptureRecordPreviewPanelTests: XCTestCase {
    private let completeDraft =
        "Ramen Nagi @eat/\n- status:: liked\n- category:: Ramen\n- location:: Clark"
    private let incompleteDraft = "Ramen Nagi @eat/"
    private let invalidDraft =
        "Ramen Nagi @eat/\n- status:: nope\n- category:: Ramen\n- location:: Clark"

    private func makeModel(
        recordURL: URL? = nil,
        environment: [String: String] = [:]
    ) throws -> CapturePanelModel {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        var env = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        if let recordURL {
            env["FAKE_BOB_RECORD_PATH"] = recordURL.path
        }
        for (key, value) in environment {
            env[key] = value
        }
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: env
        )
        return model
    }

    private func fakeBobPath() throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw NSError(domain: "CaptureRecordPreviewPanelTests", code: 1)
        }
        return path
    }

    private func fixturePath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
            .path
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOfFile: fixturePath(name), encoding: .utf8)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func isPreviewReady(_ model: CapturePanelModel) -> Bool {
        if case .ready = model.previewState { return true }
        return false
    }

    @discardableResult
    private func waitUntil(
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return false
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    func testExplicitPreviewOfCompleteDraftIsReadyWithSummary() async throws {
        let model = try makeModel(environment: [
            "FAKE_BOB_PARSE_FIXTURE": "record-parse-complete.json",
            "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("record-capture-restaurant.json"),
        ])
        model.plainDraft = completeDraft
        model.preview()
        await waitUntil {
            !model.isPreviewing && model.previewResults.first?.recordNote != nil
        }

        let results = model.previewResults
        XCTAssertEqual(results.count, 1)
        let summary = try XCTUnwrap(results.first?.recordNote)
        XCTAssertEqual(summary.path, "eat/cafe_møø_ramen.md")
        XCTAssertNil(model.recordRefusalPresentation)
        if case .failed = model.previewState {
            XCTFail("explicit preview must not set a failed preview state")
        }
    }

    func testLivePreviewOfCompleteDraftLandsReady() async throws {
        let model = try makeModel(environment: [
            "FAKE_BOB_PARSE_FIXTURE": "record-parse-complete.json",
            "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("record-capture-restaurant.json"),
        ])
        model.plainDraft = completeDraft
        model.editorTextDidChange(cursorUTF8Offset: completeDraft.utf8.count)
        await waitUntil { self.isPreviewReady(model) }

        XCTAssertNotNil(model.previewResults.first?.recordNote)
        XCTAssertNil(model.recordRefusalPresentation)
    }

    func testExplicitPreviewOfIncompleteDraftShowsInlineRefusal() async throws {
        let model = try makeModel(environment: [
            "FAKE_BOB_PARSE_FIXTURE": "record-parse-incomplete.json",
            "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("record-capture-missing.json"),
            "FAKE_BOB_CAPTURE_DRY_RUN_EXIT": "2",
        ])
        model.plainDraft = incompleteDraft
        model.preview()
        await waitUntil { model.recordRefusalPresentation != nil }

        let refusal = try XCTUnwrap(model.recordRefusalPresentation)
        XCTAssertEqual(refusal.missing, ["category", "location"])
        XCTAssertNotNil(refusal.draft)
        // The user keeps the entire original draft.
        XCTAssertEqual(model.plainDraft, incompleteDraft)
        XCTAssertTrue(model.previewResults.isEmpty)
        if case .failed = model.previewState {
        } else {
            XCTFail("expected a failed preview state")
        }
    }

    func testLiveInvalidDraftShowsInlineRefusal() async throws {
        let model = try makeModel(environment: [
            "FAKE_BOB_PARSE_FIXTURE": "record-parse-invalid.json",
            "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("record-capture-invalid.json"),
            "FAKE_BOB_CAPTURE_DRY_RUN_EXIT": "2",
        ])
        model.plainDraft = invalidDraft
        model.editorTextDidChange(cursorUTF8Offset: invalidDraft.utf8.count)
        await waitUntil { model.recordRefusalPresentation != nil }

        let refusal = try XCTUnwrap(model.recordRefusalPresentation)
        XCTAssertEqual(refusal.invalid.count, 1)
        XCTAssertEqual(refusal.invalid.first?.field, "status")
        XCTAssertEqual(model.plainDraft, invalidDraft)
    }

    func testMixedBatchPreviewKeepsTaskAndRecordOrder() async throws {
        let model = try makeModel(environment: [
            "FAKE_BOB_PARSE_FIXTURE": "record-parse-mixed.json",
            "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("record-capture-mixed.json"),
        ])
        let draft = "Fix parser @dev\n\n\(completeDraft)"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { self.isPreviewReady(model) }

        let items = model.previewResults
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].kind, "task")
        XCTAssertNil(items[0].recordNote)
        XCTAssertEqual(items[1].kind, "record_note")
        XCTAssertNotNil(items[1].recordNote)
    }

    func testSubmitReportsCommittedSummaryAndClearsDraft() async throws {
        let recordURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: recordURL) }
        let model = try makeModel(
            recordURL: recordURL,
            environment: [
                "FAKE_BOB_PARSE_FIXTURE": "record-parse-complete.json",
                "FAKE_BOB_CAPTURE_WRITE_STDOUT_FILE": fixturePath(
                    "record-capture-restaurant-commit.json"
                ),
            ]
        )
        var notified: [[CaptureCommandSuccess]] = []
        model.captureSuccessNotifier = { captures, _, _ in
            notified.append(captures)
        }
        model.plainDraft = completeDraft
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        await waitUntil(timeout: 15) { !notified.isEmpty }

        XCTAssertEqual(model.plainDraft, "", "the draft clears after commit")
        let summary = try XCTUnwrap(notified.first?.first?.recordNote)
        let expected =
            "\(CaptureRecordPreviewPresentation.headline(for: summary)) · "
            + CaptureRecordPreviewPresentation.detail(for: summary)
        XCTAssertEqual(model.statusText, expected)
        XCTAssertTrue(expected.contains("eat/cafe_møø_ramen.md"), expected)
    }

    func testDelayedStaleSuccessReplyNeverClobbersCurrentRefusal() async throws {
        let recordURL = temporaryURL()
        let sequenceURL = recordURL.path + ".dry-run-count"
        let lockPath = sequenceURL + ".lock"
        func settledDryRuns() -> Int {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: lockPath)) != nil {
                return 0
            }
            let text = (try? String(contentsOfFile: sequenceURL, encoding: .utf8)) ?? ""
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        defer {
            try? FileManager.default.removeItem(at: recordURL)
            try? FileManager.default.removeItem(atPath: sequenceURL)
            try? FileManager.default.removeItem(atPath: lockPath)
        }
        let model = try makeModel(
            recordURL: recordURL,
            environment: [
                "FAKE_BOB_PARSE_FIXTURE": "record-parse-complete.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_FIRST_FIXTURE": "record-capture-restaurant.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_NEXT_FIXTURE": "record-capture-invalid.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_DELAY_SECONDS": "2",
            ]
        )
        // The first dry run is delayed; editing before it lands makes its
        // reply stale, so only the current draft's refusal may land.
        model.plainDraft = completeDraft
        model.editorTextDidChange(cursorUTF8Offset: completeDraft.utf8.count)
        await waitUntil(timeout: 10) { settledDryRuns() >= 1 }
        model.plainDraft = invalidDraft
        model.editorTextDidChange(cursorUTF8Offset: invalidDraft.utf8.count)
        await waitUntil(timeout: 15) { model.recordRefusalPresentation != nil }
        XCTAssertGreaterThanOrEqual(settledDryRuns(), 2)

        XCTAssertEqual(model.plainDraft, invalidDraft)
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertNotNil(
            model.recordRefusalPresentation,
            "the stale success reply must not clear the current refusal")
        XCTAssertTrue(model.previewResults.isEmpty)
    }
}
