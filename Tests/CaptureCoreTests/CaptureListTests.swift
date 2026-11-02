import XCTest

@testable import CaptureCore

/// Lists under a lone `@file` header: the block-ID splice a nested-line prompt
/// returns, the owner caption, the preview grouping, and the first-bullet
/// newline. Every fixture is a raw Bob reply produced by
/// `Scripts/generate-list-fixtures.sh` (see `Tests/Fixtures/list-fixtures-README.md`).
final class CaptureListTests: XCTestCase {
    // MARK: - Fixtures

    private func fixtureData(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private func completion(_ name: String) throws -> CaptureCompletionResponse {
        try JSONDecoder().decode(CaptureCompletionResponse.self, from: fixtureData(name))
    }

    private func field(_ name: String) throws -> CaptureBlockIDField {
        try XCTUnwrap(completion(name).blockID)
    }

    private func parse(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(CaptureParseResponse.self, from: fixtureData(name))
    }

    private func success(_ name: String) throws -> CaptureCommandSuccess {
        try JSONDecoder().decode(CaptureCommandSuccess.self, from: fixtureData(name))
    }

    /// The worked example with the prompt open on the nested line.
    private let nestedPrompt = "@dev\n- Fix flaky gkeep test\n  - repro on CI first :"
    /// The same draft once the nested prompt's ID lands on the owner line.
    private let nestedAccepted =
        "@dev\n- Fix flaky gkeep test :fix-flaky-gkeep\n  - repro on CI first"

    // MARK: - Decoding

    func testNestedPromptDecodesOwnerLineAndSplice() throws {
        let field = try field("list-complete-nested.json")

        XCTAssertEqual(field.route, "dev")
        XCTAssertEqual(field.relativeTarget, "dev.md")
        XCTAssertEqual(field.body, "Fix flaky gkeep test")
        XCTAssertEqual(field.suggestions.first, "fix-flaky-gkeep")
        XCTAssertEqual(field.ownerLine, 2)
        XCTAssertEqual(
            field.splice,
            CaptureBlockIDSplice(
                range: CaptureRange(start: 27, end: 51),
                before: " :",
                after: "\n  - repro on CI first"
            )
        )
    }

    func testSameLinePromptSpliceIsTheOrdinaryInsertion() throws {
        let response = try completion("list-complete-same-line.json")
        let field = try XCTUnwrap(response.blockID)

        XCTAssertEqual(field.ownerLine, 2)
        XCTAssertEqual(
            field.splice,
            CaptureBlockIDSplice(range: response.replacement, before: "", after: "")
        )
    }

    func testPromptWithoutSpliceDecodesNil() throws {
        // Fixture from an older Bob: no `owner_line`, no `splice`.
        let data = Data(
            """
            {"ok":true,"schema_version":1,"cursor":45,"replacement":{"start":45,"end":45},
            "context":"project_task_block_id","candidates":[],
            "block_id":{"route":"cash_goog_exit","relative_target":"cash_goog_exit.md",
            "marker":":","intent":"new","body":"Draft the memo","suggestions":["draft-memo"]}}
            """.utf8
        )
        let field = try XCTUnwrap(
            JSONDecoder().decode(CaptureCompletionResponse.self, from: data).blockID
        )

        XCTAssertNil(field.ownerLine)
        XCTAssertNil(field.splice)
    }

    func testMalformedSpliceNeverBreaksTheField() throws {
        let data = Data(
            """
            {"ok":true,"schema_version":1,"cursor":4,"replacement":{"start":4,"end":4},
            "context":"project_task_block_id","candidates":[],
            "block_id":{"route":"dev","marker":":","intent":"new","owner_line":"two",
            "splice":{"range":"nope"}}}
            """.utf8
        )
        let field = try XCTUnwrap(
            JSONDecoder().decode(CaptureCompletionResponse.self, from: data).blockID
        )

        XCTAssertEqual(field.route, "dev")
        XCTAssertNil(field.ownerLine)
        XCTAssertNil(field.splice)
    }

    // MARK: - Splice

    func testNestedSpliceMovesTheIDOntoTheOwnerLineAndKeepsTheCaretWhereTyping() throws {
        let splice = try XCTUnwrap(try field("list-complete-nested.json").splice)

        let applied = try XCTUnwrap(splice.applied(id: "fix-flaky-gkeep", to: nestedPrompt))

        XCTAssertEqual(applied.draft, nestedAccepted)
        // The caret returns to the end of the nested line, where the user typed.
        XCTAssertEqual(applied.caret, nestedAccepted.utf8.count)
        XCTAssertEqual(applied.written, " :fix-flaky-gkeep\n  - repro on CI first")
    }

    func testNestedSpliceAgreesWithTheAcceptedDraftBobParses() throws {
        // The commit-agreement check: the draft the splice produces is exactly
        // the draft Bob parsed into a task carrying the ID on its own line.
        let splice = try XCTUnwrap(try field("list-complete-nested.json").splice)
        let applied = try XCTUnwrap(splice.applied(id: "fix-flaky-gkeep", to: nestedPrompt))
        let worked = try parse("list-parse-worked.json")

        XCTAssertTrue(worked.input.hasPrefix(applied.draft))
        XCTAssertEqual(worked.items.first?.blockID, "fix-flaky-gkeep")
        XCTAssertEqual(worked.items.first?.body, "Fix flaky gkeep test")
    }

    func testSameLineSpliceInsertsAtTheCaret() throws {
        let splice = try XCTUnwrap(try field("list-complete-same-line.json").splice)
        let draft = "@dev\n- Fix flaky gkeep test :"

        let applied = try XCTUnwrap(splice.applied(id: "fix-flaky-gkeep", to: draft))

        XCTAssertEqual(applied.draft, "@dev\n- Fix flaky gkeep test :fix-flaky-gkeep")
        XCTAssertEqual(applied.caret, applied.draft.utf8.count)
    }

    func testSpliceReplacesTheOwnersExistingID() throws {
        let splice = try XCTUnwrap(try field("list-complete-nested-owner-id.json").splice)
        let draft = "@dev\n- Fix flaky gkeep test :old-id\n  - repro on CI first :"

        let applied = try XCTUnwrap(splice.applied(id: "fix-flaky-gkeep", to: draft))

        XCTAssertEqual(
            applied.draft,
            "@dev\n- Fix flaky gkeep test :fix-flaky-gkeep\n  - repro on CI first"
        )
        XCTAssertFalse(applied.draft.contains("old-id"))
    }

    func testCaretSigilSpliceWritesACaretID() throws {
        let splice = try XCTUnwrap(try field("list-complete-nested-caret.json").splice)
        let draft = "@dev\n- Fix flaky gkeep test\n  - repro on CI first ^"

        let applied = try XCTUnwrap(splice.applied(id: "fix-flaky-gkeep", to: draft))

        XCTAssertEqual(
            applied.draft,
            "@dev\n- Fix flaky gkeep test ^fix-flaky-gkeep\n  - repro on CI first"
        )
    }

    func testProjectNoteSameLinePromptKeepsTheOrdinaryInsertion() throws {
        let response = try completion("list-complete-project-note-same-line.json")
        let field = try XCTUnwrap(response.blockID)
        let splice = try XCTUnwrap(field.splice)
        let draft = "Finish it @cash^goog-exit@\n- Draft the memo :"

        XCTAssertEqual(field.ownerLine, 2)
        XCTAssertEqual(splice, CaptureBlockIDSplice(range: response.replacement))
        XCTAssertEqual(
            splice.applied(id: "draft-memo", to: draft)?.draft,
            "Finish it @cash^goog-exit@\n- Draft the memo :draft-memo"
        )
    }

    func testProjectNoteNestedPromptSplicesOntoTheOwnerBullet() throws {
        let splice = try XCTUnwrap(try field("list-complete-project-note-nested.json").splice)
        let draft = "Finish it @cash^goog-exit@\n- Draft the memo\n  - outline first :"

        let applied = try XCTUnwrap(splice.applied(id: "draft-memo", to: draft))

        XCTAssertEqual(
            applied.draft,
            "Finish it @cash^goog-exit@\n- Draft the memo :draft-memo\n  - outline first"
        )
        XCTAssertEqual(applied.caret, applied.draft.utf8.count)
    }

    func testTypeThroughRemainderLandsAfterTheNestedLineText() throws {
        let splice = try XCTUnwrap(try field("list-complete-nested.json").splice)

        let applied = try XCTUnwrap(
            splice.applied(id: "fix-flaky-gkeep", remainder: " s:2", to: nestedPrompt)
        )

        XCTAssertEqual(
            applied.draft,
            "@dev\n- Fix flaky gkeep test :fix-flaky-gkeep\n  - repro on CI first s:2"
        )
        XCTAssertEqual(applied.caret, applied.draft.utf8.count)
    }

    func testSpliceRefusesAStaleDraft() throws {
        let splice = try XCTUnwrap(try field("list-complete-nested.json").splice)

        XCTAssertNil(splice.applied(id: "x", to: "@dev"))
        // A byte range that splits a multibyte character is not a valid edit.
        let multibyte = CaptureBlockIDSplice(range: CaptureRange(start: 1, end: 2))
        XCTAssertNil(multibyte.applied(id: "x", to: "é"))
    }

    func testSpliceHandlesMultibyteText() {
        let draft = "@dev\n- Café run\n  - épicerie :"
        let splice = CaptureBlockIDSplice(
            range: CaptureRange(start: 16, end: 32),
            before: " :",
            after: "\n  - épicerie"
        )

        let applied = splice.applied(id: "cafe-run", to: draft)

        XCTAssertEqual(applied?.draft, "@dev\n- Café run :cafe-run\n  - épicerie")
        XCTAssertEqual(applied?.caret, applied.map { $0.draft.utf8.count })
    }

    // MARK: - Owner caption

    func testMarkerLineCountsDraftLines() throws {
        XCTAssertEqual(try field("list-complete-nested.json").markerLine(in: nestedPrompt), 3)
        let sameLine = try field("list-complete-same-line.json")
        XCTAssertEqual(sameLine.markerLine(in: "@dev\n- Fix flaky gkeep test :"), 2)
    }

    func testOwnerCaptionAppearsOnlyWhenTheOwnerIsOnAnotherLine() throws {
        let nested = try field("list-complete-nested.json")
        XCTAssertEqual(nested.ownerTaskText(markerLine: 3), "Fix flaky gkeep test")
        XCTAssertNil(nested.ownerTaskText(markerLine: 2))
        XCTAssertNil(nested.ownerTaskText(markerLine: nil))

        let sameLine = try field("list-complete-same-line.json")
        XCTAssertNil(sameLine.ownerTaskText(markerLine: 2))
    }

    func testOwnerCaptionTruncatesLongBodies() {
        let body = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
        let field = CaptureBlockIDField(
            route: "dev",
            relativeTarget: "dev.md",
            marker: ":",
            intent: .new,
            body: body,
            allowedCharacter: "[A-Za-z0-9-]",
            allowedDescription: "",
            ownerLine: 2
        )

        let text = field.ownerTaskText(markerLine: 3)

        XCTAssertEqual(text?.count, 61)
        XCTAssertTrue(text?.hasSuffix("\u{2026}") ?? false)
    }

    func testNestedPromptNamesTheOwnerInTheHeaderAndTheDetailStrip() throws {
        let response = try completion("list-complete-nested.json")
        let index = BlockIDPickerIndex(
            field: response.blockID,
            candidates: [],
            route: "dev",
            scope: .projectTask,
            markerLine: 3
        )

        let presentation = index.presentation(filter: "")
        let status = try XCTUnwrap(presentation.blockIDStatus)
        XCTAssertEqual(status.ownerCaption, "ID for \u{2018}Fix flaky gkeep test\u{2019}")
        XCTAssertEqual(
            status.ownerOutcome,
            "Next task in \u{25A3} dev.md, linked into today's Pomodoro"
        )
        let row = try XCTUnwrap(presentation.row(id: "suggestion:fix-flaky-gkeep"))
        XCTAssertEqual(row.detail.statusText, "ID for \u{2018}Fix flaky gkeep test\u{2019}")
        XCTAssertTrue(
            row.detail.summary.hasPrefix(
                "Next task in \u{25A3} dev.md, linked into today's Pomodoro"
            )
        )
    }

    func testSameLinePromptKeepsTheTaskTitleAndNoOwnerHeader() throws {
        let response = try completion("list-complete-same-line.json")
        let index = BlockIDPickerIndex(
            field: response.blockID,
            candidates: [],
            route: "dev",
            scope: .projectTask,
            markerLine: 2
        )

        let presentation = index.presentation(filter: "")
        let status = try XCTUnwrap(presentation.blockIDStatus)
        XCTAssertNil(status.ownerCaption)
        XCTAssertNil(status.ownerOutcome)
        let row = try XCTUnwrap(presentation.row(id: "suggestion:fix-flaky-gkeep"))
        XCTAssertEqual(row.detail.statusText, "\u{201C}Fix flaky gkeep test\u{201D}")
    }

    func testIndexWithoutAMarkerLineNeverCaptionsAnOwner() throws {
        let response = try completion("list-complete-nested.json")
        let index = BlockIDPickerIndex(
            field: response.blockID,
            candidates: [],
            route: "dev",
            scope: .projectTask
        )

        XCTAssertNil(index.presentation(filter: "").blockIDStatus?.ownerCaption)
    }

    func testInsertedAnnouncementNamesTheOwnerOnlyAcrossLines() throws {
        let nested = try field("list-complete-nested.json")
        let context = BlockIDPickerContext(
            field: nested,
            route: "dev",
            marker: ":",
            intent: .new,
            rules: nil,
            scope: .projectTask
        )

        XCTAssertEqual(
            context.insertedAnnouncement(id: "fix-flaky-gkeep", markerLine: 3),
            "Inserted :fix-flaky-gkeep on \u{2018}Fix flaky gkeep test\u{2019}"
        )
        XCTAssertEqual(
            context.insertedAnnouncement(id: "fix-flaky-gkeep", markerLine: 2),
            "Inserted :fix-flaky-gkeep"
        )
        let note = BlockIDPickerContext(
            field: nil,
            route: "sase",
            marker: ":",
            intent: .link,
            rules: nil
        )
        XCTAssertEqual(
            note.insertedAnnouncement(id: "tool", markerLine: nil),
            "Inserted @sase:tool"
        )
    }

    // MARK: - Preview grouping

    func testListResultsDecodeTheListObject() throws {
        let tasks = try success("list-capture-tasks.json")

        XCTAssertEqual(tasks.captures.count, 3)
        let expected = (1...3).map { position in
            CaptureListContext(
                kind: "tasks",
                route: "dev",
                headerLine: 1,
                position: position,
                count: 3
            )
        }
        XCTAssertEqual(tasks.captures.map(\.list), expected)
        // The legacy top-level fields are the first result and carry its list too.
        XCTAssertEqual(tasks.list?.position, 1)
        XCTAssertFalse(tasks.list?.isNotes ?? true)
    }

    func testTaskListStacksUnderOneCapsule() throws {
        let tasks = try success("list-capture-tasks.json")

        let preview = CaptureListPreview(captures: tasks.normalizedCaptures)

        XCTAssertEqual(preview.groups.count, 1)
        let group = try XCTUnwrap(preview.group(startingAt: 0))
        XCTAssertEqual(group.title, "3 tasks \u{2192} dev.md")
        XCTAssertEqual(group.memberCount, 3)
        XCTAssertEqual(group.accessibilityLabel, "List of 3 tasks, filed to dev.md")
        XCTAssertNil(preview.group(startingAt: 1))
        XCTAssertFalse(preview.continuesGroup(at: 0))
        XCTAssertTrue(preview.continuesGroup(at: 1))
        XCTAssertTrue(preview.continuesGroup(at: 2))
        XCTAssertFalse(preview.continuesGroup(at: 3))
    }

    func testSectionListNamesNotesAndTheSection() throws {
        let notes = try success("list-capture-notes.json")

        let preview = CaptureListPreview(captures: notes.normalizedCaptures)

        let group = try XCTUnwrap(preview.group(startingAt: 0))
        XCTAssertEqual(group.title, "2 notes \u{2192} dev.md \u{00B7} Ideas")
        XCTAssertEqual(group.accessibilityLabel, "List of 2 notes, filed to dev.md, section Ideas")
    }

    func testSingleBulletListUsesTheSingularNoun() throws {
        let tasks = try success("list-capture-tasks.json")

        let preview = CaptureListPreview(captures: [tasks.captures[0]])

        XCTAssertEqual(preview.group(startingAt: 0)?.title, "1 task \u{2192} dev.md")
        XCTAssertEqual(
            preview.group(startingAt: 0)?.accessibilityLabel,
            "List of 1 task, filed to dev.md"
        )
    }

    func testBatchWithoutListsGetsNoCapsuleAndKeepsEveryDivider() throws {
        let tasks = try success("list-capture-tasks.json")
        let plain = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: Data(
                """
                {"ok":true,"dry_run":true,"routed":true,"route":"dev","route_label":"dev.md",
                "relative_target":"dev.md","target":"/tmp/dev.md","text":"One",
                "task_line":"- [ ] #task One","kind":"task","created":"2026-10-30",
                "placement":"appended"}
                """.utf8
            )
        )

        XCTAssertNil(plain.list)
        let preview = CaptureListPreview(captures: [plain, plain])
        XCTAssertTrue(preview.groups.isEmpty)
        XCTAssertFalse(preview.continuesGroup(at: 1))

        // A plain result between two lists splits them into separate groups.
        let mixed = CaptureListPreview(
            captures: [tasks.captures[0], tasks.captures[1], plain, tasks.captures[2]]
        )
        XCTAssertEqual(mixed.groups.map(\.startIndex), [0, 3])
        XCTAssertEqual(mixed.groups.map(\.memberCount), [2, 1])
        XCTAssertTrue(mixed.continuesGroup(at: 1))
        XCTAssertFalse(mixed.continuesGroup(at: 2))
        XCTAssertFalse(mixed.continuesGroup(at: 3))
    }

    func testTwoListsInOneBatchGetTheirOwnCapsules() throws {
        let tasks = try success("list-capture-tasks.json")
        let notes = try success("list-capture-notes.json")

        let preview = CaptureListPreview(captures: tasks.captures + notes.captures)

        XCTAssertEqual(
            preview.groups.map(\.title),
            ["3 tasks \u{2192} dev.md", "2 notes \u{2192} dev.md \u{00B7} Ideas"]
        )
        XCTAssertEqual(preview.groups.map(\.startIndex), [0, 3])
        XCTAssertFalse(preview.continuesGroup(at: 3))
        XCTAssertTrue(preview.continuesGroup(at: 4))
    }

    func testListContextDecodesTolerantly() throws {
        let context = try JSONDecoder().decode(
            CaptureListContext.self,
            from: Data(#"{"kind":"notes"}"#.utf8)
        )

        XCTAssertTrue(context.isNotes)
        XCTAssertEqual(context.route, "")
        XCTAssertNil(context.section)
        XCTAssertEqual(context.count, 0)
    }

    // MARK: - Spaced section picks

    func testSectionMenuInsertsTheSlugThatResolvesBack() throws {
        let menu = try completion("list-complete-section.json")

        XCTAssertEqual(menu.context, "section")
        XCTAssertEqual(menu.replacement, CaptureRange(start: 6, end: 8))
        let row = try XCTUnwrap(menu.candidates.first)
        XCTAssertEqual(row.replacement, "future-work")
        XCTAssertEqual(row.title, "Future Work")
    }

    func testSectionMenuOpensOnAHeaderThatAlreadyHasBullets() throws {
        let menu = try completion("list-complete-section-with-bullets.json")

        XCTAssertEqual(menu.context, "section")
        XCTAssertEqual(menu.replacement, CaptureRange(start: 6, end: 8))
        XCTAssertEqual(menu.candidates.first?.replacement, "future-work")
    }

    func testPartialQuotedSectionCoversTheOpeningQuote() throws {
        let menu = try completion("list-complete-section-partial-quote.json")

        XCTAssertEqual(menu.context, "section")
        XCTAssertEqual(menu.replacement, CaptureRange(start: 6, end: 9))
        XCTAssertEqual(menu.candidates.first?.replacement, "future-work")
    }

    func testPartialQuotedSectionOpensWithBulletsBelow() throws {
        let menu = try completion("list-complete-section-partial-quote-with-bullets.json")

        XCTAssertEqual(menu.context, "section")
        XCTAssertEqual(menu.replacement, CaptureRange(start: 6, end: 9))
        XCTAssertEqual(menu.candidates.first?.replacement, "future-work")
    }

    // MARK: - First bullet after a lone header

    func testListHeaderParseReportsTheListItemNeed() throws {
        let header = try parse("list-parse-header-only.json")

        XCTAssertEqual(header.items.first?.needs, ["list_item"])
        XCTAssertEqual(header.grammar, 6)
    }

    func testNewlineAtTheEndOfALoneHeaderStartsTheFirstBullet() throws {
        let header = try parse("list-parse-header-only.json")

        XCTAssertTrue(
            CaptureListHeaderNewline.startsFirstBullet(parse: header, draft: "@dev", caretUTF8: 4)
        )
        XCTAssertEqual(CaptureListHeaderNewline.insertion, "\n- ")
    }

    func testNewlineKeepsBeingBareAwayFromTheHeaderEnd() throws {
        let header = try parse("list-parse-header-only.json")

        // Mid-header caret.
        XCTAssertFalse(
            CaptureListHeaderNewline.startsFirstBullet(parse: header, draft: "@dev", caretUTF8: 2)
        )
        // A caret on another line is not at the header.
        XCTAssertFalse(
            CaptureListHeaderNewline.startsFirstBullet(
                parse: header,
                draft: "@dev\nnotes",
                caretUTF8: 10
            )
        )
        // An offset outside the draft never starts a bullet.
        XCTAssertFalse(
            CaptureListHeaderNewline.startsFirstBullet(parse: header, draft: "@dev", caretUTF8: 9)
        )
    }

    func testTrailingSpacesAfterTheHeaderStillStartTheFirstBullet() throws {
        let header = try parse("list-parse-header-only.json")

        XCTAssertTrue(
            CaptureListHeaderNewline.startsFirstBullet(parse: header, draft: "@dev  ", caretUTF8: 4)
        )
        XCTAssertTrue(
            CaptureListHeaderNewline.startsFirstBullet(parse: header, draft: "@dev  ", caretUTF8: 6)
        )
    }

    func testAPlaceholderRowBelowTheHeaderIsNotDoubled() throws {
        let header = try parse("list-parse-header-only.json")

        XCTAssertFalse(
            CaptureListHeaderNewline.startsFirstBullet(
                parse: header,
                draft: "@dev\n- ",
                caretUTF8: 4
            )
        )
        // A blank line below separates the header from whatever follows.
        XCTAssertTrue(
            CaptureListHeaderNewline.startsFirstBullet(
                parse: header,
                draft: "@dev\n\nBuy milk",
                caretUTF8: 4
            )
        )
    }

    func testAListThatAlreadyHasBulletsNeverStartsAnother() throws {
        let worked = try parse("list-parse-worked.json")

        XCTAssertFalse(
            CaptureListHeaderNewline.startsFirstBullet(
                parse: worked,
                draft: worked.input,
                caretUTF8: 4
            )
        )
    }

    func testListItemNeedIsACalmStatusNotAnError() {
        XCTAssertEqual(
            CapturePickerNeed.listItem.statusText,
            "Add a bullet under the header \u{2014} Shift-Return starts one"
        )
    }

    func testSectionNeedIsACalmStatusNotAnError() {
        XCTAssertEqual(
            CapturePickerNeed.section.statusText,
            "Finish the quoted section name \u{2014} pick a section"
        )
    }

    func testUnterminatedSectionReportsTheSectionNeed() throws {
        let incomplete = try parse("list-parse-section-incomplete.json")

        XCTAssertEqual(incomplete.needs, ["section"])
        XCTAssertNil(incomplete.section)
    }
}
