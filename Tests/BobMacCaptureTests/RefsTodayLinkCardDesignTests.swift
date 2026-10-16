import AppKit
import SwiftUI
import XCTest

@testable import BobMacCapture
@testable import RefsCore

@MainActor
final class RefsTodayLinkCardDesignTests: XCTestCase {
    func testTodayCardStateMatrixAndToastFixturesToPNG() throws {
        var loading = makeCard()

        var ready = makeCard()
        ready.applyListing(try fixture("refs-today-listing.json"))

        var typed = ready
        typed.editQuery("deep work")

        var multipleRunning = makeCard()
        multipleRunning.applyListing(try fixture("refs-today-multiple-running.json"))

        var noOpen = makeCard()
        noOpen.applyListing(RefsTodayLinkResponse(
            ok: false,
            error: RefsTodayLinkFailure(
                code: "no_open_pomodoro", message: "No open Pomodoros", hint: "Type a name"
            )
        ))

        var guardPreview = makeCard()
        guardPreview.applyListing(try fixture("refs-today-link-guard.json"))

        var refused = makeCard()
        refused.applyListing(try fixture("refs-today-no-reading-task.json"))

        var running = ready
        running.handle(.submit)

        var failed = ready
        failed.handle(.submit)
        failed.fail(RefsTodayLinkFailure(
            code: "note_changed", message: "The note changed", hint: "Try again"
        ))

        var reloading = ready
        reloading.handle(.submit)
        reloading.fail(RefsTodayLinkFailure(
            code: "stale_pomodoro", message: "The ledger changed", hint: "Pick again"
        ))

        let states: [(String, RefsTodayLinkCard)] = [
            ("loading", loading),
            ("ready", ready),
            ("typed-create", typed),
            ("multiple-running", multipleRunning),
            ("no-open", noOpen),
            ("guard-preview", guardPreview),
            ("refused", refused),
            ("running", running),
            ("failed", failed),
            ("reloading", reloading),
        ]
        let fixedNow = Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: 16, hour: 9, minute: 25
        ))!
        for (name, card) in states {
            for width: CGFloat in [300, 430] {
                let view = RefsTodayLinkCardView(
                    card: card,
                    focusSequence: 0,
                    previewMode: true,
                    fixedNow: fixedNow,
                    onQueryChange: { _ in },
                    onRowTap: { _ in }
                )
                .frame(width: width, height: 470, alignment: .top)
                for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
                    try RenderFixtureWriter.write(
                        view,
                        name: "refs-today-link-card-\(name)-\(Int(width))",
                        width: width,
                        appearance: appearance
                    )
                }
            }
        }

        let toastFixtures: [(String, String)] = [
            ("linked", "refs-today-linked.json"),
            ("moved", "refs-today-moved.json"),
            ("already", "refs-today-already-current.json"),
            ("guarded", "refs-today-link-guard.json"),
        ]
        for (name, fixtureName) in toastFixtures {
            let toast = try XCTUnwrap(RefsTodayLinkPresentation.toast(
                response: fixture(fixtureName), title: "Attention Is All You Need"
            ))
            let view = RefsGlassToastView(
                title: toast.title,
                value: toast.value,
                detail: toast.detail,
                style: .today(toast.style),
                previewMode: true
            )
            .frame(width: 420)
            for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
                try RenderFixtureWriter.write(
                    view,
                    name: "refs-today-link-toast-\(name)",
                    width: 420,
                    appearance: appearance
                )
            }
        }
    }

    private func makeCard() -> RefsTodayLinkCard {
        RefsTodayLinkCard(item: RefItem(
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
        ))
    }

    private func fixture(_ name: String) throws -> RefsTodayLinkResponse {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        return try JSONDecoder().decode(RefsTodayLinkResponse.self, from: data)
    }
}
