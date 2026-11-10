import Foundation
import XCTest

@testable import CaptureCore

@MainActor
final class GcalNoteSessionTests: XCTestCase {
    private var testsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fakeBobPath() -> String {
        testsRoot.appendingPathComponent("Fixtures/fake-bob").path
    }

    private func client(_ environment: [String: String] = [:]) -> BobProcessClient {
        BobProcessClient(
            executablePath: fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"].merging(environment) {
                _, new in new
            }
        )
    }

    private func session(
        _ environment: [String: String] = [:],
        debounce: UInt64 = 0,
        onAgendaRefresh: (() -> Void)? = nil
    ) -> GcalNoteSession {
        GcalNoteSession(
            process: client(environment),
            previewDebounceNanoseconds: debounce,
            onAgendaRefresh: onAgendaRefresh
        )
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

    private func waitForRecord(
        _ url: URL,
        containing needle: String,
        timeout: TimeInterval = 2
    ) async {
        await waitUntil(timeout: timeout) {
            (try? String(contentsOf: url, encoding: .utf8))?.contains(needle) == true
        }
    }

    private func writeMap(_ url: URL, _ mapping: [String: String]) throws {
        let data = try JSONSerialization.data(withJSONObject: mapping)
        try data.write(to: url)
    }

    private func listedEvent(
        _ model: GcalNoteSession,
        id: String
    ) throws -> GcalNoteEvent {
        try XCTUnwrap(model.events.first { $0.eventID == id })
    }

    func testEnterPickerListsAndFiltersLocallyWithoutSubmitting() async throws {
        let argvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: argvURL) }
        let model = session(["FAKE_BOB_GCAL_NOTE_ARGV_PATH": argvURL.path])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        XCTAssertEqual(model.events.map(\.eventID), ["gym", "deerwood"])
        XCTAssertEqual(model.groupedEvents.map(\.day), ["2026-11-13", "2026-12-13"])
        XCTAssertEqual(model.groupedEvents[0].events.map(\.eventID), ["gym"])

        model.setFilter("Deerwood")
        XCTAssertEqual(model.filteredEvents.map(\.eventID), ["deerwood"])
        XCTAssertFalse(model.hasNoFilterMatches)
        model.setFilter("zzzz")
        XCTAssertTrue(model.hasNoFilterMatches)
        XCTAssertEqual(model.phase, .listing)

        let argv = try String(contentsOf: argvURL, encoding: .utf8)
        XCTAssertEqual(argv.split(whereSeparator: \.isNewline).count, 1)
    }

    func testEmptyListIsDistinctFromNoFilterMatches() async throws {
        let model = session([
            "FAKE_BOB_GCAL_NOTE_LIST_FIXTURE": "gcal-note/waiting_states.json",
            "FAKE_BOB_GCAL_NOTE_STDOUT": #"{"schema_version":1,"ok":true,"events":[]}"#,
        ])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        XCTAssertTrue(model.isListEmpty)
        XCTAssertFalse(model.hasNoFilterMatches)
    }

    func testSelectLoadsScopeTextNotLayeredSummaryAndSkipsEmptySave() async throws {
        let argvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: argvURL) }
        let model = session(["FAKE_BOB_GCAL_NOTE_ARGV_PATH": argvURL.path])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        XCTAssertEqual(
            model.editorText, "@family\n-30 Drive to Deerwood\n+15 Drive home")
        XCTAssertFalse(model.isEditorDirty)
        XCTAssertEqual(model.showResponse?.effective?.root?.value, "family")
        let argv = try String(contentsOf: argvURL, encoding: .utf8)
        XCTAssertFalse(argv.contains("\"--\""))
    }

    func testUserEditedBlankSchedulesPreviewAndSaveSendsText() async throws {
        let argvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: argvURL) }
        let model = session(["FAKE_BOB_GCAL_NOTE_ARGV_PATH": argvURL.path])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        model.setEditorText("")
        await waitUntil { model.phase == .editing && model.previewResponse != nil }
        XCTAssertTrue(model.isEditorDirty)
        model.save()
        await waitUntil { model.phase == .listing }
        let raw = try String(contentsOf: argvURL, encoding: .utf8)
        let lines: [[String]] = try raw.split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String])
        }
        XCTAssertTrue(lines.contains { $0.contains("--") && $0.last == "" })
    }

    func testOutOfOrderShowsDoNotReplaceTheCurrentEvent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = directory.appendingPathComponent("record")
        let map = directory.appendingPathComponent("map.json")
        try writeMap(
            map,
            [
                "list": "gcal-note/list_all.json",
                "show:gym": "gcal-note/series_scope.json",
                "show": "gcal-note/show.json",
            ])
        let model = session([
            "FAKE_BOB_RECORD_PATH": record.path,
            "FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": map.path,
            "FAKE_BOB_GCAL_NOTE_DELAY_SECONDS": "0.25",
        ])
        model.enterPicker()
        await waitUntil { model.phase == .listing }

        try writeMap(
            map,
            [
                "list": "gcal-note/list_all.json",
                "show": "gcal-note/series_scope.json",
            ])
        model.select(try listedEvent(model, id: "gym"))
        await waitForRecord(record, containing: "argv=gcal note")
        try writeMap(
            map,
            [
                "list": "gcal-note/list_all.json",
                "show": "gcal-note/show.json",
            ])
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing && model.selectedIdentity?.eventID == "deerwood" }
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(model.selectedIdentity?.eventID, "deerwood")
        XCTAssertEqual(model.editorText, "@family\n-30 Drive to Deerwood\n+15 Drive home")
        XCTAssertNotEqual(model.phase, .inactive)
    }

    func testOutOfOrderPreviewsKeepTheMatchingInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = directory.appendingPathComponent("record")
        let model = session([
            "FAKE_BOB_RECORD_PATH": record.path,
            "FAKE_BOB_GCAL_NOTE_DELAY_SECONDS": "0.25",
        ])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        try? FileManager.default.removeItem(at: record)
        model.setEditorText("first draft")
        await waitForRecord(record, containing: "argv=gcal note")
        model.setEditorText("second draft")
        await waitUntil {
            model.phase == .editing && model.editorText == "second draft"
                && model.previewResponse != nil
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(model.editorText, "second draft")
        XCTAssertEqual(model.previewResponse?.action, "preview")
    }

    func testRapidEditsDebounceToOnePreview() async throws {
        let argvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: argvURL) }
        let model = session(
            ["FAKE_BOB_GCAL_NOTE_ARGV_PATH": argvURL.path],
            debounce: 80_000_000
        )
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        try? FileManager.default.removeItem(at: argvURL)
        model.setEditorText("a")
        model.setEditorText("ab")
        model.setEditorText("abc")
        await waitUntil { model.phase == .editing && model.previewResponse != nil }
        let lines = try String(contentsOf: argvURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
    }

    func testSwitchingRecurringScopeKeepsSeparateDrafts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let map = directory.appendingPathComponent("map.json")
        try writeMap(
            map,
            [
                "list": "gcal-note/list_all.json",
                "show:gym-1:event": "gcal-note/both_scopes.json",
                "show:gym-1:series": "gcal-note/series_scope.json",
                "show": "gcal-note/both_scopes.json",
            ])
        let model = session(["FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": map.path])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        let gym = try listedEvent(model, id: "gym")
        model.select(
            identity: GcalNoteIdentity(calendarID: "primary", eventID: "gym-1"),
            fallbackEvent: GcalNoteEventFixture.recurring(from: gym)
        )
        await waitUntil { model.phase == .editing }
        XCTAssertEqual(model.availableScopes, [.event, .series])
        XCTAssertEqual(model.editorText, "-0\n+5 Event after")
        model.setEditorText("occurrence draft")
        await waitUntil { model.phase == .editing }
        model.setScope(.series)
        await waitUntil { model.phase == .editing && model.scope == .series }
        XCTAssertEqual(model.editorText, "")
        model.setEditorText("series draft")
        await waitUntil { model.phase == .editing }
        model.setScope(.event)
        await waitUntil { model.phase == .editing && model.scope == .event }
        XCTAssertEqual(model.editorText, "occurrence draft")
        model.setScope(.series)
        await waitUntil { model.phase == .editing && model.scope == .series }
        XCTAssertEqual(model.editorText, "series draft")
    }

    func testSaveReturnsToPickerReloadsListAndUndoRestoresPriorText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("store")
        let refreshes = Counter()
        let model = session(
            ["FAKE_BOB_GCAL_NOTE_STORE": store.path],
            onAgendaRefresh: { refreshes.value += 1 }
        )
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        let prior = model.editorText
        model.setEditorText("@family\nBring water")
        await waitUntil { model.phase == .editing }
        model.save()
        await waitUntil { model.phase == .listing }
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "@family\nBring water")
        XCTAssertEqual(model.statusBanner?.state, "waiting_note")
        XCTAssertEqual(refreshes.value, 1)
        XCTAssertTrue(model.canUndoMutation)
        XCTAssertNil(model.selectedIdentity)

        model.undoLastMutation()
        await waitUntil { model.phase == .listing && model.mutationUndo == nil }
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), prior)
        XCTAssertEqual(refreshes.value, 2)
        XCTAssertFalse(model.canUndoMutation)
    }

    func testClearUndoRestoresCanonicalText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("store")
        let model = session(["FAKE_BOB_GCAL_NOTE_STORE": store.path])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        let prior = model.editorText
        model.clear()
        await waitUntil { model.phase == .listing }
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "")
        model.undoLastMutation()
        await waitUntil { model.phase == .listing && model.mutationUndo == nil }
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), prior)
    }

    func testFirstSaveUndoClearsTheNewNote() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("store")
        let map = directory.appendingPathComponent("map.json")
        try writeMap(
            map,
            [
                "list": "gcal-note/list_all.json",
                "show": "gcal-note/series_scope.json",
                "write": "gcal-note/saved.json",
                "clear": "gcal-note/cleared.json",
            ])
        let model = session([
            "FAKE_BOB_GCAL_NOTE_STORE": store.path,
            "FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": map.path,
        ])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "gym"))
        await waitUntil { model.phase == .editing }
        XCTAssertEqual(model.editorText, "")
        model.save()
        XCTAssertEqual(model.phase, .editing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        model.setEditorText("@family")
        await waitUntil { model.phase == .editing }
        model.save()
        await waitUntil { model.phase == .listing }
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "@family")
        model.undoLastMutation()
        await waitUntil { model.phase == .listing && model.mutationUndo == nil }
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "")
    }

    func testUnchangedDoesNotReplaceUndoAndInvalidKeepsTheDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let map = directory.appendingPathComponent("map.json")
        try writeMap(
            map,
            [
                "list": "gcal-note/list_all.json",
                "show": "gcal-note/show.json",
                "write": "gcal-note/saved.json",
            ])
        let model = session(["FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": map.path])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        model.setEditorText("@family\nBring water")
        await waitUntil { model.phase == .editing }
        model.save()
        await waitUntil { model.phase == .listing }
        XCTAssertTrue(model.canUndoMutation)

        try writeMap(
            map,
            [
                "list": "gcal-note/list_all.json",
                "show": "gcal-note/show.json",
                "write": "gcal-note/unchanged.json",
            ])
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        model.setEditorText("@family\nBring water")
        await waitUntil { model.phase == .editing }
        model.save()
        await waitUntil { model.phase == .listing }
        XCTAssertEqual(
            model.mutationUndo?.previousText, "@family\n-30 Drive to Deerwood\n+15 Drive home")

        try writeMap(
            map,
            [
                "list": "gcal-note/list_all.json",
                "show": "gcal-note/show.json",
                "write": "gcal-note/invalid.json",
            ])
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        model.setEditorText("@famly")
        await waitUntil { model.phase == .editing }
        model.save()
        await waitUntil { model.phase == .editing && model.previewError != nil }
        XCTAssertEqual(model.editorText, "@famly")
        XCTAssertEqual(model.writeResponse?.error?.kind, "invalid_note")
        XCTAssertTrue(model.canUndoMutation)
    }

    func testSyncFailedIsSuccessWithWarningAndRefreshesAgenda() async throws {
        let refreshes = Counter()
        let model = session(
            ["FAKE_BOB_GCAL_NOTE_WRITE_FIXTURE": "gcal-note/saved_sync_failed.json"],
            onAgendaRefresh: { refreshes.value += 1 }
        )
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        model.setEditorText("@family")
        await waitUntil { model.phase == .editing }
        model.save()
        await waitUntil { model.phase == .listing }
        XCTAssertEqual(model.statusBanner?.state, "sync_failed")
        XCTAssertEqual(model.warnings.first, "immediate sync failed: fake gog: second page failed")
        XCTAssertEqual(refreshes.value, 1)
        XCTAssertTrue(model.canUndoMutation)
    }

    func testRepeatSaveIsIgnoredWhileWriting() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = directory.appendingPathComponent("record")
        let model = session([
            "FAKE_BOB_RECORD_PATH": record.path,
            "FAKE_BOB_GCAL_NOTE_DELAY_SECONDS": "0.2",
        ])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        model.setEditorText("@family\nOne")
        await waitUntil { model.phase == .editing }
        try? FileManager.default.removeItem(at: record)
        model.save()
        XCTAssertEqual(model.phase, .writing)
        XCTAssertTrue(model.navigationDeferred)
        model.save()
        model.clear()
        await waitUntil { model.phase == .listing }
        let argv = try String(contentsOf: record, encoding: .utf8)
        XCTAssertEqual(argv.components(separatedBy: " -- ").count - 1, 1)
    }

    func testWriteSurvivesUnrelatedReadsAndLeaveDoesNotCancelIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("store")
        let model = session([
            "FAKE_BOB_GCAL_NOTE_STORE": store.path,
            "FAKE_BOB_GCAL_NOTE_DELAY_SECONDS": "0.25",
        ])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        model.setEditorText("@family\nKeep this write")
        model.save()
        XCTAssertEqual(model.phase, .writing)
        model.setFilter("Gym")
        model.leave()
        XCTAssertEqual(model.phase, .writing)
        await waitUntil { model.phase == .inactive }
        XCTAssertEqual(
            try String(contentsOf: store, encoding: .utf8), "@family\nKeep this write")
    }

    func testTransportFailureKeepsDraftAndRetryReloadsBeforeWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let errorFile = directory.appendingPathComponent("error")
        let argvURL = directory.appendingPathComponent("argv")
        let model = session([
            "FAKE_BOB_GCAL_NOTE_ERROR_FILE": errorFile.path,
            "FAKE_BOB_GCAL_NOTE_ARGV_PATH": argvURL.path,
        ])
        model.enterPicker()
        await waitUntil { model.phase == .listing }
        model.select(try listedEvent(model, id: "deerwood"))
        await waitUntil { model.phase == .editing }
        model.setEditorText("@family\nKeep me")
        await waitUntil { model.phase == .editing }
        try "network down".write(to: errorFile, atomically: true, encoding: .utf8)
        model.save()
        await waitUntil {
            if case .recoverableError(_, .reloadThenWrite, true) = model.phase {
                return true
            }
            return false
        }
        XCTAssertEqual(model.editorText, "@family\nKeep me")
        try FileManager.default.removeItem(at: errorFile)
        model.retry()
        await waitUntil { model.phase == .listing }
        XCTAssertEqual(model.statusBanner?.state, "waiting_note")
        let argv = try String(contentsOf: argvURL, encoding: .utf8)
        XCTAssertTrue(argv.contains("\"-i\""))
    }

    func testUnsupportedAndReplacementBobResetsCapability() async throws {
        let record = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: record) }
        let process = client([
            "FAKE_BOB_GCAL_NOTE_UNSUPPORTED": "1",
            "FAKE_BOB_RECORD_PATH": record.path,
        ])
        var identity = "first"
        process.identityTokenProvider = { identity }
        let model = GcalNoteSession(process: process, previewDebounceNanoseconds: 0)
        model.enterPicker()
        await waitUntil { model.phase == .unsupported }
        model.enterPicker()
        XCTAssertEqual(model.phase, .unsupported)
        let firstCount =
            try String(contentsOf: record, encoding: .utf8)
            .components(separatedBy: "argv=gcal note").count - 1
        XCTAssertEqual(firstCount, 1)

        identity = "replacement"
        model.enterPicker()
        await waitUntil { model.phase == .unsupported }
        let secondCount =
            try String(contentsOf: record, encoding: .utf8)
            .components(separatedBy: "argv=gcal note").count - 1
        XCTAssertEqual(secondCount, 2)
    }

    func testModeExitRejectsLateListAndDropsUndo() async throws {
        let model = session(["FAKE_BOB_GCAL_NOTE_DELAY_SECONDS": "0.2"])
        model.enterPicker()
        await waitUntil { model.phase == .loadingList }
        model.leave()
        XCTAssertEqual(model.phase, .inactive)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(model.phase, .inactive)
        XCTAssertTrue(model.events.isEmpty)
        XCTAssertFalse(model.canUndoMutation)
    }

    func testAmbiguousURLShowsCandidatesWithoutChoosing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let map = directory.appendingPathComponent("map.json")
        try writeMap(
            map,
            [
                "show": "gcal-note/ambiguous.json",
                "show:exact": "gcal-note/show.json",
            ])
        let model = session([
            "FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": map.path
        ])
        model.enter(url: "https://calendar.google.com/event?eid=deerwood")
        await waitUntil { !model.ambiguousCandidates.isEmpty }
        XCTAssertEqual(model.phase, .listing)
        XCTAssertNil(model.selectedIdentity)
        XCTAssertEqual(model.ambiguousCandidates.map(\.eventID), ["exact", "prefix", "contains"])
        model.select(model.ambiguousCandidates[0])
        await waitUntil { model.phase == .editing }
        XCTAssertNotNil(model.selectedIdentity)
    }
}

private final class Counter: @unchecked Sendable {
    var value = 0
}

private enum GcalNoteEventFixture {
    static func recurring(from event: GcalNoteEvent) -> GcalNoteEvent {
        let json = """
            {
              "calendar_id": "\(event.calendarID)",
              "event_id": "gym-1",
              "calendar_name": "\(event.calendarName ?? "Personal")",
              "series_id": "gym-series",
              "recurring": true,
              "title": "Little Gym",
              "day": "\(event.day ?? "2026-11-13")",
              "start": "\(event.start ?? "2026-11-13T09:15:00-05:00")",
              "end": "\(event.end ?? "2026-11-13T10:00:00-05:00")",
              "time": "\(event.time ?? "09:15-10:00")"
            }
            """
        return try! JSONDecoder().decode(GcalNoteEvent.self, from: Data(json.utf8))
    }
}
