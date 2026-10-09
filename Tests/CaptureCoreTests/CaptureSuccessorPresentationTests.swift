import XCTest

@testable import CaptureCore

/// Unit tests for the shared successor-row builder: destination capsules,
/// minted-ID and reason captions, still-blocked captions, and the one
/// notification line (`docs/task-dependencies.md` §12.6).
final class CaptureSuccessorPresentationTests: XCTestCase {
    private func linkedItem(
        text: String = "Re-launch all failed agents",
        entryName: String = "FIX",
        entryCreated: Bool = false,
        nextUp: Bool = false,
        blockIDCreated: Bool = false,
        inbox: Bool = false
    ) -> TaskCompleteUnblocked {
        TaskCompleteUnblocked(
            notePath: "sase.md",
            blockID: "relaunch",
            line: 8,
            text: text,
            previousStatusSymbol: "?",
            previousStatusName: "Blocked",
            statusSymbol: "*",
            statusName: "Next",
            inbox: inbox,
            link: TaskCompleteSuccessorLink(
                dayFile: "20261005.md",
                entryName: entryName,
                entryLine: 4,
                entryCreated: entryCreated,
                nextUp: nextUp,
                line: 8,
                blockLink: "[[sase#^relaunch]]",
                blockIDCreated: blockIDCreated
            )
        )
    }

    private func recoveredItem(
        text: String = "Book flights",
        statusName: String = "Ready",
        notLinked: String? = "not_planned_today"
    ) -> TaskCompleteUnblocked {
        TaskCompleteUnblocked(
            notePath: "travel.md",
            blockID: "book-flights",
            line: 2,
            text: text,
            previousStatusSymbol: "?",
            previousStatusName: "Blocked",
            statusSymbol: " ",
            statusName: statusName,
            notLinked: notLinked
        )
    }

    private func rows(
        for items: [TaskCompleteUnblocked]
    ) -> [SuccessorUnblockedRow] {
        SuccessorRows.unblockedRows(
            from: items,
            transition: { "[?] → [*]  \($0.text)" },
            locator: { "\($0.notePath) ^\($0.blockID)" }
        )
    }

    func testLinkedRowCarriesCapsuleAndNoCaptionWithoutMint() throws {
        let row = try XCTUnwrap(rows(for: [linkedItem()]).first)
        XCTAssertEqual(row.kind, .linked)
        XCTAssertEqual(row.destinationText, "→ FIX")
        XCTAssertNil(row.captionText)
        XCTAssertFalse(row.isInbox)
    }

    func testLinkedRowCaptionNamesMintedID() throws {
        let row = try XCTUnwrap(
            rows(for: [linkedItem(blockIDCreated: true)]).first
        )
        XCTAssertEqual(row.captionText, "added ^relaunch")
    }

    func testLinkedRowCapsuleForCreatedContinuation() throws {
        let row = try XCTUnwrap(
            rows(for: [linkedItem(entryName: "BOB", entryCreated: true, nextUp: true)]).first
        )
        XCTAssertEqual(row.destinationText, "→ new BOB · next up")
    }

    func testLinkedRowCapsuleForUnnamedEntry() throws {
        let named = try XCTUnwrap(
            rows(for: [linkedItem(entryName: "", entryCreated: true)]).first
        )
        XCTAssertEqual(named.destinationText, "→ new session")
        let existing = try XCTUnwrap(
            rows(for: [linkedItem(entryName: "")]).first
        )
        XCTAssertEqual(existing.destinationText, "→ line 4")
    }

    func testRecoveredRowCarriesReasonCaption() throws {
        let row = try XCTUnwrap(rows(for: [recoveredItem()]).first)
        XCTAssertEqual(row.kind, .recovered)
        XCTAssertNil(row.destinationText)
        XCTAssertEqual(row.captionText, "Ready · not planned today")
    }

    func testRecoveredRowReasonTexts() throws {
        let cases: [(String?, String?)] = [
            ("already_planned", "Ready · already planned"),
            ("breaker", "Ready · not linked · more than 5"),
            ("project_task", "Ready · project task"),
            ("hidden", "Ready · hidden"),
            ("disabled", "Ready · linking off"),
            (nil, "Ready"),
        ]
        for (reason, expected) in cases {
            let row = try XCTUnwrap(
                rows(for: [recoveredItem(notLinked: reason)]).first
            )
            XCTAssertEqual(row.captionText, expected, "reason \(reason ?? "nil")")
        }
    }

    func testStillBlockedCaptions() throws {
        let waiting = SuccessorRows.stillBlockedRows(
            from: [TaskCompleteStillBlocked(
                notePath: "sase.md", blockID: "badges", line: 21,
                text: "Add badges", statusSymbol: "?",
                statusName: "Blocked", reason: "waits_on", waitsOn: 1
            )],
            locator: { "\($0.notePath) ^\($0.blockID)" }
        )
        XCTAssertEqual(waiting.count, 1)
        XCTAssertEqual(waiting[0].captionText, "stays Blocked · waits on 1 more")
        let scheduled = SuccessorRows.stillBlockedRows(
            from: [TaskCompleteStillBlocked(
                notePath: "travel.md", blockID: "trip", line: 3,
                text: "Later trip", statusSymbol: "?",
                statusName: "Blocked", reason: "scheduled",
                waitsOn: 0, scheduled: "2026-10-13"
            )],
            locator: { "\($0.notePath) ^\($0.blockID)" }
        )
        XCTAssertEqual(scheduled[0].captionText, "stays Blocked · until Oct 13")
    }

    func testNotificationLineForOneLinked() throws {
        XCTAssertEqual(
            SuccessorRows.notificationLine(unblocked: [linkedItem()]),
            "🔓 Next in FIX: Re-launch all failed agents"
        )
    }

    func testNotificationLineForCreatedContinuation() throws {
        XCTAssertEqual(
            SuccessorRows.notificationLine(unblocked: [
                linkedItem(entryName: "BOB", entryCreated: true, nextUp: true),
            ]),
            "🔓 Next in new BOB session (next up): Re-launch all failed agents"
        )
    }

    func testNotificationLineForSeveralLinkedOneEntry() throws {
        XCTAssertEqual(
            SuccessorRows.notificationLine(unblocked: [
                linkedItem(text: "Review memory beads"),
                linkedItem(text: "Ship AGENTS.md updates to the vault"),
                linkedItem(text: "Third thing"),
            ]),
            "🔓 3 linked → FIX: Review memory beads, Ship AGENTS.md updates to the vault, +1"
        )
    }

    func testNotificationLineForSeveralEntries() throws {
        XCTAssertEqual(
            SuccessorRows.notificationLine(unblocked: [
                linkedItem(text: "One", entryName: "FIX"),
                linkedItem(text: "Two", entryName: "SASE"),
                linkedItem(text: "Three", entryName: "FIX"),
            ]),
            "🔓 3 linked · FIX, SASE"
        )
    }

    func testNotificationLineForBreaker() throws {
        let items = (1 ... 7).map { _ in recoveredItem(notLinked: "breaker") }
        XCTAssertEqual(
            SuccessorRows.notificationLine(unblocked: items),
            "🔓 7 unblocked · not linked (more than 5)"
        )
    }

    func testNotificationLineKeepsOldBodyForRecoveredOnly() throws {
        XCTAssertNil(SuccessorRows.notificationLine(unblocked: [recoveredItem()]))
        XCTAssertNil(SuccessorRows.notificationLine(unblocked: []))
    }

    func testRecoveredLine() throws {
        XCTAssertEqual(
            SuccessorRows.recoveredLine(unblocked: [recoveredItem()]),
            "🔓 Unblocked: Book flights (Ready)"
        )
        XCTAssertNil(
            SuccessorRows.recoveredLine(unblocked: [linkedItem()]),
            "linked rows use the linked line, not the recovered fallback"
        )
    }

    func testTruncation() throws {
        let full = String(repeating: "a", count: 48)
        XCTAssertEqual(SuccessorRows.truncate(full), full)
        let long = String(repeating: "b", count: 60)
        XCTAssertEqual(
            SuccessorRows.truncate(long),
            String(repeating: "b", count: 48) + "…"
        )
    }

    func testShortMonthDay() throws {
        XCTAssertEqual(SuccessorRows.shortMonthDay("2026-10-13"), "Oct 13")
        XCTAssertEqual(SuccessorRows.shortMonthDay("2026-01-05"), "Jan 5")
        XCTAssertNil(SuccessorRows.shortMonthDay("tomorrow"))
        XCTAssertNil(SuccessorRows.shortMonthDay("2026-13-01"))
    }
}
