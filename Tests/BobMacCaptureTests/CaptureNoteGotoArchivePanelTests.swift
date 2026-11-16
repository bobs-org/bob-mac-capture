import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Command-X Archive scope on Go To Notes: toggle, races, chip, peel, accept,
/// old bob, and the no-capture contract.
@MainActor
final class CaptureNoteGotoArchivePanelTests: XCTestCase {
    func testCommandXShowsAndHidesArchivedNotesWithExactArgv() async throws {
        let (model, recordURL) = try noteGotoModel()
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        model.updatePickerFilter("a")

        model.toggleGotoArchivedNotes()
        await waitUntil {
            model.picker?.includesArchivedNotes == true
                && model.picker?.candidates.count == 6
        }
        XCTAssertEqual(model.picker?.filterText, "a")
        XCTAssertNotNil(model.pickerPresentation?.row(id: "done/a_done.md"))
        XCTAssertEqual(model.statusText, "Showing archived notes, 6 notes")
        XCTAssertFalse(
            model.pickerPresentation?.orderedRowIDs.contains { $0.hasPrefix("recent:") } ?? true
        )

        model.toggleGotoArchivedNotes()
        await waitUntil {
            model.picker?.includesArchivedNotes == false
                && model.picker?.candidates.count == 5
                && model.statusText == "Showing notes, 5 notes"
        }
        XCTAssertEqual(model.picker?.filterText, "a")
        XCTAssertNil(model.pickerPresentation?.row(id: "done/a_done.md"))
        XCTAssertNotNil(model.pickerPresentation?.row(id: "Areas/cash.md"))
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains(
                "argv=capture-complete --all-tasks --archived-notes --cursor 0 --format json -- //"
            )
        )
        XCTAssertFalse(record.contains("argv=capture --"))
    }

    func testSecondToggleWinsOverAnEarlierSlowArchiveSnapshot() async throws {
        let (model, recordURL) = try noteGotoModel(extraEnvironment: [
            "FAKE_BOB_CAPTURE_COMPLETE_DELAY_SECONDS": "0.4"
        ])
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }

        model.toggleGotoArchivedNotes()
        await waitUntil { Self.record(recordURL, contains: "--archived-notes") }
        model.toggleGotoArchivedNotes()
        await waitUntil { model.statusText == "Showing notes, 5 notes" }
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(model.picker?.includesArchivedNotes ?? true)
        XCTAssertEqual(model.picker?.candidates.count, 5)
        XCTAssertFalse(try String(contentsOf: recordURL).contains("argv=capture --"))
    }

    func testLateLivingResponseCannotReplaceArchive() async throws {
        let (model, recordURL) = try noteGotoModel(extraEnvironment: [
            "FAKE_BOB_CAPTURE_COMPLETE_DELAY_SECONDS": "0.4"
        ])
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        model.toggleGotoArchivedNotes()
        await waitUntil {
            model.picker?.includesArchivedNotes == true
                && model.picker?.candidates.count == 6
        }
        model.noteGotoSnapshotStore.invalidate()

        model.toggleGotoArchivedNotes()
        await waitUntil {
            Self.recordCount(
                recordURL,
                contains: "argv=capture-complete --all-tasks --cursor"
            ) >= 2
        }
        model.toggleGotoArchivedNotes()
        await waitUntil {
            model.picker?.includesArchivedNotes == true
                && model.statusText == "Showing archived notes, 6 notes"
        }
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(model.picker?.includesArchivedNotes ?? false)
        XCTAssertEqual(model.picker?.candidates.count, 6)
    }

    func testArchiveResponseLeavesTheWarmLivingStoreUntouched() async throws {
        let (model, _) = try noteGotoModel()
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        XCTAssertFalse(model.noteGotoSnapshotStore.isEmpty)
        let livingPaths =
            model.noteGotoSnapshotStore.rows(
                bobIdentity: try XCTUnwrap(model.processClient?.identityToken)
            )?.candidates.map(\.notePath) ?? []
        XCTAssertEqual(
            livingPaths,
            [
                "2026/20261114.md", "mac_inbox.md", "Areas/cash.md", "Other/money.md",
                "Views/Monthly.base",
            ]
        )

        model.toggleGotoArchivedNotes()
        await waitUntil { model.picker?.includesArchivedNotes == true }
        XCTAssertEqual(
            model.noteGotoSnapshotStore.rows(
                bobIdentity: try XCTUnwrap(model.processClient?.identityToken)
            )?.candidates.map(\.notePath),
            livingPaths
        )
        XCTAssertEqual(
            model.noteGotoSnapshotStore.rows(
                bobIdentity: try XCTUnwrap(model.processClient?.identityToken)
            )?.noteGoto.archived,
            false
        )
    }

    func testArchiveToggleSurvivesEscapeChipAndReopen() async throws {
        let (model, _) = try noteGotoModel()
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        model.toggleGotoArchivedNotes()
        await waitUntil { model.picker?.candidates.count == 6 }

        model.escapePicker()
        XCTAssertEqual(model.pickerChip?.includesArchivedNotes, true)
        model.openPickerFromChip()

        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.picker?.includesArchivedNotes ?? false)
        XCTAssertEqual(model.picker?.candidates.count, 6)
    }

    func testPeelAndContinuationResetTheArchiveScope() async throws {
        let (model, _) = try noteGotoModel()
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        model.toggleGotoArchivedNotes()
        await waitUntil { model.picker?.includesArchivedNotes == true }

        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "/")
        await waitUntil { model.pickerVisible && model.pickerSourceIsTaskGoto }

        model.continuePickerOperator("/")
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        XCTAssertFalse(model.picker?.includesArchivedNotes ?? true)
        XCTAssertEqual(model.picker?.candidates.count, 5)
    }

    func testAcceptingArchiveRowOpensDonePathAndRecordsNoRecentEvent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteGotoOpenLogStore(
            fileURL: directory.appendingPathComponent("note-goto-open-log.json")
        )
        let (model, recordURL) = try noteGotoModel(store: store)
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        model.toggleGotoArchivedNotes()
        await waitUntil { model.picker?.includesArchivedNotes == true }

        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        model.panelDismisser = {}
        model.acceptPickerRow(id: "done/a_done.md", submitAfterInsert: true)

        XCTAssertEqual(opened.count, 1)
        let url = try XCTUnwrap(opened.first)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(
            items.first { $0.name == "path1" }?.value,
            "/tmp/bob-note-goto-fixture-vault/vault/done/a_done.md"
        )
        XCTAssertNil(items.first { $0.name == "line1" })
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertFalse(try String(contentsOf: recordURL).contains("argv=capture --"))
    }

    func testUnsupportedArchivedNotesKeepsPickerOpenWithUpdateHint() async throws {
        let (model, recordURL) = try noteGotoModel(extraEnvironment: [
            "FAKE_BOB_ARCHIVED_NOTES_UNSUPPORTED": "1"
        ])
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }

        model.toggleGotoArchivedNotes()
        await waitUntil {
            model.picker?.warnings.contains("Update bob to show archived notes") == true
        }

        XCTAssertTrue(model.pickerVisible)
        XCTAssertFalse(model.picker?.includesArchivedNotes ?? true)
        XCTAssertEqual(model.picker?.candidates.count, 5)
        XCTAssertEqual(model.statusText, "Update bob to show archived notes")
        XCTAssertFalse(try String(contentsOf: recordURL).contains("argv=capture --"))
    }

    private func noteGotoModel(
        recordURL: URL? = nil,
        store: NoteGotoOpenLogStore? = nil,
        extraEnvironment: [String: String] = [:]
    ) throws -> (CapturePanelModel, URL) {
        let url =
            recordURL
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": url.path,
            "FAKE_BOB_NOTE_GOTO_FIXTURES": "1",
        ]
        environment.merge(extraEnvironment) { _, replacement in replacement }
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: environment
            ),
            debounceNanoseconds: 5_000_000,
            canceledDraftStash: CanceledDraftStash(capacity: 10),
            noteGotoOpenLogStore: store
        )
        return (model, url)
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot =
            source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot.appendingPathComponent("Tests/Fixtures/fake-bob").path
    }

    private static func record(_ recordURL: URL, contains needle: String) -> Bool {
        (try? String(contentsOf: recordURL))?.contains(needle) == true
    }

    private static func recordCount(_ recordURL: URL, contains needle: String) -> Int {
        guard let record = try? String(contentsOf: recordURL) else {
            return 0
        }
        return record.components(separatedBy: needle).count - 1
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
