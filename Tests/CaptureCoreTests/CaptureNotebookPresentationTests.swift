import Foundation
import XCTest

@testable import CaptureCore

final class CaptureNotebookPresentationTests: XCTestCase {
    private func successFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            throw NSError(domain: "CaptureNotebookPresentationTests", code: 1)
        }
        return success
    }

    func testCreateFilePairsToItsNotebookItemByPathAndAction() throws {
        let success = try successFixture("notebook-capture-create-then-use.json")
        let items = success.normalizedCaptures
        let pairs = CaptureNotebookPresentation.pairIndexed(
            files: success.noteFiles,
            items: items
        )

        XCTAssertEqual(items.map(\.kind), ["notebook_create", "notebook_note"])
        XCTAssertEqual(pairs.keys.sorted(), [0])
        let file = try XCTUnwrap(pairs[0])
        XCTAssertEqual(file.path, "dev_keys.md")
        XCTAssertEqual(file.action, "create")
        XCTAssertEqual(file.recordType, "")
        XCTAssertEqual(file.body, "## Mappings\n\n- Leader key basics [created::2026-11-10]\n")
        XCTAssertEqual(file.markdown, success.noteFiles[0].markdown)
    }

    func testNotebookMetadataDrivesSectionAndChildNoteCopy() throws {
        let success = try successFixture("notebook-capture-existing-notes.json")
        let items = success.normalizedCaptures

        XCTAssertEqual(items.map(\.kind), [
            "notebook_note",
            "notebook_note",
            "notebook_sub_note",
            "notebook_sub_note",
        ])
        XCTAssertEqual(
            CaptureNotebookPresentation.headline(for: items[1]),
            "📓 Note → Neovim › Release Notes"
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.newSectionBadge(for: items[1]),
            "New section · Release Notes"
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.headline(for: items[2]),
            "📓 Note → Neovim › ^existing-guide"
        )
        XCTAssertEqual(CaptureNotebookPresentation.contentText(for: items[2]), "Additional guide details")
        XCTAssertNil(CaptureNotebookPresentation.newSectionBadge(for: items[0]))
    }

    func testConsecutiveNotebookNotesGroupByRouteAndSplitAtOtherKinds() throws {
        let success = try successFixture("notebook-capture-existing-notes.json")
        let items = success.normalizedCaptures
        let runs = CaptureNotebookPresentation.groupedNoteRuns(items: items)

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].route, "dev_nvim")
        XCTAssertEqual(runs[0].title, "Neovim")
        XCTAssertEqual(runs[0].itemIndexes, [0, 1])
        XCTAssertEqual(runs[0].headline, "📓 2 notes → Neovim")
        XCTAssertEqual(CaptureNotebookPresentation.destinationLine(for: items[0]), "› Setup")
        XCTAssertEqual(CaptureNotebookPresentation.destinationLine(for: items[1]), "› Release Notes")
        XCTAssertNil(CaptureNotebookPresentation.groupedNewSectionLabel(for: items[0]))
        XCTAssertEqual(CaptureNotebookPresentation.groupedNewSectionLabel(for: items[1]), "New section")
    }

    func testGroupedNotesPreserveExistingNewAndTopDestinations() throws {
        let success = try successFixture("notebook-capture-grouped-notes.json")
        let items = success.normalizedCaptures
        let runs = CaptureNotebookPresentation.groupedNoteRuns(items: items)

        XCTAssertEqual(items.map { $0.notebook?.section }, ["Setup", "Batch Notes", nil])
        XCTAssertEqual(items.map { $0.notebook?.sectionAction }, ["existing", "create", nil])
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].itemIndexes, [0, 1, 2])
        XCTAssertEqual(runs[0].headline, "📓 3 notes → Neovim")
        XCTAssertEqual(CaptureNotebookPresentation.destinationLine(for: items[0]), "› Setup")
        XCTAssertEqual(CaptureNotebookPresentation.destinationLine(for: items[1]), "› Batch Notes")
        XCTAssertEqual(CaptureNotebookPresentation.destinationLine(for: items[2]), "· top")
        XCTAssertEqual(CaptureNotebookPresentation.groupedNewSectionLabel(for: items[1]), "New section")
        XCTAssertNil(CaptureNotebookPresentation.groupedNewSectionLabel(for: items[2]))
    }

    func testGroupedNotesSplitOnMissingMetadataRouteChangeAndSeparatedOccurrences() {
        let setup = notebookNote(route: "dev_nvim", title: "Neovim", section: "Setup")
        let missing = notebookNote(route: nil, title: "Neovim", section: "Setup")
        let other = notebookNote(route: "dev_lua", title: "Lua", section: "Basics")
        let later = notebookNote(route: "dev_nvim", title: "Neovim", section: "Git")
        let sub = CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: true,
            route: "dev_nvim",
            routeLabel: "dev_nvim.md",
            relativeTarget: "dev_nvim.md",
            target: "/tmp/dev_nvim.md",
            text: "Child",
            taskLine: "- Child",
            kind: "notebook_sub_note",
            created: "",
            placement: "appended",
            notebook: CaptureNotebookSummary(route: "dev_nvim", title: "Neovim")
        )
        let items = [setup, setup, missing, other, other, sub, later, later]
        let runs = CaptureNotebookPresentation.groupedNoteRuns(items: items)

        XCTAssertEqual(runs.map(\.itemIndexes), [[0, 1], [3, 4], [6, 7]])
        XCTAssertEqual(runs.map(\.route), ["dev_nvim", "dev_lua", "dev_nvim"])
        XCTAssertEqual(CaptureNotebookPresentation.destinationLine(for: missing), "› Setup")
    }

    func testNotebookSectionEditorHelpUsesBobSpanMetadataAndBounds() {
        let draft = "hello @dev_nvim#Setup"
        let start = draft.utf8.count - "Setup".utf8.count
        let existing = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            grammar: 26,
            input: draft,
            body: draft,
            mode: "task",
            spans: [CaptureSpan(
                start: start,
                end: draft.utf8.count,
                kind: "section",
                notebook: true,
                sectionAction: "existing",
                title: "Setup"
            )]
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.editorSectionHelp(parse: existing, cursorUTF8: draft.utf8.count),
            "Setup, existing section"
        )
        XCTAssertNil(CaptureNotebookPresentation.editorSectionHelp(parse: existing, cursorUTF8: start - 1))

        let created = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            grammar: 26,
            input: draft,
            body: draft,
            mode: "task",
            spans: [CaptureSpan(
                start: start,
                end: draft.utf8.count,
                kind: "section",
                notebook: true,
                sectionAction: "future_action",
                title: "Setup"
            )]
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.editorSectionHelp(parse: created, cursorUTF8: start),
            "Setup, existing section",
            "unknown actions follow the safe existing-section wording"
        )
    }

    func testNotebookRouteAndParentCompletionMetadataDecode() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let targets = try JSONDecoder().decode(
            CaptureTargetsResponse.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("notebook-targets.json"))
        )
        let notebook = try XCTUnwrap(targets.targets.first { $0.route == "dev_nvim_lua" })
        XCTAssertEqual(notebook.title, "Lua")
        XCTAssertEqual(notebook.summary, "Lua snippets for the Neovim configuration.")
        XCTAssertEqual(notebook.owner, "dev")
        XCTAssertEqual(notebook.breadcrumb, ["dev", "Neovim", "Lua"])

        let routeCompletion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("notebook-complete-route.json"))
        )
        let route = try XCTUnwrap(
            routeCompletion.candidates.first { $0.route == "dev_nvim" }
        )
        XCTAssertEqual(route.kind, "notebook")
        XCTAssertEqual(route.title, "Neovim")
        XCTAssertEqual(route.owner, "dev")
        XCTAssertEqual(route.breadcrumb, ["dev", "Neovim"])

        let completion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("notebook-complete-parent-notes.json"))
        )
        XCTAssertTrue(completion.candidates.allSatisfy { $0.itemKind == "note" })
        XCTAssertTrue(completion.candidates.contains { $0.blockID == "existing-guide" })
        XCTAssertTrue(completion.candidates.contains { $0.requiresBlockID })

        let blockCompletion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("notebook-complete-block-id.json"))
        )
        XCTAssertEqual(blockCompletion.blockID?.intent, .new)
        XCTAssertEqual(blockCompletion.blockID?.destinationKind, "notebook")

        let directiveCompletion = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("notebook-complete-create-directive.json"))
        )
        XCTAssertTrue(directiveCompletion.candidates.contains { $0.replacement == "%n" })
    }

    func testMalformedOptionalNotebookMetadataAndCandidateRoleAreIgnored() throws {
        let summary = try JSONDecoder().decode(
            CaptureNotebookSummary.self,
            from: Data(#"{"title":false,"breadcrumb":17,"section_action":42}"#.utf8)
        )
        XCTAssertNil(summary.title)
        XCTAssertNil(summary.breadcrumb)
        XCTAssertNil(summary.sectionAction)

        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data(#"{"replacement":"x","item_kind":42,"breadcrumb":"wrong"}"#.utf8)
        )
        XCTAssertNil(candidate.itemKind)
        XCTAssertNil(candidate.breadcrumb)
    }

    func testNotebookNotificationsUseNotebookCopyForSingleAndBatchItems() throws {
        let success = try successFixture("notebook-capture-create-then-use.json")
        let create = try XCTUnwrap(success.normalizedCaptures.first)
        XCTAssertEqual(
            CaptureNotebookPresentation.notificationTitle(for: create),
            "📓 New notebook dev_keys.md · in dev"
        )
        XCTAssertEqual(CaptureNotebookPresentation.notificationBody(for: create), "Keymaps")
        XCTAssertTrue(CaptureNotebookPresentation.batchLine(for: success.normalizedCaptures[1])
            .contains("Primary leader key"))
    }

    func testCreationParentUsesPenultimateBreadcrumbComponent() throws {
        let area = try successFixture("notebook-capture-create-then-use.json")
        let areaCreate = try XCTUnwrap(area.normalizedCaptures.first)
        XCTAssertEqual(areaCreate.notebook?.breadcrumb, ["dev", "Keys"])
        XCTAssertEqual(
            CaptureNotebookPresentation.creationParentContext(for: areaCreate),
            "dev"
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.headline(for: areaCreate),
            "📓 New notebook dev_keys.md · in dev"
        )

        let nested = try successFixture("notebook-capture-create-nested.json")
        let nestedCreate = try XCTUnwrap(nested.normalizedCaptures.first)
        XCTAssertEqual(nestedCreate.notebook?.breadcrumb, ["dev", "Neovim", "Lua", "Keys"])
        XCTAssertEqual(
            CaptureNotebookPresentation.creationParentContext(for: nestedCreate),
            "Lua"
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.headline(for: nestedCreate),
            "📓 New notebook dev_nvim_lua_keys.md · in Lua"
        )
    }

    func testCreationParentOmitsMissingShortAndBlankMetadata() {
        XCTAssertNil(
            CaptureNotebookPresentation.creationParentContext(
                for: notebookCreate(breadcrumb: nil)
            )
        )
        XCTAssertNil(
            CaptureNotebookPresentation.creationParentContext(
                for: notebookCreate(breadcrumb: [])
            )
        )
        XCTAssertNil(
            CaptureNotebookPresentation.creationParentContext(
                for: notebookCreate(breadcrumb: ["Keys"])
            )
        )
        XCTAssertNil(
            CaptureNotebookPresentation.creationParentContext(
                for: notebookCreate(breadcrumb: ["  ", "Keys"])
            )
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.headline(for: notebookCreate(breadcrumb: ["Keys"])),
            "📓 New notebook dev_keys.md"
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.creationParentContext(
                for: notebookCreate(breadcrumb: ["dev", "Neovim", "Lua", "Keys"])
            ),
            "Lua"
        )
    }

    func testNestedCreationHeadlineNotificationAndFilePairing() throws {
        let success = try successFixture("notebook-capture-create-nested.json")
        let items = success.normalizedCaptures
        let pairs = CaptureNotebookPresentation.pairIndexed(
            files: success.noteFiles,
            items: items
        )

        XCTAssertEqual(items.map(\.kind), ["notebook_create"])
        XCTAssertEqual(pairs.keys.sorted(), [0])
        let file = try XCTUnwrap(pairs[0])
        XCTAssertEqual(file.path, "dev_nvim_lua_keys.md")
        XCTAssertEqual(file.action, "create")
        XCTAssertEqual(file.body, "## Mappings\n\n- Leader key basics [created::2026-11-10]\n")
        XCTAssertEqual(file.markdown, success.noteFiles[0].markdown)

        let create = try XCTUnwrap(items.first)
        XCTAssertEqual(
            CaptureNotebookPresentation.headline(for: create),
            "📓 New notebook dev_nvim_lua_keys.md · in Lua"
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.notificationTitle(for: create),
            "📓 New notebook dev_nvim_lua_keys.md · in Lua"
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.notificationBody(for: create, file: file),
            file.body
        )
        XCTAssertEqual(
            CaptureNotebookPresentation.batchLine(for: create),
            "📓 New notebook dev_nvim_lua_keys.md · in Lua · Keymaps"
        )
    }

    private func notebookNote(
        route: String?,
        title: String,
        section: String?
    ) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: true,
            route: route ?? "dev_nvim",
            routeLabel: "dev_nvim.md",
            relativeTarget: "dev_nvim.md",
            target: "/tmp/dev_nvim.md",
            text: "Note",
            taskLine: "- Note",
            kind: "notebook_note",
            created: "",
            placement: "appended",
            notebook: CaptureNotebookSummary(
                route: route,
                title: title,
                section: section
            )
        )
    }

    private func notebookCreate(breadcrumb: [String]?) -> CaptureCommandSuccess {
        let notebook: CaptureNotebookSummary?
        if let breadcrumb {
            notebook = CaptureNotebookSummary(
                route: "dev_keys",
                title: "Keys",
                breadcrumb: breadcrumb
            )
        } else {
            notebook = nil
        }
        return CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: true,
            route: "dev_keys",
            routeLabel: "dev_keys.md",
            relativeTarget: "dev_keys.md",
            target: "/tmp/dev_keys.md",
            text: "Keymaps",
            taskLine: "Keymaps",
            kind: "notebook_create",
            created: "2026-11-10",
            placement: "created",
            notebook: notebook
        )
    }
}
