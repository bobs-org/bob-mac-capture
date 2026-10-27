import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Command-\ today-Pomodoro landing: fetch, dispatch, retain, and drop.
@MainActor
final class CaptureTodayPomodoroPanelTests: XCTestCase {
    func testCurrentFixtureDispatchesURLDismissesAndRetainsDraft() async throws {
        let stash = CanceledDraftStash(capacity: 10)
        let model = try makeModel(
            environment: ["FAKE_BOB_POMODOROS_FIXTURE": "pomodoros-current-3.json"],
            stash: stash
        )
        model.prepareForPresentation()
        model.plainDraft = "keep this draft"
        var opened: [URL] = []
        var dismissed = 0
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        model.panelDismisser = { dismissed += 1 }

        model.openTodayPomodoroInObsidian()
        await waitUntil { dismissed == 1 && !model.todayPomodoroGotoInFlight }

        XCTAssertEqual(opened, [expectedURL(line: 2, ref: "2:4a0bbe15")])
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(model.plainDraft, "keep this draft")
        XCTAssertTrue(model.hasDraft)
        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertFalse(model.todayPomodoroGotoInFlight)
        XCTAssertEqual(model.statusText, "Draft retained")
    }

    func testOpenerFailureKeepsPanelAndDraft() async throws {
        let model = try makeModel()
        model.prepareForPresentation()
        model.plainDraft = "keep this draft"
        var dismissed = 0
        model.taskGotoOpener = { _, completion in
            completion(false)
        }
        model.panelDismisser = { dismissed += 1 }

        model.openTodayPomodoroInObsidian()
        await waitUntil { !model.todayPomodoroGotoInFlight }

        XCTAssertEqual(dismissed, 0)
        XCTAssertEqual(model.plainDraft, "keep this draft")
        XCTAssertTrue(model.panelVisible)
        XCTAssertEqual(model.statusText, "Couldn't open Obsidian")
    }

    func testPomodorosFailureKeepsPanelClosed() async throws {
        let model = try makeModel(environment: ["FAKE_BOB_POMODOROS_FAIL": "1"])
        model.prepareForPresentation()
        var opened = 0
        model.taskGotoOpener = { _, completion in
            opened += 1
            completion(true)
        }

        model.openTodayPomodoroInObsidian()
        await waitUntil { !model.todayPomodoroGotoInFlight }

        XCTAssertEqual(opened, 0)
        XCTAssertTrue(model.panelVisible)
        XCTAssertEqual(model.statusText, "Couldn't read today's Pomodoros")
    }

    func testDoublePressOpensOnce() async throws {
        let model = try makeModel()
        model.prepareForPresentation()
        var opened: [URL] = []
        var pending: (@MainActor (Bool) -> Void)?
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            pending = completion
        }

        model.openTodayPomodoroInObsidian()
        await waitUntil { !opened.isEmpty }
        XCTAssertTrue(model.todayPomodoroGotoInFlight)
        model.openTodayPomodoroInObsidian()
        XCTAssertEqual(opened.count, 1)
        pending?(true)
        XCTAssertFalse(model.todayPomodoroGotoInFlight)
    }

    func testNilClientAnnouncesBobIsNotResolved() {
        let model = CapturePanelModel()
        model.prepareForPresentation()
        var opened = 0
        model.taskGotoOpener = { _, completion in
            opened += 1
            completion(true)
        }

        model.openTodayPomodoroInObsidian()

        XCTAssertEqual(opened, 0)
        XCTAssertEqual(model.statusText, "Bob is not resolved")
        XCTAssertFalse(model.todayPomodoroGotoInFlight)
    }

    func testSubmittingDoesNotOpen() throws {
        let model = try makeModel()
        model.prepareForPresentation()
        model.isSubmitting = true
        var opened = 0
        model.taskGotoOpener = { _, completion in
            opened += 1
            completion(true)
        }

        model.openTodayPomodoroInObsidian()

        XCTAssertEqual(opened, 0)
        XCTAssertEqual(model.statusText, "Wait for the capture to finish")
        XCTAssertFalse(model.todayPomodoroGotoInFlight)
    }

    func testHiddenPanelDropsResult() async throws {
        let model = try makeModel(
            environment: ["FAKE_BOB_DELAY_SECONDS": "0.15"]
        )
        model.prepareForPresentation()
        var opened = 0
        model.taskGotoOpener = { _, completion in
            opened += 1
            completion(true)
        }

        model.openTodayPomodoroInObsidian()
        XCTAssertTrue(model.todayPomodoroGotoInFlight)
        model.prepareForDismissal()
        XCTAssertFalse(model.todayPomodoroGotoInFlight)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(opened, 0)
    }

    func testNoneRunningLandsOnFirstOpen() async throws {
        let model = try makeModel(
            environment: ["FAKE_BOB_POMODOROS_FIXTURE": "pomodoros-none-running.json"]
        )
        model.prepareForPresentation()
        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }

        model.openTodayPomodoroInObsidian()
        await waitUntil { !opened.isEmpty && !model.todayPomodoroGotoInFlight }

        XCTAssertEqual(opened, [expectedURL(line: 2, ref: "2:34e1da67")])
    }

    func testAllCompletedLandsOnLastCompleted() async throws {
        let model = try makeModel(
            environment: ["FAKE_BOB_POMODOROS_FIXTURE": "pomodoros-all-completed.json"]
        )
        model.prepareForPresentation()
        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }

        model.openTodayPomodoroInObsidian()
        await waitUntil { !opened.isEmpty && !model.todayPomodoroGotoInFlight }

        XCTAssertEqual(opened, [expectedURL(line: 6, ref: "6:34e1da67")])
    }

    private func expectedURL(line: Int, ref: String) -> URL {
        ObsidianOpenURL.taskGotoURL(
            path: "/tmp/bob-mac-capture-pomodoros/vault/2026/20260828.md",
            line: line,
            ref: ref
        )!
    }

    private func makeModel(
        environment: [String: String] = [:],
        stash: CanceledDraftStash? = nil
    ) throws -> CapturePanelModel {
        var full: [String: String] = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        full.merge(environment) { _, new in new }
        return CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: full
            ),
            debounceNanoseconds: 5_000_000_000,
            canceledDraftStash: stash
        )
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
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
