import CaptureCore
import Foundation
import XCTest

@testable import RefsCore

final class RefsCopyAlternatesTests: XCTestCase {
    private let item = RefItem(
        id: "ref/chat/a & b.md", link: "[[ref/chat/a & b]]", rawTitle: "[A] | B",
        stem: "a", kind: .chat, state: .ready, isBlocked: false, pdfPath: "lib/a.pdf"
    )
    private let quote = "  first line\n\nlast line  "

    private func makeCard(loading: Bool = false, narration: Bool = true) -> RefsCopyCard {
        RefsCopyCard(
            token: 1, item: item, absolutePDFPath: "/Users/test/bob/lib/a.pdf", pdfExists: true,
            notes: loading ? .loading : .loaded(notes), noteCapacity: 5,
            absoluteNotePath: "/Users/test/bob/" + item.id,
            homeDirectoryPath: "/Users/test",
            narrationFileURL: narration ? URL(fileURLWithPath: "/Users/test/bob/lib/a.m4a") : nil
        )
    }

    private var notes: RefsShowRow {
        RefsShowRow(
            path: item.id,
            annotations: [
                RefsShowAnnotation(
                    kind: "highlight", quote: quote, comment: "Comment", link: "[[a#^h-1]]"),
                RefsShowAnnotation(kind: "note", comment: "Standalone"),
                RefsShowAnnotation(kind: "highlight", comment: "No quote"),
            ])
    }

    func testAlternatesKeepEveryRowInPlaceAndPreviewExactPayloads() throws {
        let card = makeCard()
        let alternates = card.rows.map { $0.resolved(alternate: true) }
        XCTAssertEqual(alternates.map(\.key), card.rows.map(\.key))
        XCTAssertEqual(alternates.map(\.group), card.rows.map(\.group))
        let expected: [(RefsCopyKey, RefsClipboardPayload)] = [
            (.wikiLink, .text("[[ref/chat/a & b|A  B]]")),
            (.pdfPath, .text("/Users/test/bob/lib/a.pdf")),
            (.notePath, .text("~/bob/" + item.id)),
            (.pdfFile, .fileURL(URL(fileURLWithPath: "/Users/test/bob/lib/a.m4a"))),
            (.note(1), .text(quote)),
        ]
        for (key, payload) in expected {
            let primary = try XCTUnwrap(card.catalog.row(for: key))
            let alternate = primary.resolved(alternate: true)
            XCTAssertEqual(alternate.payload, payload)
            if case .text(let text) = payload { XCTAssertEqual(alternate.preview, text) }
            var copying = card
            XCTAssertEqual(copying.handle(.key(key, alternate: true)), .write(alternate))
        }
        XCTAssertEqual(card.catalog.row(for: .pdfFile)?.resolved(alternate: true).preview, "a.m4a")
        XCTAssertEqual(
            card.catalog.row(for: .pdfPath)?.resolved(alternate: true).payload,
            .text("/Users/test/bob/lib/a.pdf"))
        for key in [RefsCopyKey.title, .note(2), .allNotes] {
            let row = try XCTUnwrap(card.catalog.row(for: key))
            XCTAssertNil(row.alternate)
            XCTAssertEqual(row.resolved(alternate: true), row)
        }
        let noAudio = try XCTUnwrap(makeCard(narration: false).catalog.row(for: .pdfFile))
        XCTAssertNil(noAudio.alternate)
        XCTAssertEqual(noAudio.resolved(alternate: true), noAudio)
    }

    func testHomePathsCopyWithTilde() throws {
        let card = makeCard()
        let pdfPath = try XCTUnwrap(card.catalog.row(for: .pdfPath))
        XCTAssertEqual(pdfPath.payload, .text("~/bob/lib/a.pdf"))
        XCTAssertEqual(pdfPath.preview, "~/bob/lib/a.pdf")
        XCTAssertEqual(pdfPath.label, "PDF path")
        XCTAssertEqual(pdfPath.confirmationTitle, "Copied PDF Path")
        var copying = card
        XCTAssertEqual(copying.handle(.key(.pdfPath)), .write(pdfPath))

        let notePath = try XCTUnwrap(card.catalog.row(for: .notePath)?.alternate)
        XCTAssertEqual(notePath.label, "Note path · ~")
        XCTAssertEqual(notePath.payload, .text("~/bob/" + item.id))
        XCTAssertEqual(notePath.confirmationTitle, "Copied Note Path · ~")
        let pdfFile = try XCTUnwrap(card.catalog.row(for: .pdfFile))
        XCTAssertEqual(pdfFile.payload, .fileURL(URL(fileURLWithPath: "/Users/test/bob/lib/a.pdf")))
        XCTAssertEqual(
            pdfFile.resolved(alternate: true).help, "~/bob/lib/a.m4a")
        let obsidian = try XCTUnwrap(card.catalog.row(for: .obsidianLink))
        XCTAssertEqual(
            URLComponents(string: obsidian.preview)?.queryItems?.first(where: { $0.name == "path" })?.value,
            "/Users/test/bob/" + item.id)

        let absolutePDF = try XCTUnwrap(pdfPath.alternate)
        XCTAssertEqual(absolutePDF.label, "PDF path · absolute")
        XCTAssertEqual(absolutePDF.confirmationTitle, "Copied Absolute PDF Path")
        XCTAssertEqual(absolutePDF.payload, .text("/Users/test/bob/lib/a.pdf"))
    }

    func testHomePathsStayAbsoluteWhenTheyCannotBeShortened() throws {
        let cases: [(String, String?)] = [
            ("/Volumes/vault/ref/chat/a.md", "/Users/test"),
            ("/Users/test2/bob/ref/chat/a.md", "/Users/test"),
            ("/Users/test/bob/ref/chat/a.md", nil),
        ]
        for (notePath, home) in cases {
            let pdfPath = notePath.replacingOccurrences(of: "ref/chat/a.md", with: "lib/a.pdf")
            let catalog = RefsCopyCatalog(
                item: item, absolutePDFPath: pdfPath, pdfExists: true,
                notes: .loaded(notes), noteCapacity: 5, absoluteNotePath: notePath,
                homeDirectoryPath: home)
            let pdf = try XCTUnwrap(catalog.row(for: .pdfPath))
            XCTAssertEqual(pdf.payload, .text(pdfPath))
            XCTAssertNil(pdf.alternate)
            var card = RefsCopyCard(
                token: 1, item: item, absolutePDFPath: pdfPath, pdfExists: true,
                notes: .loaded(notes), noteCapacity: 5, absoluteNotePath: notePath,
                homeDirectoryPath: home)
            XCTAssertEqual(card.handle(.key(.pdfPath)), .write(pdf))
            let note = try XCTUnwrap(catalog.row(for: .notePath)?.alternate)
            XCTAssertEqual(note.payload, .text(notePath))
            XCTAssertEqual(note.label, "Note path · absolute")
            XCTAssertEqual(note.confirmationTitle, "Copied Absolute Note Path")
        }
    }

    func testTitledLinksAndHomeAbbreviationBoundaries() {
        XCTAssertEqual(RefsCopyFormat.titledWikiLink(link: "[[ref/a]]", title: "[]|"), "[[ref/a]]")
        XCTAssertEqual(
            RefsCopyFormat.titledWikiLink(link: "[[ref/a]]", title: " [|] "), "[[ref/a]]")
        XCTAssertEqual(
            RefsCopyFormat.titledWikiLink(link: "[[ref/a]]", title: "Café 😎"), "[[ref/a|Café 😎]]")
        for (path, expected) in [
            ("/Users/test", "~"), ("/Users/test/a b.pdf", "~/a b.pdf"),
            ("/Users/test2/a.pdf", "/Users/test2/a.pdf"), ("/vault/a.pdf", "/vault/a.pdf"),
        ] {
            XCTAssertEqual(
                RefsCopyFormat.abbreviatedPath(path, homeDirectoryPath: "/Users/test/"), expected)
        }
        XCTAssertEqual(RefsCopyFormat.abbreviatedPath("/a", homeDirectoryPath: ""), "/a")
        XCTAssertEqual(RefsCopyFormat.homeAbbreviatedPath("/a", homeDirectoryPath: nil), "/a")
    }

    func testObsidianURLFollowsNotePathWithEncodingAndFixedPosition() throws {
        let catalog = makeCard().catalog
        XCTAssertEqual(
            catalog.rows.map(\.key),
            [
                .title, .wikiLink, .notePath, .obsidianLink, .pdfPath, .pdfFile,
                .note(1), .note(2), .allNotes, .highlightPicker,
            ])
        let row = try XCTUnwrap(catalog.row(for: .obsidianLink))
        XCTAssertEqual(row.payload, .text(row.preview))
        let components = try XCTUnwrap(URLComponents(string: row.preview))
        XCTAssertEqual(components.scheme, "obsidian")
        XCTAssertEqual(components.host, "open")
        XCTAssertEqual(
            components.queryItems, [URLQueryItem(name: "path", value: "/Users/test/bob/" + item.id)]
        )
        XCTAssertNil(catalog.hiddenReason(for: .obsidianLink))
        for path in [nil, ""] as [String?] {
            let unavailable = RefsCopyCatalog(
                item: item, absolutePDFPath: nil, pdfExists: false, notes: .loading,
                noteCapacity: 0, absoluteNotePath: path
            )
            XCTAssertNil(unavailable.row(for: .obsidianLink))
            XCTAssertEqual(
                unavailable.hiddenReason(for: .obsidianLink), "No Obsidian link for this reference")
        }
    }

    func testOptionAndShiftKeyMappingKeepsOtherModifiersConsumed() {
        for (text, key) in [("W", RefsCopyKey.wikiLink), ("1", .note(1)), ("o", .obsidianLink)] {
            for flags in [RefsCopyKeyModifiers.option, [.option, .shift, .capsLock]] {
                XCTAssertEqual(
                    RefsCopyKeyMap.command(characters: text, keyCode: 0, modifiers: flags),
                    .key(key, alternate: true))
            }
        }
        XCTAssertEqual(
            RefsCopyKeyMap.command(characters: "w", keyCode: 13, modifiers: [.command, .option]),
            .consume)
        XCTAssertEqual(
            RefsCopyKeyMap.command(characters: nil, keyCode: 36, modifiers: .option), .copySelected)
        XCTAssertEqual(
            RefsCopyKeyMap.command(
                characters: nil,
                keyCode: 16,
                modifiers: [.command, .option]
            ),
            .copySelected)
    }

    func testQueuedAlternateKeepsRequestedVariantAndCloseRevokesIt() throws {
        var card = makeCard(loading: true)
        XCTAssertEqual(card.handle(.key(.note(1), alternate: true)), .none)
        let expected = try XCTUnwrap(makeCard().catalog.row(for: .note(1))).resolved(
            alternate: true)
        XCTAssertEqual(card.notesLoaded(path: "other.md", row: notes), .none)
        XCTAssertEqual(card.notesLoaded(path: item.id, row: notes), .write(expected))
        card = makeCard(loading: true)
        card.handle(.key(.note(1), alternate: true))
        card.handle(.key(.note(1)))
        let primary = try XCTUnwrap(makeCard().catalog.row(for: .note(1)))
        XCTAssertEqual(card.notesLoaded(path: item.id, row: notes), .write(primary))
        card = makeCard(loading: true)
        card.handle(.key(.note(1), alternate: true))
        card.handle(.close)
        XCTAssertEqual(card.notesLoaded(path: item.id, row: notes), .none)
    }

    func testPickerQuoteOnlyAndStandaloneFallback() throws {
        var card = makeCard()
        card.handle(.key(.highlightPicker, alternate: true))
        let entry = try XCTUnwrap(card.highlightPicker?.entries.first)
        let quoteRow = entry.copyRow(key: .note(1)).resolved(alternate: true)
        XCTAssertEqual(quoteRow.payload, .text(quote))
        XCTAssertEqual(card.handle(.key(.note(1), alternate: true)), .write(quoteRow))
        XCTAssertEqual(card.handle(.copySelected, alternatesActive: true), .write(quoteRow))
        let standalone = try XCTUnwrap(card.highlightPicker?.entries[1]).copyRow(key: .note(2))
        XCTAssertEqual(card.handle(.key(.note(2), alternate: true)), .write(standalone))
        let all = try XCTUnwrap(card.highlightPicker).allHighlightsRow()
        XCTAssertEqual(card.handle(.key(.allNotes, alternate: true)), .write(all))
    }

    func testSelectedAlternateAndFailedWriteRetryStayFrozenAfterOptionRelease() throws {
        var card = makeCard()
        card.select(.wikiLink)
        let alternate = try XCTUnwrap(card.catalog.row(for: .wikiLink)).resolved(alternate: true)
        XCTAssertEqual(card.handle(.copySelected, alternatesActive: true), .write(alternate))
        card.writeFailed(key: .wikiLink, attemptedRow: alternate)
        card.setNoteCapacity(2)
        XCTAssertEqual(card.handle(.copySelected), .write(alternate))
        let primary = try XCTUnwrap(card.catalog.row(for: .wikiLink))
        XCTAssertEqual(card.handle(.key(.wikiLink)), .write(primary))
        XCTAssertEqual(card.handle(.copySelected), .write(primary))
    }
}
