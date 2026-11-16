import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureNoteGotoRecentPanelTests: XCTestCase {
    func testSuccessfulAcceptAppendsOneOpenEvent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("note-goto-open-log.json")
        let store = NoteGotoOpenLogStore(fileURL: logURL)
        let (model, _) = try noteGotoModel(store: store)
        model.plainDraft = "//cash"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }

        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        model.panelDismisser = {}
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: true)

        XCTAssertEqual(opened.count, 1)
        let events = store.load()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.notePath, "Areas/cash.md")
        XCTAssertEqual(
            events.first?.vault,
            NoteGotoOpenLogStore.vaultHash(for: "/tmp/bob-note-goto-fixture-vault/vault")
        )
    }

    func testFailedDispatchStaleDraftAndDoubleAcceptRecordNothing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteGotoOpenLogStore(fileURL: directory.appendingPathComponent("log.json"))
        let (model, _) = try noteGotoModel(store: store)

        // Failed dispatch records nothing.
        model.plainDraft = "//cash"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        model.taskGotoOpener = { _, completion in completion(false) }
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: false)
        XCTAssertTrue(store.load().isEmpty)

        // Stale draft records nothing.
        model.plainDraft = "//cash stale"
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: false)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testDoubleAcceptDispatchesOnceAndRecordsOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteGotoOpenLogStore(fileURL: directory.appendingPathComponent("log.json"))
        let (model, _) = try noteGotoModel(store: store)
        model.plainDraft = "//cash"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }

        var opened = 0
        var pending: (@MainActor (Bool) -> Void)?
        model.taskGotoOpener = { _, completion in
            opened += 1
            pending = completion
        }
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: false)
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: true)
        XCTAssertEqual(opened, 1)
        pending?(true)
        XCTAssertEqual(store.load().count, 1)
    }

    func testRecentShowsOnNextEmptyViewIncludingWarmSwap() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteGotoOpenLogStore(fileURL: directory.appendingPathComponent("log.json"))
        let (model, _) = try noteGotoModel(store: store)

        model.plainDraft = "//cash"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        model.taskGotoOpener = { _, completion in completion(true) }
        model.panelDismisser = {}
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: true)

        // Next empty // shows Recent after Today.
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        let titles = model.pickerPresentation?.sections.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Recent"), titles.joined(separator: ","))
        XCTAssertTrue(
            model.pickerPresentation?.orderedRowIDs.contains("recent:Areas/cash.md") ?? false
        )

        // Warm swap renders Recent too: peel to Tasks and continue back.
        model.removePickerTrigger()
        await waitUntil { model.pickerVisible && model.pickerSourceIsTaskGoto }
        model.continuePickerOperator("/")
        XCTAssertTrue(model.pickerSourceIsNoteGoto)
        XCTAssertTrue(
            model.pickerPresentation?.orderedRowIDs.contains("recent:Areas/cash.md") ?? false
        )
        await waitUntil { model.statusText.hasPrefix("Go To Notes,") }
        XCTAssertTrue(
            model.pickerPresentation?.orderedRowIDs.contains("recent:Areas/cash.md") ?? false
        )
    }

    func testAcceptingRecentRowOpensSameURLAndClearEmptiesRecent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteGotoOpenLogStore(fileURL: directory.appendingPathComponent("log.json"))
        let (model, _) = try noteGotoModel(store: store)

        model.plainDraft = "//cash"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        model.taskGotoOpener = { _, completion in completion(true) }
        var dismissed = 0
        model.panelDismisser = { dismissed += 1 }
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: true)
        XCTAssertEqual(dismissed, 1)

        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        let bobURL = model.pickerPresentation?.row(id: "Areas/cash.md")?
            .noteGotoDestination?.openURL()
        let recentURL = model.pickerPresentation?.row(id: "recent:Areas/cash.md")?
            .noteGotoDestination?.openURL()
        XCTAssertNotNil(bobURL)
        XCTAssertEqual(recentURL, bobURL)

        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        dismissed = 0
        model.panelDismisser = { dismissed += 1 }
        model.acceptPickerRow(id: "recent:Areas/cash.md", submitAfterInsert: true)
        XCTAssertEqual(opened, [bobURL])
        XCTAssertEqual(dismissed, 1)

        model.clearNoteGotoHistory()
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        XCTAssertFalse(
            model.pickerPresentation?.sections.map(\.title).contains("Recent") ?? true
        )
    }

    private func noteGotoModel(store: NoteGotoOpenLogStore) throws -> (CapturePanelModel, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": url.path,
            "FAKE_BOB_NOTE_GOTO_FIXTURES": "1",
        ]
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
