import Foundation
import XCTest

@testable import CaptureCore

final class CaptureInboxRouteStateTests: XCTestCase {
    private func candidate(
        key: String = "mac_inbox.md#^route-task",
        n: Int = 1,
        text: String = "Route me",
        previousStatusName: String = "Ready",
        statusName: String = "Next"
    ) -> CaptureInboxRouteCandidate {
        CaptureInboxRouteCandidate(
            key: key,
            n: n,
            notePath: "mac_inbox.md",
            inbox: "mac_inbox",
            blockID: "route-task",
            line: 6,
            text: text,
            previousStatusSymbol: " ",
            previousStatusName: previousStatusName,
            statusSymbol: "*",
            statusName: statusName
        )
    }

    private func destination(
        relativePath: String = "health.md",
        label: String = "health",
        kind: String = "area",
        status: String? = nil,
        parent: String? = nil,
        blocked: Bool = false
    ) -> CaptureInboxRouteDestination {
        CaptureInboxRouteDestination(
            relativePath: relativePath,
            route: String(relativePath.dropSuffix(".md")),
            label: label,
            kind: kind,
            status: status,
            parent: parent,
            blocked: blocked
        )
    }

    private func twoCandidates() -> [CaptureInboxRouteCandidate] {
        [
            candidate(),
            CaptureInboxRouteCandidate(
                key: "gkeep_inbox.md#^gkeep-task",
                n: 2,
                notePath: "gkeep_inbox.md",
                inbox: "gkeep_inbox",
                blockID: "gkeep-task",
                line: 6,
                text: "GKeep task",
                previousStatusSymbol: " ",
                previousStatusName: "Ready",
                statusSymbol: "*",
                statusName: "Next"
            ),
        ]
    }

    private func threeDestinations() -> [CaptureInboxRouteDestination] {
        [
            destination(relativePath: "app.md", label: "app", kind: "project", status: "wip"),
            destination(relativePath: "errands.md", label: "errands"),
            destination(),
        ]
    }

    func testAnswerMoveAndKeepAdvanceCursor() {
        var state = CaptureInboxRouteChoiceState(
            candidates: twoCandidates(),
            destinations: threeDestinations()
        )
        XCTAssertEqual(state.cursor, 0)
        XCTAssertTrue(state.answerMoveCurrent(destination: "health.md"))
        XCTAssertEqual(state.cursor, 1)
        XCTAssertEqual(
            state.answers["mac_inbox.md#^route-task"],
            .move(destination: "health.md")
        )
        XCTAssertFalse(state.answerKeepCurrent())
        XCTAssertEqual(state.cursor, 1)
        XCTAssertEqual(state.answers["gkeep_inbox.md#^gkeep-task"], .keep)
        XCTAssertTrue(state.isComplete)
    }

    func testGoBackKeepsAnswers() {
        var state = CaptureInboxRouteChoiceState(
            candidates: twoCandidates(),
            destinations: threeDestinations()
        )
        _ = state.answerMoveCurrent(destination: "health.md")
        XCTAssertTrue(state.goBack())
        XCTAssertEqual(state.cursor, 0)
        XCTAssertEqual(
            state.answers["mac_inbox.md#^route-task"],
            .move(destination: "health.md")
        )
        XCTAssertFalse(state.goBack())
    }

    func testFilterMatchesLabelRouteAndRelativePath() {
        var state = CaptureInboxRouteChoiceState(
            candidates: [candidate()],
            destinations: threeDestinations()
        )
        state.filterText = "heal"
        XCTAssertEqual(state.filteredDestinations.map(\.relativePath), ["health.md"])
        state.filterText = "app"
        XCTAssertEqual(state.filteredDestinations.map(\.relativePath), ["app.md"])
        state.filterText = "errands.md"
        XCTAssertEqual(state.filteredDestinations.map(\.relativePath), ["errands.md"])
        state.filterText = "zzz"
        XCTAssertTrue(state.filteredDestinations.isEmpty)
        state.filterText = ""
        XCTAssertEqual(state.filteredDestinations.count, 3)
    }

    func testInitialHighlightPrefersPreviousAnswerThenLastUsedThenFirst() {
        var state = CaptureInboxRouteChoiceState(
            candidates: twoCandidates(),
            destinations: threeDestinations()
        )
        state.applyInitialHighlight(previousAnswerDestination: nil, lastUsedDestination: nil)
        XCTAssertEqual(state.highlightedRow?.relativePath, "app.md")

        state.applyInitialHighlight(previousAnswerDestination: nil, lastUsedDestination: "health.md")
        XCTAssertEqual(state.highlightedRow?.relativePath, "health.md")

        state.applyInitialHighlight(
            previousAnswerDestination: "errands.md",
            lastUsedDestination: "health.md"
        )
        XCTAssertEqual(state.highlightedRow?.relativePath, "errands.md")

        state.filterText = "heal"
        state.applyInitialHighlight(previousAnswerDestination: nil, lastUsedDestination: "app.md")
        XCTAssertEqual(state.highlightedRow?.relativePath, "health.md")
    }

    func testHighlightWrapsAroundFilteredRows() {
        var state = CaptureInboxRouteChoiceState(
            candidates: [candidate()],
            destinations: threeDestinations()
        )
        state.applyInitialHighlight(previousAnswerDestination: nil, lastUsedDestination: nil)
        XCTAssertEqual(state.highlightedRow?.relativePath, "app.md")
        state.moveHighlightForward()
        XCTAssertEqual(state.highlightedRow?.relativePath, "errands.md")
        state.moveHighlightForward()
        XCTAssertEqual(state.highlightedRow?.relativePath, "health.md")
        state.moveHighlightForward()
        XCTAssertEqual(state.highlightedRow?.relativePath, "app.md")
        state.moveHighlightBackward()
        XCTAssertEqual(state.highlightedRow?.relativePath, "health.md")
    }

    func testReopenAtRefusedKeyShowsMessageAndKeepsAnswers() {
        var state = CaptureInboxRouteChoiceState(
            candidates: twoCandidates(),
            destinations: threeDestinations()
        )
        _ = state.answerMoveCurrent(destination: "health.md")
        _ = state.answerKeepCurrent()
        state.reopenAtRefusedKey(
            "mac_inbox.md#^route-task",
            message: "health.md has no ## Tasks section"
        )
        XCTAssertEqual(state.cursor, 0)
        XCTAssertEqual(state.refusedKey, "mac_inbox.md#^route-task")
        XCTAssertEqual(state.refusalMessage, "health.md has no ## Tasks section")
        XCTAssertEqual(
            state.answers["gkeep_inbox.md#^gkeep-task"],
            .keep
        )
    }

    func testReseedKeepsSurvivingAnswers() {
        var state = CaptureInboxRouteChoiceState(
            candidates: twoCandidates(),
            destinations: threeDestinations()
        )
        _ = state.answerMoveCurrent(destination: "health.md")
        _ = state.answerKeepCurrent()
        state.reseed(candidates: [candidate()], destinations: threeDestinations())
        XCTAssertEqual(state.cursor, 0)
        XCTAssertEqual(state.answers.count, 1)
        XCTAssertEqual(
            state.answers["mac_inbox.md#^route-task"],
            .move(destination: "health.md")
        )
    }

    func testAnswersForSubmitOmitsUnanswered() {
        var state = CaptureInboxRouteChoiceState(
            candidates: twoCandidates(),
            destinations: threeDestinations()
        )
        _ = state.answerMoveCurrent(destination: "health.md")
        let submit = state.answersForSubmit
        XCTAssertEqual(submit.count, 1)
        XCTAssertEqual(submit[0].key, "mac_inbox.md#^route-task")
        XCTAssertEqual(submit[0].destination, "health.md")
        XCTAssertFalse(state.isComplete)
    }

    func testContextLineAndRefusal() {
        let line = CaptureInboxRoutePresentation.contextLine(
            candidate: candidate(),
            index: 0,
            total: 2
        )
        XCTAssertEqual(line, "Route me · Ready → Next · Task 1 of 2")

        let single = CaptureInboxRoutePresentation.contextLine(
            candidate: candidate(),
            index: 0,
            total: 1
        )
        XCTAssertEqual(single, "Route me · Ready → Next")

        let refused = CaptureInboxRoutePresentation.contextLine(
            candidate: candidate(),
            index: 0,
            total: 1,
            refusalMessage: "health.md has no ## Tasks section"
        )
        XCTAssertEqual(refused, "health.md has no ## Tasks section")
    }

    func testRowTextAndDetail() {
        let row = destination(
            relativePath: "areas/health.md",
            label: "health",
            kind: "area",
            parent: "Life"
        )
        XCTAssertEqual(CaptureInboxRoutePresentation.rowText(destination: row), "health")
        XCTAssertEqual(
            CaptureInboxRoutePresentation.rowDetail(destination: row),
            "areas/health.md · Life"
        )
        let blocked = destination(
            relativePath: "blocked.md",
            label: "blocked",
            kind: "project",
            status: "wip",
            blocked: true
        )
        XCTAssertEqual(
            CaptureInboxRoutePresentation.rowDetail(destination: blocked),
            "blocked.md · wip · Blocked"
        )
    }

    func testPreviewSummary() {
        XCTAssertNil(CaptureInboxRoutePresentation.previewSummary(candidates: []))
        XCTAssertEqual(
            CaptureInboxRoutePresentation.previewSummary(candidates: [candidate()]),
            "Inbox · Route me · Ready → Next · ↩ choose where it goes"
        )
        XCTAssertEqual(
            CaptureInboxRoutePresentation.previewSummary(candidates: twoCandidates()),
            "2 inbox tasks · ↩ choose where they go"
        )
    }

    func testSuccessNoticeSuffix() {
        XCTAssertNil(CaptureInboxRoutePresentation.successNoticeSuffix(route: nil))
        let pending = CaptureInboxRoute(
            supported: true,
            candidateCount: 1,
            candidates: [candidate()]
        )
        XCTAssertNil(CaptureInboxRoutePresentation.successNoticeSuffix(route: pending))

        let movedCandidate = CaptureInboxRouteCandidate(
            key: "mac_inbox.md#^route-task",
            n: 1,
            notePath: "mac_inbox.md",
            inbox: "mac_inbox",
            blockID: "route-task",
            line: 6,
            text: "Route me",
            previousStatusSymbol: " ",
            previousStatusName: "Ready",
            statusSymbol: "*",
            statusName: "Next",
            answer: CaptureInboxRouteAnswer(action: "move", destination: "health.md"),
            outcome: "moved",
            moved: CaptureInboxRouteMoved(
                destination: "health.md",
                line: 6,
                blockID: "route-task",
                previousBlockID: "route-task",
                fresh: "2026-10-24"
            )
        )
        let moved = CaptureInboxRoute(
            supported: true,
            candidateCount: 1,
            routedCount: 1,
            candidates: [movedCandidate],
            destinations: threeDestinations()
        )
        XCTAssertEqual(
            CaptureInboxRoutePresentation.successNoticeSuffix(route: moved),
            "· moved to health"
        )

        let keptCandidate = CaptureInboxRouteCandidate(
            key: "mac_inbox.md#^route-task",
            n: 1,
            notePath: "mac_inbox.md",
            inbox: "mac_inbox",
            blockID: "route-task",
            line: 6,
            text: "Route me",
            previousStatusSymbol: " ",
            previousStatusName: "Ready",
            statusSymbol: "*",
            statusName: "Next",
            answer: CaptureInboxRouteAnswer(action: "keep"),
            outcome: "kept"
        )
        let kept = CaptureInboxRoute(
            supported: true,
            candidateCount: 1,
            keptCount: 1,
            candidates: [keptCandidate]
        )
        XCTAssertEqual(
            CaptureInboxRoutePresentation.successNoticeSuffix(route: kept),
            "· kept in mac_inbox"
        )
    }
}

extension String {
    fileprivate func dropSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
