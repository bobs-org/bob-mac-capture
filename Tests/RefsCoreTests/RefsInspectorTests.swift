import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Tests for the inspector's RefsCore slice: the `ref show` envelope,
/// the Bottom-line/Abstract extractors, reading-time estimates, and
/// outline cleaning. Text fixtures are modeled on pandoc report page
/// text; the show payload mirrors real `bob ref show -c` output.
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
        XCTAssertEqual(row.remainingCommentCount, 0)
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
            "argv=ref show ref/chat/small_reading.md -f json -c"
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
}
