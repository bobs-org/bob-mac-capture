import AppKit
import SwiftUI
import XCTest

@testable import BobMacCapture
@testable import RefsCore

@MainActor
final class RefsTodayLinkCardDesignTests: XCTestCase {
    func testTodayCardAndToastFixturesToPNG() throws {
        let item = RefItem(
            id: "ref/papers/attention.md",
            link: "[[ref/papers/attention]]",
            rawTitle: "Attention Is All You Need",
            stem: "attention",
            kind: .paper,
            state: .ready,
            isBlocked: false,
            pdfPath: "lib/papers/attention.pdf",
            task: RefTask(
                path: "sase.md",
                blockID: "ref-attention",
                link: "[[sase#^ref-attention]]",
                mark: " "
            )
        )
        var card = RefsTodayLinkCard(item: item)
        card.applyListing(RefsTodayLinkResponse(
            ok: true,
            mode: "dry_run",
            pomodoros: [
                RefsTodayLinkPomodoro(
                    ref: "41:0b1c2d3e",
                    name: "BUGS",
                    slug: "bugs",
                    timeRange: "0920-0950",
                    startsAt: "2026-10-16T09:20",
                    endsAt: "2026-10-16T09:50",
                    running: true,
                    isDefault: true,
                    taskLinkCount: 2
                ),
                RefsTodayLinkPomodoro(
                    ref: "44:9a8b7c6d",
                    name: "READING",
                    slug: "reading",
                    placeholder: true
                ),
            ]
        ))

        let cardView = RefsTodayLinkCardView(
            card: card,
            focusSequence: 0,
            previewMode: true,
            onQueryChange: { _ in },
            onRowTap: { _ in }
        )
        .frame(width: 405, height: 470, alignment: .top)
        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            try RenderFixtureWriter.write(
                cardView,
                name: "refs-today-link-card",
                width: 405,
                appearance: appearance
            )
        }

        let toast = RefsGlassToastView(
            title: "Linked under BUGS",
            value: "Attention Is All You Need",
            detail: "Ready → Next · removed future schedule",
            style: .linked,
            previewMode: true
        )
        .frame(width: 420)
        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            try RenderFixtureWriter.write(
                toast,
                name: "refs-today-link-toast",
                width: 420,
                appearance: appearance
            )
        }
    }
}
