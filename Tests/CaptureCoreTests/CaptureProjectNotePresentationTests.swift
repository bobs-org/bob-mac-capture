import XCTest

@testable import CaptureCore

final class CaptureProjectNotePresentationTests: XCTestCase {
    private func projectNoteSuccess(
        taskLinks: [CaptureProjectTaskLink],
        pomodoroName: String? = "ADMIN",
        createsPomodoro: Bool? = true
    ) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: true,
            route: "cash",
            routeLabel: "cash_goog_exit.md",
            relativeTarget: "cash_goog_exit.md",
            target: "/tmp/vault/cash_goog_exit.md",
            text: "Finish the Google exit packet!",
            taskLine: "- [ ] #task #prj Finish the Google exit packet! #hide ^prj",
            kind: "project_note",
            created: "2026-09-20",
            placement: "created",
            blockID: "prj",
            dayFile: "/tmp/vault/day.md",
            pomodoroName: pomodoroName,
            createsPomodoro: createsPomodoro,
            projectNote: CaptureProjectNoteSummary(
                basename: "cash_goog_exit.md",
                parentRoute: "cash",
                parentLink: "[[cash]]",
                tasks: 3,
                sections: ["Future Work"],
                taskLinks: taskLinks
            )
        )
    }

    private func link(_ id: String, text: String) -> CaptureProjectTaskLink {
        CaptureProjectTaskLink(
            blockID: id,
            blockLink: "[[cash_goog_exit#^\(id)]]",
            text: text,
            taskLine: "- [*] #task \(text) [created::2026-09-20] ^\(id)"
        )
    }

    func testTwoLinksIntoNewNamedPomodoro() throws {
        let success = projectNoteSuccess(
            taskLinks: [
                link("draft-memo", text: "Draft the resignation memo"),
                link("call-ms", text: "Call Morgan Stanley about the 401k"),
            ]
        )
        let presentation = try XCTUnwrap(CaptureProjectNotePresentation(capture: success))

        XCTAssertEqual(presentation.destinationLabel, "ADMIN")
        XCTAssertTrue(presentation.createdPomodoro)
        XCTAssertEqual(presentation.headerText, "Links 2 tasks into ADMIN (new)")
        XCTAssertEqual(
            presentation.linkedTasks,
            [
                CaptureProjectNotePresentation.LinkedTaskRow(
                    text: "Draft the resignation memo",
                    blockID: "draft-memo"
                ),
                CaptureProjectNotePresentation.LinkedTaskRow(
                    text: "Call Morgan Stanley about the 401k",
                    blockID: "call-ms"
                ),
            ]
        )
        XCTAssertEqual(presentation.notificationDetail, "Linked 2 tasks into ADMIN")
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains(
            "Links 2 tasks into ADMIN (new)"
        ))
    }

    func testOneLinkIntoExistingPomodoroUsesSingular() throws {
        let success = projectNoteSuccess(
            taskLinks: [link("draft-memo", text: "Draft the resignation memo")],
            createsPomodoro: false
        )
        let presentation = try XCTUnwrap(CaptureProjectNotePresentation(capture: success))

        XCTAssertEqual(presentation.headerText, "Links 1 task into ADMIN")
        XCTAssertEqual(presentation.notificationDetail, "Linked 1 task into ADMIN")
    }

    func testUnnamedPomodoroFallsBackToToday() throws {
        let success = projectNoteSuccess(
            taskLinks: [link("draft-memo", text: "Draft the resignation memo")],
            pomodoroName: nil,
            createsPomodoro: false
        )
        let presentation = try XCTUnwrap(CaptureProjectNotePresentation(capture: success))

        XCTAssertEqual(presentation.destinationLabel, "today's Pomodoro")
        XCTAssertEqual(presentation.headerText, "Links 1 task into today's Pomodoro")
        XCTAssertEqual(presentation.notificationDetail, "Linked 1 task into today's Pomodoro")
    }

    func testEmptyLinksAndMissingNoteYieldNil() {
        XCTAssertNil(CaptureProjectNotePresentation(
            capture: projectNoteSuccess(taskLinks: [])
        ))

        var withoutNote = projectNoteSuccess(taskLinks: [
            link("draft-memo", text: "Draft the resignation memo"),
        ])
        withoutNote = CaptureCommandSuccess(
            ok: withoutNote.ok,
            dryRun: withoutNote.dryRun,
            routed: withoutNote.routed,
            route: withoutNote.route,
            routeLabel: withoutNote.routeLabel,
            relativeTarget: withoutNote.relativeTarget,
            target: withoutNote.target,
            text: withoutNote.text,
            taskLine: withoutNote.taskLine,
            kind: withoutNote.kind,
            created: withoutNote.created,
            placement: withoutNote.placement,
            blockID: withoutNote.blockID,
            dayFile: withoutNote.dayFile
        )
        XCTAssertNil(CaptureProjectNotePresentation(capture: withoutNote))
    }

    func testFixtureDecodesTwoTaskLinks() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(
            contentsOf: fixtures.appendingPathComponent("project-note-task-links.json")
        )
        let success = try JSONDecoder().decode(CaptureCommandSuccess.self, from: data)

        XCTAssertEqual(success.kind, "project_note")
        let note = try XCTUnwrap(success.projectNote)
        XCTAssertEqual(note.basename, "cash_goog_exit.md")
        XCTAssertEqual(note.taskLinks.map { $0.blockID }, ["draft-memo", "call-ms"])
        XCTAssertEqual(
            note.taskLinks.map { $0.blockLink },
            ["[[cash_goog_exit#^draft-memo]]", "[[cash_goog_exit#^call-ms]]"]
        )
        XCTAssertEqual(success.pomodoroName, "ADMIN")
        XCTAssertEqual(success.createsPomodoro, true)

        let presentation = try XCTUnwrap(CaptureProjectNotePresentation(capture: success))
        XCTAssertEqual(presentation.headerText, "Links 2 tasks into ADMIN (new)")
    }
}
