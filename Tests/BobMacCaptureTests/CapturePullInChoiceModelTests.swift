import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CapturePullInChoiceModelTests: XCTestCase {
    func testPreviewOpensChoiceAndEscapePerformsNoCaptureWrite() async throws {
        let record = temporaryRecordURL()
        let model = makeModel(record: record, stdout: successResponse())
        model.plainDraft = "complete task"
        model.preview()
        try await waitUntil { !model.isPreviewing }

        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertFalse(model.isSubmitting)
        XCTAssertTrue(model.pullInChoice?.markedKeys.isEmpty == true)
        XCTAssertEqual(model.pullInChoice?.effectiveSelectionKeys, ["offer#one^key"])
        XCTAssertTrue(model.editorInputLocked)
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)

        model.cancelPullInChoiceFromKeyboard()
        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertFalse(model.editorInputLocked)
        XCTAssertEqual(model.plainDraft, "complete task")
        XCTAssertEqual(model.focusRequest.target, .editor)
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)
    }

    func testProjectNoteOfferFixtureOpensNewProjectChoiceUnmarked() async throws {
        let record = temporaryRecordURL()
        let model = makeModel(
            record: record,
            stdout: try fixtureText("project-note-successors.json")
        )
        model.plainDraft = "Finish the exit packet @cash:goog-exit@"
        model.preview()
        try await waitUntil { !model.isPreviewing }

        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)

        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertTrue(choice.markedKeys.isEmpty)
        XCTAssertTrue(choice.isNewProjectPrompt)
        XCTAssertEqual(choice.promptStatusText, "Choose tasks to pull in")
        XCTAssertEqual(choice.selectableKeys.count, 2)
        XCTAssertEqual(
            choice.contextText,
            "New project · Finish the exit packet"
        )
        XCTAssertEqual(choice.sections.first?.title, "Project cash_goog_exit")
        XCTAssertEqual(model.statusText, "Choose tasks to pull in")
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)
    }

    func testRealNotePullFixturePreviewsAndEscReturnsWithoutWriting() async throws {
        let record = temporaryRecordURL()
        let model = makeModel(
            record: record,
            stdout: try fixtureText("note-pull-np1.json")
        )
        model.plainDraft = "@sase"
        model.preview()
        try await waitUntil { !model.isPreviewing }

        XCTAssertEqual(model.primaryActionTitle, "Pull In")
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)

        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertTrue(choice.isOnlyNotePull)
        XCTAssertEqual(choice.promptStatusText, "Choose tasks to pull in from ‹sase›")
        XCTAssertTrue(choice.markedKeys.isEmpty)
        XCTAssertEqual(choice.selectableKeys.count, 3)
        XCTAssertEqual(choice.sections.first?.glyph, "tray.and.arrow.down.fill")
        XCTAssertEqual(choice.rows.map(\.laneText), ["Pending", "Next", "Ready"])
        XCTAssertTrue(choice.rows.allSatisfy { !$0.metaDetails.contains("trigger: note_pull") })

        model.chooseNoPullInOffers()
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertEqual(model.statusText, "Escape returns to the draft without pulling in")
        model.cancelPullInChoiceFromKeyboard()

        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertEqual(model.plainDraft, "@sase")
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)
    }

    func testTwoNotePullOnlyDraftSaysPullInAndNamesBothSources() async throws {
        let record = temporaryRecordURL()
        let model = makeModel(
            record: record,
            stdout: try fixtureText("note-pull-two-notes.json")
        )
        model.plainDraft = "@work\n\n@dev"
        model.preview()
        try await waitUntil { !model.isPreviewing }

        XCTAssertEqual(model.previewResults.map(\.kind), ["note_pull", "note_pull"])
        XCTAssertEqual(model.primaryActionTitle, "Pull In")
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)

        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertTrue(choice.isOnlyNotePull)
        XCTAssertEqual(choice.notePullSources, ["work.md", "dev.md"])
        XCTAssertEqual(choice.promptStatusText, "Choose tasks to pull in from 2 notes")
        XCTAssertEqual(model.statusText, "Choose tasks to pull in from 2 notes")
        XCTAssertEqual(choice.sections.map(\.title), ["Pull from ‹work›", "Pull from ‹dev›"])
        XCTAssertEqual(choice.sections.map { $0.rows.compactMap(\.offerNumber) }, [[1, 2, 3], [4]])
        XCTAssertTrue(choice.markedKeys.isEmpty)

        // Shift-Return stays explanatory and Esc leaves the draft unchanged.
        model.chooseNoPullInOffers()
        XCTAssertTrue(model.pullInChoiceVisible)
        model.cancelPullInChoiceFromKeyboard()
        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertEqual(model.plainDraft, "@work\n\n@dev")
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)
    }

    func testMovedNotePullRowsStayInTheirRequestedSourceSections() async throws {
        let record = temporaryRecordURL()
        let model = makeModel(
            record: record,
            stdout: try fixtureText("note-pull-move.json")
        )
        model.plainDraft = Self.notePullMoveDraft
        model.preview()
        try await waitUntil { !model.isPreviewing }

        // Transfers and a project note make this a mixed draft.
        XCTAssertNotEqual(model.primaryActionTitle, "Pull In")
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)

        let choice = try XCTUnwrap(model.pullInChoice)
        assertMovedNotePullSections(choice)
        XCTAssertEqual(choice.promptStatusText, "Choose tasks to pull in from 2 notes")
        model.cancelPullInChoiceFromKeyboard()
        XCTAssertEqual(model.plainDraft, Self.notePullMoveDraft)
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)
    }

    func testRequiredChoiceFlatOffersKeepRequestedSourceSections() throws {
        let data = Data(try fixtureText("note-pull-move-choice.json").utf8)
        guard case .failure(let failure) = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: data
        ) else {
            return XCTFail("Expected Bob's pull_in_choice_required refusal")
        }
        XCTAssertEqual(failure.code, "pull_in_choice_required")
        let pullIn = try XCTUnwrap(failure.pullIn)
        let model = CapturePanelModel()
        model.installPullInChoiceForPreviews(
            offers: failure.offers,
            pullIn: pullIn,
            draft: Self.notePullMoveDraft
        )

        let choice = try XCTUnwrap(model.pullInChoice)
        assertMovedNotePullSections(choice)
        XCTAssertEqual(choice.promptStatusText, "Choose tasks to pull in from 2 notes")
    }

    func testPrimaryActionTitleForSingleAndEmptyNotePullPreviewStates() async throws {
        let single = makeModel(
            record: temporaryRecordURL(),
            stdout: try fixtureText("note-pull-np1.json")
        )
        single.plainDraft = "@sase"
        single.preview()
        try await waitUntil { !single.isPreviewing }
        XCTAssertEqual(single.primaryActionTitle, "Pull In")

        let empty = makeModel(record: temporaryRecordURL(), stdout: successResponse())
        XCTAssertTrue(empty.previewResults.isEmpty)
        XCTAssertEqual(empty.primaryActionTitle, "Capture")
    }

    private static let notePullMoveDraft = """
        @work

        @dev

        @work+gamma > @bob

        @dev+delta > @bob

        Docs push @work^docs-push@
        - ^beta
        """

    /// One section per requested source in Bob's order. Rows keep their
    /// final homes (`note_path`) while membership follows `offer.note`.
    private func assertMovedNotePullSections(
        _ choice: CapturePullInChoiceState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(choice.isOnlyNotePull, file: file, line: line)
        XCTAssertEqual(choice.notePullSources, ["work.md", "dev.md"], file: file, line: line)
        XCTAssertEqual(
            choice.sections.map(\.title),
            ["Pull from ‹work›", "Pull from ‹dev›"],
            file: file,
            line: line
        )
        XCTAssertEqual(choice.sections.map(\.note), ["work.md", "dev.md"], file: file, line: line)
        XCTAssertEqual(
            choice.sections.map { $0.rows.compactMap(\.offerNumber) },
            [[1, 2, 3], [4]],
            file: file,
            line: line
        )
        XCTAssertEqual(
            choice.sections.map { $0.rows.map(\.notePath) },
            [["work.md", "work_docs_push.md", "bob.md"], ["bob.md"]],
            file: file,
            line: line
        )
        XCTAssertEqual(
            choice.sections.map { $0.rows.map(\.sourceNotePath) },
            [["work.md", "work.md", "work.md"], ["dev.md"]],
            file: file,
            line: line
        )
        XCTAssertEqual(choice.sections.last?.folded?.hidden, 1, file: file, line: line)
        XCTAssertEqual(
            choice.selectableKeys,
            ["work.md#^alpha", "work.md#^beta", "work.md#^gamma", "dev.md#^delta"],
            file: file,
            line: line
        )
    }

    func testNothingToPullInRefusalUsesCalmCardState() async throws {
        let model = makeModel(
            record: temporaryRecordURL(),
            stdout: try fixtureText("note-pull-empty.json"),
            exit: "1"
        )
        model.plainDraft = "@sase"
        model.preview()
        try await waitUntil { !model.isPreviewing }

        XCTAssertEqual(model.emptyNotePullPresentation?.title, "Nothing ready in ‹sase›")
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.errorCode)
        XCTAssertEqual(model.statusText, "Nothing ready in ‹sase›")
    }

    func testRealKeepMovingFixtureOpensChoiceAndSubmitsItsOpaqueKey() async throws {
        let record = temporaryRecordURL()
        let fixture = try fixtureText("task-complete-keep-moving.json")
        let success = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: Data(fixture.utf8)
        )
        let offers = try XCTUnwrap(success.taskComplete?.keepMoving)
        XCTAssertEqual(offers.count, 3)
        let keys = offers.sorted { ($0.offer?.n ?? 0) < ($1.offer?.n ?? 0) }
            .compactMap { $0.offer?.key }
        XCTAssertEqual(keys, ["sase_badges.md#^p", "sase_badges.md#^b", "sase_badges.md#^a"])
        let model = makeModel(record: record, stdout: fixture)
        model.plainDraft = "!sase_badges:t"
        model.preview()
        try await waitUntil { !model.isPreviewing }

        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)

        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertTrue(choice.isOnlyKeepMoving)
        XCTAssertEqual(choice.promptStatusText, "Choose tasks to keep moving")
        XCTAssertEqual(choice.selectableKeys, keys)
        XCTAssertEqual(choice.effectiveSelectionKeys, [keys.first].compactMap { $0 })
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)

        model.confirmPullInChoice()
        try await waitUntil { !model.isSubmitting }

        let calls = try recordText(record)
        XCTAssertEqual(captureCallCount(calls), 2)
        XCTAssertTrue(calls.contains("--pull-in \(keys[0])"), calls)
    }

    func testKeepMovingChoiceHasDistinctContextAndRanksLast() throws {
        let model = CapturePanelModel()
        model.installPullInChoiceForPreviews(
            offers: [
                cardOffer(n: 1, text: "Hand-off", group: "hand_off"),
                cardOffer(
                    n: 2,
                    text: "Project task",
                    group: "project",
                    project: "projects/sase_badges.md"
                ),
                cardOffer(
                    n: 3,
                    text: "Keep the renderer moving",
                    group: "keep_moving",
                    project: "projects/sase_badges.md",
                    cause: "Wire badges into the README",
                    trigger: "last_planned"
                ),
            ],
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 3,
                groups: [
                    CapturePullInGroup(
                        group: "keep_moving",
                        project: "projects/sase_badges.md",
                        folded: CapturePullInFolded(blocked: 2, scheduled: 1, hidden: 3)
                    )
                ]
            ),
            draft: "complete task"
        )

        let choice = try XCTUnwrap(model.pullInChoice)
        let section = try XCTUnwrap(choice.sections.last)
        let row = try XCTUnwrap(section.rows.first)
        XCTAssertEqual(section.group, "keep_moving")
        XCTAssertEqual(section.title, "Keep sase_badges moving")
        XCTAssertEqual(
            section.caption,
            "✓ Wire badges into the README was the last sase_badges task planned today")
        XCTAssertEqual(section.contrastTag, "ready in sase_badges · not dependents")
        XCTAssertEqual(section.folded?.blocked, 2)
        XCTAssertEqual(section.folded?.scheduled, 1)
        XCTAssertEqual(section.folded?.hidden, 3)
        XCTAssertEqual(row.detailText, "Ready")
        XCTAssertFalse(row.metaDetails.contains(where: { $0.hasPrefix("trigger:") }))
        XCTAssertTrue(choice.isOnlyKeepMoving == false)
        XCTAssertFalse(choice.contextText?.contains("Unblocked by") == true)

        let onlyMoving = CapturePanelModel()
        onlyMoving.installPullInChoiceForPreviews(
            offers: [
                cardOffer(
                    n: 1,
                    text: "Keep the renderer moving",
                    group: "keep_moving",
                    project: "projects/sase_badges.md",
                    cause: "Wire badges into the README",
                    trigger: "last_planned"
                )
            ],
            pullIn: CapturePullIn(supported: true, offerCount: 1),
            draft: "complete task"
        )
        let movingChoice = try XCTUnwrap(onlyMoving.pullInChoice)
        XCTAssertTrue(movingChoice.isOnlyKeepMoving)
        XCTAssertEqual(
            movingChoice.contextText,
            "Wire badges into the README was the last sase_badges task planned today · ready tasks, not dependents"
        )
    }

    func testProjectNoteOfferSkipSubmitsExplicitNoneWithoutPickedLinks() async throws {
        let record = temporaryRecordURL()
        let model = try await openProjectOfferChoice(record: record)
        XCTAssertTrue(model.pullInChoice?.markedKeys.isEmpty == true)

        let controller = CapturePanelController(model: model)
        XCTAssertTrue(controller.perform(.chooseNoPullInOffers))
        try await waitUntil { !model.isSubmitting }

        let calls = try recordText(record)
        // The real-Bob preview advertises `inbox_route.supported`, so the submit
        // also carries `--require-inbox-route-choice` ahead of `--refuse-override`.
        XCTAssertTrue(
            calls.contains(
                "argv=capture --format json --pull-in none --require-inbox-route-choice "
                    + "--refuse-override -- \(Self.projectOfferDraft)"
            ),
            calls
        )
        // Skip names no opaque key: Bob creates the project and links nothing it offered.
        XCTAssertFalse(calls.contains("--pull-in cash_goog_exit.md@"))
        XCTAssertEqual(captureCallCount(calls), 2)
        XCTAssertNil(model.pullInChoice)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testProjectNoteOfferEscapeKeepsTheDraftAndNeverSubmits() async throws {
        let record = temporaryRecordURL()
        let model = try await openProjectOfferChoice(record: record)

        model.cancelPullInChoiceFromKeyboard()

        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertFalse(model.editorInputLocked)
        XCTAssertEqual(model.plainDraft, Self.projectOfferDraft)
        XCTAssertEqual(model.focusRequest.target, .editor)
        let calls = try recordText(record)
        XCTAssertEqual(captureCallCount(calls), 1, "only the preview ran")
        XCTAssertFalse(calls.contains("--pull-in"))
    }

    func testProjectNoteOfferMarkedKeySubmitsOnceWithOpenIntent() async throws {
        let record = temporaryRecordURL()
        let model = try await openProjectOfferChoice(record: record)
        let success = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: Data(try fixtureText("project-note-successors.json").utf8)
        )
        let keys = try XCTUnwrap(success.projectNote).successors.compactMap { $0.offer?.key }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(model.pullInChoice?.selectableKeys, keys)

        model.movePullInChoiceHighlight(by: 1)
        model.toggleHighlightedPullInOffer()
        XCTAssertEqual(model.pullInChoice?.markedKeys, [keys[1]])

        let controller = CapturePanelController(model: model)
        var opened: [URL] = []
        model.captureSuccessNotifier = { _, _, _ in }
        model.noteOpener = { url, completion in
            opened.append(url)
            completion(nil)
        }
        model.panelDismisser = {}
        XCTAssertTrue(controller.perform(.confirmPullInChoiceAndOpen))
        try await waitUntil { !model.isSubmitting }

        XCTAssertNil(model.pullInChoice)
        XCTAssertEqual(model.plainDraft, "")
        let calls = try recordText(record)
        XCTAssertEqual(captureCallCount(calls), 2)
        XCTAssertTrue(
            calls.contains(
                "argv=capture --format json --pull-in \(keys[1]) --require-inbox-route-choice "
                    + "--refuse-override -- \(Self.projectOfferDraft)"
            ),
            calls
        )
        XCTAssertFalse(calls.contains(keys[0]))
        let url = try XCTUnwrap(opened.first)
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(url.host, "bob-open-notes")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let paths = items.filter { $0.name.hasPrefix("path") }.compactMap(\.value)
        XCTAssertTrue(paths.contains { $0.hasSuffix("/cash_goog_exit.md") }, "\(paths)")
    }

    func testMarkedSubsetDispatchesOpaqueKeysOnceAndKeepsOpenAfterIntent() async throws {
        let record = temporaryRecordURL()
        let model = makeModel(record: record, stdout: successResponse())
        model.plainDraft = "complete task"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.pullInChoiceVisible)

        model.movePullInChoiceHighlight(by: 1)
        model.toggleHighlightedPullInOffer()
        XCTAssertEqual(model.pullInChoice?.markedKeys, ["opaque:two#^suffix"])
        let controller = CapturePanelController(model: model)
        var opened: [URL] = []
        var successNotifications = 0
        model.captureSuccessNotifier = { _, _, _ in successNotifications += 1 }
        var dismissed = 0
        model.noteOpener = { url, completion in
            opened.append(url)
            completion(nil)
        }
        model.panelDismisser = { dismissed += 1 }
        XCTAssertTrue(controller.perform(.confirmPullInChoiceAndOpen))
        try await waitUntil { !model.isSubmitting }

        XCTAssertNil(model.pullInChoice)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(successNotifications, 1)
        XCTAssertEqual(opened[0].host, "bob-open-notes")
        XCTAssertEqual(
            URLComponents(url: opened[0], resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "path1" })?.value,
            "/tmp/day.md")
        XCTAssertEqual(dismissed, 1)
        let calls = try recordText(record)
        XCTAssertEqual(captureCallCount(calls), 2)
        XCTAssertTrue(calls.contains("argv=capture --format json --dry-run -- complete task"))
        XCTAssertTrue(
            calls.contains(
                "argv=capture --format json --pull-in opaque:two#^suffix --refuse-override -- complete task"
            ))
        XCTAssertFalse(calls.contains("--require-pull-in-choice"))
        let captureBlocks = calls.components(separatedBy: "argv=")
            .dropFirst()
            .filter { $0.hasPrefix("capture ") }
        let seeds = captureBlocks.compactMap { block in
            block.components(separatedBy: "BOB_PRIORITY_ROLL_SEED=").dropFirst()
                .first?.components(separatedBy: "\n").first
        }
        XCTAssertEqual(seeds.count, 2)
        XCTAssertEqual(try XCTUnwrap(seeds.first), try XCTUnwrap(seeds.dropFirst().first))
    }

    func testControlReturnWithEmptySelectionDoesNotStickOpenIntent() async throws {
        let record = temporaryRecordURL()
        let model = makeModel(record: record, stdout: successResponse())
        model.plainDraft = "complete task"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.pullInChoiceVisible)
        model.updatePullInChoiceFilter("no matching offer")
        XCTAssertEqual(model.pullInChoice?.effectiveSelectionKeys, [])
        XCTAssertEqual(model.pullInChoice?.openAfterCapture, false)

        var opened = 0
        model.noteOpener = { _, completion in
            opened += 1
            completion(nil)
        }

        model.confirmPullInChoice(openAfterCapture: true)
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertEqual(model.pullInChoice?.openAfterCapture, false)
        XCTAssertEqual(opened, 0)

        model.confirmPullInChoice()
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertEqual(opened, 0)

        model.chooseNoPullInOffers()
        try await waitUntil { !model.isSubmitting }
        XCTAssertEqual(opened, 0)
        XCTAssertTrue(
            try recordText(record).contains(
                "argv=capture --format json --pull-in none --refuse-override -- complete task"))
    }

    func testShiftReturnSubmitsExplicitNone() async throws {
        let record = temporaryRecordURL()
        let model = makeModel(record: record, stdout: successResponse())
        model.plainDraft = "complete task"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.pullInChoiceVisible)

        let controller = CapturePanelController(model: model)
        XCTAssertTrue(controller.perform(.chooseNoPullInOffers))
        try await waitUntil { !model.isSubmitting }
        XCTAssertTrue(
            try recordText(record).contains(
                "argv=capture --format json --pull-in none --refuse-override -- complete task"))
        XCTAssertEqual(model.plainDraft, "")
    }

    func testGuardRefusalOpensChoiceWithoutFailureOrDraftLoss() async throws {
        let record = temporaryRecordURL()
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": record.path,
                    "FAKE_BOB_CAPTURE_STDOUT": capabilityPreviewResponse(),
                    "FAKE_BOB_CAPTURE_WRITE_STDOUT": refusalResponse(),
                    "FAKE_BOB_CAPTURE_WRITE_EXIT": "1",
                ]
            ),
            debounceNanoseconds: 0
        )
        model.plainDraft = "complete task"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertNil(model.errorMessage)

        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        try await waitUntil { model.pullInChoiceVisible }

        XCTAssertFalse(model.isSubmitting)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.plainDraft, "complete task")
        XCTAssertEqual(model.pullInChoice?.selectableKeys, ["refusal:key"])
        let calls = try recordText(record)
        XCTAssertEqual(captureCallCount(calls), 2)
        XCTAssertTrue(
            calls.contains(
                "argv=capture --format json --require-pull-in-choice --refuse-override -- complete task"
            )
        )
    }

    func testRealRelationFixtureOpensChoiceAndSubmitsItsOpaqueKey() async throws {
        let record = temporaryRecordURL()
        let fixture = try fixtureText("relation-successor-parked-x-star.json")
        let success = try JSONDecoder().decode(CaptureCommandSuccess.self, from: Data(fixture.utf8))
        let key = try XCTUnwrap(success.allRelationSuccessors.first?.offer?.key)
        let model = makeModel(record: record, stdout: fixture)
        model.plainDraft = "x*"
        model.preview()
        try await waitUntil { !model.isPreviewing }

        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)

        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertTrue(choice.isOnlyRelation)
        XCTAssertEqual(choice.authoredCopy?.capsule, "Starts after")
        XCTAssertEqual(choice.sections.first?.glyph, "link")
        XCTAssertEqual(choice.selectableKeys, [key])
        XCTAssertEqual(choice.effectiveSelectionKeys, [key])
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)

        model.confirmPullInChoice()
        try await waitUntil { !model.isSubmitting }

        let calls = try recordText(record)
        XCTAssertEqual(captureCallCount(calls), 2)
        XCTAssertTrue(calls.contains("--pull-in \(key)"), calls)
        XCTAssertFalse(calls.contains("--pull-in none"))
    }

    func testRelationToggleAndNestedFixturesOpenTheChooser() async throws {
        for name in [
            "relation-successor-pending-toggle-unlink.json",
            "relation-successor-nested-complete-label.json",
            "relation-successor-done-bang.json",
        ] {
            let record = temporaryRecordURL()
            let fixture = try fixtureText(name)
            let success = try JSONDecoder().decode(
                CaptureCommandSuccess.self,
                from: Data(fixture.utf8)
            )
            let key = try XCTUnwrap(success.allRelationSuccessors.first?.offer?.key)
            let model = makeModel(record: record, stdout: fixture)
            model.plainDraft = "relation successor"
            model.preview()
            try await waitUntil { !model.isPreviewing }
            model.installCompatibleCaptureGrammarForTests()
            model.submit(openAfterCapture: false)
            let choice = try XCTUnwrap(model.pullInChoice, "chooser did not open for \(name)")
            XCTAssertEqual(choice.selectableKeys, [key], name)
            XCTAssertEqual(choice.sections.first?.group, "relation", name)
        }
    }

    func testRelationRequiredChoiceRefusalOpensChooserWithOpaqueKey() async throws {
        let record = temporaryRecordURL()
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": record.path,
                    "FAKE_BOB_CAPTURE_STDOUT": capabilityPreviewResponse(),
                    "FAKE_BOB_CAPTURE_WRITE_STDOUT": try fixtureText(
                        "relation-successor-required-choice-refusal.json"
                    ),
                    "FAKE_BOB_CAPTURE_WRITE_EXIT": "1",
                ]
            ),
            debounceNanoseconds: 0
        )
        model.plainDraft = "x*"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        XCTAssertFalse(model.pullInChoiceVisible)

        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        try await waitUntil { model.pullInChoiceVisible }

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.plainDraft, "x*")
        let choice = try XCTUnwrap(model.pullInChoice)
        XCTAssertEqual(choice.selectableKeys, ["agents.md#^evaluate"])
        XCTAssertEqual(choice.sections.first?.title, "Starts after “Send implementation prompt”")
        XCTAssertEqual(choice.authoredCopy?.capsule, "Starts after")
    }

    func testRelationSkipSubmitsExplicitNone() async throws {
        let record = temporaryRecordURL()
        let model = makeModel(
            record: record,
            stdout: try fixtureText("relation-successor-parked-x-star.json")
        )
        model.plainDraft = "x*"
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.pullInChoiceVisible)

        model.chooseNoPullInOffers()
        try await waitUntil { !model.isSubmitting }
        let calls = try recordText(record)
        XCTAssertTrue(calls.contains("--pull-in none"), calls)
        XCTAssertFalse(calls.contains("--pull-in agents.md#^evaluate"))
    }

    func testDraftChangeInvalidatesChoiceAndPicks() {
        let model = CapturePanelModel()
        model.installPullInChoiceForPreviews(
            offers: [testOffer(key: "one"), testOffer(key: "two", number: 2)],
            pullIn: CapturePullIn(supported: true, offerCount: 2),
            draft: "original"
        )
        model.markAllPullInOffers()
        XCTAssertTrue(model.pullInChoiceVisible)
        model.plainDraft = "edited"
        model.editorTextDidChange()

        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertEqual(model.plainDraft, "edited")
        XCTAssertFalse(model.editorInputLocked)
    }

    private static let projectOfferDraft = "Finish the exit packet @cash:goog-exit@"

    /// Previews the generated real-Bob project-offer response and opens its
    /// unmarked choice card.
    private func openProjectOfferChoice(record: URL) async throws -> CapturePanelModel {
        let model = makeModel(
            record: record,
            stdout: try fixtureText("project-note-successors.json")
        )
        model.plainDraft = Self.projectOfferDraft
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertEqual(captureCallCount(try recordText(record)), 1)
        return model
    }

    private func makeModel(record: URL, stdout: String, exit: String = "0") -> CapturePanelModel {
        CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": record.path,
                    "FAKE_BOB_STDOUT": stdout,
                    "FAKE_BOB_EXIT": exit,
                ]
            ),
            debounceNanoseconds: 0
        )
    }

    private func fakeBobPath() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func fixtureText(_ name: String) throws -> String {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    private func temporaryRecordURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func recordText(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for model state")
    }

    private func testOffer(key: String, number: Int = 1) -> TaskCompleteUnblocked {
        TaskCompleteUnblocked(
            notePath: "travel.md",
            blockID: "task-\(number)",
            line: number,
            text: "Task \(number)",
            statusSymbol: " ",
            statusName: "Ready",
            notLinked: "not_selected",
            offer: TaskCompleteOffer(
                key: key,
                n: number,
                group: "hand_off",
                destination: TaskCompleteOfferDestination(dayFile: "20261013.md")
            )
        )
    }

    private func capabilityPreviewResponse() -> String {
        #"""
        {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"day.md","target":"/tmp/day.md","text":"!task","task_line":"- [ ] #task Task","kind":"task_complete","created":"2026-10-13","placement":"updated","pull_in":{"supported":true,"offer_count":0,"choice":null,"picked_count":0},"task_complete":{"raw":"!travel:parent","unblocked":[]}}
        """#
    }

    private func successResponse() -> String {
        #"""
        {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"day.md","target":"/tmp/day.md","text":"!task","task_line":"- [ ] #task Task","kind":"task_complete","created":"2026-10-13","placement":"updated","pull_in":{"supported":true,"offer_count":2,"choice":null,"picked_count":0,"groups":[{"group":"hand_off","project":"","folded":{"hidden":0,"already_planned":0,"sub_projects":0}}]},"task_complete":{"raw":"!travel:parent","unblocked":[{"note_path":"travel.md","block_id":"one","line":1,"text":"One task","previous_status_symbol":"?","previous_status_name":"Blocked","status_symbol":" ","status_name":"Ready","not_linked":"not_selected","offer":{"key":"offer#one^key","n":1,"group":"hand_off","project":null,"destination":{"day_file":"20261013.md","entry_name":"FOCUS","entry_role":"current","fallback":false},"selected":false,"block_id_needed":false}},{"note_path":"travel.md","block_id":"two","line":2,"text":"Two task","previous_status_symbol":"?","previous_status_name":"Blocked","status_symbol":" ","status_name":"Ready","not_linked":"not_selected","offer":{"key":"opaque:two#^suffix","n":2,"group":"hand_off","project":null,"destination":{"day_file":"20261013.md","entry_name":"FOCUS","entry_role":"current","fallback":false},"selected":false,"block_id_needed":false}}]}}
        """#
    }

    private func refusalResponse() -> String {
        #"{"ok":false,"error":"Choose successor offers","code":"pull_in_choice_required","pull_in":{"supported":true,"offer_count":1,"choice":"explicit","picked_count":0},"offers":[{"note_path":"travel.md","block_id":"one","line":1,"text":"One task","previous_status_symbol":"?","previous_status_name":"Blocked","status_symbol":" ","status_name":"Ready","not_linked":"not_selected","offer":{"key":"refusal:key","n":1,"group":"hand_off","destination":{"day_file":"20261013.md","entry_name":"FOCUS","entry_role":"current","fallback":false},"selected":false,"block_id_needed":false}}]}"#
    }
}

private func captureCallCount(_ record: String) -> Int {
    record.components(separatedBy: "argv=")
        .dropFirst()
        .filter { $0.hasPrefix("capture ") }
        .count
}
