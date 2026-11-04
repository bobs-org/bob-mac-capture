import XCTest

@testable import CaptureCore

/// Decodes the `Tests/Fixtures/move-preview-mv*.json` dry runs that
/// `Scripts/generate-move-preview-fixtures.sh` captures from a real Bob, and
/// checks the moves band, hint, and ghost presentation built from them.
final class CaptureProjectNoteMovePresentationTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func moveSuccess(_ name: String) throws -> CaptureCommandSuccess {
        let data = try Data(
            contentsOf: fixtures.appendingPathComponent(name)
        )
        let success = try JSONDecoder().decode(CaptureCommandSuccess.self, from: data)
        XCTAssertEqual(success.kind, "project_note")
        return success
    }

    private func movedTask(
        sigil: String = "^",
        blockID: String = "equity-docs",
        draftRange: [Int] = [42, 54],
        text: String = "Collect the equity paperwork",
        previousStatusSymbol: String = " ",
        statusSymbol: String = " ",
        detail: String? = "Task Link follows"
    ) -> CaptureProjectNoteMovedTask {
        CaptureProjectNoteMovedTask(
            sigil: sigil,
            draftRange: draftRange,
            itemLine: 2,
            source: "cash.md",
            sourceLine: 6,
            line: 13,
            blockID: blockID,
            text: text,
            previousStatusSymbol: previousStatusSymbol,
            previousStatusName: "Ready",
            statusSymbol: statusSymbol,
            statusName: statusSymbol == "*" ? "Next" : "Ready",
            fresh: "2026-09-20",
            detail: detail
        )
    }

    private func moveSuccess(
        movedTasks: [CaptureProjectNoteMovedTask],
        moveSummary: CaptureProjectNoteMoveSummary? = CaptureProjectNoteMoveSummary(
            parent: "cash.md",
            moved: 1,
            repairedLinks: 1,
            repairedNotes: 1
        ),
        moveHint: CaptureProjectNoteMoveHint? = nil
    ) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: true,
            route: "cash",
            routeLabel: "cash_goog_exit.md",
            relativeTarget: "cash_goog_exit.md",
            target: "/tmp/vault/cash_goog_exit.md",
            text: "Finish the exit packet",
            taskLine: "- [ ] #task #prj Finish the exit packet #hide ^prj",
            kind: "project_note",
            created: "2026-09-20",
            placement: "created",
            blockID: "prj",
            dayFile: "/tmp/vault/day.md",
            projectNote: CaptureProjectNoteSummary(
                basename: "cash_goog_exit.md",
                parentRoute: "cash",
                parentLink: "[[cash]]",
                tasks: 1,
                movedTasks: movedTasks,
                moveSummary: moveSummary,
                moveHint: moveHint
            )
        )
    }

    // MARK: - Fixture decoding

    func testMV1FixtureDecodesOneMoveWithSummaryAndRepair() throws {
        let success = try moveSuccess("move-preview-mv1.json")
        let note = try XCTUnwrap(success.projectNote)

        XCTAssertEqual(note.movedTasks.count, 1)
        let moved = try XCTUnwrap(note.movedTasks.first)
        XCTAssertEqual(moved.sigil, "^")
        XCTAssertEqual(moved.draftRange, [42, 54])
        XCTAssertEqual(moved.blockID, "equity-docs")
        XCTAssertEqual(moved.text, "Collect the equity paperwork")
        XCTAssertEqual(moved.detail, "Task Link follows")

        let summary = try XCTUnwrap(note.moveSummary)
        XCTAssertEqual(summary.parent, "cash.md")
        XCTAssertEqual(summary.moved, 1)
        XCTAssertEqual(summary.repairedLinks, 1)
        XCTAssertEqual(summary.repairedNotes, 1)
        XCTAssertFalse(summary.needsReconcile)
        XCTAssertNil(note.moveHint)

        let presentation = try XCTUnwrap(
            CaptureProjectNoteMovePresentation(capture: success)
        )
        XCTAssertEqual(presentation.headerText, "↪ Moves 1 task from cash.md")
        XCTAssertEqual(presentation.movedTasks.map(\.blockID), ["equity-docs"])
        XCTAssertEqual(presentation.repairFooterText, "1 link repaired in 1 note")
        XCTAssertEqual(presentation.notificationTitle, "Created cash_goog_exit")
        XCTAssertEqual(presentation.notificationDetail, "moved 1 task from cash")
        XCTAssertTrue(
            presentation.previewAccessibilitySummary.contains("Moves 1 task from cash.md")
        )
        XCTAssertTrue(
            presentation.previewAccessibilitySummary.contains("Collect the equity paperwork")
        )
    }

    func testMV4FixtureDecodesColonMoveWithNextDetail() throws {
        let success = try moveSuccess("move-preview-mv4.json")
        let note = try XCTUnwrap(success.projectNote)
        let moved = try XCTUnwrap(note.movedTasks.first)

        XCTAssertEqual(moved.sigil, ":")
        XCTAssertEqual(moved.statusSymbol, "*")
        XCTAssertEqual(moved.detail, "becomes Next · links under ADMIN")
        XCTAssertEqual(moved.link?.blockLink, "[[cash_x#^a]]")

        let presentation = try XCTUnwrap(
            CaptureProjectNoteMovePresentation(capture: success)
        )
        XCTAssertEqual(presentation.movedTasks.first?.glyph, "◉")
        // Nothing was repaired, so the band carries no repair footer.
        XCTAssertNil(presentation.repairFooterText)
    }

    func testMV5FixtureDecodesOfferMovedFrom() throws {
        let success = try moveSuccess("move-preview-mv5.json")
        let note = try XCTUnwrap(success.projectNote)

        XCTAssertEqual(note.form, "offer")
        XCTAssertEqual(note.successors.count, 2)
        XCTAssertEqual(note.successors[0].blockID, "call-ms")
        XCTAssertEqual(note.successors[0].offer?.movedFrom, "cash.md")
        XCTAssertNil(note.successors[1].offer?.movedFrom)
        XCTAssertEqual(note.movedTasks.count, 1)
        XCTAssertNil(note.movedTasks.first?.detail)

        // The moves band still renders on the offer form.
        let presentation = try XCTUnwrap(
            CaptureProjectNoteMovePresentation(capture: success)
        )
        XCTAssertEqual(presentation.headerText, "↪ Moves 1 task from cash.md")
    }

    func testMV17FixtureDecodesMoveHintWithoutMoves() throws {
        let success = try moveSuccess("move-preview-mv17.json")
        let note = try XCTUnwrap(success.projectNote)

        XCTAssertTrue(note.movedTasks.isEmpty)
        XCTAssertNil(note.moveSummary)
        let hint = try XCTUnwrap(note.moveHint)
        XCTAssertEqual(hint.parent, "cash.md")
        XCTAssertGreaterThanOrEqual(hint.openCount, 1)

        XCTAssertNil(CaptureProjectNoteMovePresentation(capture: success))
        let presentation = try XCTUnwrap(
            CaptureProjectNoteMoveHintPresentation(capture: success)
        )
        XCTAssertEqual(
            presentation.hintText,
            "Type - ^ to move tasks from cash.md (\(hint.openCount) open)"
        )
    }

    func testOlderBobWithoutMoveKeysDecodesTolerantly() throws {
        let data = try Data(
            contentsOf: fixtures.appendingPathComponent("project-note-successors.json")
        )
        let success = try JSONDecoder().decode(CaptureCommandSuccess.self, from: data)
        let note = try XCTUnwrap(success.projectNote)

        XCTAssertTrue(note.movedTasks.isEmpty)
        XCTAssertNil(note.moveSummary)
        XCTAssertNil(note.moveHint)
        XCTAssertNil(note.repairedFiles)
        XCTAssertNil(CaptureProjectNoteMovePresentation(capture: success))
        XCTAssertNil(CaptureProjectNoteMoveHintPresentation(capture: success))
        XCTAssertTrue(note.successors.allSatisfy { $0.offer?.movedFrom == nil })
    }

    // MARK: - Band wording

    func testBandPluralizesAndSkipsBlankDetails() throws {
        let success = moveSuccess(
            movedTasks: [
                movedTask(),
                movedTask(
                    sigil: ":",
                    blockID: "call-ms",
                    draftRange: [55, 62],
                    text: "Call Morgan Stanley",
                    previousStatusSymbol: " ",
                    statusSymbol: "*",
                    detail: "becomes Next · links under ADMIN"
                ),
            ],
            moveSummary: CaptureProjectNoteMoveSummary(
                parent: "cash.md",
                moved: 2,
                repairedLinks: 3,
                repairedNotes: 2
            )
        )
        let presentation = try XCTUnwrap(
            CaptureProjectNoteMovePresentation(capture: success)
        )

        XCTAssertEqual(presentation.headerText, "↪ Moves 2 tasks from cash.md")
        XCTAssertEqual(
            presentation.movedTasks.map(\.glyph),
            ["○", "◉"]
        )
        XCTAssertEqual(presentation.repairFooterText, "3 links repaired in 2 notes")
        XCTAssertEqual(presentation.notificationDetail, "moved 2 tasks from cash")
        XCTAssertTrue(
            presentation.previewAccessibilitySummary.contains(
                "Call Morgan Stanley, Next, ^call-ms, becomes Next · links under ADMIN"
            )
        )
    }

    func testBandWithoutSummaryStillRendersWithBareParent() throws {
        let success = moveSuccess(movedTasks: [movedTask()], moveSummary: nil)
        let presentation = try XCTUnwrap(
            CaptureProjectNoteMovePresentation(capture: success)
        )
        XCTAssertEqual(presentation.headerText, "↪ Moves 1 task from ")
        XCTAssertNil(presentation.repairFooterText)
    }

    func testHintHidesWhenMovesExist() throws {
        let success = moveSuccess(
            movedTasks: [movedTask()],
            moveHint: CaptureProjectNoteMoveHint(parent: "cash.md", openCount: 12)
        )
        XCTAssertNotNil(CaptureProjectNoteMovePresentation(capture: success))
        XCTAssertNil(CaptureProjectNoteMoveHintPresentation(capture: success))
    }

    func testStatusGlyphs() {
        XCTAssertEqual(CaptureProjectNoteMoveGlyph.text(for: " "), "○")
        XCTAssertEqual(CaptureProjectNoteMoveGlyph.text(for: "*"), "◉")
        XCTAssertEqual(CaptureProjectNoteMoveGlyph.text(for: "/"), "◐")
        XCTAssertEqual(CaptureProjectNoteMoveGlyph.text(for: "x"), "●")
        XCTAssertEqual(CaptureProjectNoteMoveGlyph.text(for: "?"), "?")
        XCTAssertEqual(CaptureProjectNoteMoveGlyph.text(for: ""), "○")
    }

    // MARK: - Ghost anchors and staleness

    func testGhostAnchorsAfterEachMoveBullet() {
        let draft = "Finish the exit packet @cash^goog-exit@\n- ^equity-docs\n- :call-ms"
        let ghosts = CaptureProjectNoteMoveGhosts.ghosts(
            draft: draft,
            previewDraft: draft,
            movedTasks: [
                movedTask(),
                movedTask(
                    sigil: ":",
                    blockID: "call-ms",
                    draftRange: [57, 65],
                    text: "Call Morgan Stanley",
                    previousStatusSymbol: " ",
                    statusSymbol: "*"
                ),
            ]
        )

        XCTAssertEqual(ghosts.count, 2)
        XCTAssertEqual(ghosts[0].lineNumber, 2)
        XCTAssertEqual(ghosts[0].text, "○ Collect the equity paperwork")
        XCTAssertEqual(ghosts[0].accessibilityText, "Collect the equity paperwork, Ready")
        XCTAssertEqual(ghosts[1].lineNumber, 3)
        XCTAssertEqual(ghosts[1].text, "◉ Call Morgan Stanley · becomes Next")
        XCTAssertEqual(
            ghosts[1].accessibilityText,
            "Call Morgan Stanley, Next, becomes Next"
        )
        // Each ghost inserts at the end of its own bullet line.
        let lines = draft.split(separator: "\n", omittingEmptySubsequences: false)
        for ghost in ghosts {
            let line = String(lines[ghost.lineNumber - 1])
            let prefix = String(
                decoding: Array(draft.utf8)[..<ghost.insertionUTF8Offset],
                as: UTF8.self
            )
            XCTAssertTrue(prefix.hasSuffix(line), "\(prefix) should end with \(line)")
        }
    }

    func testGhostStalenessHidesOnAnyDraftMismatch() {
        let previewDraft = "Finish the exit packet @cash^goog-exit@\n- ^equity-docs"
        let moved = [movedTask()]
        XCTAssertEqual(
            CaptureProjectNoteMoveGhosts.ghosts(
                draft: previewDraft,
                previewDraft: previewDraft,
                movedTasks: moved
            ).count,
            1
        )
        // Any keystroke — even after the last ghost — hides every ghost
        // until the next preview lands.
        XCTAssertTrue(
            CaptureProjectNoteMoveGhosts.ghosts(
                draft: previewDraft + "\n- Book the lawyer",
                previewDraft: previewDraft,
                movedTasks: moved
            ).isEmpty
        )
        XCTAssertTrue(
            CaptureProjectNoteMoveGhosts.ghosts(
                draft: previewDraft,
                previewDraft: previewDraft + "\n- Book the lawyer",
                movedTasks: moved
            ).isEmpty
        )
    }

    func testGhostStalePreviewHidesEveryBullet() {
        let previewDraft = "Finish it @cash^x@\n- ^aaa\n- ^bbb"
        // `- ^aaa` was retyped to `- ^aax`; `- ^bbb` is untouched.
        let current = "Finish it @cash^x@\n- ^aax\n- ^bbb"
        let moved = [
            movedTask(blockID: "aaa", draftRange: [21, 25], text: "First"),
            movedTask(blockID: "bbb", draftRange: [28, 32], text: "Second"),
        ]
        // The preview describes the old draft, so every ghost hides even
        // though the second bullet is byte-identical.
        XCTAssertTrue(
            CaptureProjectNoteMoveGhosts.ghosts(
                draft: current,
                previewDraft: previewDraft,
                movedTasks: moved
            ).isEmpty
        )
    }

    func testGhostRangeCheckSkipsOnlyTheEditedBullet() {
        // Same text on both sides isolates the per-bullet range check from
        // the draft-equality gate: the retyped bullet hides while the
        // untouched one keeps its ghost.
        let current = "Finish it @cash^x@\n- ^aax\n- ^bbb"
        let moved = [
            movedTask(blockID: "aaa", draftRange: [21, 25], text: "First"),
            movedTask(blockID: "bbb", draftRange: [28, 32], text: "Second"),
        ]
        let ghosts = CaptureProjectNoteMoveGhosts.ghosts(
            draft: current,
            previewDraft: current,
            movedTasks: moved
        )
        XCTAssertEqual(ghosts.map(\.text), ["○ Second"])
    }

    func testGhostSkipsMalformedRanges() {
        let draft = "Finish it @cash^x@\n- ^aaa"
        let moved = [
            movedTask(blockID: "", draftRange: [20, 20], text: "Empty"),
            movedTask(blockID: "aaa", draftRange: [-1, 4], text: "Negative"),
            movedTask(blockID: "aaa", draftRange: [20, 200], text: "Long"),
            movedTask(blockID: "aaa", draftRange: [21, 24], text: "Shifted"),
        ]
        XCTAssertTrue(
            CaptureProjectNoteMoveGhosts.ghosts(
                draft: draft,
                previewDraft: draft,
                movedTasks: moved
            ).isEmpty
        )
    }

    func testGhostHandlesMultibyteDraftsByByteOffsets() {
        // The emoji occupies 4 UTF-8 bytes before the move bullet.
        let draft = "☕️ Finish @cash^x@\n- ^aaa"
        let tokenStart = draft.utf8.count - 4
        let moved = [
            movedTask(blockID: "aaa", draftRange: [tokenStart, tokenStart + 4], text: "A"),
        ]
        let ghosts = CaptureProjectNoteMoveGhosts.ghosts(
            draft: draft,
            previewDraft: draft,
            movedTasks: moved
        )
        XCTAssertEqual(ghosts.count, 1)
        XCTAssertEqual(ghosts[0].lineNumber, 2)
    }
}
