import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import BobMacCapture
@testable import RefsCore

/// Rendered-image review for the Copy card and HUD at inspector-column
/// width, light and dark, through `RenderFixtureWriter`.
@MainActor
final class RefsCopyCardDesignTests: XCTestCase {
    func testCopyCardAndHUDFixturesToPNG() throws {
        try write(card: chatCard(), name: "refs-copy-card-chat")
        try write(card: annotatedPaperCard(), name: "refs-copy-card-paper-notes")
        try write(card: sharedMissingPDFCard(), name: "refs-copy-card-shared-missing")
        try write(card: overflowCard(), name: "refs-copy-card-notes-overflow")
        try write(card: loadingQueuedCard(), name: "refs-copy-card-notes-loading")
        try write(card: errorCard(), name: "refs-copy-card-error")
        try write(card: highlightPickerCard(), name: "refs-copy-highlight-picker")
        try write(card: alternatesCard(), name: "refs-copy-card-alternates", alternates: true)
        try write(card: alternatesCard(), name: "refs-copy-card-home-paths")
        try write(
            card: highlightPickerCard(), name: "refs-copy-picker-alternates", alternates: true)
        try writeHUD()
    }

    private func write(card: RefsCopyCard, name: String, alternates: Bool = false) throws {
        let width = inspectorColumnWidth
        let view = RefsCopyCardView(card: card, alternatesActive: alternates, previewMode: true)
            .frame(width: width, height: 480, alignment: .top)
        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            try RenderFixtureWriter.write(
                view,
                name: name,
                width: width,
                appearance: appearance
            )
        }
    }

    private func writeHUD() throws {
        let view = RefsCopyHUDView(
            title: "Copied Marker ID",
            value: "marker-chat-1",
            previewMode: true
        )
        .frame(width: 420)
        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            try RenderFixtureWriter.write(
                view,
                name: "refs-copy-hud",
                width: 420,
                appearance: appearance
            )
        }
    }

    private var inspectorColumnWidth: CGFloat {
        880 - RefsVisualTokens.listWidth(panelWidth: 880)
    }

    private func chatCard() -> RefsCopyCard {
        RefsCopyCard(
            token: 1,
            item: makeItem(
                markerID: .present("marker-chat-1"),
                title: "Team Fit Review",
                task: RefTask(
                    path: "sase.md",
                    link: "[[sase#^team-fit]]"
                )
            ),
            absolutePDFPath: "/vault/lib/chat/team_fit_review.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5
        )
    }

    private func annotatedPaperCard() -> RefsCopyCard {
        let item = makeItem(
            id: "ref/papers/harness_buy.md",
            link: "[[ref/papers/harness_buy]]",
            markerID: .present("paper-id"),
            title: "What Does a Harness Buy You?",
            kind: .paper,
            commentCount: 2,
            urls: ["https://arxiv.org/abs/2501.01234"],
            arxivID: "2501.01234",
            doi: "10.1000/example",
            researchRef: "research:papers/harness_buy.md"
        )
        let notes = RefsShowRow(
            path: item.id,
            annotations: [
                RefsShowAnnotation(
                    pageLabel: "Page 11",
                    kind: "highlight",
                    quote: "the dolla dolla bills didn't hurt",
                    comment: "Replace with cash and cool 😎 .",
                    blockID: "^h-bf02e5a34bcb",
                    link: "[[ref/papers/harness_buy#^h-bf02e5a34bcb]]"
                ),
                RefsShowAnnotation(
                    pageLabel: "Page 28",
                    kind: "highlight",
                    quote: "Quoted",
                    comment: "First line\nSecond line",
                    blockID: "^h-1",
                    link: "[[ref/papers/harness_buy#^h-1]]"
                ),
            ],
            ownNotes: "Keep the provenance line."
        )
        return RefsCopyCard(
            token: 2,
            item: item,
            absolutePDFPath: "/vault/lib/papers/harness_buy.pdf",
            pdfExists: true,
            notes: .loaded(notes),
            noteCapacity: 6
        )
    }

    private func sharedMissingPDFCard() -> RefsCopyCard {
        RefsCopyCard(
            token: 3,
            item: makeItem(
                markerID: .present("shared-id"),
                markerIDShareCount: 3,
                title: "Weekly links roundup"
            ),
            absolutePDFPath: "/vault/lib/chat/weekly_links.pdf",
            pdfExists: false,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5
        )
    }

    private func overflowCard() -> RefsCopyCard {
        let item = makeItem(
            id: "ref/papers/overflow.md",
            link: "[[ref/papers/overflow]]",
            markerID: .present("overflow-id"),
            title: "Notes that overflow the card",
            kind: .paper,
            commentCount: 5
        )
        let annotations = (1...5).map { index in
            RefsShowAnnotation(
                pageLabel: "Page \(index * 4)",
                kind: "highlight",
                quote: "Quote \(index)",
                comment: "Comment \(index)",
                link: "[[ref/papers/overflow#^h-\(index)]]"
            )
        }
        return RefsCopyCard(
            token: 4,
            item: item,
            absolutePDFPath: "/vault/lib/papers/overflow.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: item.id, annotations: annotations)),
            noteCapacity: 3
        )
    }

    private func loadingQueuedCard() -> RefsCopyCard {
        var card = RefsCopyCard(
            token: 5,
            item: makeItem(
                markerID: .present("loading-id"),
                title: "Waiting for notes",
                annotationCount: 4,
                commentCount: 2
            ),
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loading,
            noteCapacity: 5
        )
        _ = card.handle(.key(.note(1)))
        return card
    }

    private func errorCard() -> RefsCopyCard {
        var card = chatCard()
        card.writeFailed(key: .wikiLink)
        return card
    }

    private func highlightPickerCard() -> RefsCopyCard {
        let item = makeItem(
            id: "ref/papers/harness_buy.md",
            link: "[[ref/papers/harness_buy]]",
            markerID: .present("paper-id"),
            title: "What Does a Harness Buy You?",
            kind: .paper,
            commentCount: 8
        )
        let annotations: [RefsShowAnnotation] = (1...29).map { index in
            if index == 7 {
                return RefsShowAnnotation(
                    pageLabel: "Page \(index)",
                    kind: "note",
                    comment: "Standalone note \(index)",
                    link: "[[ref/papers/harness_buy#^n-\(index)]]"
                )
            }
            let commented = index.isMultiple(of: 3)
            return RefsShowAnnotation(
                pageLabel: "Page \(index)",
                kind: "highlight",
                quote: "Quote \(index) that is long enough to truncate in the picker window",
                comment: commented ? "Comment \(index) on this highlight" : nil,
                link: "[[ref/papers/harness_buy#^h-\(index)]]"
            )
        }
        var card = RefsCopyCard(
            token: 6,
            item: item,
            absolutePDFPath: "/vault/lib/papers/harness_buy.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: item.id, annotations: annotations)),
            noteCapacity: 4,
            pickerWindowSize: 9
        )
        _ = card.handle(.key(.highlightPicker))
        for _ in 0..<14 {
            _ = card.handle(.move(1))
        }
        return card
    }

    private func alternatesCard() -> RefsCopyCard {
        let item = makeItem(markerID: .present("marker-chat-1"), title: "Team Fit Review")
        return RefsCopyCard(
            token: 7, item: item,
            absolutePDFPath: "/Users/bryan/bob/lib/chat/team_fit_review.pdf", pdfExists: true,
            notes: .loaded(
                RefsShowRow(
                    path: item.id,
                    annotations: [
                        RefsShowAnnotation(
                            pageLabel: "Page 11", kind: "highlight", quote: "Keep the exact quote.",
                            comment: "A comment that Option hides.",
                            link: "[[ref/chat/example#^h-1]]"
                        )
                    ])), noteCapacity: 3,
            absoluteNotePath: "/Users/bryan/bob/" + item.id, homeDirectoryPath: "/Users/bryan",
            narrationFileURL: URL(fileURLWithPath: "/Users/bryan/bob/lib/chat/team_fit_review.m4a")
        )
    }

    private func makeItem(
        id: String = "ref/chat/example.md",
        link: String = "[[ref/chat/example]]",
        markerID: RefMarkerID = .unsupported,
        markerIDShareCount: Int = 1,
        title: String = "Example",
        kind: RefKind = .chat,
        annotationCount: Int = 0,
        commentCount: Int = 0,
        urls: [String] = [],
        arxivID: String? = nil,
        doi: String? = nil,
        researchRef: String? = nil,
        task: RefTask? = nil
    ) -> RefItem {
        RefItem(
            id: id,
            link: link,
            rawTitle: title,
            stem: "example",
            markerID: markerID,
            markerIDShareCount: markerIDShareCount,
            researchRef: researchRef,
            kind: kind,
            state: .ready,
            isBlocked: false,
            pdfPath: "lib/chat/example.pdf",
            task: task,
            annotationCount: annotationCount,
            commentCount: commentCount,
            urls: urls,
            arxivID: arxivID,
            doi: doi
        )
    }
}
