import Foundation
import XCTest

@testable import RefsCore

final class RefsCodeTests: XCTestCase {
    func testCodeEnvelopeDecodesSourceBlocksAndIgnoresFutureFields() throws {
        let response = try decodeResponse()

        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.reference.path, "ref/chat/example.md")
        XCTAssertEqual(response.status, .available)
        XCTAssertEqual(response.source?.path, ".bob/ref-sources/chat/example--abc123/source.md")
        XCTAssertEqual(response.source?.text, "# Example\n")
        XCTAssertEqual(response.blocks.count, 3)
        XCTAssertEqual(response.blocks[0].language, "yaml")
        XCTAssertEqual(response.blocks[0].section?.heading, "2  Root cause")
        XCTAssertEqual(response.blocks[1].pageEnd, 8)
        XCTAssertEqual(response.blocks[2].kind, "mermaid")
    }

    func testCodeEnvelopeSkipsMalformedBlocksButKeepsEnvelope() throws {
        let response = try JSONDecoder().decode(
            RefsCodeResponse.self,
            from: Data(#"{"reference":{"path":"ref/chat/example.md"},"status":"available","source":{"path":"x","text":""},"blocks":[42,{"n":1,"text":"kept"},{"n":"bad","text":"skipped"}]}"#.utf8)
        )

        XCTAssertEqual(response.blocks.map(\.number), [1])
        XCTAssertEqual(response.blocks.first?.fenced, "```\nkept\n```\n")
    }

    func testRefListSourceMarkdownPointerSurvivesCacheRoundTrip() throws {
        let record = try JSONDecoder().decode(
            RefRecord.self,
            from: Data(#"{"path":"ref/chat/example.md","link":"[[ref/chat/example]]","title":"Example","source_pdf":"ref/chat/example.pdf","source_markdown":".bob/ref-sources/chat/example--abc123/source.md"}"#.utf8)
        )
        XCTAssertEqual(record.sourceMarkdown, ".bob/ref-sources/chat/example--abc123/source.md")
        XCTAssertTrue(record.reportsSourceMarkdown)

        let snapshot = RefsSnapshot(fetchedAt: Date(timeIntervalSince1970: 1), records: [record])
        let data = try RefsStoreCodecs.encoder().encode(snapshot)
        let decoded = try RefsStoreCodecs.decoder().decode(RefsSnapshot.self, from: data)
        XCTAssertEqual(decoded.records.first?.sourceMarkdown, record.sourceMarkdown)
        XCTAssertTrue(try XCTUnwrap(decoded.records.first).reportsSourceMarkdown)
        XCTAssertEqual(
            RefsCatalog.items(from: decoded).first?.sourceMarkdown,
            record.sourceMarkdown
        )

        let older = try JSONDecoder().decode(
            RefRecord.self,
            from: Data(#"{"path":"ref/chat/old.md","link":"[[ref/chat/old]]","title":"Old"}"#.utf8)
        )
        XCTAssertNil(older.sourceMarkdown)
        XCTAssertFalse(older.reportsSourceMarkdown)
    }

    func testCopyCatalogAddsCAndMAndFormatsPageAwareSummary() throws {
        let response = try decodeResponse()
        let catalog = RefsCopyCatalog(
            item: makeItem(),
            absolutePDFPath: nil,
            pdfExists: false,
            notes: .unavailable,
            noteCapacity: 0,
            homeDirectoryPath: "/Users/test",
            code: .loaded(response),
            highlightedPage: 7
        )

        let code = try XCTUnwrap(catalog.row(for: .codePicker))
        XCTAssertEqual(code.group, .contents)
        XCTAssertEqual(code.label, "Code block…")
        XCTAssertEqual(code.preview, "3 blocks · ● 1 on this page · yaml, rust, mermaid")
        XCTAssertEqual(code.truncation, .tail)
        let codeDotRange = try XCTUnwrap(code.onPageDotRange)
        XCTAssertEqual(String(code.preview[codeDotRange]), "●")
        XCTAssertTrue(code.preview[codeDotRange.upperBound...].hasPrefix(" 1 on this page"))
        XCTAssertEqual(code.payload, .text(""))

        let markdown = try XCTUnwrap(catalog.row(for: .sourceMarkdown))
        XCTAssertEqual(markdown.payload, .text("# Example\n"))
        XCTAssertEqual(markdown.preview, "source.md · 12 KB · captured Oct 20")
        XCTAssertEqual(
            markdown.resolved(alternate: true).payload,
            .text("~/bob/.bob/ref-sources/chat/example--abc123/source.md")
        )
    }

    func testCopyCatalogExplainsUnavailableRowsAndKeepsMarkdownForNoCode() throws {
        let noCode = try decodeResponse(status: "no_code", blocks: "[]")
        let catalog = RefsCopyCatalog(
            item: makeItem(), absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0, code: .loaded(noCode)
        )
        XCTAssertNil(catalog.row(for: .codePicker))
        XCTAssertNotNil(catalog.row(for: .sourceMarkdown))
        XCTAssertEqual(
            catalog.hiddenReason(for: .codePicker),
            "No code blocks in this reference — M copies its Markdown"
        )

        for (status, expected) in [
            ("no_catalog", "Code blocks weren't recorded for this reference — M copies its Markdown"),
            ("source_missing", "Saved Markdown isn't on this Mac yet — sync the vault"),
            ("source_invalid", "Saved Markdown doesn't match its digest — run bob ref doctor"),
            ("no_source", "No saved Markdown — code copy needs a reference bob rendered from Markdown"),
        ] {
            let response = try decodeResponse(status: status, blocks: "[]", source: status == "no_source" || status == "source_missing" || status == "source_invalid" ? "null" : nil)
            let catalog = RefsCopyCatalog(
                item: makeItem(), absolutePDFPath: nil, pdfExists: false,
                notes: .unavailable, noteCapacity: 0, code: .loaded(response)
            )
            XCTAssertNil(catalog.row(for: .codePicker), status)
            XCTAssertEqual(catalog.hiddenReason(for: .codePicker), expected, status)
        }

        let unsupported = RefsCopyCatalog(
            item: makeItem(), absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0, code: .unsupported
        )
        XCTAssertEqual(unsupported.hiddenReason(for: .sourceMarkdown), "Code copy needs a newer bob")
        let failed = RefsCopyCatalog(
            item: makeItem(), absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0, code: .failed
        )
        XCTAssertEqual(failed.hiddenReason(for: .codePicker), "Code unavailable — nothing copied")
    }

    func testCodePickerSelectsPageAndSharesSectionedWindowRules() throws {
        let blocks = try decodeResponse().blocks
        let picker = RefsCodePicker(
            blocks: blocks,
            highlightedPage: 7,
            windowSize: 2,
            groupHeaderHeight: 22,
            entryRowHeight: 36
        )
        XCTAssertEqual(picker.selectedIndex, 1)
        XCTAssertEqual(picker.selectedEntry?.block.number, 2)
        XCTAssertTrue(picker.selectedEntry?.isOnPage == true)
        XCTAssertEqual(picker.pageBlockCount, 1)
        XCTAssertTrue(picker.windowRows.contains { row in
            if case .group(let title) = row { return title == "2  Root cause" }
            return false
        })

        XCTAssertEqual(RefsCodePicker.initialSelection(in: blocks, page: 4), 0)
        XCTAssertEqual(RefsCodePicker.initialSelection(in: blocks, page: 10), 2)
        XCTAssertEqual(RefsCodePicker.initialSelection(in: blocks, page: nil), 0)
    }

    func testCodeCopyUsesExactPlainOrFencedPayload() throws {
        let entry = try XCTUnwrap(RefsCodePicker(blocks: decodeResponse().blocks).entries.first)
        XCTAssertEqual(entry.copyRow(fenced: false).payload, .text("refresh:\n\tinterval_ms: 250"))
        XCTAssertEqual(entry.copyRow(fenced: false).confirmationTitle, "Copied yaml · 2 lines")
        XCTAssertEqual(entry.copyRow(fenced: true).payload, .text("```yaml\nrefresh:\n\tinterval_ms: 250\n```\n"))
        XCTAssertEqual(entry.copyRow(fenced: true).confirmationTitle, "Copied yaml · fenced")

        let mermaid = try XCTUnwrap(RefsCodePicker(blocks: decodeResponse().blocks).entries.last)
        XCTAssertEqual(mermaid.copyRow(fenced: false).confirmationTitle, "Copied Mermaid source")
    }

    func testPreviewWellShowsTabsFencesAndBoundedContentWithoutChangingPayload() throws {
        let block = try XCTUnwrap(decodeResponse().blocks.first)
        let preview = RefsCodePreviewWell(block: block, fenced: false, visibleLineCount: 8)
        XCTAssertEqual(preview.lines.map(\.text), ["refresh:", "→   interval_ms: 250"])
        XCTAssertEqual(preview.overflowLineCount, 0)

        let fenced = RefsCodePreviewWell(block: block, fenced: true, visibleLineCount: 8)
        XCTAssertTrue(fenced.lines.first?.isFence == true)
        XCTAssertTrue(fenced.lines.last?.isFence == true)
        XCTAssertEqual(block.text, "refresh:\n\tinterval_ms: 250")
    }

    func testPreviewLayoutClampsHeightAndPickerRows() {
        let layout = RefsCodePreviewWellLayout.make(availableHeightUnderHeader: 800)
        XCTAssertEqual(layout.height, 306)
        XCTAssertEqual(layout.visibleCodeLines, 18)
        XCTAssertEqual(layout.pickerWindowSize, 9)

        let middle = RefsCodePreviewWellLayout.make(availableHeightUnderHeader: 500)
        XCTAssertEqual(middle.height, 225)
        XCTAssertEqual(middle.visibleCodeLines, 12)
        XCTAssertEqual(middle.pickerWindowSize, 7)

        let small = RefsCodePreviewWellLayout.make(availableHeightUnderHeader: 100)
        XCTAssertEqual(small.visibleCodeLines, 6)
        XCTAssertEqual(small.pickerWindowSize, 2)
    }

    func testCopyCardQueuesCodeKeyUntilCatalogLoads() throws {
        let item = makeItem()
        var card = RefsCopyCard(
            token: 1, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0, code: .loading, highlightedPage: 7
        )
        XCTAssertEqual(
            card.handle(try XCTUnwrap(RefsCopyEntry.code.seedCommand)),
            .none
        )
        XCTAssertEqual(card.pending, .codePicker)
        XCTAssertEqual(card.message?.text, "Loading code… esc cancels")

        XCTAssertEqual(card.codeLoaded(path: item.id, response: try decodeResponse()), .none)
        XCTAssertNil(card.pending)
        XCTAssertEqual(card.codePicker?.selectedEntry?.block.number, 2)
        guard case .write(let row) = card.handle(.copySelected) else {
            return XCTFail("expected the selected code block to be copied")
        }
        XCTAssertEqual(row.payload, .text("fn run() {}"))
    }

    func testCodeEntrySeedShowsHiddenReasonWhenCatalogHasNoCode() throws {
        let item = makeItem()
        var card = RefsCopyCard(
            token: 1, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .unavailable, noteCapacity: 0, code: .loading
        )
        XCTAssertEqual(card.handle(try XCTUnwrap(RefsCopyEntry.code.seedCommand)), .none)
        XCTAssertEqual(card.pending, .codePicker)
        XCTAssertEqual(
            card.codeLoaded(path: item.id, response: try decodeResponse(status: "no_code", blocks: "[]")),
            .none
        )
        XCTAssertNil(card.pending)
        XCTAssertEqual(card.message?.text, "No code blocks in this reference — M copies its Markdown")
        XCTAssertTrue(card.message?.isError == true)
    }

    private func decodeResponse(
        status: String = "available",
        blocks: String? = nil,
        source: String? = nil
    ) throws -> RefsCodeResponse {
        let defaultBlocks = #"[{"id":"abc123/1","n":1,"kind":"code","lang":"yaml","title":null,"summary":"refresh:","caption":"refresh:","lines":2,"bytes":27,"text":"refresh:\n\tinterval_ms: 250","fenced":"```yaml\nrefresh:\n\tinterval_ms: 250\n```\n","section":{"number":"2","title":"Root cause"},"page":5,"page_end":5,"page_source":"anchor"},{"id":"abc123/2","n":2,"kind":"code","lang":"rust","title":"Runner","summary":"fn run() {}","caption":"Runner","lines":1,"bytes":11,"text":"fn run() {}","fenced":"```rust\nfn run() {}\n```\n","section":{"number":"2","title":"Root cause"},"page":7,"page_end":8,"page_source":"anchor"},{"id":"abc123/3","n":3,"kind":"mermaid","lang":"mermaid","title":null,"summary":"flowchart LR","caption":"Overview","lines":1,"bytes":12,"text":"flowchart LR","fenced":"```mermaid\nflowchart LR\n```\n","section":{"number":"3","title":"Overview"},"page":9,"page_end":9,"page_source":"anchor"}]"#
        let sourceJSON = source ?? ##"{"path":".bob/ref-sources/chat/example--abc123/source.md","sha256":"digest","bytes":12000,"captured":"2026-10-20","route":"markdown","text":"# Example\n"}"##
        let blocksJSON = blocks ?? defaultBlocks
        let data = Data(
            """
            {"ok":true,"schema_version":1,"command":"ref code","generated_at":"2026-10-26T09:00:00Z","reference":{"path":"ref/chat/example.md","title":"Example","marker_id":"example"},"status":"\(status)","detail":null,"source":\(sourceJSON),"blocks":\(blocksJSON),"future_field":true}
            """.utf8
        )
        return try JSONDecoder().decode(RefsCodeResponse.self, from: data)
    }

    private func makeItem() -> RefItem {
        RefItem(
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
    }
}
