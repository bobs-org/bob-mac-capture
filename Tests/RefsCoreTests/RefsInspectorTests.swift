import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Tests for the inspector's RefsCore slice: the `ref show` envelope,
/// the Bottom-line/Abstract extractors, reading-time estimates, and
/// outline cleaning. Text fixtures are modeled on pandoc report page
/// text; the show payload mirrors real `bob ref show` output.
final class RefsInspectorTests: XCTestCase {
    // MARK: - Show decoding

    func testShowFixtureDecodesAnnotationsAndTasks() throws {
        let response = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: fixtureData("refs-show.json")
        )

        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.refs.count, 1)
        let row = try XCTUnwrap(response.refs.first)
        XCTAssertEqual(row.path, "ref/chat/reading_deep_dive.md")
        XCTAssertEqual(row.annotationsStatus, "parsed")
        XCTAssertEqual(row.annotations.count, 1)
        XCTAssertEqual(row.annotations.first?.pageLabel, "3")
        XCTAssertEqual(row.annotations.first?.kind, "highlight")
        XCTAssertEqual(
            row.annotations.first?.quote,
            "The pipeline drains while the child runs."
        )
        XCTAssertEqual(
            row.annotations.first?.comment,
            "Key insight for the fetcher."
        )
        XCTAssertEqual(row.tasks.count, 1)
        XCTAssertFalse(try XCTUnwrap(row.tasks.first).checked)
        XCTAssertEqual(row.tasks.first?.text, "Follow up.")
    }

    func testShowFieldsAreLossy() throws {
        let row = try JSONDecoder().decode(
            RefsShowRow.self,
            from: Data(
                """
                {"path":"ref/chat/x.md"}
                """.utf8
            )
        )

        XCTAssertEqual(row.path, "ref/chat/x.md")
        XCTAssertEqual(row.annotations, [])
        XCTAssertEqual(row.tasks, [])
        XCTAssertNil(row.annotationsStatus)
    }

    func testShowSkipsUndecodableRows() throws {
        let response = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: Data(
                """
                {"schema_version":1,"refs":[42,{"path":"ref/chat/x.md"}]}
                """.utf8
            )
        )

        XCTAssertEqual(response.refs.count, 1)
        XCTAssertEqual(response.refs.first?.path, "ref/chat/x.md")
    }

    func testMissingAnnotationsVariantDecodesEmpty() throws {
        let response = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: fixtureData("refs-show-no-annotations.json")
        )

        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.refs.count, 1)
        let row = try XCTUnwrap(response.refs.first)
        XCTAssertEqual(row.path, "ref/papers/small_ready.md")
        XCTAssertEqual(row.annotationsStatus, "absent")
        XCTAssertEqual(row.annotations, [])
        XCTAssertEqual(row.tasks, [])
        XCTAssertEqual(row.commentedHighlights, [])
    }

    func testShowFixtureOverrideServesTheVariant() async throws {
        let fetcher = BobRefsFetcher(client: try client(environment: [
            "FAKE_BOB_REFS_SHOW_FIXTURE": "refs-show-no-annotations.json",
        ]))

        let response = try await fetcher.show(path: "ref/papers/small_ready.md")

        XCTAssertEqual(response.refs.count, 1)
        XCTAssertEqual(response.refs.first?.annotationsStatus, "absent")
    }

    func testShowUnknownFieldsAreIgnored() throws {
        let response = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: Data(
                """
                {"schema_version":1,"ok":true,"command":"ref show",
                 "refs":[{"path":"ref/chat/x.md","future_field":"new",
                 "annotations":[{"page_label":"1","kind":"note",
                 "comment":"A note.","asset":null,"block_id":"^a",
                 "link":"[[x#^a]]"}]}]}
                """.utf8
            )
        )

        XCTAssertEqual(response.refs.count, 1)
        XCTAssertEqual(response.refs.first?.annotations.first?.kind, "note")
    }

    func testCommentedHighlightsKeepOnlyCommentedHighlights() throws {
        let row = RefsShowRow(
            path: "ref/chat/x.md",
            annotations: [
                RefsShowAnnotation(pageLabel: "1", kind: "highlight", quote: "A"),
                RefsShowAnnotation(
                    pageLabel: "2",
                    kind: "highlight",
                    quote: "B",
                    comment: "Keep."
                ),
                RefsShowAnnotation(
                    pageLabel: nil,
                    kind: "note",
                    comment: "Standalone."
                ),
                RefsShowAnnotation(
                    pageLabel: "3",
                    kind: "highlight",
                    quote: "C",
                    comment: "  "
                ),
            ]
        )

        XCTAssertEqual(row.commentedHighlights.count, 1)
        XCTAssertEqual(row.commentedHighlights.first?.comment, "Keep.")
    }

    func testCommentedHighlightsReturnAllEightInNoteOrder() throws {
        let annotations = (1...8).map { index in
            RefsShowAnnotation(
                pageLabel: "\(index)",
                kind: "highlight",
                quote: "Quote \(index)",
                comment: "Comment \(index)"
            )
        }
        let row = RefsShowRow(path: "ref/chat/x.md", annotations: annotations)

        XCTAssertEqual(row.commentedHighlights.count, 8)
        XCTAssertEqual(
            row.commentedHighlights.map(\.comment),
            (1...8).map { "Comment \($0)" as String? }
        )
    }

    // MARK: - Notes paging

    func testNotesPageDefaultsAndClampsSize() throws {
        XCTAssertEqual(RefsNotesPage.defaultSize, 3)
        XCTAssertEqual(RefsNotesPage(size: 3).size, 3)
        XCTAssertEqual(RefsNotesPage(size: 0).size, 1)
        XCTAssertEqual(RefsNotesPage(size: 1).size, 1)
        XCTAssertEqual(RefsNotesPage(size: 20).size, 20)
        XCTAssertEqual(RefsNotesPage(size: 99).size, 20)
        XCTAssertEqual(RefsNotesPage.clampedSize(0), 1)
        XCTAssertEqual(RefsNotesPage.clampedSize(99), 20)
    }

    func testNotesPageRevealsEightNotesInPages() throws {
        var page = RefsNotesPage(size: 3)
        XCTAssertEqual(page.visibleCount(total: 8), 3)
        XCTAssertEqual(page.hiddenCount(total: 8), 5)
        XCTAssertEqual(page.nextBatchCount(total: 8), 3)
        XCTAssertNil(page.batchStart)
        XCTAssertEqual(page.generation, 0)

        XCTAssertEqual(page.reveal(total: 8), 3..<6)
        XCTAssertEqual(page.visibleCount(total: 8), 6)
        XCTAssertEqual(page.batchStart, 3)
        XCTAssertEqual(page.generation, 1)

        XCTAssertEqual(page.reveal(total: 8), 6..<8)
        XCTAssertEqual(page.visibleCount(total: 8), 8)
        XCTAssertEqual(page.batchStart, 6)
        XCTAssertEqual(page.generation, 2)

        XCTAssertNil(page.reveal(total: 8))
        XCTAssertEqual(page.generation, 2)
    }

    func testNotesPageShrunkenTotalClampsVisible() throws {
        var page = RefsNotesPage(size: 3)
        XCTAssertEqual(page.reveal(total: 8), 3..<6)
        // The total shrank below shown: the visible count clamps and the
        // next reveal starts at the clamped count or is nil.
        XCTAssertEqual(page.visibleCount(total: 4), 4)
        XCTAssertNil(page.reveal(total: 4))
        var fresh = RefsNotesPage(size: 3)
        XCTAssertEqual(fresh.visibleCount(total: 2), 2)
        XCTAssertNil(fresh.reveal(total: 2))
    }

    func testNotesPageTotalWithinFirstPageRevealsNothing() throws {
        var page = RefsNotesPage(size: 3)
        XCTAssertEqual(page.hiddenCount(total: 3), 0)
        XCTAssertNil(page.reveal(total: 3))
        XCTAssertNil(page.reveal(total: 0))
    }

    func testMoreTextStrings() throws {
        XCTAssertNil(RefsNotesPage.moreText(hidden: 0, nextBatch: 0))
        XCTAssertEqual(
            RefsNotesPage.moreText(hidden: 5, nextBatch: 3),
            "+5 more · ⌃D shows 3 more"
        )
        XCTAssertEqual(
            RefsNotesPage.moreText(hidden: 1, nextBatch: 1),
            "+1 more · ⌃D shows it"
        )
        XCTAssertEqual(
            RefsNotesPage.moreText(hidden: 2, nextBatch: 2),
            "+2 more · ⌃D shows the rest"
        )
    }

    func testDisplayPageLabel() throws {
        XCTAssertEqual(
            RefsShowAnnotation(pageLabel: "Page 1").displayPageLabel,
            "Page 1"
        )
        XCTAssertEqual(
            RefsShowAnnotation(pageLabel: "page 2").displayPageLabel,
            "page 2"
        )
        XCTAssertEqual(
            RefsShowAnnotation(pageLabel: "p. 4").displayPageLabel,
            "p. 4"
        )
        XCTAssertEqual(
            RefsShowAnnotation(pageLabel: "Pages 11–12").displayPageLabel,
            "Pages 11–12"
        )
        XCTAssertEqual(
            RefsShowAnnotation(pageLabel: "pp. 11–12").displayPageLabel,
            "pp. 11–12"
        )
        XCTAssertEqual(
            RefsShowAnnotation(pageLabel: "PP. 11–12").displayPageLabel,
            "PP. 11–12"
        )
        XCTAssertEqual(
            RefsShowAnnotation(pageLabel: "3").displayPageLabel,
            "Page 3"
        )
        XCTAssertNil(RefsShowAnnotation(pageLabel: "  ").displayPageLabel)
        XCTAssertNil(RefsShowAnnotation(pageLabel: nil).displayPageLabel)
    }

    func testHighlightPickerPreservesPluralPageLabels() throws {
        let pages = RefsHighlightPicker.Entry(annotation: RefsShowAnnotation(
            pageLabel: "Pages 11–12", kind: "highlight", quote: "Merged quote"
        ))
        XCTAssertEqual(pages.pageLabel, "pp. 11–12")
        XCTAssertEqual(pages.confirmationTitle, "Copied Highlight · pp. 11–12")

        let short = RefsHighlightPicker.Entry(annotation: RefsShowAnnotation(
            pageLabel: "pp. 11–12", kind: "highlight", quote: "Merged quote"
        ))
        XCTAssertEqual(short.pageLabel, "pp. 11–12")
        XCTAssertEqual(short.confirmationTitle, "Copied Highlight · pp. 11–12")

        let list = RefsHighlightPicker.Entry(annotation: RefsShowAnnotation(
            pageLabel: "pp. 3, 5", kind: "highlight", quote: "Merged quote"
        ))
        XCTAssertEqual(list.pageLabel, "pp. 3, 5")
        XCTAssertEqual(list.confirmationTitle, "Copied Highlight · pp. 3, 5")
    }

    func testHighlightsFixtureProjectsUncommentedHighlights() throws {
        let response = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: fixtureData("refs-show-highlights.json")
        )
        let row = try XCTUnwrap(response.refs.first)

        XCTAssertEqual(row.commentedHighlights.count, 1)
        XCTAssertEqual(
            row.commentedHighlights.first?.comment,
            "Keep this in the notes section."
        )
        XCTAssertEqual(
            row.uncommentedHighlights.map(\.quote),
            [
                "Uncommented highlights belong under Highlights.",
                "A whitespace-only comment still counts as uncommented.",
                "Same-page highlights share one page label.",
                "The second highlight on this page has no extra label.",
            ]
        )
        XCTAssertEqual(row.highlightPickerEntries.count, 6)
    }

    func testFeedEntriesShowPageLabelsPerSectionRun() {
        let feed = RefsInspectorFeed(
            notes: [
                highlight(page: "Page 2", comment: "A"),
                highlight(page: "Page 6", comment: "B"),
            ],
            highlights: [
                highlight(page: "Page 1"),
                highlight(page: "Page 2"),
                highlight(page: "Page 3"),
                highlight(page: "Page 3"),
                highlight(page: "Page 3"),
            ]
        )
        let entries = feed.entries(visible: 7)

        XCTAssertEqual(entries.map(\.index), Array(0...6))
        XCTAssertEqual(
            entries.map(\.section),
            [.notes, .notes, .highlights, .highlights, .highlights, .highlights, .highlights]
        )
        XCTAssertEqual(
            entries.map(\.showsPageLabel),
            [true, true, true, true, true, false, false]
        )
    }

    func testFeedHighlightOnTheLastNotePageStillShowsItsLabel() {
        let feed = RefsInspectorFeed(
            notes: [highlight(page: "Page 2", comment: "Note")],
            highlights: [highlight(page: "Page 2")]
        )
        let entries = feed.entries(visible: 2)

        XCTAssertTrue(entries[0].showsPageLabel)
        XCTAssertEqual(entries[1].section, .highlights)
        XCTAssertTrue(entries[1].showsPageLabel)
    }

    func testFeedNilPageLabelNeverShows() {
        let feed = RefsInspectorFeed(
            notes: [highlight(page: nil, comment: "Note")],
            highlights: [highlight(page: nil), highlight(page: "Page 1")]
        )
        let entries = feed.entries(visible: 3)

        XCTAssertEqual(entries.map(\.showsPageLabel), [false, false, true])
    }

    func testFeedVisibleClampsAtZeroAndTotal() {
        let feed = feed(notes: 2, highlights: 3)
        XCTAssertEqual(feed.entries(visible: -1), [])
        XCTAssertEqual(feed.entries(visible: 0), [])
        XCTAssertEqual(feed.entries(visible: 5).count, 5)
        XCTAssertEqual(feed.entries(visible: 99).count, 5)
    }

    func testFeedMoreTextStrings() {
        XCTAssertEqual(
            feed(notes: 0, highlights: 27).moreText(visible: 3, nextBatch: 3),
            "+24 more · ⌃D shows 3 more"
        )
        XCTAssertEqual(
            feed(notes: 16, highlights: 6).moreText(visible: 3, nextBatch: 3),
            "+13 notes · 6 highlights · ⌃D shows 3 more"
        )
        XCTAssertEqual(
            feed(notes: 3, highlights: 5).moreText(visible: 3, nextBatch: 3),
            "+5 highlights · ⌃D shows 3 more"
        )
        XCTAssertEqual(
            feed(notes: 1, highlights: 1).moreText(visible: 1, nextBatch: 1),
            "+1 highlight · ⌃D shows it"
        )
        XCTAssertEqual(
            feed(notes: 2, highlights: 2).moreText(visible: 1, nextBatch: 1),
            "+1 note · 2 highlights · ⌃D shows 1 more"
        )
        XCTAssertEqual(
            feed(notes: 8, highlights: 0).moreText(visible: 3, nextBatch: 3),
            RefsNotesPage.moreText(hidden: 5, nextBatch: 3)
        )
        XCTAssertEqual(
            feed(notes: 8, highlights: 0).moreText(visible: 3, nextBatch: 3),
            "+5 more · ⌃D shows 3 more"
        )
        XCTAssertNil(feed(notes: 2, highlights: 1).moreText(visible: 3, nextBatch: 3))
    }

    func testFeedHiddenAccessibilityLabelAndRevealAnnouncement() {
        XCTAssertEqual(
            feed(notes: 8, highlights: 0).hiddenAccessibilityLabel(visible: 3),
            "5 more notes"
        )
        XCTAssertEqual(
            feed(notes: 0, highlights: 27).hiddenAccessibilityLabel(visible: 3),
            "24 more highlights"
        )
        XCTAssertEqual(
            feed(notes: 16, highlights: 6).hiddenAccessibilityLabel(visible: 3),
            "13 more notes and 6 highlights"
        )
        XCTAssertEqual(
            feed(notes: 2, highlights: 0).hiddenAccessibilityLabel(visible: 1),
            "1 more note"
        )
        XCTAssertEqual(
            feed(notes: 1, highlights: 1).hiddenAccessibilityLabel(visible: 1),
            "1 more highlight"
        )
        XCTAssertEqual(
            feed(notes: 2, highlights: 2).hiddenAccessibilityLabel(visible: 1),
            "1 more note and 2 highlights"
        )
        XCTAssertNil(feed(notes: 2, highlights: 1).hiddenAccessibilityLabel(visible: 3))

        XCTAssertEqual(
            feed(notes: 8, highlights: 0).revealAnnouncement(visible: 6),
            "Showing 6 of 8 notes"
        )
        XCTAssertEqual(
            feed(notes: 0, highlights: 27).revealAnnouncement(visible: 6),
            "Showing 6 of 27 highlights"
        )
        XCTAssertEqual(
            feed(notes: 2, highlights: 27).revealAnnouncement(visible: 6),
            "Showing 6 of 29 notes and highlights"
        )
    }

    func testQuoteEmphasisRuns() {
        XCTAssertEqual(
            RefsQuoteEmphasis.runs("plain text"),
            [RefsTextRun(text: "plain text", isStrong: false)]
        )
        XCTAssertEqual(
            RefsQuoteEmphasis.runs("Say **this** now"),
            [
                RefsTextRun(text: "Say ", isStrong: false),
                RefsTextRun(text: "this", isStrong: true),
                RefsTextRun(text: " now", isStrong: false),
            ]
        )
        XCTAssertEqual(
            RefsQuoteEmphasis.runs("**A** **B**"),
            [
                RefsTextRun(text: "A", isStrong: true),
                RefsTextRun(text: " ", isStrong: false),
                RefsTextRun(text: "B", isStrong: true),
            ]
        )
        XCTAssertEqual(
            RefsQuoteEmphasis.runs("hello **"),
            [RefsTextRun(text: "hello **", isStrong: false)]
        )
        XCTAssertEqual(
            RefsQuoteEmphasis.runs("a ** b"),
            [RefsTextRun(text: "a ** b", isStrong: false)]
        )
        XCTAssertEqual(RefsQuoteEmphasis.runs("****"), [])
        XCTAssertEqual(RefsQuoteEmphasis.runs(""), [])
        XCTAssertEqual(
            RefsQuoteEmphasis.runs("star * and _under_ and __wide__ and `code`"),
            [RefsTextRun(
                text: "star * and _under_ and __wide__ and `code`",
                isStrong: false
            )]
        )
    }

    func testPagingAcrossTheNotesHighlightsBoundary() {
        var page = RefsNotesPage(size: 3)
        let feed = feed(notes: 2, highlights: 5)
        XCTAssertEqual(page.reveal(total: feed.total), 3..<6)
        let entries = feed.entries(visible: 6)
        XCTAssertEqual(entries.filter { $0.section == .notes }.count, 2)
        XCTAssertEqual(entries.filter { $0.section == .highlights }.count, 4)
    }

    func testRevealAnchorPinsTheHighlightsHeaderAtTheBoundary() {
        let mixed = feed(notes: 2, highlights: 5)
        XCTAssertEqual(mixed.revealAnchor(batchStart: 2), .highlightsHeader)
        XCTAssertEqual(mixed.revealAnchor(batchStart: 3), .entry(3))
        XCTAssertEqual(mixed.revealAnchor(batchStart: 1), .entry(1))

        let highlightsOnly = feed(notes: 0, highlights: 5)
        XCTAssertEqual(highlightsOnly.revealAnchor(batchStart: 3), .entry(3))

        let notesOnly = feed(notes: 4, highlights: 0)
        XCTAssertEqual(notesOnly.revealAnchor(batchStart: 4), .entry(4))
    }

    // MARK: - Show fetcher

    func testShowRunsTheShowArgvOnItsOwnLane() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let fetcher = BobRefsFetcher(client: try client(
            environment: ["FAKE_BOB_RECORD_PATH": recordURL.path]
        ))

        let response = try await fetcher.show(
            path: "ref/chat/small_reading.md"
        )

        XCTAssertEqual(response.refs.count, 1)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains(
            "argv=ref show ref/chat/small_reading.md -f json"
        ))
    }

    func testShowLaneDoesNotCancelTheListLane() async throws {
        let fetcher = BobRefsFetcher(client: try client(environment: [
            "FAKE_BOB_DELAY_SECONDS": "2",
        ]))

        // `ref show` runs on `refs-show`, so a delayed show plus an
        // immediate list resolve independently.
        async let shown = fetcher.show(path: "ref/chat/small_reading.md")
        async let listed = fetcher.list(gitDates: false)
        let (show, list) = try await (shown, listed)

        XCTAssertEqual(show.refs.count, 1)
        XCTAssertEqual(list.refs.count, 6)
    }

    // MARK: - Bottom line

    func testBottomLineFindsAParagraph() throws {
        let summary = try XCTUnwrap(RefsSummaryExtractor.bottomLine(
            fromLeadText: """
            Field Notes on Retrieval

            Bottom line

            Retrieval quality beats index size for this workload.
            """
        ))

        XCTAssertEqual(summary.label, "SUMMARY")
        XCTAssertEqual(
            summary.paragraph,
            "Retrieval quality beats index size for this workload."
        )
        XCTAssertEqual(summary.bullets, [])
    }

    func testBottomLineMatchesHeadingVariants() throws {
        let variants = [
            "tl;dr:",
            "TL;DR",
            "1 Summary:",
            "2.1 Key findings",
            "Executive Summary",
        ]
        for heading in variants {
            let summary = try XCTUnwrap(
                RefsSummaryExtractor.bottomLine(
                    fromLeadText: "\(heading)\n\nThe takeaway."
                ),
                "heading \(heading) should match"
            )
            XCTAssertEqual(summary.paragraph, "The takeaway.")
        }
    }

    func testBottomLineCollectsBullets() throws {
        let summary = try XCTUnwrap(RefsSummaryExtractor.bottomLine(
            fromLeadText: """
            Bottom line
            - First finding
            - Second finding
            - Third finding
            - Fourth finding falls off
            """
        ))

        XCTAssertNil(summary.paragraph)
        XCTAssertEqual(
            summary.bullets,
            ["First finding", "Second finding", "Third finding"]
        )
    }

    func testBottomLineStopsAtABlankLine() throws {
        let summary = try XCTUnwrap(RefsSummaryExtractor.bottomLine(
            fromLeadText: """
            Bottom line

            One paragraph here.

            Method
            """
        ))

        XCTAssertEqual(summary.paragraph, "One paragraph here.")
    }

    func testBottomLineCapsLongParagraphsAtAWordBoundary() throws {
        let long = Array(repeating: "word", count: 100).joined(separator: " ")
        let summary = try XCTUnwrap(RefsSummaryExtractor.bottomLine(
            fromLeadText: "Bottom line\n\n\(long)"
        ))

        let paragraph = try XCTUnwrap(summary.paragraph)
        XCTAssertTrue(paragraph.hasSuffix("…"))
        XCTAssertLessThanOrEqual(paragraph.count, 361)
        XCTAssertFalse(paragraph.dropLast().hasSuffix(" "))
    }

    func testBottomLineReturnsNilWithoutAHeading() throws {
        XCTAssertNil(RefsSummaryExtractor.bottomLine(
            fromLeadText: "Just a report.\n\nNothing marked."
        ))
        XCTAssertNil(RefsSummaryExtractor.bottomLine(
            fromLeadText: "Bottom line\n\n   \n"
        ))
    }

    // MARK: - Abstract

    func testAbstractAfterABareHeading() throws {
        let summary = try XCTUnwrap(RefsSummaryExtractor.abstract(
            fromLeadText: """
            A Harness Study
            Abstract
            We study harness reuse across three workloads.
            """
        ))

        XCTAssertEqual(summary.label, "ABSTRACT")
        XCTAssertEqual(
            summary.paragraph,
            "We study harness reuse across three workloads."
        )
    }

    func testAbstractAfterAPrefixedHeading() throws {
        let dash = try XCTUnwrap(RefsSummaryExtractor.abstract(
            fromLeadText: "Abstract—We measure tail latency."
        ))
        XCTAssertEqual(dash.paragraph, "We measure tail latency.")

        let colon = try XCTUnwrap(RefsSummaryExtractor.abstract(
            fromLeadText: "Abstract: We measure tail latency."
        ))
        XCTAssertEqual(colon.paragraph, "We measure tail latency.")
    }

    func testAbstractCapsAt420Characters() throws {
        let long = Array(repeating: "word", count: 120).joined(separator: " ")
        let summary = try XCTUnwrap(RefsSummaryExtractor.abstract(
            fromLeadText: "Abstract\n\(long)"
        ))

        let paragraph = try XCTUnwrap(summary.paragraph)
        XCTAssertTrue(paragraph.hasSuffix("…"))
        XCTAssertLessThanOrEqual(paragraph.count, 421)
    }

    func testAbstractReturnsNilWithoutAHeading() throws {
        XCTAssertNil(RefsSummaryExtractor.abstract(
            fromLeadText: "A paper with no marked abstract."
        ))
    }

    // MARK: - Reading time

    func testReadingTimeMinimums() throws {
        let empty = RefsReadingTime.estimate(words: 0)
        XCTAssertEqual(empty.minutes, 1)
        XCTAssertEqual(empty.pomodoros, 1)
        XCTAssertEqual(empty.formatted, "≈ 1 min · 1 Pomodoro")
    }

    func testReadingTimeFormatsSingularPomodoro() throws {
        let time = RefsReadingTime.estimate(
            words: 17 * RefsReadingTime.wordsPerMinute
        )

        XCTAssertEqual(time.minutes, 17)
        XCTAssertEqual(time.pomodoros, 1)
        XCTAssertEqual(time.formatted, "≈ 17 min · 1 Pomodoro")
    }

    func testReadingTimeRoundsLongReadsToFive() throws {
        // 23 raw minutes round to 25, which is still 1 Pomodoro.
        let lower = RefsReadingTime.estimate(
            words: 23 * RefsReadingTime.wordsPerMinute
        )
        XCTAssertEqual(lower.minutes, 25)
        XCTAssertEqual(lower.pomodoros, 1)

        // 68 raw minutes round to 70: 3 Pomodoros.
        let upper = RefsReadingTime.estimate(
            words: 68 * RefsReadingTime.wordsPerMinute
        )
        XCTAssertEqual(upper.minutes, 70)
        XCTAssertEqual(upper.pomodoros, 3)
        XCTAssertEqual(upper.formatted, "≈ 70 min · 3 Pomodoros")
    }

    func testReadingTimeCountsPomodorosByCeiling() throws {
        let time = RefsReadingTime.estimate(
            words: 26 * RefsReadingTime.wordsPerMinute
        )

        XCTAssertEqual(time.minutes, 25)
        XCTAssertEqual(time.pomodoros, 1)
    }

    // MARK: - Outline

    func testOutlineCleanTrimsDedupesAndCaps() throws {
        XCTAssertEqual(
            RefsOutline.clean([
                "  Method  ",
                "",
                "Contents",
                "Table of Contents",
                "Method",
                "Results",
                "Discussion",
                "Limits",
                "Related",
                "Appendix",
                "Extra",
            ]),
            ["Method", "Results", "Discussion", "Limits", "Related", "Appendix"]
        )
    }

    // MARK: - Helpers

    private func client(environment: [String: String]) throws -> BobProcessClient {
        BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
                .merging(environment) { _, override in override }
        )
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
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

    private func feed(notes: Int, highlights: Int) -> RefsInspectorFeed {
        RefsInspectorFeed(
            notes: (0..<notes).map {
                highlight(page: "\($0)", comment: "Comment \($0)")
            },
            highlights: (0..<highlights).map {
                highlight(page: "\($0)")
            }
        )
    }

    private func highlight(
        page: String?,
        quote: String = "Quote",
        comment: String? = nil
    ) -> RefsShowAnnotation {
        RefsShowAnnotation(
            pageLabel: page,
            kind: "highlight",
            quote: quote,
            comment: comment
        )
    }
}
