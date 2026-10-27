import XCTest

@testable import CaptureCore

final class CaptureOpenPlanTests: XCTestCase {
    func testDecodesBobOpenNotesAndDropsBadEntriesAndOptionalValues() throws {
        let json = #"""
            [
              {"path":"/vault/one.md","relative_path":"one.md","role":"note","label":"One","line":0,"ref":"bad","block_id":"bad id"},
              {"path":"relative.md","relative_path":"relative.md","role":"future","label":"Future"},
              {"path":"/vault/two.md","relative_path":"two.md","role":"future-role","label":"Two","line":4,"ref":"4:deadbeef","block_id":"abc-123"}
            ]
            """#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode([CaptureOpenNote].self, from: data)
        let plan = CaptureOpenPlan(openNotes: decoded, captures: [])

        XCTAssertEqual(plan.source, .bob)
        XCTAssertEqual(plan.notes.count, 2)
        XCTAssertNil(plan.notes[0].line)
        XCTAssertNil(plan.notes[0].ref)
        XCTAssertNil(plan.notes[0].blockID)
        XCTAssertEqual(plan.notes[1].role, .other("future-role"))
        XCTAssertEqual(plan.notes[1].line, 4)
    }

    func testCaptureSuccessDistinguishesMissingAndEmptyOpenNotes() throws {
        let old = try decodeSuccess(openNotes: nil)
        let explicitEmpty = try decodeSuccess(openNotes: "[]")

        XCTAssertNil(old.openNotes)
        XCTAssertEqual(explicitEmpty.openNotes, [])
        XCTAssertEqual(CaptureOpenPlan(openNotes: old.openNotes, captures: [old]).source, .legacy)
        XCTAssertTrue(CaptureOpenPlan(openNotes: explicitEmpty.openNotes, captures: [old]).isEmpty)
    }

    func testLegacyPlanDeduplicatesCaptureTargetsInOrder() {
        let first = capture(target: "/vault/one.md", relativeTarget: "one.md")
        let duplicate = capture(target: "/vault/one.md", relativeTarget: "one.md")
        let second = capture(target: "/vault/two.md", relativeTarget: "two.md")

        let plan = CaptureOpenPlan(openNotes: nil, captures: [first, duplicate, second])

        XCTAssertEqual(plan.source, .legacy)
        XCTAssertEqual(plan.notes.map(\.path), ["/vault/one.md", "/vault/two.md"])
    }

    func testBobNotesAreDeduplicatedAndNotificationPayloadRoundTrips() throws {
        let notes = [
            CaptureOpenNote(path: "/vault/a.md", relativePath: "a.md", role: .note, label: "A", line: 3, ref: "3:deadbeef", blockID: "abc-1"),
            CaptureOpenNote(path: "/vault/a.md", relativePath: "duplicate.md", role: .day, label: "Duplicate"),
            CaptureOpenNote(path: "/vault/b.md", relativePath: "b.md", role: .other("pdf"), label: "B"),
        ]
        let plan = CaptureOpenPlan(openNotes: notes, captures: [])
        let restored = try XCTUnwrap(CaptureOpenPlan(notificationPayload: plan.notificationPayload))

        XCTAssertEqual(plan.notes.count, 2)
        XCTAssertEqual(restored.notes, plan.notes)
        XCTAssertEqual(restored.source, .bob)
        XCTAssertNil(CaptureOpenPlan(notificationPayload: [["relative_path": "missing path"]]))
    }

    func testOpenNotesURLEncodesValuesAndIncludesLineRefAndBlock() throws {
        let note = CaptureOpenNote(
            path: "/vault/é +&.md",
            relativePath: "é +&.md",
            role: .note,
            label: "One",
            line: 9,
            ref: "9:a1b2c3d4",
            blockID: "abc-123"
        )
        let plan = CaptureOpenPlan(openNotes: [note], captures: [])
        let url = try XCTUnwrap(ObsidianOpenURL.openNotesURL(for: plan))
        let absolute = try XCTUnwrap(url.absoluteString.removingPercentEncoding)

        XCTAssertTrue(url.absoluteString.hasPrefix("obsidian://bob-open-notes?count=1&path1=/vault/"))
        XCTAssertTrue(absolute.contains("/vault/é +&.md"))
        XCTAssertTrue(url.absoluteString.contains("line1=9"))
        XCTAssertTrue(url.absoluteString.contains("ref1=9%3Aa1b2c3d4"))
        XCTAssertTrue(url.absoluteString.contains("block1=abc-123"))
    }

    func testOpenNotesURLEncodesHashInPath() throws {
        let note = CaptureOpenNote(
            path: "/vault/foo#bar.md",
            relativePath: "foo#bar.md",
            role: .note,
            label: "Hash"
        )
        let plan = CaptureOpenPlan(openNotes: [note], captures: [])
        let url = try XCTUnwrap(ObsidianOpenURL.openNotesURL(for: plan))
        XCTAssertTrue(url.absoluteString.contains("path1="))
        XCTAssertFalse(url.absoluteString.contains("/vault/foo#bar.md"))
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "path1" })?.value,
            "/vault/foo#bar.md"
        )
    }

    func testLegacyDayFileLabelIsToday() {
        let capture = CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: true,
            routeLabel: "cash.md",
            relativeTarget: "cash.md",
            target: "/vault/cash.md",
            text: "Task",
            taskLine: "- [ ] Task",
            kind: "pomodoro_start",
            created: "today",
            placement: "toggled",
            dayFile: "/vault/day.md",
            pomodoroStart: PomodoroStartSummary(
                start: "0940",
                end: "1005",
                durationMinutes: 25,
                offsetUnits: 0,
                pomodoroName: "WORK",
                pomodoroLine: 3,
                createdPomodoro: false,
                timeRange: "(**0940-1005** [t:: 25m])"
            )
        )
        let plan = CaptureOpenPlan(openNotes: nil, captures: [capture])
        XCTAssertEqual(plan.source, .legacy)
        XCTAssertEqual(plan.notes.map(\.role), [.note, .day])
        XCTAssertEqual(plan.notes.map(\.label), ["cash.md", "Today"])
    }

    func testCaptureSuccessDropsOnlyMalformedOpenNoteEntries() throws {
        let json = """
        {
          "ok": true, "dry_run": false, "routed": false, "route_label": "Inbox",
          "relative_target": "inbox.md", "target": "/vault/inbox.md", "text": "Task",
          "task_line": "- [ ] Task", "kind": "task", "created": "today", "placement": "append",
          "open_notes": [
            {"path":"/vault/good.md","relative_path":"good.md","role":"note","label":"Good"},
            {"path":123,"role":"note","label":"Bad path"},
            {"path":"/vault/no-role.md","relative_path":"no-role.md","label":"Missing role"},
            {"path":"/vault/no-label.md","relative_path":"no-label.md","role":"note"},
            7,
            {"path":"/vault/also.md","relative_path":"also.md","role":"day","label":"Today","line":3}
          ]
        }
        """
        let success = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(success.openNotes?.map(\.path), ["/vault/good.md", "/vault/also.md"])
        XCTAssertEqual(success.openNotes?.map(\.label), ["Good", "Today"])
    }

    func testOpenNotesURLTruncatesToEightAndReportsTotal() throws {
        let notes = (1...10).map { index in
            CaptureOpenNote(
                path: "/vault/\(index).md",
                relativePath: "\(index).md",
                role: .note,
                label: "\(index)"
            )
        }
        let url = try XCTUnwrap(ObsidianOpenURL.openNotesURL(for: CaptureOpenPlan(openNotes: notes, captures: [])))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertEqual(query.first(where: { $0.name == "count" })?.value, "8")
        XCTAssertEqual(query.first(where: { $0.name == "path8" })?.value, "/vault/8.md")
        XCTAssertNil(query.first(where: { $0.name == "path9" }))
        XCTAssertEqual(query.first(where: { $0.name == "total" })?.value, "10")
        XCTAssertNil(ObsidianOpenURL.openNotesURL(for: CaptureOpenPlan(openNotes: [], captures: [])))
    }

    private func decodeSuccess(openNotes: String?) throws -> CaptureCommandSuccess {
        let notes = openNotes.map { ", \"open_notes\": \($0)" } ?? ""
        let json = """
        {
          "ok": true, "dry_run": false, "routed": false, "route_label": "Inbox",
          "relative_target": "inbox.md", "target": "/vault/inbox.md", "text": "Task",
          "task_line": "- [ ] Task", "kind": "task", "created": "today", "placement": "append"\(notes)
        }
        """
        return try JSONDecoder().decode(CaptureCommandSuccess.self, from: Data(json.utf8))
    }

    func testDecodesRealBobLinkedTaskOpenNotesFixture() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/capture-open-notes-linked-task.json")
        let success = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(success.kind, "task_toggle")
        let notes = try XCTUnwrap(success.openNotes)
        XCTAssertEqual(notes.map(\.role), [.note, .day])
        XCTAssertEqual(notes.map(\.label), ["cash.md", "Today"])
        XCTAssertEqual(notes[0].blockID, "goog-exit")
        XCTAssertEqual(notes[1].line, 2)
        let plan = CaptureOpenPlan(openNotes: notes, captures: [success])
        XCTAssertEqual(plan.source, .bob)
        XCTAssertNotNil(ObsidianOpenURL.openNotesURL(for: plan))
    }

    private func capture(target: String, relativeTarget: String) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: false,
            routeLabel: "Inbox",
            relativeTarget: relativeTarget,
            target: target,
            text: "Task",
            taskLine: "- [ ] Task",
            kind: "task",
            created: "today",
            placement: "append"
        )
    }
}
