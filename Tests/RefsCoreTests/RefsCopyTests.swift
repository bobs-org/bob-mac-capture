import Foundation
import XCTest

@testable import RefsCore

final class RefsCopyTests: XCTestCase {
    func testMarkerIDDistinguishesPresentNullAndMissingThroughCache() throws {
        let values: [(String, RefMarkerID, Bool)] = [
            (#"{"path":"ref/chat/a.md","link":"[[a]]","title":"A","source_pdf":"ref/chat/a.pdf","marker_id":"marker-a"}"#, .present("marker-a"), true),
            (#"{"path":"ref/chat/a.md","link":"[[a]]","title":"A","source_pdf":"ref/chat/a.pdf","marker_id":null}"#, .absent, true),
            (#"{"path":"ref/chat/a.md","link":"[[a]]","title":"A","source_pdf":"ref/chat/a.pdf"}"#, .unsupported, false),
        ]

        for (json, expected, reportsKey) in values {
            let record = try JSONDecoder().decode(RefRecord.self, from: Data(json.utf8))
            XCTAssertEqual(record.reportsMarkerID, reportsKey)
            XCTAssertEqual(
                record.reportsMarkerID
                    ? (record.markerID.map(RefMarkerID.present) ?? .absent)
                    : .unsupported,
                expected
            )
            let decodedItem = try XCTUnwrap(RefsCatalog.items(from: RefsSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
                records: [record]
            )).first)
            XCTAssertEqual(decodedItem.markerID, expected)
            let snapshot = RefsSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
                records: [record]
            )
            let encoded = try RefsStoreCodecs.encoder().encode(snapshot)
            let roundTrip = try RefsStoreCodecs.decoder().decode(RefsSnapshot.self, from: encoded)
            XCTAssertEqual(roundTrip.records.first?.reportsMarkerID, reportsKey)
            XCTAssertEqual(roundTrip.records.first?.markerID, record.markerID)
        }
    }

    func testResearchRefDecodesAndSurvivesSnapshotCache() throws {
        let record = try JSONDecoder().decode(
            RefRecord.self,
            from: Data(#"{"path":"ref/papers/a.md","link":"[[a]]","title":"A","research_ref":"research:papers/a.md"}"#.utf8)
        )
        XCTAssertEqual(record.researchRef, "research:papers/a.md")

        let snapshot = RefsSnapshot(fetchedAt: Date(timeIntervalSince1970: 1), records: [record])
        let encoded = try RefsStoreCodecs.encoder().encode(snapshot)
        let roundTrip = try RefsStoreCodecs.decoder().decode(RefsSnapshot.self, from: encoded)
        XCTAssertEqual(roundTrip.records.first?.researchRef, "research:papers/a.md")
    }

    func testCatalogCountsMarkerIDsAcrossRecordsWithoutPDFs() throws {
        let records = [
            RefRecord(
                path: "ref/chat/with.pdf.md", link: "[[with]]", title: "With",
                markerID: "shared", reportsMarkerID: true, sourcePDF: "ref/chat/a.pdf"
            ),
            RefRecord(
                path: "ref/chat/no-pdf.md", link: "[[without]]", title: "Without",
                markerID: "shared", reportsMarkerID: true
            ),
        ]
        let snapshot = RefsSnapshot(fetchedAt: Date(timeIntervalSince1970: 1), records: records)

        let items = RefsCatalog.items(from: snapshot)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].markerID, .present("shared"))
        XCTAssertEqual(items[0].markerIDShareCount, 2)
    }

    func testShowDecodesBlockProvenanceAndOwnNotes() throws {
        let row = try JSONDecoder().decode(
            RefsShowRow.self,
            from: Data(#"{"path":"ref/chat/a.md","own_notes":"Keep this","annotations":[{"kind":"highlight","comment":"Mine","block_id":"^h-a","link":"[[a#^h-a]]"}]}"#.utf8)
        )

        XCTAssertEqual(row.ownNotes, "Keep this")
        XCTAssertEqual(row.annotations.first?.blockID, "^h-a")
        XCTAssertEqual(row.annotations.first?.link, "[[a#^h-a]]")
        XCTAssertEqual(row.yourNotes, row.commentedHighlights)
    }

    func testYourNotesKeepsHighlightsAndStandaloneNotesInSourceOrder() {
        let row = RefsShowRow(path: "ref/chat/a.md", annotations: [
            RefsShowAnnotation(kind: "highlight", comment: "First highlight"),
            RefsShowAnnotation(kind: "note", comment: "Standalone"),
            RefsShowAnnotation(kind: "highlight", quote: "Uncommented"),
            RefsShowAnnotation(kind: "highlight", comment: "Second highlight"),
        ])

        XCTAssertEqual(row.commentedHighlights.map(\.comment), ["First highlight", "Second highlight"])
        XCTAssertEqual(row.standaloneNotes.map(\.comment), ["Standalone"])
        XCTAssertEqual(row.yourNotes.map(\.comment), ["First highlight", "Standalone", "Second highlight"])
        XCTAssertEqual(
            row.highlightPickerEntries.map { $0.comment ?? $0.quote },
            ["First highlight", "Standalone", "Uncommented", "Second highlight"]
        )
    }

    func testDigitRowsUseCommentedHighlightsWhileAllNotesIncludesStandaloneNotes() throws {
        let item = makeItem(markerID: .absent)
        let row = RefsShowRow(path: item.id, annotations: [
            RefsShowAnnotation(kind: "highlight", quote: "First", comment: "First comment"),
            RefsShowAnnotation(kind: "note", comment: "Standalone"),
            RefsShowAnnotation(kind: "highlight", quote: "Second", comment: "Second comment"),
        ])
        let catalog = RefsCopyCatalog(
            item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(row), noteCapacity: 9
        )

        XCTAssertEqual(catalog.noteCount, 2)
        XCTAssertEqual(catalog.allNotesCount, 3)
        XCTAssertEqual(
            catalog.rows.filter { if case .note = $0.key { true } else { false } }.map(\.key),
            [.note(1), .note(2)]
        )
        XCTAssertEqual(
            catalog.row(for: .note(1))?.payload,
            .text("> First\n\nComment: First comment")
        )
        XCTAssertEqual(
            catalog.row(for: .note(2))?.payload,
            .text("> Second\n\nComment: Second comment")
        )
        let allNotes = try XCTUnwrap(catalog.row(for: .allNotes))
        XCTAssertEqual(allNotes.preview, "3 notes · Markdown")
        XCTAssertEqual(allNotes.payload, .text(
            "> First\n\nComment: First comment\n\nNote: Standalone\n\n> Second\n\nComment: Second comment"
        ))
    }

    func testAllNotesConfirmationTitlesUseTheActualNoteCount() throws {
        let item = makeItem(markerID: .absent)
        func title(annotations: [RefsShowAnnotation], ownNotes: String = "") throws -> String? {
            let catalog = RefsCopyCatalog(
                item: item, absolutePDFPath: nil, pdfExists: false,
                notes: .loaded(RefsShowRow(
                    path: item.id, annotations: annotations, ownNotes: ownNotes
                )), noteCapacity: 9
            )
            return catalog.row(for: .allNotes)?.confirmationTitle
        }

        XCTAssertEqual(
            try title(annotations: [RefsShowAnnotation(kind: "highlight", comment: "One")]),
            "Copied 1 Note"
        )
        XCTAssertEqual(
            try title(annotations: [
                RefsShowAnnotation(kind: "highlight", comment: "One"),
                RefsShowAnnotation(kind: "note", comment: "Two"),
            ]),
            "Copied 2 Notes"
        )
        XCTAssertEqual(try title(annotations: [], ownNotes: "Own notes"), "Copied Your Notes")
    }

    func testChatCatalogHasFixedLettersAndMarkerDefault() {
        let item = makeItem(markerID: .present("real-id"), task: RefTask(path: "sase.md", link: "[[sase#^task]]"))
        let catalog = RefsCopyCatalog(
            item: item,
            absolutePDFPath: "/vault/ref/chat/example.pdf",
            pdfExists: true,
            notes: .loaded(RefsShowRow(path: item.id)),
            noteCapacity: 5
        )

        XCTAssertEqual(catalog.rows.map { $0.key.glyph }, ["I", "T", "W", "N", "P", "F", "R"])
        XCTAssertEqual(catalog.defaultKey, .markerID)
        XCTAssertEqual(catalog.row(for: .markerID)?.payload, .text("real-id"))
        XCTAssertEqual(catalog.row(for: .pdfFile)?.preview, "example.pdf")
    }

    func testPaperCatalogFormatsValuesAndNotes() {
        let item = makeItem(
            markerID: .present("paper-id"),
            title: "A title",
            urls: ["https://example.test/a (b)"],
            arxivID: "2501.01234",
            doi: "10.1000/example",
            researchRef: "research:papers/example.md",
            task: RefTask(path: "done/reading.md", link: "[[done/reading#^read]]", archived: true)
        )
        let notes = RefsShowRow(path: item.id, annotations: [
            RefsShowAnnotation(
                pageLabel: "Page 28", kind: "highlight", quote: "Quoted",
                comment: "First line\nSecond line", blockID: "^h-1", link: "[[paper#^h-1]]"
            ),
        ], ownNotes: "My own notes")
        let catalog = RefsCopyCatalog(
            item: item,
            absolutePDFPath: "/vault/ref/papers/paper.pdf",
            pdfExists: false,
            notes: .loaded(notes),
            noteCapacity: 4,
            absoluteNotePath: "/vault/ref/papers/paper.md"
        )

        XCTAssertEqual(catalog.rows.map { $0.key.glyph }, ["I", "T", "W", "U", "L", "X", "D", "N", "O", "P", "R", "S", "1", "A", "H"])
        XCTAssertEqual(catalog.defaultKey, .markerID)
        XCTAssertEqual(catalog.row(for: .markdownLink)?.preview, "[A title](https://example.test/a%20%28b%29)")
        XCTAssertEqual(catalog.row(for: .pdfPath)?.tag, .missing)
        XCTAssertNil(catalog.row(for: .pdfFile))
        XCTAssertEqual(catalog.row(for: .readingTask)?.label, "Reading task · archived")
        XCTAssertEqual(catalog.row(for: .readingTask)?.tag, .archived)
        XCTAssertEqual(catalog.row(for: .note(1))?.detail, "p. 28")
        XCTAssertEqual(catalog.row(for: .note(1))?.preview, "↳ First line")
        XCTAssertEqual(
            catalog.row(for: .note(1))?.payload,
            .text("> Quoted\n\nComment: First line\nSecond line\n\n— Page 28 · [[paper#^h-1]]")
        )
        XCTAssertEqual(catalog.row(for: .allNotes)?.preview, "1 note · Markdown + your notes")
        XCTAssertEqual(
            catalog.row(for: .allNotes)?.payload,
            .text("> Quoted\n\nComment: First line\nSecond line\n\n— Page 28 · [[paper#^h-1]]\n\n### Notes\n\nMy own notes")
        )
        let valueKeys: [RefsCopyKey] = [
            .markerID, .title, .wikiLink, .sourceURL, .markdownLink, .arxiv,
            .doi, .notePath, .obsidianLink, .pdfPath, .readingTask, .researchRef,
        ]
        for key in valueKeys {
            guard let row = catalog.row(for: key), case .text(let payload) = row.payload else {
                XCTFail("Expected text value row for \(key)")
                continue
            }
            XCTAssertEqual(row.preview, payload, "Preview must equal \(key)'s payload")
        }
    }

    func testMissingRowsExplainAbsenceAndOlderBob() {
        let absent = RefsCopyCatalog(
            item: makeItem(markerID: .absent), absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")), noteCapacity: 2
        )
        XCTAssertEqual(absent.defaultKey, .wikiLink)
        XCTAssertEqual(absent.hiddenReason(for: .markerID), "No marker ID on this note — N copies its path")
        XCTAssertEqual(absent.hiddenReason(for: .sourceURL), "No source URL for this reference")
        XCTAssertEqual(absent.hiddenReason(for: .pdfPath), "No PDF path for this reference")
        XCTAssertEqual(absent.hiddenReason(for: .pdfFile), "No PDF path for this reference")
        XCTAssertEqual(absent.hiddenReason(for: .readingTask), "No reading task for this reference")
        XCTAssertEqual(absent.hiddenReason(for: .researchRef), "No research ref for this reference")
        XCTAssertEqual(absent.hiddenReason(for: .note(1)), "No note 1")
        XCTAssertEqual(absent.hiddenReason(for: .allNotes), "No notes on this reference")
        XCTAssertEqual(absent.hiddenReason(for: .highlightPicker), "No highlights on this reference")

        let oldBob = RefsCopyCatalog(
            item: makeItem(markerID: .unsupported), absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(RefsShowRow(path: "ref/chat/example.md")), noteCapacity: 2
        )
        XCTAssertEqual(oldBob.hiddenReason(for: .markerID), "Marker IDs need a newer bob — N copies the note path")
    }

    func testSharedIDAndVisibleNoteCapacity() {
        let item = makeItem(markerID: .present("same-id"), markerIDShareCount: 3)
        let annotations = (1...4).map { index in
            RefsShowAnnotation(pageLabel: "\(index)", kind: "highlight", comment: "Comment \(index)")
        }
        let catalog = RefsCopyCatalog(
            item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(RefsShowRow(path: item.id, annotations: annotations)), noteCapacity: 3
        )

        XCTAssertEqual(catalog.row(for: .markerID)?.tag, .shared(3))
        XCTAssertEqual(catalog.rows.filter { if case .note = $0.key { true } else { false } }.count, 2)
        XCTAssertEqual(catalog.noteOverflowCount, 2)
        XCTAssertEqual(catalog.hiddenReason(for: .note(3)), "Note 3 doesn't fit — A copies all · H picks one")
        XCTAssertEqual(catalog.notesOverflowText, "+2 more — A copies all · H picks one")
        XCTAssertEqual(catalog.row(for: .highlightPicker)?.preview, "4 highlights")
        XCTAssertEqual(catalog.hiddenReason(for: .highlightPicker), nil)
        XCTAssertEqual(catalog.hiddenReason(for: .note(5)), "No note 5")
        XCTAssertEqual(RefsCopyCatalog.visibleNoteCount(total: 9, cap: 0), 0)
        XCTAssertEqual(RefsCopyCatalog.visibleNoteCount(total: 9, cap: 1), 0)
        XCTAssertEqual(RefsCopyCatalog.visibleNoteCount(total: 3, cap: 3), 3)
    }

    func testMarkdownLinkEscapingIsNarrowAndDeterministic() {
        XCTAssertEqual(
            RefsCopyFormat.markdownLink(title: #"A [title] \ path"#, url: "https://x.test/a (b)"),
            #"[A \[title\] \\ path](https://x.test/a%20%28b%29)"#
        )
    }

    func testNoteFormatHandlesBlankQuoteLinesAndMissingProvenance() {
        let annotation = RefsShowAnnotation(
            pageLabel: nil, quote: "First\n\nLast", comment: "Comment", link: nil
        )
        XCTAssertEqual(RefsCopyFormat.noteBlock(annotation), "> First\n>\n> Last\n\nComment: Comment")
        XCTAssertEqual(
            RefsCopyFormat.standaloneNote(RefsShowAnnotation(
                pageLabel: "p. 4", kind: "note", comment: "Standalone\nSecond", link: "[[x#^a]]"
            )),
            "Note: Standalone\nSecond\n— p. 4 · [[x#^a]]"
        )
        XCTAssertEqual(RefsCopyFormat.shortPageLabel("Page 11"), "p. 11")
        XCTAssertEqual(RefsCopyFormat.shortPageLabel("Pages 11–12"), "pp. 11–12")
        XCTAssertEqual(RefsCopyFormat.shortPageLabel("pages 11, 14"), "pp. 11, 14")
        XCTAssertEqual(RefsCopyFormat.shortPageLabel("Appendix A"), "Appendix A")
        XCTAssertEqual(
            RefsCopyFormat.noteBlock(RefsShowAnnotation(quote: "  \n ", comment: "Kept")),
            "Comment: Kept"
        )
        XCTAssertEqual(
            RefsCopyFormat.noteBlock(RefsShowAnnotation(quote: "Quote", comment: " \t\n ")),
            "> Quote"
        )
    }

    func testKeyMapNormalizesLettersAndRoutesControlKeys() {
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "I", keyCode: 34, modifiers: [.shift, .capsLock]), .key(.markerID))
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "v", keyCode: 9, modifiers: [.command]), .consume)
        XCTAssertEqual(RefsCopyKeyMap.command(characters: nil, keyCode: 125, modifiers: [.numericPad, .function]), .move(1))
        XCTAssertEqual(RefsCopyKeyMap.command(characters: nil, keyCode: 126, modifiers: [.numericPad, .function]), .move(-1))
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "n", keyCode: 45, modifiers: [.control]), .move(1))
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "j", keyCode: 38, modifiers: [.control]), .move(1))
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "p", keyCode: 35, modifiers: [.control]), .move(-1))
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "k", keyCode: 40, modifiers: [.control]), .move(-1))
        XCTAssertEqual(RefsCopyKeyMap.command(characters: nil, keyCode: 36, modifiers: []), .copySelected)
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "\u{F700}", keyCode: 123, modifiers: [.shift]), .consume)
        XCTAssertEqual(RefsCopyKeyMap.command(characters: nil, keyCode: 53, modifiers: []), .close)
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "[", keyCode: 33, modifiers: []), .unknown("["))
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "[", keyCode: 33, modifiers: [.control]), .close)
        XCTAssertEqual(
            RefsCopyKeyMap.command(characters: "y", keyCode: 16, modifiers: [.command]),
            .copySelected
        )
        XCTAssertEqual(
            RefsCopyKeyMap.command(characters: "y", keyCode: 16, modifiers: [.command, .capsLock]),
            .copySelected
        )
        XCTAssertEqual(
            RefsCopyKeyMap.command(characters: "y", keyCode: 16, modifiers: [.control]),
            .consume
        )
        XCTAssertEqual(RefsCopyKeyMap.command(characters: nil, keyCode: 76, modifiers: [.numericPad]), .copySelected)
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "k", keyCode: 40, modifiers: [.command]), .showActions)
        XCTAssertEqual(RefsCopyKeyMap.command(characters: "q", keyCode: 12, modifiers: []), .unknown("q"))
    }

    func testCardQueuesMatchingNotesAndRevokesOnClose() {
        let item = makeItem(markerID: .absent)
        var card = RefsCopyCard(
            token: 7, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loading, noteCapacity: 5
        )
        XCTAssertEqual(card.handle(.key(.note(1))), .none)
        XCTAssertEqual(card.pending, .note(1))
        XCTAssertEqual(card.message?.text, "Waiting for notes… esc cancels")
        _ = card.handle(.move(1))
        XCTAssertEqual(card.message?.text, "Waiting for notes… esc cancels")
        card.clearTransientMessage()
        XCTAssertEqual(card.message?.text, "Waiting for notes… esc cancels")
        XCTAssertEqual(
            card.notesLoaded(path: "ref/chat/other.md", row: RefsShowRow(path: "ref/chat/other.md")),
            .none
        )
        XCTAssertEqual(card.pending, .note(1))
        let loaded = RefsShowRow(path: item.id, annotations: [
            RefsShowAnnotation(kind: "highlight", comment: "Keep")
        ])
        let effect = card.notesLoaded(path: item.id, row: loaded)
        guard case .write(let row) = effect else { return XCTFail("Expected queued note write") }
        XCTAssertEqual(row.key, .note(1))
        XCTAssertEqual(row.payload, .text("Comment: Keep"))

        var closing = RefsCopyCard(
            token: 8, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loading, noteCapacity: 5
        )
        _ = closing.handle(.key(.allNotes))
        XCTAssertEqual(closing.handle(.close), .close)
        XCTAssertEqual(closing.notesLoaded(path: item.id, row: loaded), .none)
        XCTAssertNil(closing.pending)
    }

    func testPendingTimeoutShowsErrorAndClearsQueuedCopy() {
        let item = makeItem(markerID: .absent)
        var card = RefsCopyCard(
            token: 11, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loading, noteCapacity: 5
        )
        XCTAssertEqual(card.handle(.key(.note(1))), .none)
        card.pendingTimedOut()
        XCTAssertNil(card.pending)
        XCTAssertEqual(card.message?.text, "Notes didn't load — nothing copied")
        XCTAssertTrue(card.message?.isError == true)
    }

    func testCardLoadFailureAndTransientMessageState() {
        let item = makeItem()
        var card = RefsCopyCard(
            token: 9, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loading, noteCapacity: 5
        )
        _ = card.handle(.key(.note(1)))
        card.notesFailed(path: item.id)
        XCTAssertNil(card.pending)
        XCTAssertEqual(card.message?.text, "Notes unavailable — nothing copied")
        XCTAssertTrue(card.message?.isError == true)
        XCTAssertEqual(card.handle(.key(.note(1))), .none)
        XCTAssertEqual(card.message?.text, "Notes unavailable — nothing copied")

        _ = card.handle(.unknown("q"))
        XCTAssertTrue(card.message?.isTransient == true)
        card.clearTransientMessage()
        XCTAssertNil(card.message)

        card.writeUnavailable(key: .wikiLink)
        XCTAssertEqual(card.selectedKey, .wikiLink)
        XCTAssertEqual(
            card.message?.text,
            "Nothing to copy — this value is unavailable"
        )
        XCTAssertTrue(card.message?.isError == true)
    }

    func testCardMoveWrapsAndCapacityKeepsOrResetsSelection() {
        let item = makeItem(markerID: .absent)
        var card = RefsCopyCard(
            token: 1, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(RefsShowRow(path: item.id)), noteCapacity: 4
        )
        XCTAssertEqual(card.selectedKey, .wikiLink)
        _ = card.handle(.move(-1))
        XCTAssertEqual(card.selectedKey, .title)
        _ = card.handle(.move(-1))
        XCTAssertEqual(card.selectedKey, .notePath)
        _ = card.handle(.move(1))
        XCTAssertEqual(card.selectedKey, .title)

        let annotations = (1...3).map { index in
            RefsShowAnnotation(kind: "highlight", comment: "Comment \(index)")
        }
        var notesCard = RefsCopyCard(
            token: 2, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(RefsShowRow(path: item.id, annotations: annotations)), noteCapacity: 4
        )
        notesCard.select(.note(2))
        notesCard.setNoteCapacity(3)
        XCTAssertEqual(notesCard.selectedKey, .note(2))
        notesCard.setNoteCapacity(2)
        XCTAssertEqual(notesCard.selectedKey, .wikiLink)
    }

    func testLayoutReturnsFittingNoteRows() {
        let metrics = RefsCopyCardMetrics(
            headerHeight: 40, rowHeight: 24, separatorHeight: 1,
            notesHeaderHeight: 16, messageLineHeight: 18, verticalPadding: 20
        )
        XCTAssertEqual(
            RefsCopyCardLayout.noteCapacity(
                cardHeight: 298, nonNoteRowCount: 5, groupCount: 3, metrics: metrics
            ),
            3
        )
        XCTAssertEqual(RefsCopyCardLayout.visibleNoteCount(total: 5, cap: 3), 2)
        XCTAssertEqual(
            RefsCopyCardLayout.highlightWindowSize(
                cardHeight: 424, metrics: metrics, rowHeight: 36
            ),
            9
        )
        XCTAssertEqual(
            RefsCopyCardLayout.highlightWindowSize(
                cardHeight: 208, metrics: metrics, rowHeight: 36
            ),
            3
        )
    }

    func testHighlightPickerEntriesExcludeImagesAndEmptyQuotes() {
        let row = RefsShowRow(path: "ref/papers/a.md", annotations: [
            RefsShowAnnotation(kind: "highlight", quote: "Keep this quote"),
            RefsShowAnnotation(kind: "highlight", quote: "   "),
            RefsShowAnnotation(kind: "image", quote: "a figure"),
            RefsShowAnnotation(kind: "highlight", comment: "Commented only"),
            RefsShowAnnotation(kind: "note", comment: "Standalone"),
            RefsShowAnnotation(kind: "note", comment: "  "),
        ])

        XCTAssertEqual(
            row.highlightPickerEntries.map { $0.quote ?? $0.comment },
            ["Keep this quote", "Commented only", "Standalone"]
        )
    }

    func testUncommentedHighlightsShowHWithoutNoteRows() {
        let item = makeItem(markerID: .absent)
        let notes = RefsShowRow(path: item.id, annotations: [
            RefsShowAnnotation(
                pageLabel: "11", kind: "highlight", quote: "Uncommented",
                link: "[[paper#^h-1]]"
            ),
        ])
        let catalog = RefsCopyCatalog(
            item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(notes), noteCapacity: 5
        )

        XCTAssertNil(catalog.row(for: .note(1)))
        XCTAssertNil(catalog.row(for: .allNotes))
        XCTAssertEqual(catalog.row(for: .highlightPicker)?.preview, "1 highlight")
        XCTAssertEqual(
            RefsCopyFormat.highlightBlock(notes.annotations[0]),
            "> Uncommented\n\n— Page 11 · [[paper#^h-1]]"
        )
    }

    func testPickerWindowsAndCopiesDigitsAndAll() {
        let item = makeItem(markerID: .absent)
        let annotations = (1...12).map { index in
            RefsShowAnnotation(
                pageLabel: "Page \(index)",
                kind: "highlight",
                quote: "Quote \(index)",
                comment: index.isMultiple(of: 4) ? "Comment \(index)" : nil,
                link: "[[paper#^h-\(index)]]"
            )
        }
        var card = RefsCopyCard(
            token: 3, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(RefsShowRow(path: item.id, annotations: annotations)),
            noteCapacity: 4,
            pickerWindowSize: 9
        )

        XCTAssertEqual(card.handle(.key(.highlightPicker)), .none)
        XCTAssertEqual(card.highlightPicker?.entries.count, 12)
        XCTAssertEqual(card.highlightPicker?.windowStart, 0)
        XCTAssertEqual(card.highlightPicker?.windowSize, 9)
        XCTAssertEqual(card.highlightPicker?.selectedIndex, 0)

        for _ in 0..<10 {
            XCTAssertEqual(card.handle(.move(1)), .none)
        }
        XCTAssertEqual(card.highlightPicker?.selectedIndex, 10)
        XCTAssertEqual(card.highlightPicker?.windowStart, 2)

        let digit = card.handle(.key(.note(1)))
        guard case .write(let firstVisible) = digit else {
            return XCTFail("Expected window digit write")
        }
        XCTAssertEqual(firstVisible.confirmationTitle, "Copied Highlight · p. 3")
        XCTAssertTrue(
            {
                if case .text(let value) = firstVisible.payload {
                    return value.contains("> Quote 3")
                }
                return false
            }()
        )

        XCTAssertEqual(card.handle(.close), .none)
        XCTAssertNil(card.highlightPicker)
        XCTAssertFalse(card.isClosed)
        XCTAssertEqual(card.selectedKey, .highlightPicker)

        XCTAssertEqual(card.handle(.key(.highlightPicker)), .none)
        let all = card.handle(.key(.allNotes))
        guard case .write(let allRow) = all else {
            return XCTFail("Expected all-highlights write")
        }
        XCTAssertEqual(allRow.confirmationTitle, "Copied 12 Highlights")
        if case .text(let value) = allRow.payload {
            XCTAssertTrue(value.contains("> Quote 1"))
            XCTAssertTrue(value.contains("Comment: Comment 4"))
            XCTAssertFalse(value.contains("### Notes"))
        } else {
            XCTFail("Expected text payload")
        }
    }

    func testPickerEscKeepsCardAndUnknownKeysStayTransient() {
        let item = makeItem()
        var card = RefsCopyCard(
            token: 4, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(RefsShowRow(path: item.id, annotations: [
                RefsShowAnnotation(kind: "highlight", quote: "Only quote"),
            ])),
            noteCapacity: 4
        )
        _ = card.handle(.key(.highlightPicker))
        XCTAssertEqual(card.handle(.unknown("q")), .none)
        XCTAssertEqual(card.message?.text, "Nothing on ‘q’")
        XCTAssertEqual(card.handle(.key(.title)), .none)
        XCTAssertEqual(card.message?.text, "Nothing on ‘t’")
        XCTAssertEqual(card.handle(.key(.note(9))), .none)
        XCTAssertEqual(card.message?.text, "No highlight 9")
        XCTAssertEqual(card.handle(.close), .none)
        XCTAssertNil(card.highlightPicker)
        XCTAssertFalse(card.isClosed)
    }

    func testQueuedHOpensPickerWhenNotesLoad() {
        let item = makeItem(markerID: .absent)
        var card = RefsCopyCard(
            token: 5, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loading, noteCapacity: 5
        )
        XCTAssertEqual(card.handle(.key(.highlightPicker)), .none)
        XCTAssertEqual(card.pending, .highlightPicker)
        let loaded = RefsShowRow(path: item.id, annotations: [
            RefsShowAnnotation(kind: "highlight", quote: "Later"),
        ])
        XCTAssertEqual(card.notesLoaded(path: item.id, row: loaded), .none)
        XCTAssertNil(card.pending)
        XCTAssertEqual(card.highlightPicker?.entries.count, 1)
    }

    func testGroupCopyKeepsPiecesInOrderWithBlankLineBetween() throws {
        let group = RefsShowAnnotation(
            pageLabel: "Pages 11–12",
            kind: "highlight",
            quote: "Head words on eleven\n\nTail words on twelve",
            comment: "Follower note",
            blockID: "^h-06d27eae3c84",
            link: "[[ref/blogs/group_case#^h-06d27eae3c84]]",
            pieces: [
                RefsShowPiece(pageLabel: "Page 11", quote: "Head words on eleven"),
                RefsShowPiece(
                    pageLabel: "Page 12",
                    quote: "Tail words on twelve",
                    comment: "Follower note"
                ),
            ]
        )
        XCTAssertTrue(group.isGroup)
        XCTAssertEqual(
            RefsShowRow(path: "ref/blogs/group_case.md", annotations: [group]).commentedHighlights,
            [group]
        )
        let block = RefsCopyFormat.noteBlock(group)
        XCTAssertTrue(block.contains("> Head words on eleven"), block)
        XCTAssertTrue(block.contains("> Tail words on twelve"), block)
        XCTAssertTrue(block.contains("Comment: Follower note"), block)
        XCTAssertEqual(RefsCopyFormat.highlightBlock(group), block)
        let quoteOnly = try XCTUnwrap(RefsCopyFormat.quoteAlternate(group))
        XCTAssertEqual(quoteOnly.payload, .text("Head words on eleven\n\nTail words on twelve"))
        XCTAssertEqual(quoteOnly.label, "Quote only")
    }

    private func makeItem(
        markerID: RefMarkerID = .unsupported,
        markerIDShareCount: Int = 1,
        title: String = #"A [title] \\ path"#,
        urls: [String] = [],
        arxivID: String? = nil,
        doi: String? = nil,
        researchRef: String? = nil,
        task: RefTask? = nil
    ) -> RefItem {
        RefItem(
            id: "ref/chat/example.md",
            link: "[[ref/chat/example]]",
            rawTitle: title,
            stem: "example",
            markerID: markerID,
            markerIDShareCount: markerIDShareCount,
            researchRef: researchRef,
            kind: .chat,
            state: .ready,
            isBlocked: false,
            pdfPath: "ref/chat/example.pdf",
            task: task,
            urls: urls,
            arxivID: arxivID,
            doi: doi
        )
    }
}
