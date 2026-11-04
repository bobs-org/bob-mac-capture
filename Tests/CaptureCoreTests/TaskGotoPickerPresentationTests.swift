import XCTest

@testable import CaptureCore

final class TaskGotoPickerPresentationTests: XCTestCase {
    private func candidates() throws -> [CaptureCompletionCandidate] {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/task-goto-candidates.json")
        return try JSONDecoder().decode(
            [CaptureCompletionCandidate].self,
            from: Data(contentsOf: fixture)
        )
    }

    private func closedCandidates() throws -> [CaptureCompletionCandidate] {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/task-goto-complete-closed.json")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any]
        )
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(object["candidates"]))
        return try JSONDecoder().decode([CaptureCompletionCandidate].self, from: data)
    }

    func testDecodesTaskGotoDestinationFieldsAndBuildsSelectableRows() throws {
        let candidates = try candidates()
        XCTAssertEqual(candidates[0].notePath, "Areas/dev.md")
        XCTAssertEqual(candidates[0].target, "/Users/example/Vault/Areas/dev.md")
        XCTAssertEqual(candidates[0].taskRef, "42:abcd1234")
        XCTAssertNil(candidates[0].blockID)

        let index = TaskLinkPickerIndex(candidates: candidates, mode: .taskGoto)
        let presentation = index.presentation(filter: "/")
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.countText, "3 tasks")

        let idless = try XCTUnwrap(presentation.row(id: "Areas/dev.md|42:abcd1234"))
        XCTAssertTrue(idless.isSelectable)
        XCTAssertNil(idless.insertion)
        XCTAssertNil(idless.pendingBlockID)
        XCTAssertNil(idless.blockID)
        XCTAssertEqual(idless.scheduledText, "Oct 3")
        XCTAssertFalse(idless.pullsForward)
        XCTAssertEqual(
            index.actionLine(for: idless),
            "↩ Opens Areas/dev.md at line 42"
        )
        XCTAssertEqual(
            idless.taskGotoDestination,
            CaptureTaskGotoDestination(
                target: "/Users/example/Vault/Areas/dev.md",
                notePath: "Areas/dev.md",
                line: 42,
                ref: "42:abcd1234"
            )
        )
    }

    func testTaskGotoKeepsTheTaskLinkCatalogOrderAndQueryRanking() throws {
        let candidates = try candidates()
        let goto = TaskLinkPickerIndex(candidates: candidates, mode: .taskGoto)
        let link = TaskLinkPickerIndex(candidates: candidates)

        let gotoAll = goto.presentation(filter: "")
        let linkAll = link.presentation(filter: "")
        XCTAssertEqual(
            gotoAll.sections.flatMap(\.rows).map(\.displayText),
            linkAll.sections.flatMap(\.rows).map(\.displayText)
        )

        let gotoMatches = goto.presentation(filter: "/ship")
        let linkMatches = link.presentation(filter: ":ship")
        XCTAssertEqual(
            gotoMatches.sections.flatMap(\.rows).map(\.displayText),
            linkMatches.sections.flatMap(\.rows).map(\.displayText)
        )
        XCTAssertEqual(gotoMatches.orderedRowIDs, ["Projects/Launch.md|9:beef9876"])

        let project = try XCTUnwrap(gotoMatches.row(id: "Projects/Launch.md|9:beef9876"))
        XCTAssertEqual(
            goto.actionLine(for: project),
            "↩ Opens Projects/Launch.md at ^ship-it"
        )
        XCTAssertEqual(
            project.taskGotoDestination?.target,
            "/Users/example/Vault/Projects/Launch.md"
        )

        let inbox = try XCTUnwrap(gotoAll.row(id: "Inbox.md|4:1020abcd"))
        XCTAssertEqual(
            goto.actionLine(for: inbox),
            "↩ Opens Inbox.md at line 4"
        )
    }

    func testMissingTaskGotoDestinationDoesNotBecomeALinkOrBlockIDPrompt() throws {
        let candidate = CaptureCompletionCandidate(
            replacement: "",
            route: "inbox",
            taskRef: "1:abcd1234",
            requiresBlockID: true,
            text: "Call the bank",
            line: 1,
            notePath: "Inbox.md"
        )
        let index = TaskLinkPickerIndex(candidates: [candidate], mode: .taskGoto)
        let row = try XCTUnwrap(index.presentation(filter: "/").row(id: "Inbox.md|1:abcd1234"))

        XCTAssertTrue(row.isSelectable)
        XCTAssertNil(row.insertion)
        XCTAssertNil(row.pendingBlockID)
        XCTAssertNil(row.taskGotoDestination)
        XCTAssertEqual(index.actionLine(for: row), "Task location unavailable")
    }

    func testCompletedTasksTrailOpenRowsAndUseVaultPathKeys() throws {
        let all = try closedCandidates()
        let index = TaskLinkPickerIndex(candidates: all, mode: .taskGoto)
        let presentation = index.presentation(filter: "/")
        let openCandidates = all.filter { $0.group != "completed" }
        let openOnly = TaskLinkPickerIndex(candidates: openCandidates, mode: .taskGoto)
            .presentation(filter: "/")

        XCTAssertEqual(
            Array(presentation.orderedRowIDs.prefix(openOnly.orderedRowIDs.count)),
            openOnly.orderedRowIDs
        )
        XCTAssertEqual(presentation.sections.last?.title, "Completed")
        XCTAssertEqual(presentation.sections.last?.kind, .other)
        XCTAssertEqual(
            presentation.sections.last?.rows.map(\.id),
            [
                "done/old.md|12:deadbeef", "mac_inbox.md|13:cafebabe",
                "References/old.md|12:deadbeef",
            ]
        )

        let done = try XCTUnwrap(presentation.row(id: "done/old.md|12:deadbeef"))
        XCTAssertEqual(done.glyph, .task(.done))
        XCTAssertEqual(done.scheduledText, "Closed Oct 31, 2020")
        XCTAssertEqual(done.taskGotoDestination?.target, "/tmp/bob-fixture/done/old.md")
        XCTAssertEqual(
            index.actionLine(for: done),
            "↩ Opens done/old.md at ^old-fix"
        )
        let duplicateLocator = try XCTUnwrap(presentation.row(id: "References/old.md|12:deadbeef"))
        XCTAssertEqual(duplicateLocator.route, "shared")
    }

    func testFilteredGoToMatchesKeepOpenTasksBeforeCompletedTasks() throws {
        var all = try closedCandidates()
        all.insert(
            CaptureCompletionCandidate(
                replacement: "",
                route: "old-work",
                taskRef: "1:11111111",
                statusSymbol: " ",
                statusName: "Todo",
                text: "Old issue follow-up",
                line: 1,
                group: "note",
                notePath: "Areas/old-work.md"
            ),
            at: 0
        )
        let index = TaskLinkPickerIndex(candidates: all, mode: .taskGoto)
        let rows = index.presentation(filter: "/old").sections.flatMap(\.rows)

        XCTAssertGreaterThan(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "Areas/old-work.md|1:11111111")
        XCTAssertTrue(
            rows.dropFirst().allSatisfy {
                $0.id.contains("|") && $0.id != "Areas/old-work.md|1:11111111"
            })
    }

    func testTaskGotoSourceNeedAndCompletionContextStrings() throws {
        XCTAssertEqual(CapturePickerSource.taskGoto.triggerByte, 47)
        XCTAssertEqual(CapturePickerSource.taskGoto.scopeSymbolText, "/")
        XCTAssertEqual(CapturePickerSource.taskGoto.scopeCaption, "Go To")
        XCTAssertEqual(
            CapturePickerSource.taskGoto.scopeCaption(includesClosedTasks: true),
            "Go To · + Completed"
        )
        XCTAssertEqual(
            CapturePickerSource.taskGoto.filterPlaceholder,
            "Search tasks to open by text, note, or ^id"
        )
        XCTAssertEqual(CapturePickerSource.taskGoto.appearedAnnouncementPrefix, "Go To")
        XCTAssertEqual(
            CapturePickerSource.taskGoto.keyHintItems(includesClosedTasks: true)
                .first(where: { $0.keys == "⌘X" })?.action,
            "Hide Completed"
        )
        XCTAssertEqual(
            CapturePickerNeed.taskGoto.statusText,
            "Pick a task to open — press Tab to browse"
        )
        XCTAssertEqual(CaptureCompletionContext(rawContext: "task_goto"), .taskGoto)

        let candidate = try candidates()[0]
        let content = completionRowContent(for: candidate, context: "task_goto", query: "")
        XCTAssertEqual(content.contextLabel, "Task to open")
        XCTAssertEqual(content.secondaryText, "Areas/dev.md:line 42")
        XCTAssertTrue(content.accessibilityHint.contains("without changing the vault"))
    }

    func testTaskGotoURLStrictlyEncodesAndValidatesProtocolParameters() throws {
        let url = try XCTUnwrap(
            ObsidianOpenURL.taskGotoURL(
                path: "/Users/bryan/Vault/Café + notes & more # 100% = yes.md",
                line: 42,
                ref: "42:abcd1234",
                blockID: "cash-notes"
            )
        )
        XCTAssertEqual(url.scheme, "obsidian")
        XCTAssertEqual(url.host, "bob-goto-task")
        XCTAssertEqual(
            url.absoluteString,
            "obsidian://bob-goto-task?path=/Users/bryan/Vault/Caf%C3%A9%20%2B%20notes%20%26%20more%20%23%20100%25%20%3D%20yes.md&line=42&ref=42%3Aabcd1234&block=cash-notes"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            components.queryItems?.map(\.name),
            ["path", "line", "ref", "block"]
        )
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "path" }?.value,
            "/Users/bryan/Vault/Café + notes & more # 100% = yes.md"
        )

        XCTAssertNil(ObsidianOpenURL.taskGotoURL(path: "relative.md", line: 1, ref: "1:abcd1234"))
        XCTAssertNil(ObsidianOpenURL.taskGotoURL(path: "/note.md", line: 0, ref: "1:abcd1234"))
        XCTAssertNil(ObsidianOpenURL.taskGotoURL(path: "/note.md", line: 1, ref: "01:abcd1234"))
        XCTAssertNil(ObsidianOpenURL.taskGotoURL(path: "/note.md", line: 1, ref: "1:ABCDEF12"))
        XCTAssertNil(
            ObsidianOpenURL.taskGotoURL(
                path: "/note.md",
                line: 1,
                ref: "1:abcd1234",
                blockID: "bad_id"
            )
        )
    }

    func testTaskGotoURLOmitsRefQueryItemWhenRefIsNil() throws {
        let url = try XCTUnwrap(
            ObsidianOpenURL.taskGotoURL(path: "/note.md", line: 1, ref: nil)
        )
        XCTAssertEqual(url.absoluteString, "obsidian://bob-goto-task?path=/note.md&line=1")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.map(\.name), ["path", "line"])
        XCTAssertNil(components.queryItems?.first { $0.name == "ref" })
    }

    func testTaskGotoURLStillRejectsInvalidNonNilRef() {
        XCTAssertNil(ObsidianOpenURL.taskGotoURL(path: "/note.md", line: 1, ref: "1:ABCDEF12"))
        XCTAssertNil(ObsidianOpenURL.taskGotoURL(path: "/note.md", line: 1, ref: "01:abcd1234"))
    }
}
