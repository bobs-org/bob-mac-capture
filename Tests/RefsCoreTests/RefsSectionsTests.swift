import Foundation
import XCTest

@testable import RefsCore

/// Section decoding, header attachment, disclosure text, Copy A grouping,
/// and H picker group rows. Unsectioned fixtures stay byte-identical.
final class RefsSectionsTests: XCTestCase {
    func testSectionsFixtureDecodesDescriptorsAndMembership() throws {
        let response = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: fixtureData("refs-show-sections.json")
        )
        XCTAssertEqual(response.schemaVersion, 1)
        let row = try XCTUnwrap(response.refs.first)
        XCTAssertEqual(row.sections.map(\.id), [
            "intro", "memory", "related", "visuals", "coda",
        ])
        XCTAssertEqual(row.sections[0].count, 0)
        XCTAssertNil(row.sections[0].description)
        XCTAssertNil(row.sections[0].pages)
        XCTAssertEqual(row.sections[0].images, [])
        XCTAssertEqual(
            row.sections[1].description,
            "Everything that belongs in the blog's memory section.\n\nKeep the second paragraph."
        )
        XCTAssertEqual(row.sections[1].pages, "Pages 4–5")
        XCTAssertEqual(row.sections[1].images, ["ref/notes/pic.png"])
        XCTAssertEqual(row.sections[1].blockID, "s-memory")
        XCTAssertEqual(row.annotations.map(\.section), [
            "memory", "memory", "memory", "visuals", nil, nil,
        ])
        XCTAssertTrue(row.annotations[2].isGroup)
        XCTAssertEqual(row.annotations[3].kind, "image")
        XCTAssertEqual(row.annotations[5].kind, "note")
    }

    func testOldFixturesStayUnsectioned() throws {
        let show = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: fixtureData("refs-show.json")
        )
        XCTAssertEqual(show.refs.first?.sections, [])
        XCTAssertNil(show.refs.first?.annotations.first?.section)

        let highlights = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: fixtureData("refs-show-highlights.json")
        )
        XCTAssertEqual(highlights.refs.first?.sections, [])
        XCTAssertTrue(
            highlights.refs.first?.annotations.allSatisfy { $0.section == nil } == true
        )
    }

    func testAbsentNullAndWrongTypeSectionMetadataKeepTheRow() throws {
        let row = try JSONDecoder().decode(
            RefsShowRow.self,
            from: Data(
                """
                {
                  "path": "ref/chat/x.md",
                  "sections": null,
                  "annotations": [
                    {"kind": "highlight", "quote": "Keep", "section": null}
                  ]
                }
                """.utf8
            )
        )
        XCTAssertEqual(row.path, "ref/chat/x.md")
        XCTAssertEqual(row.sections, [])
        XCTAssertEqual(row.annotations.count, 1)
        XCTAssertNil(row.annotations[0].section)

        let wrongType = try JSONDecoder().decode(
            RefsShowRow.self,
            from: Data(
                """
                {
                  "path": "ref/chat/x.md",
                  "sections": "nope",
                  "annotations": [
                    {"kind": "highlight", "quote": "Keep", "section": 12}
                  ]
                }
                """.utf8
            )
        )
        XCTAssertEqual(wrongType.sections, [])
        XCTAssertEqual(wrongType.annotations.count, 1)
        XCTAssertNil(wrongType.annotations[0].section)
    }

    func testMalformedSectionElementsDropWhileSiblingsSurvive() throws {
        let row = try JSONDecoder().decode(
            RefsShowRow.self,
            from: Data(
                """
                {
                  "path": "ref/chat/x.md",
                  "sections": [
                    42,
                    {"id": "", "title": "Blank"},
                    {"id": "memory", "title": "Memory", "tag": "@memory", "count": 2},
                    {"id": "memory", "title": "Duplicate"},
                    {"title": "No id"},
                    {"id": "related", "title": "Related", "tag": "@related", "count": 0}
                  ]
                }
                """.utf8
            )
        )
        XCTAssertEqual(row.sections.map(\.id), ["memory", "related"])
        XCTAssertEqual(row.sections[0].title, "Memory")
        XCTAssertEqual(row.sections[0].count, 2)
    }

    func testHeaderAttachmentLeadingMiddleOtherAndPageReset() throws {
        let row = try decodedSectionsRow()
        let feed = RefsInspectorFeed(
            highlights: row.inspectorEntries,
            sections: row.sections
        )
        XCTAssertEqual(feed.total, 6)
        let entries = feed.entries(visible: 6)
        XCTAssertEqual(entries.map(\.index), Array(0...5))

        XCTAssertEqual(headerTitles(entries[0].leadingHeaders), ["Intro", "Memory"])
        XCTAssertEqual(entries[0].section?.id, "memory")
        XCTAssertTrue(entries[0].showsPageLabel)

        XCTAssertEqual(entries[1].leadingHeaders, [])
        XCTAssertEqual(entries[1].section?.id, "memory")

        XCTAssertEqual(entries[2].leadingHeaders, [])
        XCTAssertEqual(entries[2].section?.id, "memory")

        XCTAssertEqual(headerTitles(entries[3].leadingHeaders), ["Related", "Visuals"])
        XCTAssertTrue(entries[3].showsPageLabel)
        XCTAssertEqual(entries[3].annotation.displayPageLabel, "Page 4")

        XCTAssertEqual(headerTitles(entries[4].leadingHeaders), ["Coda", nil])
        XCTAssertTrue(entries[4].leadingHeaders.contains(.other))
        XCTAssertNil(entries[4].section)
        XCTAssertTrue(entries[4].showsPageLabel)

        XCTAssertEqual(entries[5].leadingHeaders, [])
        XCTAssertEqual(feed.trailingHeaders(visible: 6), [])
        XCTAssertEqual(feed.ungroupedCount, 2)
    }

    func testTrailingEmptyHeadersWaitUntilFullyRevealed() throws {
        let sections = [
            section("memory", title: "Memory", count: 1),
            section("coda", title: "Coda", count: 0),
        ]
        let highlights = [
            RefsShowAnnotation(
                pageLabel: "Page 4",
                quote: "Kept",
                section: "memory"
            )
        ]
        let feed = RefsInspectorFeed(highlights: highlights, sections: sections)
        XCTAssertEqual(feed.trailingHeaders(visible: 0), [])
        XCTAssertEqual(headerTitles(feed.entries(visible: 1)[0].leadingHeaders), ["Memory"])
        XCTAssertEqual(headerTitles(feed.trailingHeaders(visible: 1)), ["Coda"])
        XCTAssertEqual(
            feed.moreText(visible: 0, nextBatch: 1),
            "+1 more · 1 section · ⌃D shows it"
        )
        XCTAssertEqual(feed.hiddenSectionHeaderCount(visible: 0), 1)
    }

    func testOnlyEmptySectionsExposeHeadersImmediately() {
        let sections = [
            section("intro", title: "Intro", count: 0),
            section("coda", title: "Coda", count: 0),
        ]
        let feed = RefsInspectorFeed(highlights: [], sections: sections)
        XCTAssertEqual(feed.total, 0)
        XCTAssertEqual(feed.entries(visible: 0), [])
        XCTAssertEqual(
            headerTitles(feed.trailingHeaders(visible: 0)),
            ["Intro", "Coda"]
        )
    }

    func testUnknownSectionIdFallsIntoOtherWithoutInventedHeading() {
        let sections = [section("memory", title: "Memory", count: 1)]
        let feed = RefsInspectorFeed(
            highlights: [
                RefsShowAnnotation(pageLabel: "1", quote: "Known", section: "memory"),
                RefsShowAnnotation(pageLabel: "2", quote: "Unknown", section: "ghost"),
            ],
            sections: sections
        )
        let entries = feed.entries(visible: 2)
        XCTAssertEqual(headerTitles(entries[0].leadingHeaders), ["Memory"])
        XCTAssertEqual(headerTitles(entries[1].leadingHeaders), [nil])
        XCTAssertNil(entries[1].section)
        XCTAssertEqual(entries[1].accessibilityLabel, "Highlight, Page 2: Unknown")
    }

    func testUnsectionedFeedMatchesToday() {
        let highlights = [
            RefsShowAnnotation(pageLabel: "P1", quote: "A"),
            RefsShowAnnotation(pageLabel: "P1", quote: "B"),
            RefsShowAnnotation(pageLabel: "P2", quote: "C", comment: "Note"),
        ]
        let feed = RefsInspectorFeed(highlights: highlights)
        let entries = feed.entries(visible: 3)
        XCTAssertEqual(entries.map(\.showsPageLabel), [true, false, true])
        XCTAssertTrue(entries.allSatisfy(\.leadingHeaders.isEmpty))
        XCTAssertTrue(entries.allSatisfy { $0.section == nil })
        XCTAssertEqual(feed.trailingHeaders(visible: 3), [])
        XCTAssertEqual(
            entries[0].accessibilityLabel,
            "Highlight, Page P1: A"
        )
        XCTAssertEqual(
            feed.moreText(visible: 1, nextBatch: 2),
            "+2 more · 1 with a note · ⌃D shows the rest"
        )
    }

    func testSamePageLabelRestartsAcrossAHeader() {
        let feed = RefsInspectorFeed(
            highlights: [
                RefsShowAnnotation(pageLabel: "Page 4", quote: "A", section: "memory"),
                RefsShowAnnotation(pageLabel: "Page 4", quote: "B", section: "visuals"),
            ],
            sections: [
                section("memory", title: "Memory", count: 1),
                section("visuals", title: "Visuals", count: 1),
            ]
        )
        let entries = feed.entries(visible: 2)
        XCTAssertEqual(entries.map(\.showsPageLabel), [true, true])
        XCTAssertEqual(headerTitles(entries[1].leadingHeaders), ["Visuals"])
    }

    func testDisclosureCountsSectionStartsNotOther() throws {
        let row = try decodedSectionsRow()
        let feed = RefsInspectorFeed(
            highlights: row.inspectorEntries,
            sections: row.sections
        )
        XCTAssertEqual(feed.hiddenSectionHeaderCount(visible: 0), 5)
        XCTAssertEqual(
            feed.moreText(visible: 0, nextBatch: 5),
            "+6 more · 4 with notes · 5 sections · ⌃D shows 5 more"
        )
        XCTAssertEqual(
            feed.hiddenAccessibilityLabel(visible: 0),
            "6 more highlights, 4 with notes, 5 sections"
        )
        XCTAssertEqual(feed.hiddenSectionHeaderCount(visible: 3), 3)
        XCTAssertEqual(
            feed.moreText(visible: 3, nextBatch: 5),
            "+3 more · 2 with notes · 3 sections · ⌃D shows the rest"
        )
        XCTAssertNil(feed.moreText(visible: 6, nextBatch: 5))
    }

    func testFilteredOutMembersTreatTheSectionAsEmpty() {
        let sections = [
            section("memory", title: "Memory", count: 1),
            section("visuals", title: "Visuals", count: 1),
        ]
        let feed = RefsInspectorFeed(
            highlights: [
                RefsShowAnnotation(
                    pageLabel: "Page 4",
                    kind: "image",
                    asset: "crop.jpg",
                    section: "visuals"
                )
            ],
            sections: sections
        )
        let entry = feed.entries(visible: 1)[0]
        XCTAssertEqual(headerTitles(entry.leadingHeaders), ["Memory", "Visuals"])
        XCTAssertEqual(entry.index, 0)
        XCTAssertEqual(feed.total, 1)
    }

    func testPaginationRangeAndIndexStayFlat() {
        var page = RefsNotesPage(size: 2)
        let feed = RefsInspectorFeed(
            highlights: (0..<5).map { index in
                RefsShowAnnotation(
                    pageLabel: "Page \(index + 1)",
                    quote: "Q\(index)",
                    section: index < 3 ? "memory" : nil
                )
            },
            sections: [section("memory", title: "Memory", count: 3)]
        )
        XCTAssertEqual(page.visibleCount(total: feed.total), 2)
        XCTAssertEqual(feed.entries(visible: 2).map(\.index), [0, 1])
        let revealed = page.reveal(total: feed.total)
        XCTAssertEqual(revealed, 2..<4)
        XCTAssertEqual(page.batchStart, 2)
        let entries = feed.entries(visible: 4)
        XCTAssertEqual(entries.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(headerTitles(entries[3].leadingHeaders), [nil])
        XCTAssertEqual(page.generation, 1)
    }

    func testEntryAccessibilityIncludesSectionTitle() throws {
        let row = try decodedSectionsRow()
        let feed = RefsInspectorFeed(
            highlights: row.inspectorEntries,
            sections: row.sections
        )
        let entries = feed.entries(visible: 6)
        XCTAssertEqual(
            entries[0].accessibilityLabel,
            "Highlight, Memory, Page 4: Make a point about how if I were building AI from scratch."
        )
        XCTAssertEqual(
            entries[1].accessibilityLabel,
            "Highlight with note, Memory, Page 5: Mention that you've implemented project memory every wrong way.. Your note: Compare with the intro"
        )
        XCTAssertEqual(
            entries[2].pieceAccessibilityLabels[0],
            "Highlight, Memory, Page 11: Head words on eleven"
        )
        XCTAssertEqual(
            entries[2].pieceAccessibilityLabels[1],
            "Highlight with note, Memory, continued on Page 12: Tail words on twelve. Your note: Follower note"
        )
        XCTAssertTrue(
            entries[3].accessibilityLabel.hasPrefix("Image highlight, Visuals, Page 4")
        )
        XCTAssertEqual(
            entries[4].accessibilityLabel,
            "Highlight, Page 4: POTENTIAL QUOTES: keep these ungrouped."
        )
        XCTAssertEqual(
            entries[5].accessibilityLabel,
            "Note, Page 8: A standalone note in the ungrouped tail."
        )
        XCTAssertEqual(
            RefsInspectorFeedHeader.section(row.sections[1]).accessibilityLabel(ungroupedCount: 0),
            "Section Memory, 3 highlights. Everything that belongs in the blog's memory section.\n\nKeep the second paragraph."
        )
        XCTAssertEqual(
            RefsInspectorFeedHeader.other.accessibilityLabel(ungroupedCount: 2),
            "Other highlights, 2"
        )
    }

    func testCopyAGroupsNotesAndKeepsLegacyByteIdentical() throws {
        let row = try decodedSectionsRow()
        let grouped = RefsCopyFormat.allNotes(from: row)
        XCTAssertEqual(
            grouped,
            """
            ### Memory

            > Everything that belongs in the blog's memory section.
            >
            > Keep the second paragraph.

            > Mention that you've implemented project memory every wrong way.

            Comment: Compare with the intro

            — Page 5 · [[ref/articles/sections_preview#^h-memory-2]]

            > Head words on eleven

            > Tail words on twelve

            Comment: Follower note

            — Pages 11–12 · [[ref/articles/sections_preview#^h-memory-3]]

            ### Other highlights

            Note: A standalone note in the ungrouped tail.
            — Page 8 · [[ref/articles/sections_preview#^n-other-1]]

            ### Notes

            A short own-notes paragraph.
            """
        )

        let legacy = RefsShowRow(
            path: "ref/chat/a.md",
            annotations: [
                RefsShowAnnotation(kind: "highlight", quote: "First", comment: "First comment"),
                RefsShowAnnotation(kind: "note", comment: "Standalone"),
                RefsShowAnnotation(kind: "highlight", quote: "Second", comment: "Second comment"),
            ]
        )
        XCTAssertEqual(
            RefsCopyFormat.allNotes(from: legacy),
            "> First\n\nComment: First comment\n\nNote: Standalone\n\n> Second\n\nComment: Second comment"
        )
    }

    func testCopyAOmitsEmptyGroupsAndLeavesCopyOneUnchanged() throws {
        let row = RefsShowRow(
            path: "ref/papers/a.md",
            sections: [
                section("memory", title: "Memory", count: 1),
                section("empty", title: "Empty", count: 0),
            ],
            annotations: [
                RefsShowAnnotation(
                    quote: "Uncommented only",
                    section: "memory"
                ),
                RefsShowAnnotation(
                    quote: "Commented",
                    comment: "Keep",
                    section: "memory"
                ),
            ],
            ownNotes: "Own"
        )
        let markdown = RefsCopyFormat.allNotes(from: row)
        XCTAssertTrue(markdown.contains("### Memory"))
        XCTAssertFalse(markdown.contains("### Empty"))
        XCTAssertFalse(markdown.contains("### Other highlights"))
        XCTAssertTrue(markdown.contains("### Notes"))
        XCTAssertEqual(
            RefsCopyFormat.highlightBlock(row.annotations[1]),
            "> Commented\n\nComment: Keep"
        )
        XCTAssertEqual(
            RefsCopyFormat.allHighlights(from: row),
            "> Uncommented only\n\n> Commented\n\nComment: Keep"
        )
    }

    func testPickerGroupRowsNeverTakeDigitsAndKeepEntryNavigation() {
        let row = RefsShowRow(
            path: "ref/papers/a.md",
            sections: [
                section("memory", title: "Memory", count: 2),
                section("empty", title: "Empty", count: 0),
            ],
            annotations: [
                RefsShowAnnotation(quote: "A", section: "memory"),
                RefsShowAnnotation(quote: "B", section: "memory"),
                RefsShowAnnotation(quote: "C"),
            ]
        )
        var picker = RefsHighlightPicker(
            entries: RefsHighlightPicker.entries(from: row),
            windowSize: 9,
            groupHeaderHeight: RefsCopyCardLayout.pickerGroupHeaderHeight
        )
        XCTAssertEqual(picker.entries.count, 3)
        XCTAssertEqual(picker.budgetWindowSize, 9)
        XCTAssertEqual(picker.windowSize, 3)
        let rows = picker.windowRows
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0], .group(title: "Memory"))
        if case .entry(let position, _) = rows[1] {
            XCTAssertEqual(position, 1)
        } else {
            XCTFail("expected digit 1")
        }
        if case .entry(let position, _) = rows[2] {
            XCTAssertEqual(position, 2)
        } else {
            XCTFail("expected digit 2")
        }
        XCTAssertEqual(rows[3], .group(title: "Other highlights"))
        if case .entry(let position, _) = rows[4] {
            XCTAssertEqual(position, 3)
        } else {
            XCTFail("expected digit 3")
        }
        XCTAssertEqual(picker.entry(atWindowPosition: 1)?.annotation.quote, "A")
        picker.move(1)
        XCTAssertEqual(picker.selectedIndex, 1)
        picker.move(1)
        XCTAssertEqual(picker.selectedIndex, 2)
        picker.move(1)
        XCTAssertEqual(picker.selectedIndex, 0)
        XCTAssertEqual(picker.selectWindowPosition(3)?.annotation.quote, "C")
        XCTAssertFalse(
            picker.windowRows.contains { row in
                if case .group(let title) = row { return title == "Empty" }
                return false
            }
        )
    }

    func testPickerMidGroupContextHeaderAndHeaderAwareCapacity() {
        let annotations = (0..<8).map { index in
            RefsShowAnnotation(
                quote: "Q\(index)",
                section: index < 4 ? "memory" : "visuals"
            )
        }
        let row = RefsShowRow(
            path: "ref/papers/a.md",
            sections: [
                section("memory", title: "Memory", count: 4),
                section("visuals", title: "Visuals", count: 4),
            ],
            annotations: annotations
        )
        let picker = RefsHighlightPicker(
            entries: RefsHighlightPicker.entries(from: row),
            selectedIndex: 4,
            windowSize: 3,
            groupHeaderHeight: 0
        )
        XCTAssertEqual(picker.windowStart, 2)
        XCTAssertEqual(picker.windowSize, 3)
        XCTAssertEqual(picker.windowRows.first, .group(title: "Memory"))
        XCTAssertTrue(
            picker.windowRows.contains { row in
                if case .group(let title) = row { return title == "Visuals" }
                return false
            }
        )

        let many = (0..<9).map { index in
            RefsShowAnnotation(quote: "S\(index)", section: "s\(index)")
        }
        let crowded = RefsShowRow(
            path: "ref/papers/a.md",
            sections: (0..<9).map { section("s\($0)", title: "S\($0)", count: 1) },
            annotations: many
        )
        let unsectioned = RefsHighlightPicker(
            entries: many.map { RefsHighlightPicker.Entry(annotation: $0) },
            windowSize: 9
        )
        XCTAssertEqual(unsectioned.windowSize, 9)
        var sectioned = RefsHighlightPicker(
            entries: RefsHighlightPicker.entries(from: crowded),
            windowSize: 9,
            groupHeaderHeight: RefsCopyCardLayout.pickerGroupHeaderHeight
        )
        XCTAssertLessThan(sectioned.windowSize, 9)
        XCTAssertGreaterThanOrEqual(sectioned.windowSize, 1)
        XCTAssertTrue(sectioned.windowStart <= sectioned.selectedIndex)
        XCTAssertTrue(
            sectioned.selectedIndex < sectioned.windowStart + sectioned.windowSize
        )
        sectioned.move(8)
        XCTAssertEqual(sectioned.selectedIndex, 8)
        XCTAssertTrue(sectioned.windowStart <= 8)
        XCTAssertTrue(8 < sectioned.windowStart + sectioned.windowSize)
    }

    func testUnsectionedPickerCapacityUnchanged() {
        let entries = (0..<12).map {
            RefsHighlightPicker.Entry(
                annotation: RefsShowAnnotation(quote: "Q\($0)")
            )
        }
        let picker = RefsHighlightPicker(entries: entries, windowSize: 9)
        XCTAssertEqual(picker.windowSize, 9)
        XCTAssertEqual(picker.windowRows.count, 9)
        XCTAssertTrue(
            picker.windowRows.allSatisfy {
                if case .entry = $0 { return true }
                return false
            }
        )
    }

    private func decodedSectionsRow() throws -> RefsShowRow {
        let response = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: fixtureData("refs-show-sections.json")
        )
        return try XCTUnwrap(response.refs.first)
    }

    private func section(
        _ id: String,
        title: String,
        count: Int
    ) -> RefsShowSection {
        RefsShowSection(id: id, title: title, tag: "@\(id)", count: count)
    }

    private func headerTitles(_ headers: [RefsInspectorFeedHeader]) -> [String?] {
        headers.map { header in
            switch header {
            case .section(let section):
                return section.title
            case .other:
                return nil
            }
        }
    }

    private func fixtureData(_ name: String) throws -> Data {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/\(name)")
        )
    }
}
