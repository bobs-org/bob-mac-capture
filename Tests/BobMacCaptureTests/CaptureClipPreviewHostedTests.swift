import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Hosted `%c` live preview: the debounced preview omits `--no-clip` only
/// for the current draft whose accepted parse reports a clip directive span,
/// carries Bob's `clip` onto the preview results for the Clip card, refreshes
/// on activation, and re-previews on pasteboard-counter changes at or under
/// 1 Hz. Bob authors every parse and preview below; fake-bob serves them
/// from real-bob fixtures.
@MainActor
final class CaptureClipPreviewHostedTests: XCTestCase {
    func testClipDraftPreviewOmitsNoClip() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(
            recordURL: recordURL,
            environment: ["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-inline.json")]
        )
        let draft = "jot idea %c"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { self.isPreviewReady(model) }

        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(
            record.contains("argv=capture --dry-run --format json -- \(draft)"),
            "a %c draft with a clip span reads the clipboard")
        XCTAssertFalse(record.contains("--no-clip"))

        let success = try XCTUnwrap(model.previewResults.first)
        let clip = try XCTUnwrap(success.clip)
        XCTAssertEqual(clip.mode, "inline")
        XCTAssertEqual(clip.lines, ["\t- hello-clip"])
        let card = try XCTUnwrap(CaptureClipPresentation(capture: success))
        XCTAssertEqual(card.headerText, "Clipboard · 1 line")
        XCTAssertEqual(card.childLines, ["\t- hello-clip"])
    }

    func testPlainDraftPreviewKeepsNoClip() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(recordURL: recordURL)
        let draft = "jot idea"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { self.isPreviewReady(model) }

        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(
            record.contains("argv=capture --dry-run --no-clip --format json -- \(draft)"))
    }

    func testBareEscapedAndUnknownPercentKeepNoClip() async throws {
        // Bare `%` has a directive span but no directive value; escaped
        // `%c` and `%x` have no directive span at all. None authorizes a
        // read. The bare draft skips its doomed preview through the normal
        // incomplete-marker path; the others preview with `--no-clip`.
        for (draft, parseFixture) in [
            ("jot idea %", "directive-parse-bare-percent.json"),
            ("jot idea \\%c", "directive-parse-escaped.json"),
            ("jot idea %x", "directive-parse-unknown.json"),
        ] {
            let recordURL = temporaryURL()
            let model = try makeModel(
                recordURL: recordURL,
                environment: ["FAKE_BOB_PARSE_FIXTURE": parseFixture]
            )
            model.plainDraft = draft
            model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
            await waitUntil { self.isPreviewSettled(model) }

            let record = try String(contentsOf: recordURL, encoding: .utf8)
            let previewLines = record.components(separatedBy: "\n").filter {
                $0.hasPrefix("argv=capture --dry-run")
            }
            for line in previewLines {
                XCTAssertTrue(
                    line.contains("--no-clip"),
                    "\(draft): every live preview keeps --no-clip (\(line))")
            }
            XCTAssertFalse(
                model.previewResults.first?.clip?.wasRead ?? false,
                "\(draft): no clip content reaches the preview")
        }
    }

    func testRemovedDirectiveRestoresNoClip() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(recordURL: recordURL)
        var draft = "jot idea %c"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { self.isPreviewReady(model) }

        // Removing the directive reschedules: the new parse has no clip
        // span, so the new preview keeps `--no-clip`. Waiting on the new
        // argv (not readiness, which the old preview already set).
        draft = "jot idea"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil {
            self.recordContains(
                recordURL, "argv=capture --dry-run --no-clip --format json -- \(draft)")
        }

        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(
            record.contains("argv=capture --dry-run --format json -- jot idea %c"))
        XCTAssertTrue(
            record.contains("argv=capture --dry-run --no-clip --format json -- \(draft)"))
    }

    func testCountedClipCarriesHistoryEntries() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(
            recordURL: recordURL,
            environment: [
                "FAKE_BOB_PARSE_FIXTURE": "directive-parse-clip-count.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-history.json"),
            ]
        )
        let draft = "jot idea %c3"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { self.isPreviewReady(model) }

        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(
            record.contains("argv=capture --dry-run --format json -- \(draft)"))
        let success = try XCTUnwrap(model.previewResults.first)
        let clip = try XCTUnwrap(success.clip)
        XCTAssertEqual(clip.mode, "history")
        XCTAssertEqual(clip.entries.count, 3)
        let card = try XCTUnwrap(CaptureClipPresentation(capture: success))
        XCTAssertEqual(card.headerText, "Last 3 clips")
        XCTAssertEqual(
            card.historyEntries.map(\.dividerText),
            ["Entry 1 of 3", "Entry 2 of 3", "Entry 3 of 3"])
    }

    func testBatchItemsEachCarryTheirOwnClip() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(
            recordURL: recordURL,
            environment: [
                "FAKE_BOB_PARSE_FIXTURE": "directive-parse-batch-three-items.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-batch.json"),
            ]
        )
        let draft = "first %c\n\nsecond\n\nthird %c"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        guard await waitUntil(condition: {
            self.isPreviewReady(model) && model.previewResults.count == 3
        }) else {
            return
        }

        XCTAssertEqual(model.previewResults.count, 3)
        let cards = model.previewResults.map(CaptureClipPresentation.init(capture:))
        XCTAssertEqual(cards[0]?.childLines, ["\t- hello-clip"])
        XCTAssertNil(cards[1], "the middle item has no %c and no clip")
        XCTAssertEqual(cards[2]?.childLines, ["\t- hello-clip"])
    }

    func testActivationRefreshesThePreviewAndArmsPolling() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(
            recordURL: recordURL,
            environment: ["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-inline.json")]
        )
        model.clipboardChangeCounter = { 100 }
        let draft = "jot idea %c"
        model.plainDraft = draft

        // Showing the panel refreshes the preview through the normal
        // debounced analysis and arms counter polling for the %c draft.
        model.prepareForPresentation()
        await waitUntil { self.isPreviewReady(model) }

        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(record.contains("argv=capture --dry-run --format json -- \(draft)"))
        XCTAssertTrue(model.clipboardPollingForTests)
    }

    func testClipboardCounterChangeRepreviewsAnUnchangedDraft() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(
            recordURL: recordURL,
            environment: ["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-inline.json")]
        )
        var counter = 100
        model.clipboardChangeCounter = { counter }
        let draft = "jot idea %c"
        model.plainDraft = draft
        model.prepareForPresentation()
        await waitUntil { self.isPreviewReady(model) }
        XCTAssertTrue(model.clipboardPollingForTests)

        // An unchanged counter never re-previews.
        model.fireClipboardPollForTests()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(previewCallCount(recordURL), 1)

        // A moved counter re-runs the debounced preview for the same draft.
        counter = 101
        model.fireClipboardPollForTests()
        await waitUntil { self.previewCallCount(recordURL) >= 2 }
        XCTAssertEqual(model.plainDraft, draft)
        XCTAssertEqual(model.previewResults.first?.clip?.lines, ["\t- hello-clip"])
    }

    func testPollingStopsOnHideFocusLossAndDraftRemoval() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(
            recordURL: recordURL,
            environment: ["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-inline.json")]
        )
        model.clipboardChangeCounter = { 7 }
        let draft = "jot idea %c"
        model.plainDraft = draft
        model.prepareForPresentation()
        await waitUntil { self.isPreviewReady(model) }
        XCTAssertTrue(model.clipboardPollingForTests)

        // Focus loss stops the poll; a later tick is a no-op.
        model.notePanelKeyActive(false)
        XCTAssertFalse(model.clipboardPollingForTests)
        model.fireClipboardPollForTests()
        XCTAssertEqual(previewCallCount(recordURL), 1)

        // Activation refreshes and re-arms through the normal analysis.
        model.notePanelKeyActive(true)
        await waitUntil { self.previewCallCount(recordURL) >= 2 }
        XCTAssertTrue(model.clipboardPollingForTests)

        // Hiding the panel stops the poll; showing again re-arms, and
        // clearing the draft disarms for good.
        model.prepareForDismissal()
        XCTAssertFalse(model.clipboardPollingForTests)
        model.prepareForPresentation()
        await waitUntil { self.previewCallCount(recordURL) >= 3 }
        XCTAssertTrue(model.clipboardPollingForTests)
        model.plainDraft = ""
        model.editorTextDidChange()
        XCTAssertFalse(model.clipboardPollingForTests)
    }

    func testPollRateStaysAtOrUnderOneHertz() {
        XCTAssertGreaterThanOrEqual(
            CapturePanelModel.clipboardPollIntervalNanoseconds, 1_000_000_000)
    }

    func testPollingObservationsStayAtOrBelowOneHertz() async throws {
        let model = try makeModel(
            environment: ["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-inline.json")]
        )
        var observations: [Date] = []
        model.clipboardChangeCounter = {
            observations.append(Date())
            return 100
        }
        let draft = "jot idea %c"
        model.plainDraft = draft
        model.prepareForPresentation()

        guard await waitUntil(timeout: 4, condition: { observations.count >= 3 }) else {
            return
        }
        for pair in zip(observations, observations.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.timeIntervalSince(pair.0), 0.95)
        }
    }

    func testClipboardPollingTaskDoesNotRetainTheModelAfterTeardown() async throws {
        var model: CapturePanelModel? = try makeModel(
            environment: ["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-inline.json")]
        )
        var counterReads = 0
        model?.clipboardChangeCounter = {
            counterReads += 1
            return 100
        }
        let draft = "jot idea %c"
        model?.plainDraft = draft
        model?.prepareForPresentation()

        guard await waitUntil(condition: {
            model?.clipboardPollingForTests == true && counterReads >= 2
        }) else {
            return
        }
        weak var weakModel = model
        model?.prepareForDismissal()
        let readsAtDismissal = counterReads
        model = nil

        guard await waitUntil(timeout: 1, condition: { weakModel == nil }) else {
            return
        }
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(counterReads, readsAtDismissal)
    }

    func testTwoClipboardChangesSupersedeOlderPreviewsForTheSameDraft() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(
            recordURL: recordURL,
            environment: [
                "FAKE_BOB_PARSE_FIXTURE": "directive-parse-clip-count.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_FIRST_FIXTURE": "clip-history-one.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_NEXT_FIXTURE": "clip-history-two.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_THIRD_FIXTURE": "clip-history.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_DELAY_SECONDS": "2",
            ]
        )
        let sequenceURL = recordURL.path + ".dry-run-count"
        let lockPath = sequenceURL + ".lock"
        func settledDryRuns() -> Int {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: lockPath)) != nil {
                return 0
            }
            let text = (try? String(contentsOfFile: sequenceURL, encoding: .utf8)) ?? ""
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        var counter = 100
        model.clipboardChangeCounter = { counter }
        let draft = "jot idea %c3"
        model.plainDraft = draft
        model.prepareForPresentation()
        guard await waitUntil(condition: {
            model.clipboardPollingForTests && settledDryRuns() >= 1
        }) else {
            return
        }
        XCTAssertTrue(
            self.recordContains(recordURL, "argv=capture --dry-run --format json -- \(draft)")
        )

        counter = 101
        model.fireClipboardPollForTests()
        guard await waitUntil(condition: { settledDryRuns() >= 2 }) else {
            return
        }

        counter = 102
        model.fireClipboardPollForTests()
        guard await waitUntil(condition: {
            self.previewCallCount(recordURL) >= 3
                && model.previewResults.first?.clip?.entries.first?.lines == ["\t- newest"]
        }) else {
            return
        }

        try await Task.sleep(nanoseconds: 2_200_000_000)
        XCTAssertEqual(model.plainDraft, draft)
        XCTAssertEqual(model.previewResults.first?.clip?.entries.count, 3)
        XCTAssertEqual(model.previewResults.first?.clip?.entries.first?.lines, ["\t- newest"])
    }

    func testFocusLossAndHideInvalidateInflightClipboardPreviews() async throws {
        for lifecycle in ["focus-loss", "hide"] {
            let recordURL = temporaryURL()
            defer { try? FileManager.default.removeItem(at: recordURL) }
            let model = try makeModel(
                recordURL: recordURL,
                environment: [
                    "FAKE_BOB_PARSE_FIXTURE": "directive-parse-clip-count.json",
                    "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-history-one.json"),
                    "FAKE_BOB_CAPTURE_DRY_RUN_DELAY_SECONDS": "1",
                ]
            )
            let draft = "jot idea %c3"
            model.plainDraft = draft
            model.prepareForPresentation()
            guard await waitUntil(condition: {
                self.recordContains(
                    recordURL, "argv=capture --dry-run --format json -- \(draft)")
            }) else {
                continue
            }

            if lifecycle == "focus-loss" {
                model.notePanelKeyActive(false)
            } else {
                model.prepareForDismissal()
            }
            try await Task.sleep(nanoseconds: 1_200_000_000)

            XCTAssertTrue(model.previewResults.isEmpty, lifecycle)
            if case .ready = model.previewState {
                XCTFail("Canceled (lifecycle) preview must not land")
            }
            XCTAssertFalse(model.clipboardPollingForTests, lifecycle)
        }
    }

    func testRemovedDirectiveDuringInflightPreviewInvalidatesTheRead() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(
            recordURL: recordURL,
            environment: [
                "FAKE_BOB_DELAY_SECONDS": "2",
                "FAKE_BOB_PARSE_FIXTURE": "directive-parse-clip.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-inline.json"),
            ]
        )
        let clipped = "jot idea %c"
        model.plainDraft = clipped
        model.editorTextDidChange(cursorUTF8Offset: clipped.utf8.count)
        // The clip preview is in flight; replacing the client (as Recheck
        // Bob does) and removing the directive must invalidate the read, so
        // the delayed clip result can never restore stale content.
        await waitUntil { self.recordContains(recordURL, "argv=capture --dry-run --format json") }
        model.processClient = try plainClient(recordURL: recordURL)
        let plain = "jot idea"
        model.plainDraft = plain
        model.editorTextDidChange(cursorUTF8Offset: plain.utf8.count)
        await waitUntil(timeout: 15) {
            self.isPreviewReady(model) && model.previewResults.first?.clip == nil
        }
        // Past the delayed clip landing: still the new draft, no clip.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(model.latestParse?.input, plain)
        XCTAssertNil(model.previewResults.first?.clip)

        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(record.contains("argv=capture --dry-run --format json -- \(clipped)"))
        XCTAssertTrue(
            record.contains("argv=capture --dry-run --no-clip --format json -- \(plain)"))
    }

    func testDelayedOldParseCannotOverwriteTheNewDraft() async throws {
        let recordURL = temporaryURL()
        let model = try makeModel(
            recordURL: recordURL,
            environment: [
                "FAKE_BOB_DELAY_SECONDS": "2",
                "FAKE_BOB_PARSE_FIXTURE": "directive-parse-clip.json",
                "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": fixture("clip-inline.json"),
            ]
        )
        let clipped = "jot idea %c"
        model.plainDraft = clipped
        model.editorTextDidChange(cursorUTF8Offset: clipped.utf8.count)
        // The old parse is still in flight when the client is replaced and
        // the new draft schedules; only the new draft may land.
        try await Task.sleep(nanoseconds: 300_000_000)
        model.processClient = try plainClient(recordURL: recordURL)
        let plain = "jot idea"
        model.plainDraft = plain
        model.editorTextDidChange(cursorUTF8Offset: plain.utf8.count)
        await waitUntil(timeout: 15) {
            self.isPreviewReady(model) && self.modelParseMatches(model, plain)
        }
        // Past the delayed old parse landing: still the new draft, no clip.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(model.latestParse?.input, plain)
        XCTAssertEqual(model.plainDraft, plain)
        XCTAssertNil(model.previewResults.first?.clip)

        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(
            record.contains("argv=capture --dry-run --no-clip --format json -- \(plain)"))
        XCTAssertFalse(record.contains("argv=capture --dry-run --format json"))
    }

    func testClipThumbnailLoadsReadableImagesAndSkipsMissingOnes() throws {
        let png = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))
        XCTAssertEqual(png.count, 70)
        let readable = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: readable)

        XCTAssertNotNil(ClipAttachmentRow.loadImage(source: readable.path))
        XCTAssertNil(
            ClipAttachmentRow.loadImage(
                source: readable.deletingLastPathComponent()
                    .appendingPathComponent("missing-\(UUID().uuidString).png").path))
    }

    // MARK: - Helpers

    /// One transparent 1x1 PNG, for the readable-thumbnail check.
    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQ"
        + "AAAABJRU5ErkJggg=="

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

    /// A default fake-bob client on the same record file: no delay, no
    /// fixture overrides, so its previews carry no clip content.
    private func plainClient(recordURL: URL) throws -> BobProcessClient {
        BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )
    }

    private func fakeBobPath() throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw NSError(domain: "CaptureClipPreviewHostedTests", code: 1)
        }
        return path
    }

    private func fixture(_ name: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent(name),
            encoding: .utf8)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func isPreviewReady(_ model: CapturePanelModel) -> Bool {
        if case .ready = model.previewState { return true }
        return false
    }

    private func isPreviewSettled(_ model: CapturePanelModel) -> Bool {
        // Bare `%` skips its doomed preview through the incomplete-marker
        // path; anything else lands ready. Either way analysis is done when
        // the latest parse matches the visible draft.
        if isPreviewReady(model) { return true }
        return model.latestParse?.input == model.plainDraft
    }

    private func modelParseMatches(_ model: CapturePanelModel, _ draft: String) -> Bool {
        model.latestParse?.input == draft
    }

    private func previewCallCount(_ recordURL: URL) -> Int {
        (try? String(contentsOf: recordURL, encoding: .utf8))?
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("argv=capture --dry-run") }
            .count ?? 0
    }

    private func recordContains(_ recordURL: URL, _ needle: String) -> Bool {
        (try? String(contentsOf: recordURL, encoding: .utf8))?.contains(needle) ?? false
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
}
