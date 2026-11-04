import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureMoveChoiceDesignTests: XCTestCase {
    @available(macOS 26.0, *)
    func testRenderMoveCardAtSupportedWidthsAndAppearances() throws {
        let slot = CaptureMoveChoiceSlot(
            item: 1,
            itemLine: 4,
            draftRange: [112, 114],
            parent: "cash.md",
            destination: "cash_goog_exit.md",
            pomodoroName: "ADMIN",
            openCount: 25,
            copy: CaptureMoveChoiceCopy(
                title: "Move into cash_goog_exit.md",
                subtitle: "from cash.md · 25 open",
                slot: "Lands between “Pay the credit card” and “Book the lawyer”, in cash.md order",
                leave: "Stays in cash.md"
            ),
            rows: [
                task(
                    "cash.md#^equity-docs",
                    text: "Collect the equity paperwork",
                    section: "Tasks",
                    status: "/",
                    pomodoro: "WORK 13:30",
                    answer: .move
                ),
                task(
                    "cash.md#^call-ms",
                    text: "Call Morgan Stanley about the 401k",
                    section: "Tasks",
                    pomodoro: "ADMIN",
                    answer: .moveAndLink
                ),
                CaptureMoveChoiceRow(
                    key: "cash.md@1a2b3c4d",
                    n: 3,
                    line: 15,
                    section: "Tasks",
                    mint: "renew-the-passport",
                    text: "Renew the passport",
                    statusSymbol: " ",
                    statusName: "Ready",
                    choices: [
                        CaptureMoveChoiceOption(
                            sigil: "^",
                            consequence: "Moves into cash_goog_exit.md · adds ^renew-the-passport",
                            addsLink: false
                        ),
                        CaptureMoveChoiceOption(
                            sigil: ":",
                            consequence: "Moves in · adds ^renew-the-passport · links under ADMIN",
                            addsLink: true
                        ),
                    ]
                ),
                CaptureMoveChoiceRow(
                    key: "cash.md#^pay-cc",
                    n: 9,
                    line: 21,
                    section: "Admin",
                    blockID: "pay-cc",
                    text: "Pay the credit card",
                    statusSymbol: " ",
                    statusName: "Ready",
                    choices: [],
                    locked: CaptureMoveChoiceLock(sigil: "^", itemLine: 3)
                ),
                task(
                    "cash.md#^expenses",
                    text: "File the expense report",
                    section: "Admin"
                ),
            ]
        )
        let view = MoveChoiceFixtureHost(slot: slot)
        for (name, width) in [
            ("capture-move-choice-card-wide", CGFloat(760)),
            (
                "capture-move-choice-card-minimum",
                CGFloat(CapturePanelLayout.panelMinimumContentWidth)
            ),
        ] {
            try RenderFixtureWriter.write(view, name: name, width: width, appearance: .aqua)
            try RenderFixtureWriter.write(view, name: name, width: width, appearance: .darkAqua)
        }
    }

    @available(macOS 26.0, *)
    func testManySectionsKeepCardBoundedAndLastTaskReachable() throws {
        let rows = (0..<76).map { index in
            task(
                "cash.md#^task-\(index)",
                text:
                    "A long task title \(index) that still has a visible consequence and identity",
                section: "Section \(index)")
        }
        let slot = CaptureMoveChoiceSlot(parent: "cash.md", destination: "cash_new.md", rows: rows)
        var choice = CaptureMoveChoiceState(slot: slot)
        choice.moveHighlight(by: 75)
        XCTAssertEqual(choice.currentRow?.key, "cash.md#^task-75")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: MoveChoiceFixtureHost(slot: slot).frame(width: 640))
            host.appearance = NSAppearance(named: appearance)
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThan(host.fittingSize.height, 650)
        }
    }

    private func task(
        _ key: String,
        text: String,
        section: String,
        status: String = " ",
        pomodoro: String? = nil,
        answer: CaptureMoveChoiceAnswer? = nil
    ) -> CaptureMoveChoiceRow {
        CaptureMoveChoiceRow(
            key: key,
            n: 1,
            line: 7,
            section: section,
            blockID: String(key.split(separator: "^").last ?? ""),
            text: text,
            statusSymbol: status,
            statusName: status == "/" ? "In Progress" : "Ready",
            pomodoro: pomodoro.map { CaptureMoveChoicePomodoro(line: 2, name: $0) },
            choices: [
                CaptureMoveChoiceOption(
                    sigil: "^", consequence: "Moves into cash_goog_exit.md", addsLink: false),
                CaptureMoveChoiceOption(
                    sigil: ":", consequence: "Moves in · links under ADMIN", addsLink: true),
            ],
            answer: answer?.sigil
        )
    }
}

@available(macOS 26.0, *)
private struct MoveChoiceFixtureHost: View {
    @State private var choice: CaptureMoveChoiceState

    init(slot: CaptureMoveChoiceSlot) {
        _choice = State(initialValue: CaptureMoveChoiceState(slot: slot))
    }

    var body: some View {
        CaptureMoveChoiceCard(
            choice: $choice,
            todayBadge: TodayBadgePresentation(count: 9, cap: 10),
            previewMode: true
        )
        .padding(18)
    }
}
