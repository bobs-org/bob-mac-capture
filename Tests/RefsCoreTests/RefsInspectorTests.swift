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

    func testShowDecodesImageFieldsLossilyAndCleansPaths() throws {
        let row = try JSONDecoder().decode(
            RefsShowRow.self,
            from: Data(
                """
                {"path":"ref/papers/images.md","annotations":[
                  {"kind":"image","asset":" ref/a.jpg ","images":[" ref/b.png ","  "],"unresolved_images":[" missing.heic "]},
                  {"kind":"highlight","quote":"No image fields"},
                  {"kind":"highlight","quote":"Null fields","asset":null,"images":null,"unresolved_images":null},
                  {"kind":"highlight","quote":"Survives malformed image fields","asset":42,"images":"not-an-array","unresolved_images":[7]}
                ]}
                """.utf8
            )
        )

        XCTAssertEqual(row.annotations.count, 4)
        XCTAssertEqual(row.annotations[0].asset, "ref/a.jpg")
        XCTAssertEqual(row.annotations[0].images, ["ref/b.png"])
        XCTAssertEqual(row.annotations[0].unresolvedImages, ["missing.heic"])
        XCTAssertNil(row.annotations[1].asset)
        XCTAssertEqual(row.annotations[1].images, [])
        XCTAssertEqual(row.annotations[1].unresolvedImages, [])
        XCTAssertNil(row.annotations[2].asset)
        XCTAssertEqual(row.annotations[2].images, [])
        XCTAssertEqual(row.annotations[2].unresolvedImages, [])
        XCTAssertEqual(row.annotations[3].quote, "Survives malformed image fields")
        XCTAssertNil(row.annotations[3].asset)
        XCTAssertEqual(row.annotations[3].images, [])
        XCTAssertEqual(row.annotations[3].unresolvedImages, [])
    }

    func testShowDecodesTheTwoVaultImageShapes() throws {
        let response = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: Data(
                """
                {"schema_version":1,"refs":[{"path":"ref/docs/gastown_readme.md","annotations":[{"page_label":"Page 5","kind":"image","quote":null,"comment":null,"asset":"ref/docs/gastown_readme.assets/h-9584a9d023de.jpg","images":[],"unresolved_images":[],"block_id":"h-9584a9d023de"}]},{"path":"ref/blogs/gas_town_emergency_user_manual.md","annotations":[{"page_label":"Page 9","kind":"highlight","quote":"Gas Town crew, Mayor, and Beads Crew tmux sessions","comment":null,"asset":null,"images":["ref/blogs/gas_town_emergency_user_manual.assets/20261019_062455-ec3b885e.png"],"unresolved_images":[],"block_id":"h-36fa970fb80b"}]}]}
                """.utf8
            )
        )

        XCTAssertEqual(response.refs.count, 2)
        XCTAssertEqual(response.refs[0].annotations.first?.asset,
                       "ref/docs/gastown_readme.assets/h-9584a9d023de.jpg")
        XCTAssertEqual(response.refs[1].annotations.first?.images,
                       ["ref/blogs/gas_town_emergency_user_manual.assets/20261019_062455-ec3b885e.png"])
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
        XCTAssertEqual(RefsNotesPage.defaultSize, 5)
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

    func testHighlightsFixtureProjectsInspectorHighlights() throws {
        let response = try JSONDecoder().decode(
            RefsShowResponse.self,
            from: fixtureData("refs-show-highlights.json")
        )
        let row = try XCTUnwrap(response.refs.first)

        XCTAssertEqual(
            row.inspectorHighlights.map(\.quote),
            [
                "Commented highlights keep their place in Your notes.",
                "Uncommented highlights belong under Highlights.",
                "A whitespace-only comment still counts as uncommented.",
                "Same-page highlights share one page label.",
                "The second highlight on this page has no extra label.",
            ]
        )
        XCTAssertEqual(
            row.inspectorHighlights.filter(\.hasComment).map(\.comment),
            ["Keep this in the notes section."]
        )
        XCTAssertEqual(row.commentedHighlights.count, 1)
        XCTAssertEqual(row.highlightPickerEntries.count, 6)
    }

    func testIsInspectorHighlightMembership() {
        XCTAssertTrue(
            RefsShowAnnotation(
                kind: "highlight", quote: "A quote"
            ).isInspectorHighlight
        )
        XCTAssertTrue(
            RefsShowAnnotation(
                kind: "highlight", quote: "A quote", comment: "A note"
            ).isInspectorHighlight
        )
        XCTAssertTrue(
            RefsShowAnnotation(
                kind: "highlight", quote: "", comment: "A note"
            ).isInspectorHighlight
        )
        XCTAssertFalse(
            RefsShowAnnotation(
                kind: "highlight", quote: "", comment: nil
            ).isInspectorHighlight
        )
        XCTAssertFalse(
            RefsShowAnnotation(
                kind: "highlight", quote: "", comment: "  \n\t"
            ).isInspectorHighlight
        )
        XCTAssertFalse(
            RefsShowAnnotation(kind: "note", comment: "Standalone").isInspectorHighlight
        )
        XCTAssertFalse(
            RefsShowAnnotation(
                kind: "image", quote: "a figure"
            ).isInspectorHighlight
        )
    }

    func testInspectorEntriesIncludeImageHighlightsAndStandaloneNotes() {
        let row = RefsShowRow(
            path: "ref/chat/x.md",
            annotations: [
                RefsShowAnnotation(kind: "highlight", quote: "Quote"),
                RefsShowAnnotation(kind: "highlight", images: ["attached.png"]),
                RefsShowAnnotation(kind: "image", asset: "crop.jpg"),
                RefsShowAnnotation(kind: "image", asset: "  "),
                RefsShowAnnotation(kind: "note", comment: "Standalone"),
                RefsShowAnnotation(kind: "note", images: ["note.png"]),
                RefsShowAnnotation(kind: "note", comment: "  "),
                RefsShowAnnotation(kind: "other", quote: "Ignored"),
            ]
        )

        XCTAssertEqual(row.inspectorEntries.map(\.kind), [
            "highlight", "highlight", "image", "note", "note",
        ])
        XCTAssertEqual(row.inspectorHighlights.map(\.quote), ["Quote"])
        XCTAssertEqual(row.inspectorEntries[3].comment, "Standalone")
        XCTAssertEqual(row.inspectorEntries[4].images, ["note.png"])
        XCTAssertEqual(row.commentedHighlights, [])
    }

    func testFeedPageRunsOverOneStream() {
        let feed = RefsInspectorFeed(highlights: [
            highlight(page: "P1", comment: "Noted"),
            highlight(page: "P2"),
            highlight(page: "P2", comment: "Noted"),
            highlight(page: "P3"),
            highlight(page: nil),
            highlight(page: "P3"),
        ])
        let entries = feed.entries(visible: 6)

        XCTAssertEqual(entries.map(\.index), Array(0...5))
        XCTAssertEqual(
            entries.map(\.showsPageLabel),
            [true, true, false, true, false, true]
        )
        XCTAssertEqual(
            entries.map(\.hasNote),
            [true, false, true, false, false, false]
        )
        XCTAssertEqual(feed.entries(visible: -1), [])
        XCTAssertEqual(feed.entries(visible: 0), [])
        XCTAssertEqual(feed.entries(visible: 6).count, 6)
        XCTAssertEqual(feed.entries(visible: 99).count, 6)
    }

    func testFeedMoreTextStrings() {
        XCTAssertEqual(
            makeFeed(count: 27).moreText(visible: 3, nextBatch: 3),
            "+24 more · ⌃D shows 3 more"
        )
        XCTAssertEqual(
            makeFeed(count: 27).moreText(visible: 3, nextBatch: 3),
            RefsNotesPage.moreText(hidden: 24, nextBatch: 3)
        )
        XCTAssertEqual(
            makeFeed(count: 29, noted: [8, 13]).moreText(visible: 3, nextBatch: 3),
            "+26 more · 2 with notes · ⌃D shows 3 more"
        )
        XCTAssertEqual(
            makeFeed(count: 7, noted: [1, 4]).moreText(visible: 3, nextBatch: 3),
            "+4 more · 1 with a note · ⌃D shows 3 more"
        )
        XCTAssertEqual(
            makeFeed(count: 2, noted: [1]).moreText(visible: 1, nextBatch: 1),
            "+1 more · 1 with a note · ⌃D shows it"
        )
        XCTAssertEqual(
            makeFeed(count: 8, noted: Set(0..<8)).moreText(visible: 6, nextBatch: 3),
            "+2 more · 2 with notes · ⌃D shows the rest"
        )
        XCTAssertEqual(
            makeFeed(count: 7, noted: [1]).moreText(visible: 3, nextBatch: 3),
            "+4 more · ⌃D shows 3 more"
        )
        XCTAssertNil(makeFeed(count: 3).moreText(visible: 3, nextBatch: 3))
    }

    func testFeedHiddenAccessibilityLabelRevealAnnouncementAndHeader() {
        XCTAssertEqual(
            makeFeed(count: 27).hiddenAccessibilityLabel(visible: 3),
            "24 more highlights"
        )
        XCTAssertEqual(
            makeFeed(count: 29, noted: [8, 13]).hiddenAccessibilityLabel(visible: 3),
            "26 more highlights, 2 with notes"
        )
        XCTAssertEqual(
            makeFeed(count: 2, noted: [1]).hiddenAccessibilityLabel(visible: 1),
            "1 more highlight, 1 with a note"
        )
        XCTAssertNil(makeFeed(count: 3).hiddenAccessibilityLabel(visible: 3))

        XCTAssertEqual(
            makeFeed(count: 29).revealAnnouncement(visible: 6),
            "Showing 6 of 29 highlights"
        )

        XCTAssertEqual(
            makeFeed(count: 29, noted: [8, 13]).headerAccessibilityLabel,
            "Highlights, 29, 2 with notes"
        )
        XCTAssertEqual(makeFeed(count: 7).headerAccessibilityLabel, "Highlights, 7")
        XCTAssertEqual(
            makeFeed(count: 1, noted: [0]).headerAccessibilityLabel,
            "Highlights, 1, 1 with a note"
        )
    }

    func testFeedImageCountsAppearOnlyForHiddenResolvableImages() {
        let feed = RefsInspectorFeed(
            highlights: [
                highlight(page: "1"),
                RefsShowAnnotation(
                    pageLabel: "2",
                    kind: "image",
                    comment: "A note.",
                    asset: "crop.jpg",
                    images: ["attached.png"],
                    unresolvedImages: ["missing.heic"]
                ),
                RefsShowAnnotation(kind: "note", images: ["note-image.png"]),
            ],
            availableImages: ["crop.jpg", "attached.png", "note-image.png"]
        )

        XCTAssertEqual(feed.hiddenImageCount(visible: 1), 3)
        XCTAssertEqual(feed.hiddenImageCount(visible: 2), 1)
        XCTAssertEqual(feed.hiddenImageCount(visible: 3), 0)
        XCTAssertEqual(
            feed.moreText(visible: 1, nextBatch: 2),
            "+2 more · 2 with notes · 3 images · ⌃D shows the rest"
        )
        XCTAssertEqual(
            feed.hiddenAccessibilityLabel(visible: 1),
            "2 more highlights, 2 with notes, 3 images"
        )
        XCTAssertEqual(
            feed.moreText(visible: 2, nextBatch: 1),
            "+1 more · 1 with a note · 1 image · ⌃D shows it"
        )
    }

    func testFeedAvailabilityCountsAndAccessibilityForMixedImages() {
        let feed = RefsInspectorFeed(
            highlights: [
                RefsShowAnnotation(
                    pageLabel: "5",
                    kind: "image",
                    comment: "Figure.",
                    asset: "crop.jpg",
                    images: ["ok.png", "gone.png", "../secret.jpg"],
                    unresolvedImages: ["camera.heic"]
                ),
                RefsShowAnnotation(
                    pageLabel: "6",
                    kind: "image",
                    asset: "missing-crop.jpg"
                ),
                RefsShowAnnotation(
                    pageLabel: "7",
                    kind: "note",
                    comment: "Standalone note."
                ),
            ],
            availableImages: ["crop.jpg", "ok.png"]
        )
        let entries = feed.entries(visible: 3)

        XCTAssertEqual(feed.hiddenImageCount(visible: 0), 2)
        XCTAssertEqual(feed.hiddenImageCount(visible: 1), 0)
        XCTAssertEqual(feed.notedCount, 2)
        XCTAssertEqual(
            feed.moreText(visible: 0, nextBatch: 5),
            "+3 more · 2 with notes · 2 images · ⌃D shows the rest"
        )
        XCTAssertEqual(
            entries[0].accessibilityLabel,
            "Image highlight, Page 5. Your note: Figure., 1 attached image, "
                + "2 attached images unavailable, 1 image unavailable"
        )
        XCTAssertEqual(
            entries[1].accessibilityLabel,
            "Image highlight, Page 6, 1 image unavailable"
        )
        XCTAssertEqual(
            entries[2].accessibilityLabel,
            "Note, Page 7: Standalone note."
        )
    }

    func testEntryAccessibilityLabelShapes() {
        XCTAssertEqual(
            entry(page: "3", quote: "The quote").accessibilityLabel,
            "Highlight, Page 3: The quote"
        )
        XCTAssertEqual(
            entry(page: nil, quote: "The quote").accessibilityLabel,
            "Highlight: The quote"
        )
        XCTAssertEqual(
            entry(page: "3", quote: "The quote", comment: "Keep.").accessibilityLabel,
            "Highlight with note, Page 3: The quote. Your note: Keep."
        )
        XCTAssertEqual(
            entry(page: nil, quote: "The quote", comment: "Keep.").accessibilityLabel,
            "Highlight with note: The quote. Your note: Keep."
        )
        XCTAssertEqual(
            entry(page: "3", quote: "", comment: "Keep.").accessibilityLabel,
            "Highlight with note, Page 3. Your note: Keep."
        )
        XCTAssertEqual(
            entry(page: nil, quote: "", comment: "Keep.").accessibilityLabel,
            "Highlight with note. Your note: Keep."
        )
        XCTAssertEqual(
            entry(page: "1", quote: "Say **this** now").accessibilityLabel,
            "Highlight, Page 1: Say this now"
        )
        XCTAssertEqual(
            entry(page: "2", quote: "The quote", comment: "  Keep this.  ").accessibilityLabel,
            "Highlight with note, Page 2: The quote. Your note: Keep this."
        )
    }

    func testFeedEntryKindsNoteCardsAndImageAccessibility() {
        let feed = RefsInspectorFeed(
            highlights: [
                RefsShowAnnotation(
                    pageLabel: "5",
                    kind: "image",
                    comment: "Figure note.",
                    asset: "crop.jpg",
                    images: ["attached.png"],
                    unresolvedImages: ["missing.heic"]
                ),
                RefsShowAnnotation(
                    pageLabel: "6",
                    kind: "highlight",
                    quote: "Quoted text",
                    images: ["attached-1.png", "attached-2.png"]
                ),
                RefsShowAnnotation(
                    pageLabel: "7",
                    kind: "note",
                    comment: "Standalone note."
                ),
            ],
            availableImages: [
                "crop.jpg", "attached.png", "attached-1.png", "attached-2.png",
            ]
        )
        let entries = feed.entries(visible: 3)

        XCTAssertEqual(entries.map(\.kind), [.image, .highlight, .note])
        XCTAssertEqual(entries[0].imagePath, "crop.jpg")
        XCTAssertEqual(entries[0].attachedImages, ["attached.png"])
        XCTAssertEqual(entries[0].unresolvedImages, ["missing.heic"])
        XCTAssertEqual(entries.map(\.hasNoteCard), [true, true, true])
        XCTAssertEqual(entries.map(\.hasNote), [true, true, true])
        XCTAssertEqual(feed.notedCount, 3)
        XCTAssertEqual(
            entries[0].accessibilityLabel,
            "Image highlight, Page 5. Your note: Figure note., 1 attached image, 1 image unavailable"
        )
        XCTAssertEqual(
            entries[1].accessibilityLabel,
            "Highlight with note, Page 6: Quoted text, 2 attached images"
        )
        XCTAssertEqual(
            entries[2].accessibilityLabel,
            "Note, Page 7: Standalone note."
        )

        let blankNote = RefsInspectorFeed(
            highlights: [
                RefsShowAnnotation(
                    kind: "note",
                    images: ["attached.png"],
                    unresolvedImages: ["no.png"]
                ),
            ],
            availableImages: ["attached.png"]
        ).entries(visible: 1)[0]
        XCTAssertEqual(
            blankNote.accessibilityLabel,
            "Note, 1 attached image, 1 image unavailable"
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

    func testQuoteEmphasisPlainText() {
        XCTAssertEqual(RefsQuoteEmphasis.plainText("plain text"), "plain text")
        XCTAssertEqual(
            RefsQuoteEmphasis.plainText("Say **this** now"),
            "Say this now"
        )
        XCTAssertEqual(RefsQuoteEmphasis.plainText("hello **"), "hello **")
        XCTAssertEqual(RefsQuoteEmphasis.plainText(""), "")
        XCTAssertEqual(
            entry(page: "1", quote: "Say **this** now").accessibilityLabel,
            "Highlight, Page 1: Say this now"
        )
    }

    func testQuoteExcerptWithoutRunIsUnchanged() {
        XCTAssertEqual(RefsQuoteExcerpt.preview("plain text"), "plain text")
        XCTAssertEqual(RefsQuoteExcerpt.preview("hello **"), "hello **")
        XCTAssertEqual(RefsQuoteExcerpt.preview(""), "")
    }

    func testQuoteExcerptWithEarlyRunIsUnchanged() {
        let quote = "Say **this** now, then keep reading for a while longer."
        XCTAssertEqual(RefsQuoteExcerpt.preview(quote), quote)
    }

    func testQuoteExcerptWithLateRunKeepsALeadIn() {
        let quote =
            "The first hundred pages set the scene in full, introducing every "
            + "minor character and every side plot in turn, before the narrator "
            + "turns at last to the part that really matters, which is **the hinge "
            + "of the whole argument** and everything after it."
        XCTAssertEqual(
            RefsQuoteExcerpt.preview(quote),
            "… to the part that really matters, which is **the hinge of the "
                + "whole argument** and everything after it."
        )
    }

    func testQuoteExcerptLeadInNeverCrossesALineBreak() {
        let first = String(repeating: "setting the scene in full ", count: 8)
        let quote = first + "\n**the hinge** and everything after it."
        XCTAssertEqual(
            RefsQuoteExcerpt.preview(quote),
            "… **the hinge** and everything after it."
        )
    }

    func testQuoteExcerptWithFewWordsBeforeTheRunKeepsThemAll() {
        let scene = String(repeating: "setting the scene in full detail ", count: 5)
        let quote = scene + "a short line\ntiny lead **the hinge** tail."
        XCTAssertEqual(
            RefsQuoteExcerpt.preview(quote),
            "… tiny lead **the hinge** tail."
        )
    }

    func testQuoteExcerptKeepsDelimitersAndSpacing() {
        let scene = String(repeating: "setting the scene in full detail ", count: 5)
        let quote = scene + "keep  double  spaces **the  hinge** tail."
        let excerpt = RefsQuoteExcerpt.preview(quote)
        XCTAssertTrue(excerpt.hasPrefix("… "))
        XCTAssertTrue(excerpt.contains("**the  hinge**"))
        XCTAssertTrue(excerpt.contains("keep  double  spaces "))
        XCTAssertEqual(
            RefsQuoteEmphasis.runs(excerpt).filter(\.isStrong).map(\.text),
            ["the  hinge"]
        )
    }

    func testQuoteExcerptWithFullyStrongQuoteIsUnchanged() {
        let quote = "**" + String(repeating: "wholly emphasized passage ", count: 8) + "**"
        XCTAssertEqual(RefsQuoteExcerpt.preview(quote), quote)
    }

    func testQuoteExcerptWithUnpairedMarkerIsUnchanged() {
        let quote = String(repeating: "setting the scene in full detail ", count: 5)
            + "an unpaired ** marker at the end"
        XCTAssertEqual(RefsQuoteExcerpt.preview(quote), quote)
    }

    func testQuoteExcerptCountsPlainCharactersWithUnicode() {
        let scene = String(repeating: "don’t stop 🎉 believing the scene ", count: 5)
        let quote = scene + "nearly there **the hinge** tail."
        let excerpt = RefsQuoteExcerpt.preview(quote)
        XCTAssertTrue(excerpt.hasPrefix("… "))
        XCTAssertTrue(excerpt.contains("**the hinge**"))
    }

    func testPagingRevealsTheNextPageOfASevenEntryFeed() {
        var page = RefsNotesPage(size: 3)
        let feed = makeFeed(count: 7)
        XCTAssertEqual(page.reveal(total: feed.total), 3..<6)
        XCTAssertEqual(feed.entries(visible: 6).count, 6)
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

    private func makeFeed(count: Int, noted: Set<Int> = []) -> RefsInspectorFeed {
        RefsInspectorFeed(
            highlights: (0..<count).map { index in
                highlight(
                    page: "\(index)",
                    comment: noted.contains(index) ? "Comment \(index)" : nil
                )
            }
        )
    }

    private func entry(
        page: String?,
        quote: String,
        comment: String? = nil
    ) -> RefsInspectorFeed.Entry {
        let feed = RefsInspectorFeed(highlights: [
            highlight(page: page, quote: quote, comment: comment)
        ])
        return feed.entries(visible: 1)[0]
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
