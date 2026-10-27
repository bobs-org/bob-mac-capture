import Foundation
import XCTest

@testable import RefsCore

final class RefsLinksTests: XCTestCase {
    func testGoldenEnvelopeDecodesComputedFieldsAndIgnoresFutureKeys() throws {
        let response = try decodeGolden()

        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.reference.path, "ref/papers/demo.md")
        XCTAssertEqual(response.reference.title, "Demo")
        XCTAssertEqual(response.status, .available)
        XCTAssertEqual(
            response.source?.path,
            ".bob/ref-sources/papers/demo--8b3d3805c049/source.md"
        )
        XCTAssertEqual(response.links.count, 9)

        let imagen = response.links[1]
        XCTAssertEqual(imagen.id, "8b3d3805c049/link-2")
        XCTAssertEqual(imagen.number, 2)
        XCTAssertEqual(imagen.url, "https://ai.google.dev/gemini-api/docs/imagen")
        XCTAssertEqual(imagen.text, "Imagen 4 model card")
        XCTAssertNil(imagen.title)
        XCTAssertFalse(imagen.autolink)
        XCTAssertEqual(imagen.label, "Imagen 4 model card")
        XCTAssertEqual(imagen.labelKind, .text)
        XCTAssertEqual(imagen.site, "ai.google.dev")
        XCTAssertEqual(
            imagen.markdown,
            "[Imagen 4 model card](https://ai.google.dev/gemini-api/docs/imagen)"
        )
        XCTAssertEqual(imagen.section?.heading, "4  Image models")
        XCTAssertEqual(imagen.page, 7)
        XCTAssertEqual(imagen.pageSource, "anchor")

        XCTAssertEqual(response.links[2].label, "Sources")
        XCTAssertEqual(response.links[2].labelKind, .context)
        XCTAssertEqual(response.links[2].site, "github.com")
        XCTAssertEqual(
            response.links[2].markdown,
            "<https://www.github.com/black-forest-labs/flux>"
        )

        XCTAssertEqual(response.links[3].label, "example.com/bare")
        XCTAssertEqual(response.links[3].labelKind, .url)
        XCTAssertEqual(response.links[4].label, "me@example.com")
        XCTAssertEqual(response.links[4].site, "email")
        XCTAssertEqual(response.links[4].markdown, "<me@example.com>")
        XCTAssertEqual(response.links[5].site, "obsidian")
        XCTAssertNil(response.links[5].page)
        XCTAssertEqual(
            response.links[6].markdown,
            "[see \\[this\\] path](<https://example.com/a b>)"
        )
        XCTAssertEqual(
            response.links[7].markdown,
            "[slash \\\\ brackets](<https://example.com/foo(bar>)"
        )
    }

    func testOlderPayloadMissingOptionalFieldsStillDecodes() throws {
        let response = try JSONDecoder().decode(
            RefsLinksResponse.self,
            from: Data(
                #"{"reference":{"path":"ref/papers/demo.md"},"status":"available","links":[{"n":1,"url":"https://example.com"}]}"#
                    .utf8)
        )
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.links.count, 1)
        XCTAssertEqual(response.links[0].url, "https://example.com")
        XCTAssertEqual(response.links[0].label, "https://example.com")
        XCTAssertEqual(response.links[0].markdown, "https://example.com")
        XCTAssertEqual(response.links[0].site, "")
    }

    func testEnvelopeSkipsMalformedLinksButKeepsTheRest() throws {
        let response = try JSONDecoder().decode(
            RefsLinksResponse.self,
            from: Data(
                #"{"reference":{"path":"ref/papers/demo.md"},"status":"available","links":[42,{"n":1,"url":"https://kept.example"},{"n":"bad"}]}"#
                    .utf8)
        )
        XCTAssertEqual(response.links.map(\.number), [1])
        XCTAssertEqual(response.links.first?.url, "https://kept.example")
    }

    func testEveryStatusDecodes() throws {
        let cases: [(String, RefsLinksStatus)] = [
            ("available", .available),
            ("no_links", .noLinks),
            ("not_recorded", .notRecorded),
            ("no_catalog", .noCatalog),
            ("no_source", .noSource),
            ("source_missing", .sourceMissing),
            ("source_invalid", .sourceInvalid),
            ("mystery", .unknown),
        ]
        for (raw, expected) in cases {
            let response = try decodeStatus(raw)
            XCTAssertEqual(response.status, expected, raw)
        }
    }

    func testLKeyRemainsMarkdownLinkWithoutSavedMarkdown() throws {
        XCTAssertEqual(RefsCopyKey.parse("l"), .markdownLink)
        XCTAssertEqual(RefsCopyKey.parse("L"), .markdownLink)
        XCTAssertEqual(RefsCopyKey.linkPicker.glyph, "L")

        let item = makeItem(sourceMarkdown: nil, urls: ["https://example.test/a"])
        let catalog = RefsCopyCatalog(
            item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0
        )
        XCTAssertNotNil(catalog.row(for: .markdownLink))
        XCTAssertNil(catalog.row(for: .linkPicker))
        XCTAssertEqual(
            catalog.row(for: .sourceURL)?.alternate?.label,
            "Markdown link"
        )
        var card = makeCard(item: item)
        let markdown = try XCTUnwrap(catalog.row(for: .markdownLink))
        XCTAssertEqual(
            card.handle(try XCTUnwrap(RefsCopyEntry.links.seedCommand)),
            .write(markdown)
        )
    }

    func testCopyEntrySeedsMatchCommandYFollowUpKeys() {
        XCTAssertEqual(RefsCopyEntry.card.seedCommand, nil)
        XCTAssertEqual(RefsCopyEntry.card.retryGlyph, "⌘Y")
        XCTAssertEqual(RefsCopyEntry.code.seedCommand, .key(.codePicker))
        XCTAssertEqual(RefsCopyEntry.code.retryGlyph, "⌘B")
        XCTAssertEqual(RefsCopyEntry.links.seedCommand, .key(.markdownLink))
        XCTAssertEqual(RefsCopyEntry.links.retryGlyph, "⌘L")
    }

    func testLKeyResolvesToLinkPickerWhenMarkdownIsSaved() throws {
        let item = makeItem(
            sourceMarkdown: ".bob/ref-sources/papers/demo--8b3d3805c049/source.md",
            urls: ["https://example.test/a"]
        )
        let response = try decodeGolden()
        let catalog = RefsCopyCatalog(
            item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0, links: .loaded(response),
            highlightedPage: 7
        )
        XCTAssertNil(catalog.row(for: .markdownLink))
        let linkRow = try XCTUnwrap(catalog.row(for: .linkPicker))
        XCTAssertEqual(linkRow.group, .contents)
        XCTAssertEqual(linkRow.label, "Link…")
        XCTAssertEqual(
            linkRow.preview,
            "9 links · ● 3 on this page · example.com, ai.google.dev, developers.openai.com"
        )
        XCTAssertEqual(linkRow.truncation, .tail)
        let linkDotRange = try XCTUnwrap(linkRow.onPageDotRange)
        XCTAssertEqual(String(linkRow.preview[linkDotRange]), "●")
        XCTAssertTrue(linkRow.preview[linkDotRange.upperBound...].hasPrefix(" 3 on this page"))
        let source = try XCTUnwrap(catalog.row(for: .sourceURL))
        XCTAssertEqual(source.alternate?.label, "Markdown link")
        XCTAssertEqual(
            source.resolved(alternate: true).payload,
            .text("[Demo](https://example.test/a)")
        )
        XCTAssertEqual(
            source.resolved(alternate: true).confirmationTitle,
            "Copied Markdown Link"
        )

        var card = makeCard(item: item, links: .loaded(response), highlightedPage: 7)
        XCTAssertEqual(
            card.handle(try XCTUnwrap(RefsCopyEntry.links.seedCommand)),
            .none
        )
        XCTAssertEqual(card.selectedKey, .linkPicker)
        XCTAssertEqual(card.linkPicker?.selectedEntry?.link.number, 2)
    }

    func testOptionUCopiesMarkdownLinkFromTheCard() throws {
        let item = makeItem(
            sourceMarkdown: ".bob/ref-sources/papers/demo--8b3d3805c049/source.md",
            urls: ["https://example.test/a"]
        )
        var card = makeCard(item: item, links: .loaded(try decodeGolden()))
        let source = try XCTUnwrap(card.catalog.row(for: .sourceURL))
        XCTAssertEqual(
            card.handle(.key(.sourceURL, alternate: true)),
            .write(source.resolved(alternate: true))
        )
    }

    func testRowVisibilityAndHiddenReasonsForEachState() throws {
        let item = makeItem(
            sourceMarkdown: ".bob/ref-sources/papers/demo--8b3d3805c049/source.md"
        )
        let loading = RefsCopyCatalog(
            item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0, links: .loading
        )
        XCTAssertEqual(loading.row(for: .linkPicker)?.preview, "Loading links…")
        XCTAssertNil(loading.hiddenReason(for: .linkPicker))

        let available = RefsCopyCatalog(
            item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0, links: .loaded(try decodeGolden())
        )
        XCTAssertNotNil(available.row(for: .linkPicker))
        XCTAssertNil(available.hiddenReason(for: .linkPicker))

        let expected: [(RefsLinksLoadState, String)] = [
            (.loaded(try decodeStatus("no_links")), "No links in this reference"),
            (
                .loaded(try decodeStatus("not_recorded")),
                "Links weren't recorded for this reference yet — bob ref recatalog"
            ),
            (
                .loaded(try decodeStatus("no_catalog")),
                "Links weren't recorded for this reference — M copies its Markdown"
            ),
            (
                .loaded(try decodeStatus("no_source")),
                "No saved Markdown — link copy needs a reference bob rendered from Markdown"
            ),
            (
                .loaded(try decodeStatus("source_missing")),
                "Saved Markdown isn't on this Mac yet — sync the vault"
            ),
            (
                .loaded(try decodeStatus("source_invalid")),
                "Saved Markdown doesn't match its digest — run bob ref doctor"
            ),
            (.unsupported, "Link copy needs a newer bob"),
            (.failed, "Links unavailable — nothing copied"),
            (.notRequested, "Links unavailable — nothing copied"),
        ]
        for (state, message) in expected {
            let catalog = RefsCopyCatalog(
                item: item, absolutePDFPath: nil, pdfExists: false,
                notes: .unavailable, noteCapacity: 0, links: state
            )
            XCTAssertNil(catalog.row(for: .linkPicker), message)
            XCTAssertEqual(catalog.hiddenReason(for: .linkPicker), message)
        }

        let web = RefsCopyCatalog(
            item: makeItem(sourceMarkdown: nil), absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0
        )
        XCTAssertEqual(
            web.hiddenReason(for: .markdownLink),
            "No source URL for this reference"
        )
    }

    func testContentsGroupKeepsCLMOrderWhileLoadsFinishIndependently() throws {
        let item = RefItem(
            id: "ref/chat/example.md",
            link: "[[ref/chat/example]]",
            rawTitle: "Example",
            stem: "example",
            markerID: .absent,
            kind: .chat,
            state: .ready,
            isBlocked: false,
            pdfPath: "ref/chat/example.pdf",
            sourceMarkdown: ".bob/ref-sources/chat/example--abc123/source.md"
        )
        let code = try JSONDecoder().decode(
            RefsCodeResponse.self,
            from: RefsModelTests.fixtureData("refs-code.json")
        )
        let catalog = RefsCopyCatalog(
            item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0,
            code: .loaded(code), links: .loading, highlightedPage: 7
        )
        XCTAssertEqual(
            catalog.rows.filter { $0.group == .contents }.map(\.key),
            [.codePicker, .linkPicker, .sourceMarkdown]
        )
        XCTAssertEqual(catalog.row(for: .linkPicker)?.preview, "Loading links…")
        XCTAssertEqual(catalog.row(for: .codePicker)?.label, "Code block…")
    }

    func testLinkPickerSelectsPageAndKeepsSectionHeaders() throws {
        let links = try decodeGolden().links
        let picker = RefsLinkPicker(
            links: links,
            highlightedPage: 7,
            windowSize: 3,
            groupHeaderHeight: 22,
            entryRowHeight: 36
        )
        XCTAssertEqual(picker.selectedIndex, 1)
        XCTAssertEqual(picker.selectedEntry?.link.number, 2)
        XCTAssertTrue(picker.selectedEntry?.isOnPage == true)
        XCTAssertEqual(picker.pageLinkCount, 3)
        XCTAssertTrue(
            picker.windowRows.contains { row in
                if case .group(let title) = row { return title == "4  Image models" }
                return false
            })
        XCTAssertEqual(picker.openingVoiceOverLabel, "Links. Press a number or Return.")
        XCTAssertEqual(
            picker.selectedEntry?.voiceOverLabel(index: 2, total: 9, key: 1),
            "Link 2 of 9, Imagen 4 model card, ai.google.dev, page 7, on this page, key 1"
        )

        XCTAssertEqual(RefsLinkPicker.initialSelection(in: links, page: 4), 0)
        XCTAssertEqual(RefsLinkPicker.initialSelection(in: links, page: 8), 4)
        XCTAssertEqual(RefsLinkPicker.initialSelection(in: links, page: 10), 8)
        XCTAssertEqual(RefsLinkPicker.initialSelection(in: links, page: nil), 0)

        let withPageless = [
            makeLink(number: 1, url: "https://a.example/1", label: "A", site: "a.example", page: 2),
            makeLink(number: 2, url: "https://a.example/2", label: "B", site: "a.example", page: nil),
            makeLink(number: 3, url: "https://a.example/3", label: "C", site: "a.example", page: 5),
        ]
        XCTAssertEqual(RefsLinkPicker.initialSelection(in: withPageless, page: 3), 2)
        XCTAssertEqual(RefsLinkPicker.initialSelection(in: withPageless, page: 5), 2)
        XCTAssertEqual(RefsLinkPicker.initialSelection(in: withPageless, page: 1), 0)
    }

    func testCopyPayloadsAreExactPlainMarkdownAllAndOptionAll() throws {
        let picker = RefsLinkPicker(links: try decodeGolden().links)
        let imagen = try XCTUnwrap(picker.entries[1])
        XCTAssertEqual(
            imagen.copyRow(markdown: false).payload,
            .text("https://ai.google.dev/gemini-api/docs/imagen")
        )
        XCTAssertEqual(
            imagen.copyRow(markdown: false).confirmationTitle,
            "Copied link · ai.google.dev"
        )
        XCTAssertEqual(
            imagen.copyRow(markdown: true).payload,
            .text("[Imagen 4 model card](https://ai.google.dev/gemini-api/docs/imagen)")
        )
        XCTAssertEqual(
            imagen.copyRow(markdown: true).confirmationTitle,
            "Copied Markdown link · ai.google.dev"
        )

        let all = picker.allLinksRow(markdown: false)
        XCTAssertEqual(
            all.payload,
            .text(
                """
                https://developers.openai.com/docs/image-generation
                https://ai.google.dev/gemini-api/docs/imagen
                https://www.github.com/black-forest-labs/flux
                https://example.com/bare
                mailto:me@example.com
                obsidian://open?vault=bob
                https://example.com/a b
                https://example.com/foo(bar
                """
            )
        )
        XCTAssertEqual(all.confirmationTitle, "Copied 8 links")
        let allMarkdown = picker.allLinksRow(markdown: true)
        XCTAssertEqual(
            allMarkdown.payload,
            .text(
                """
                - [OpenAI image guide](https://developers.openai.com/docs/image-generation)
                - [Imagen 4 model card](https://ai.google.dev/gemini-api/docs/imagen)
                - <https://www.github.com/black-forest-labs/flux>
                - <https://example.com/bare>
                - <me@example.com>
                - [open vault](obsidian://open?vault=bob)
                - [see \\[this\\] path](<https://example.com/a b>)
                - [slash \\\\ brackets](<https://example.com/foo(bar>)
                """
            )
        )
        XCTAssertEqual(allMarkdown.confirmationTitle, "Copied 8 links · Markdown")
        if case .text(let payload) = all.payload {
            XCTAssertFalse(payload.hasSuffix("\n"))
        }
    }

    func testPreviewWrapsStyledRunsAndReportsOverflow() {
        let url =
            "https://ai.google.dev/gemini-api/docs/imagen?hl=en#model-versions-extra"
        let link = makeLink(
            number: 1, url: url, label: "Imagen", site: "ai.google.dev",
            markdown: "[Imagen](\(url))", page: 7,
            section: RefsCodeSection(number: "4", title: "Image models")
        )

        let wrapped = RefsLinkPreview.wrap(
            "https://example.com/path/to/resource", columns: 20)
        XCTAssertEqual(wrapped.first, "https://example.com/")
        XCTAssertEqual(wrapped.dropFirst().joined(), "path/to/resource")

        let hard = RefsLinkPreview.wrap(String(repeating: "a", count: 25), columns: 10)
        XCTAssertEqual(hard, ["aaaaaaaaaa", "aaaaaaaaaa", "aaaaa"])

        let preview = RefsLinkPreview(link: link, markdown: false, columns: 20, visibleLines: 2)
        XCTAssertEqual(preview.site, "ai.google.dev")
        XCTAssertEqual(preview.sectionTitle, "Image models")
        XCTAssertEqual(preview.pageLabel, "p. 7")
        XCTAssertEqual(preview.voiceOverLabel, "Preview, link to ai.google.dev")
        XCTAssertEqual(preview.lines.first?.runs.first?.role, .scheme)
        let hostText = preview.lines.flatMap(\.runs).filter { $0.role == .host }.map(\.text)
            .joined()
        XCTAssertEqual(hostText, "ai.google.dev")
        XCTAssertGreaterThan(preview.overflowCharacterCount, 0)
        XCTAssertEqual(preview.lines.last?.isFaded, true)

        let unsplittable = makeLink(
            number: 2, url: "not a url", label: "plain", site: "x", page: nil)
        let plain = RefsLinkPreview(
            link: unsplittable, markdown: false, columns: 20, visibleLines: 2)
        XCTAssertEqual(plain.lines.first?.runs.map(\.role), [.plain])

        let markdown = RefsLinkPreview(link: link, markdown: true, columns: 80, visibleLines: 5)
        XCTAssertEqual(markdown.lines.first?.runs.first?.role, .markdownPunctuation)
        XCTAssertTrue(markdown.lines.contains { line in
            line.runs.contains { $0.role == .markdownText && $0.text == "Imagen" }
        })

        let autolink = makeLink(
            number: 3, url: "https://example.com/bare", label: "bare",
            site: "example.com", markdown: "<https://example.com/bare>", page: 1)
        let autoPreview = RefsLinkPreview(
            link: autolink, markdown: true, columns: 80, visibleLines: 3)
        XCTAssertEqual(autoPreview.lines.first?.runs.first?.role, .markdownPunctuation)
        XCTAssertEqual(autoPreview.lines.first?.runs.last?.role, .markdownPunctuation)
    }

    func testPreviewLayoutClampsBodyLinesAndPickerRows() {
        let short = RefsLinkPreviewLayout.make(
            availableHeightUnderHeader: 500,
            columns: 80,
            longestURL: "https://example.com"
        )
        XCTAssertEqual(short.bodyLines, 2)
        XCTAssertEqual(short.height, 50)
        XCTAssertEqual(short.pickerWindowSize, 9)

        let longURL = String(repeating: "https://example.com/very/long/path/", count: 8)
        let tall = RefsLinkPreviewLayout.make(
            availableHeightUnderHeader: 800,
            columns: 20,
            longestURL: longURL
        )
        XCTAssertEqual(tall.bodyLines, 5)
        XCTAssertEqual(tall.pickerWindowSize, 9)

        let tight = RefsLinkPreviewLayout.make(
            availableHeightUnderHeader: 80,
            columns: 80,
            longestURL: "https://example.com"
        )
        XCTAssertEqual(tight.pickerWindowSize, 2)
    }

    func testQueuedLReturnOpensPickerAndCopiesThePreselectedLink() throws {
        let item = makeItem(
            sourceMarkdown: ".bob/ref-sources/papers/demo--8b3d3805c049/source.md"
        )
        var card = makeCard(item: item, links: .loading, highlightedPage: 7)
        XCTAssertEqual(card.handle(.key(.markdownLink)), .none)
        XCTAssertEqual(card.pending, .linkPicker)
        XCTAssertEqual(card.message?.text, "Loading links… esc cancels")
        XCTAssertEqual(card.handle(.copySelected), .none)

        guard case .write(let row) = card.linksLoaded(
            path: item.id, response: try decodeGolden()
        ) else {
            return XCTFail("expected the preselected link to copy after load")
        }
        XCTAssertNil(card.pending)
        XCTAssertEqual(card.linkPicker?.selectedEntry?.link.number, 2)
        XCTAssertEqual(
            row.payload,
            .text("https://ai.google.dev/gemini-api/docs/imagen")
        )
        XCTAssertEqual(row.confirmationTitle, "Copied link · ai.google.dev")
    }

    func testLAfterLinksFailedShowsTheReasonAndCopiesNothing() throws {
        let item = makeItem(
            sourceMarkdown: ".bob/ref-sources/papers/demo--8b3d3805c049/source.md"
        )
        var card = makeCard(item: item, links: .loading)
        XCTAssertEqual(card.handle(.key(.markdownLink)), .none)
        card.linksFailed(path: item.id, unsupported: true)
        XCTAssertNil(card.pending)
        XCTAssertEqual(card.message?.text, "Link copy needs a newer bob")
        XCTAssertEqual(card.handle(.key(.markdownLink)), .none)
        XCTAssertEqual(card.message?.text, "Link copy needs a newer bob")
        XCTAssertNil(card.linkPicker)

        var failed = makeCard(item: item, links: .failed)
        XCTAssertEqual(failed.handle(.key(.linkPicker)), .none)
        XCTAssertEqual(failed.message?.text, "Links unavailable — nothing copied")

        var timed = makeCard(item: item, links: .loading)
        XCTAssertEqual(timed.handle(.key(.markdownLink)), .none)
        timed.pendingTimedOut()
        XCTAssertEqual(timed.message?.text, "Links unavailable — nothing copied")
    }

    func testLinkPickerKeysCopyDigitsReturnAllAndEsc() throws {
        let item = makeItem(
            sourceMarkdown: ".bob/ref-sources/papers/demo--8b3d3805c049/source.md"
        )
        var card = makeCard(
            item: item, links: .loaded(try decodeGolden()), highlightedPage: 7)
        XCTAssertEqual(card.handle(.key(.linkPicker)), .none)
        guard case .write(let second) = card.handle(.key(.note(2))) else {
            return XCTFail("expected digit 2 to copy the visible row")
        }
        XCTAssertEqual(
            second.payload,
            .text("https://ai.google.dev/gemini-api/docs/imagen")
        )

        guard case .write(let markdown) = card.handle(.copySelected, alternatesActive: true)
        else {
            return XCTFail("expected option-return to copy markdown")
        }
        XCTAssertEqual(
            markdown.payload,
            .text("[Imagen 4 model card](https://ai.google.dev/gemini-api/docs/imagen)")
        )

        guard case .write(let all) = card.handle(.key(.allNotes)) else {
            return XCTFail("expected A to copy every distinct URL")
        }
        XCTAssertEqual(all.confirmationTitle, "Copied 8 links")

        guard case .write(let allMarkdown) = card.handle(
            .key(.allNotes, alternate: true)
        ) else {
            return XCTFail("expected option-A to copy markdown list")
        }
        XCTAssertEqual(allMarkdown.confirmationTitle, "Copied 8 links · Markdown")

        XCTAssertEqual(card.handle(.close), .none)
        XCTAssertNil(card.linkPicker)
    }

    func testPathRemainderOmitsUrlLabels() throws {
        let written = try decodeGolden().links[1]
        XCTAssertEqual(written.pathRemainder, "/gemini-api/docs/imagen")
        let autolinkURL = try decodeGolden().links[3]
        XCTAssertNil(autolinkURL.pathRemainder)
        XCTAssertEqual(
            RefsLink.pathRemainder(in: "https://www.github.com/black-forest-labs/flux"),
            "/black-forest-labs/flux"
        )
    }

    private func decodeGolden() throws -> RefsLinksResponse {
        try JSONDecoder().decode(
            RefsLinksResponse.self,
            from: RefsModelTests.fixtureData("refs-links.json")
        )
    }

    private func decodeStatus(_ status: String) throws -> RefsLinksResponse {
        let data = Data(
            """
            {"ok":true,"schema_version":1,"command":"ref links","reference":{"path":"ref/papers/demo.md","title":"Demo"},"status":"\(status)","detail":null,"source":{"path":".bob/ref-sources/papers/demo--8b3d3805c049/source.md"},"links":[]}
            """.utf8
        )
        return try JSONDecoder().decode(RefsLinksResponse.self, from: data)
    }

    private func makeItem(
        sourceMarkdown: String?,
        urls: [String] = []
    ) -> RefItem {
        RefItem(
            id: "ref/papers/demo.md",
            link: "[[ref/papers/demo]]",
            rawTitle: "Demo",
            stem: "demo",
            markerID: .absent,
            kind: .paper,
            state: .ready,
            isBlocked: false,
            pdfPath: "lib/papers/demo.pdf",
            sourceMarkdown: sourceMarkdown,
            urls: urls
        )
    }

    private func makeCard(
        item: RefItem,
        links: RefsLinksLoadState = .notRequested,
        highlightedPage: Int? = nil
    ) -> RefsCopyCard {
        RefsCopyCard(
            token: 1, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0, links: links,
            highlightedPage: highlightedPage
        )
    }

    private func makeLink(
        number: Int,
        url: String,
        label: String,
        site: String,
        markdown: String? = nil,
        page: Int?,
        section: RefsCodeSection? = nil
    ) -> RefsLink {
        RefsLink(
            number: number, url: url, label: label, site: site,
            markdown: markdown, section: section, page: page
        )
    }
}
