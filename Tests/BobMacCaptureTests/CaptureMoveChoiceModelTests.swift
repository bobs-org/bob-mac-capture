import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureMoveChoiceModelTests: XCTestCase {
    private let draft =
        "Finish the exit packet @cash^goog-exit@\n- Draft the memo ^memo\n- ^pay-cc\n- ^^\n- Book the lawyer ^lawyer"

    func testReturnOpensWithoutWritingAndEscapeRemembersIDlessMarkAfterEdit() async throws {
        let (model, record) = makeModel()
        try await preview(model)
        model.submit(openAfterCapture: false)
        let slot = try XCTUnwrap(model.moveChoice?.slot)
        let idless = try XCTUnwrap(slot.rows.first { $0.mint != nil })
        var state = try XCTUnwrap(model.moveChoice)
        state.highlight(rowKey: idless.key)
        model.updateMoveChoice(state)
        model.setMoveChoiceAnswer(.move)
        XCTAssertEqual(try callCount(record), 1)
        model.cancelMoveChoice()
        XCTAssertFalse(model.editorInputLocked)
        XCTAssertEqual(model.plainDraft, draft)
        model.plainDraft = draft.replacingOccurrences(of: "packet", with: "packets")
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertEqual(model.moveChoice?.answers[idless.key], .move)
        XCTAssertEqual(try callCount(record), 2)
    }

    func testZeroMarksIsInertAndShiftReturnSendsExplicitNone() async throws {
        let (model, record) = makeModel()
        try await preview(model)
        model.submit(openAfterCapture: false)
        model.confirmMoveChoice()
        XCTAssertTrue(model.moveChoiceVisible)
        XCTAssertEqual(model.moveChoiceMessage, "Mark tasks with ^ or :")
        XCTAssertEqual(try callCount(record), 1)
        model.confirmMoveChoice(none: true)
        try await waitUntil { !model.isSubmitting }
        XCTAssertTrue(try calls(record).contains("--move-in none"))
        XCTAssertEqual(model.plainDraft, "")
    }

    func testMoveThenPullInBackAndInboxCarryOneAnswerAndSeed() async throws {
        let (model, record) = makeModel(extra: [
            "FAKE_BOB_MOVE_CHOICE_FIXTURE": "move-choice-offer.json",
            "FAKE_BOB_MOVE_CHOICE_INBOX": "1",
        ])
        try await preview(model, draft: draft.replacingOccurrences(of: "@cash^", with: "@cash:"))
        model.submit(openAfterCapture: false)
        model.setMoveChoiceAnswer(.moveAndLink)
        let selection = try XCTUnwrap(model.moveChoice?.selection)
        model.confirmMoveChoice()
        XCTAssertTrue(model.pullInChoiceVisible)
        XCTAssertEqual(try callCount(record), 1)
        model.cancelPullInChoiceFromKeyboard()
        XCTAssertEqual(model.moveChoice?.selection, selection)
        model.confirmMoveChoice()
        model.chooseNoPullInOffers()
        try await waitUntil { model.inboxRouteChoiceVisible }
        model.backInboxRouteChoice()
        XCTAssertTrue(model.pullInChoiceVisible)
        model.chooseNoPullInOffers()
        try await waitUntil { model.inboxRouteChoiceVisible }
        model.keepInboxRouteCandidate()
        try await waitUntil { !model.isSubmitting }
        let text = try calls(record)
        XCTAssertTrue(text.contains("--move-in \(selection) --pull-in none"))
        XCTAssertTrue(text.contains("--inbox-route mac_inbox.md#^route-task="))
        let seeds = text.split(separator: "\n").filter { $0.hasPrefix("BOB_PRIORITY_ROLL_SEED=") }
        XCTAssertEqual(Set(seeds).count, 1)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testDirectInboxChainKeepsMoveAnswer() async throws {
        let (model, record) = makeModel(extra: ["FAKE_BOB_MOVE_CHOICE_INBOX": "1"])
        try await preview(model)
        model.submit(openAfterCapture: false)
        model.setMoveChoiceAnswer(.move)
        let selection = try XCTUnwrap(model.moveChoice?.selection)
        model.confirmMoveChoice()
        XCTAssertTrue(model.inboxRouteChoiceVisible)
        XCTAssertEqual(try callCount(record), 1)
        model.backInboxRouteChoice()
        XCTAssertEqual(model.moveChoice?.selection, selection)
        model.confirmMoveChoice()
        model.keepInboxRouteCandidate()
        try await waitUntil { !model.isSubmitting }
        XCTAssertTrue(try calls(record).contains("--move-in \(selection) --inbox-route"))
    }

    func testStaleReopenKeepsSurvivorsAndReportsLostMarks() async throws {
        let (model, _) = makeModel(extra: [
            "FAKE_BOB_MOVE_CHOICE_FAILURE": "move_choice_stale",
            "FAKE_BOB_MOVE_CHOICE_GONE": "cash.md#^equity-docs",
        ])
        try await preview(model)
        model.submit(openAfterCapture: false)
        model.selectAllMoveChoices()
        let before = try XCTUnwrap(model.moveChoice?.selectedCount)
        model.confirmMoveChoice()
        try await waitUntil { !model.isSubmitting }
        XCTAssertTrue(model.moveChoiceVisible)
        XCTAssertEqual(model.moveChoice?.selectedCount, before - 1)
        XCTAssertEqual(model.moveChoiceMessage, "cash.md changed · 1 marked task is gone")
        XCTAssertEqual(model.plainDraft, draft)
    }

    func testRequiredRefusalWithoutPreviewOpensCard() async throws {
        let (model, record) = makeModel()
        model.plainDraft = draft
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        // Without capability evidence, acknowledge the compatibility warning first.
        model.submit(openAfterCapture: false)
        try await waitUntil { !model.isSubmitting }
        XCTAssertTrue(model.moveChoiceVisible)
        XCTAssertFalse(try calls(record).contains("--move-in"))
    }

    func testRequiredRefusalRefreshesFollowOnOffersBeforeWriting() async throws {
        let (model, record) = makeModel(extra: [
            "FAKE_BOB_MOVE_CHOICE_FIXTURE": "move-choice-offer.json"
        ])
        model.plainDraft = draft.replacingOccurrences(of: "@cash^", with: "@cash:")
        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        // Without capability evidence, acknowledge the compatibility warning first.
        model.submit(openAfterCapture: false)
        try await waitUntil { !model.isSubmitting }
        model.setMoveChoiceAnswer(.move)
        model.confirmMoveChoice()
        try await waitUntil { model.pullInChoiceVisible }
        XCTAssertEqual(try callCount(record), 2)
        XCTAssertTrue(try calls(record).contains("--dry-run --move-in cash.md#^equity-docs"))
        XCTAssertEqual(model.pullInChoice?.moveInSelection, "cash.md#^equity-docs")
        model.cancelPullInChoiceFromKeyboard()
        XCTAssertTrue(model.moveChoiceVisible)
    }

    func testOtherMoveRefusalsShowBobMessageInCard() async throws {
        for code in ["move_choice_refused", "move_choice_conflict", "move_choice_empty"] {
            let (model, _) = makeModel(extra: ["FAKE_BOB_MOVE_CHOICE_FAILURE": code])
            try await preview(model)
            model.submit(openAfterCapture: false)
            model.setMoveChoiceAnswer(.move)
            model.confirmMoveChoice()
            try await waitUntil { !model.isSubmitting }
            XCTAssertTrue(model.moveChoiceVisible, code)
            XCTAssertEqual(model.moveChoiceMessage, "Parent tasks changed: " + code)
        }
    }

    func testOldBobWarnsOnceAndNeverGetsMoveFlag() async throws {
        let (model, record) = makeModel(extra: ["FAKE_BOB_MOVE_CHOICE_OLD": "1"])
        try await preview(model)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(
            model.moveChoiceCapabilityWarning, CaptureMoveChoicePresentation.oldBobWarning)
        XCTAssertEqual(try callCount(record), 1)
        model.submit(openAfterCapture: false)
        try await waitUntil { !model.isSubmitting }
        XCTAssertEqual(try callCount(record), 2)
        XCTAssertFalse(try calls(record).contains("--move-in"))
    }

    func testNamedProjectRequiresColonAndControlReturnOpensReportedNote() async throws {
        let (model, record) = makeModel(extra: [
            "FAKE_BOB_MOVE_CHOICE_FIXTURE": "move-choice-mq16.json"
        ])
        var opened = false
        model.noteOpener = { _, completion in
            opened = true
            completion(nil)
        }
        try await preview(model, draft: draft.replacingOccurrences(of: "@\n", with: "@#admin\n"))
        model.submit(openAfterCapture: false)
        model.confirmMoveChoice(none: true)
        XCTAssertEqual(try callCount(record), 1)
        XCTAssertEqual(model.moveChoiceMessage, "#admin needs a : pick, or remove #admin")
        model.setMoveChoiceAnswer(.moveAndLink)
        model.confirmMoveChoice(openAfterCapture: true)
        try await waitUntil { !model.isSubmitting }
        XCTAssertTrue(opened)
        XCTAssertTrue(try calls(record).contains("--move-in :cash.md#^equity-docs"))
    }

    func testMoveKeysOwnFilterAndIgnoreReturnRepeat() throws {
        let router = CaptureKeyCommandRouter()
        var context = CaptureKeyRoutingContext(moveChoiceVisible: true)
        func event(
            _ code: UInt16, _ text: String = "", _ modifiers: NSEvent.ModifierFlags = [],
            repeat repeated: Bool = false
        ) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: repeated, keyCode: code)!
        }
        XCTAssertEqual(
            router.command(for: event(22, "^", .shift), context: context), .setMoveChoice(.move))
        XCTAssertEqual(
            router.command(for: event(41, ":", .shift), context: context),
            .setMoveChoice(.moveAndLink))
        XCTAssertEqual(router.command(for: event(36), context: context), .confirmMoveChoice)
        XCTAssertEqual(router.command(for: event(36, "", .shift), context: context), .chooseNoMoves)
        XCTAssertEqual(
            router.command(for: event(36, "", .control), context: context),
            .confirmMoveChoiceAndOpen)
        XCTAssertEqual(router.command(for: event(36, repeat: true), context: context), .consumeKey)
        XCTAssertEqual(router.command(for: event(49, " "), context: context), .toggleMoveChoice)
        context.moveChoiceFilterFocused = true
        context.moveChoiceFilterIsEmpty = false
        XCTAssertNil(router.command(for: event(49, " "), context: context))
        XCTAssertEqual(
            router.command(for: event(41, ":", .shift), context: context),
            .setMoveChoice(.moveAndLink))
        XCTAssertEqual(
            router.command(for: event(0, "a", .command), context: context), .selectAllMoveChoices)
    }

    func testDiscardDropsMarks() async throws {
        let (model, _) = makeModel()
        try await preview(model)
        model.submit(openAfterCapture: false)
        model.setMoveChoiceAnswer(.move)
        model.cancelMoveChoice()
        model.discardDraft()
        try await preview(model)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(model.moveChoice?.selectedCount, 0)
    }

    private func makeModel(extra: [String: String] = [:]) -> (CapturePanelModel, URL) {
        let record = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        var env = [
            "HOME": "/tmp", "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": record.path, "FAKE_BOB_MOVE_CHOICE": "1",
        ]
        env.merge(extra) { _, new in new }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/fake-bob")
        return (
            CapturePanelModel(
                processClient: BobProcessClient(
                    executablePath: fixture.path, environment: env
                ), debounceNanoseconds: 0), record
        )
    }

    private func preview(_ model: CapturePanelModel, draft: String? = nil) async throws {
        model.plainDraft = draft ?? self.draft
        model.preview()
        try await waitUntil { !model.isPreviewing }
        model.installCompatibleCaptureGrammarForTests()
    }

    private func calls(_ record: URL) throws -> String {
        try String(contentsOf: record, encoding: .utf8)
    }

    private func callCount(_ record: URL) throws -> Int {
        try calls(record).components(separatedBy: "argv=capture ").count - 1
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for Move flow")
    }
}