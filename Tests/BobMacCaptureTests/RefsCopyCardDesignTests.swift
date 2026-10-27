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
        try write(card: underlinedPickerCard(), name: "refs-copy-highlight-picker-underline")
        try write(
            card: groupedHighlightPickerCard(),
            name: "refs-copy-highlight-picker-sections"
        )
        try write(card: alternatesCard(), name: "refs-copy-card-alternates", alternates: true)
        try write(card: alternatesCard(), name: "refs-copy-card-home-paths")
        try write(
            card: highlightPickerCard(), name: "refs-copy-picker-alternates", alternates: true)
        try write(card: codeRowsCard(), name: "refs-copy-card-code-rows")
        try write(card: try codePickerCard(), name: "refs-copy-code-picker")
        try write(
            card: try codePickerCard(), name: "refs-copy-code-picker-fenced", alternates: true)
        try write(card: try mermaidPickerCard(), name: "refs-copy-code-picker-mermaid")
        try write(card: try longLinePickerCard(), name: "refs-copy-code-picker-long-line")
        try write(card: loadingCodeCard(), name: "refs-copy-card-code-loading")
        try write(card: try noCodeCard(), name: "refs-copy-card-no-code")
        try write(card: try linkRowsCard(), name: "refs-copy-card-link-rows")
        try write(card: try linkPickerCard(), name: "refs-copy-link-picker")
        try write(
            card: try linkPickerCard(),
            name: "refs-copy-link-picker-open",
            linkOpenActive: true
        )
        try write(
            card: try linkPickerCard(), name: "refs-copy-link-picker-markdown", alternates: true)
        try write(card: try urlLabelPickerCard(), name: "refs-copy-link-picker-url-label")
        try write(card: longLinkPickerCard(), name: "refs-copy-link-picker-long-line")
        try write(card: loadingLinksCard(), name: "refs-copy-card-links-loading")
        try write(card: linksNotRecordedCard(), name: "refs-copy-card-links-not-recorded")
        try writeHUD(
            title: "Copied link · ai.google.dev",
            value: "https://ai.google.dev/gemini-api/docs/imagen",
            name: "refs-copy-hud-link")
        try writeHUD(
            title: "Copied 8 links",
            value: "https://developers.openai.com/docs/image-generation…",
            name: "refs-copy-hud-links-all")
        try writeHUD()
        try writeHUD(
            title: "Copied yaml · 14 lines", value: "refresh:", name: "refs-copy-hud-code")
        try writeHUD(
            title: "Copied yaml · fenced", value: "refresh:", name: "refs-copy-hud-code-fenced")
        try writeHUD(
            title: "Copied Markdown · 41 KB",
            value: "source.md",
            name: "refs-copy-hud-markdown"
        )
    }

    private func write(
        card: RefsCopyCard,
        name: String,
        alternates: Bool = false,
        linkOpenActive: Bool = false
    ) throws {
        let width = inspectorColumnWidth
        let view = RefsCopyCardView(
            card: card,
            alternatesActive: alternates,
            linkOpenActive: linkOpenActive,
            previewMode: true
        )
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

    private func writeHUD(
        title: String = "Copied Marker ID",
        value: String = "marker-chat-1",
        name: String = "refs-copy-hud"
    ) throws {
        let view = RefsCopyHUDView(
            title: title,
            value: value,
            previewMode: true
        )
        .frame(width: 420)
        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            try RenderFixtureWriter.write(
                view,
                name: name,
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

    private func underlinedPickerCard() -> RefsCopyCard {
        let item = makeItem(
            id: "ref/blogs/redesigning_source_control.md",
            link: "[[ref/blogs/redesigning_source_control]]",
            markerID: .present("blog-id"),
            title: "Redesigning source control",
            kind: .article,
            commentCount: 2
        )
        let annotations = [
            RefsShowAnnotation(
                pageLabel: "Page 4",
                kind: "highlight",
                quote:
                    "**all of our clients were agents and jobs that are "
                    + "online by definition.** They are **always online**.",
                link: "[[ref/blogs/redesigning_source_control#^h-1]]"
            ),
            RefsShowAnnotation(
                pageLabel: "Page 5",
                kind: "highlight",
                quote:
                    "Source control for huge monorepos has **prior art, "
                    + "notably Google’s Piper and Meta’s Sapling,2** so we "
                    + "were able to build Scion with their hard-won lessons "
                    + "in mind.",
                comment: "Cite the prior art.",
                link: "[[ref/blogs/redesigning_source_control#^h-2]]"
            ),
            RefsShowAnnotation(
                pageLabel: "Page 2",
                kind: "highlight",
                quote:
                    "In order to support this growth, we built Scion, an "
                    + "in-house version control system.",
                link: "[[ref/blogs/redesigning_source_control#^h-3]]"
            ),
        ]
        var card = RefsCopyCard(
            token: 8,
            item: item,
            absolutePDFPath: "/vault/lib/blogs/redesigning_source_control.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: item.id, annotations: annotations)),
            noteCapacity: 4,
            pickerWindowSize: 9
        )
        _ = card.handle(.key(.highlightPicker))
        return card
    }

    private func groupedHighlightPickerCard() -> RefsCopyCard {
        let item = makeItem(
            id: "ref/articles/sections_preview.md",
            link: "[[ref/articles/sections_preview]]",
            markerID: .present("sections-id"),
            title: "Synthetic Sections Preview",
            kind: .article,
            commentCount: 4
        )
        let annotations = [
            RefsShowAnnotation(
                pageLabel: "Page 4",
                kind: "highlight",
                quote: "Make a point about how if I were building AI from scratch.",
                section: "memory"
            ),
            RefsShowAnnotation(
                pageLabel: "Page 5",
                kind: "highlight",
                quote: "Mention that you've implemented project memory every wrong way.",
                comment: "Compare with the intro",
                section: "memory"
            ),
            RefsShowAnnotation(
                pageLabel: "Page 4",
                kind: "highlight",
                quote: "A visuals quote that still copies.",
                section: "visuals"
            ),
            RefsShowAnnotation(
                pageLabel: "Page 4",
                kind: "highlight",
                quote: "POTENTIAL QUOTES: keep these ungrouped."
            ),
            RefsShowAnnotation(
                pageLabel: "Page 8",
                kind: "note",
                comment: "A standalone note in the ungrouped tail."
            ),
        ]
        var card = RefsCopyCard(
            token: 9,
            item: item,
            absolutePDFPath: "/vault/lib/articles/sections_preview.pdf",
            pdfExists: true,
            notes: .loaded(
                RefsShowRow(
                    path: item.id,
                    sections: [
                        RefsShowSection(
                            id: "memory", title: "Memory", tag: "@memory", count: 2
                        ),
                        RefsShowSection(
                            id: "visuals", title: "Visuals", tag: "@visuals", count: 1
                        ),
                    ],
                    annotations: annotations
                )
            ),
            noteCapacity: 4,
            pickerWindowSize: 9,
            pickerGroupHeaderHeight: RefsCopyCardLayout.pickerGroupHeaderHeight,
            pickerRowHeight: Double(RefsVisualTokens.copyCardPickerRowHeight)
        )
        _ = card.handle(.key(.highlightPicker))
        _ = card.handle(.move(1))
        _ = card.handle(.move(1))
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

    private func codeRowsCard() throws -> RefsCopyCard {
        RefsCopyCard(
            token: 20,
            item: makeCodeItem(),
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5,
            code: .loaded(try decodeCode()),
            highlightedPage: 7
        )
    }

    private func codePickerCard(page: Int? = 7) throws -> RefsCopyCard {
        var card = RefsCopyCard(
            token: 21,
            item: makeCodeItem(),
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5,
            pickerWindowSize: 9,
            pickerGroupHeaderHeight: RefsCopyCardLayout.pickerGroupHeaderHeight,
            pickerRowHeight: Double(RefsVisualTokens.copyCardPickerRowHeight),
            code: .loaded(try decodeCode()),
            highlightedPage: page
        )
        _ = card.handle(.key(.codePicker))
        return card
    }

    private func mermaidPickerCard() throws -> RefsCopyCard {
        var card = try codePickerCard(page: 7)
        _ = card.handle(.move(1))
        _ = card.handle(.move(1))
        return card
    }

    private func longLinePickerCard() throws -> RefsCopyCard {
        try codePickerCard(page: 11)
    }

    private func loadingCodeCard() -> RefsCopyCard {
        RefsCopyCard(
            token: 22,
            item: makeCodeItem(),
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5,
            code: .loading,
            highlightedPage: 7
        )
    }

    private func noCodeCard() throws -> RefsCopyCard {
        RefsCopyCard(
            token: 23,
            item: makeCodeItem(),
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5,
            code: .loaded(try decodeCode(named: "refs-code-no-code.json")),
            highlightedPage: 7
        )
    }

    private func linkRowsCard() throws -> RefsCopyCard {
        RefsCopyCard(
            token: 30,
            item: makeLinkItem(),
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5,
            code: .loaded(try decodeCode()),
            links: .loaded(try decodeLinks()),
            highlightedPage: 7
        )
    }

    private func linkPickerCard(page: Int? = 7) throws -> RefsCopyCard {
        var card = RefsCopyCard(
            token: 31,
            item: makeLinkItem(),
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5,
            pickerWindowSize: 9,
            pickerGroupHeaderHeight: RefsCopyCardLayout.pickerGroupHeaderHeight,
            pickerRowHeight: Double(RefsVisualTokens.copyCardPickerRowHeight),
            links: .loaded(try decodeLinks()),
            highlightedPage: page
        )
        _ = card.handle(.key(.markdownLink))
        return card
    }

    private func urlLabelPickerCard() throws -> RefsCopyCard {
        var card = try linkPickerCard(page: 7)
        _ = card.handle(.move(1))
        _ = card.handle(.move(1))
        return card
    }

    private func longLinkPickerCard() -> RefsCopyCard {
        let longURL =
            "https://example.com/reports/2026/agent-image-generation-toolset"
            + "/appendix-a/methodology-and-ablations?source=highlights&sort=desc#section-4"
        let item = makeLinkItem()
        let response = RefsLinksResponse(
            reference: RefsCodeReference(path: item.id, title: item.rawTitle),
            status: .available,
            links: [
                RefsLink(
                    number: 1,
                    url: "https://developers.openai.com/docs/image-generation",
                    label: "OpenAI image guide",
                    site: "developers.openai.com",
                    markdown:
                        "[OpenAI image guide](https://developers.openai.com/docs/image-generation)",
                    section: RefsCodeSection(number: "3", title: "Prior art"),
                    page: 6,
                    pageSource: "anchor"
                ),
                RefsLink(
                    number: 2,
                    url: longURL,
                    label: "Appendix A methodology and ablations",
                    site: "example.com",
                    markdown: "[Appendix A methodology and ablations](\(longURL))",
                    section: RefsCodeSection(number: "9", title: "Appendix"),
                    page: 7,
                    pageSource: "anchor"
                ),
            ]
        )
        var card = RefsCopyCard(
            token: 32,
            item: item,
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5,
            pickerWindowSize: 9,
            pickerGroupHeaderHeight: RefsCopyCardLayout.pickerGroupHeaderHeight,
            pickerRowHeight: Double(RefsVisualTokens.copyCardPickerRowHeight),
            links: .loaded(response),
            highlightedPage: 7
        )
        _ = card.handle(.key(.markdownLink))
        return card
    }

    private func loadingLinksCard() -> RefsCopyCard {
        RefsCopyCard(
            token: 33,
            item: makeLinkItem(),
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5,
            links: .loading,
            highlightedPage: 7
        )
    }

    private func linksNotRecordedCard() -> RefsCopyCard {
        let item = makeLinkItem()
        return RefsCopyCard(
            token: 34,
            item: item,
            absolutePDFPath: "/vault/lib/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")),
            noteCapacity: 5,
            links: .loaded(
                RefsLinksResponse(
                    reference: RefsCodeReference(path: item.id, title: item.rawTitle),
                    status: .notRecorded,
                    detail: "links were not recorded for this reference; run bob ref recatalog",
                    links: []
                )
            ),
            highlightedPage: 7
        )
    }

    private func makeLinkItem() -> RefItem {
        makeItem(
            markerID: .present("example"),
            title: "Agent Image Generation Toolset",
            sourceMarkdown: ".bob/ref-sources/chat/example--abc123/source.md"
        )
    }

    private func makeCodeItem() -> RefItem {
        makeItem(
            markerID: .present("example"),
            title: "Why sase ace Is Slow",
            sourceMarkdown: ".bob/ref-sources/chat/example--abc123/source.md"
        )
    }

    private func decodeCode(named fixture: String = "refs-code.json") throws -> RefsCodeResponse {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/\(fixture)")
        )
        return try JSONDecoder().decode(RefsCodeResponse.self, from: data)
    }

    private func decodeLinks(path: String = "ref/chat/example.md") throws -> RefsLinksResponse {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/refs-links.json")
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        if var reference = json["reference"] as? [String: Any] {
            reference["path"] = path
            json["reference"] = reference
        }
        let patched = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(RefsLinksResponse.self, from: patched)
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
        task: RefTask? = nil,
        sourceMarkdown: String? = nil
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
            sourceMarkdown: sourceMarkdown,
            task: task,
            annotationCount: annotationCount,
            commentCount: commentCount,
            urls: urls,
            arxivID: arxivID,
            doi: doi
        )
    }
}
