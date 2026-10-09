import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Model tests: kind/state/scope tables, the blocked overlay, RefDay,
/// disambiguators, parent labels, git-date merging, and snapshot filtering.
final class RefsModelTests: XCTestCase {
    func testKindMappingTable() {
        XCTAssertEqual(RefKind(refType: "chat"), .chat)
        XCTAssertEqual(RefKind(refType: "papers"), .paper)
        XCTAssertEqual(RefKind(refType: "blogs"), .article)
        XCTAssertEqual(RefKind(refType: "docs"), .doc)
        XCTAssertEqual(RefKind(refType: "books"), .book)
        XCTAssertEqual(RefKind(refType: "slides"), .slides)
        XCTAssertEqual(RefKind(refType: "code"), .other(raw: "code"))
        XCTAssertEqual(RefKind(refType: nil), .other(raw: nil))

        XCTAssertEqual(RefKind.chat.label, "Chat")
        XCTAssertEqual(RefKind.paper.label, "Paper")
        XCTAssertEqual(RefKind.article.label, "Article")
        XCTAssertEqual(RefKind.doc.label, "Doc")
        XCTAssertEqual(RefKind.book.label, "Book")
        XCTAssertEqual(RefKind.slides.label, "Slides")
        XCTAssertEqual(RefKind(refType: "code").label, "Code")
        XCTAssertEqual(RefKind(refType: nil).label, "Reference")

        XCTAssertEqual(RefKind.chat.symbolName, "bubble.left.and.bubble.right")
        XCTAssertEqual(RefKind.paper.symbolName, "graduationcap")
        XCTAssertEqual(RefKind.article.symbolName, "newspaper")
        XCTAssertEqual(RefKind.doc.symbolName, "book.closed")
        XCTAssertEqual(RefKind.book.symbolName, "books.vertical")
        XCTAssertEqual(RefKind.slides.symbolName, "rectangle.on.rectangle")
        XCTAssertEqual(RefKind(refType: "code").symbolName, "doc")
    }

    func testKindScopeMapping() {
        XCTAssertEqual(RefKind.chat.scope, .chats)
        XCTAssertEqual(RefKind.paper.scope, .papers)
        XCTAssertEqual(RefKind.article.scope, .articles)
        XCTAssertEqual(RefKind.doc.scope, .docs)
        XCTAssertNil(RefKind.book.scope)
        XCTAssertNil(RefKind.slides.scope)
        XCTAssertNil(RefKind(refType: "code").scope)
        XCTAssertNil(RefKind(refType: nil).scope)
    }

    func testScopeContains() {
        XCTAssertTrue(RefScope.all.contains(.book))
        XCTAssertTrue(RefScope.chats.contains(.chat))
        XCTAssertFalse(RefScope.chats.contains(.paper))
        XCTAssertTrue(RefScope.papers.contains(.paper))
        XCTAssertTrue(RefScope.articles.contains(.article))
        XCTAssertFalse(RefScope.articles.contains(.doc))
        XCTAssertTrue(RefScope.docs.contains(.doc))
        XCTAssertFalse(RefScope.docs.contains(.other(raw: "code")))
        XCTAssertEqual(RefScope.all.label, "All")
        XCTAssertEqual(RefScope.allCases.map(\.rawValue), [1, 2, 3, 4, 5])
    }

    func testStatusMappingTable() {
        XCTAssertEqual(RefState(status: "wip", readingState: nil), .reading)
        XCTAssertEqual(RefState(status: "next", readingState: nil), .next)
        XCTAssertEqual(RefState(status: "ready", readingState: nil), .ready)
        XCTAssertEqual(RefState(status: "read", readingState: nil), .read)
        XCTAssertEqual(RefState(status: "abandoned", readingState: nil), .dropped)
    }

    func testUnknownStatusFallsBackToReadingState() {
        XCTAssertEqual(RefState(status: "legacy", readingState: "queued"), .ready)
        XCTAssertEqual(RefState(status: nil, readingState: "started"), .reading)
        XCTAssertEqual(RefState(status: nil, readingState: "queued"), .ready)
        XCTAssertEqual(RefState(status: nil, readingState: "finished"), .read)
        XCTAssertEqual(RefState(status: nil, readingState: "dropped"), .dropped)
        XCTAssertEqual(RefState(status: nil, readingState: "mysterious"), .unknown)
        XCTAssertEqual(RefState(status: nil, readingState: nil), .unknown)
    }

    func testBlockedIsAnOverlayOnTheLane() throws {
        let items = try goldenItems()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        let blockedNext = try XCTUnwrap(byID["ref/docs/next_blocked_runbook.md"])
        XCTAssertTrue(blockedNext.isBlocked)
        XCTAssertEqual(blockedNext.state, .next)

        let blockedReady = try XCTUnwrap(byID["ref/blogs/ready_blocked_post.md"])
        XCTAssertTrue(blockedReady.isBlocked)
        XCTAssertEqual(blockedReady.state, .ready)

        XCTAssertFalse(try XCTUnwrap(byID["ref/chat/next_migration.md"]).isBlocked)
    }

    func testRefDayParsingComparisonAndValidation() {
        XCTAssertEqual(
            RefDay(parsing: "2026-10-08"),
            RefDay(year: 2026, month: 10, day: 8)
        )
        XCTAssertLessThan(
            RefDay(parsing: "2026-10-07")!,
            RefDay(parsing: "2026-10-08")!
        )
        XCTAssertNil(RefDay(parsing: "2026-13-01"))
        XCTAssertNil(RefDay(parsing: "2026-02-30"))
        XCTAssertNil(RefDay(parsing: "2023-02-29"))
        XCTAssertNotNil(RefDay(parsing: "2024-02-29"))
        XCTAssertNil(RefDay(parsing: "not-a-date"))
        XCTAssertNil(RefDay(parsing: "2026-1-1"))
        XCTAssertEqual(RefDay(year: 2026, month: 10, day: 8).isoString, "2026-10-08")
    }

    func testTitleDisambiguatorMarksOnlyCollisions() throws {
        let items = try goldenItems()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        XCTAssertEqual(
            try XCTUnwrap(byID["ref/chat/same_title_a.md"]).titleDisambiguator,
            "same_title_a"
        )
        XCTAssertEqual(
            try XCTUnwrap(byID["ref/blogs/same_title_b.md"]).titleDisambiguator,
            "same_title_b"
        )
        XCTAssertNil(
            try XCTUnwrap(byID["ref/chat/omnigent_review_notes.md"]).titleDisambiguator
        )
    }

    func testParentLabelStripsBracketsAndRefSuffix() {
        XCTAssertEqual(RefItem.parentLabel(from: "obsidian_ref"), "obsidian")
        XCTAssertEqual(RefItem.parentLabel(from: "[[obsidian_ref]]"), "obsidian")
        XCTAssertEqual(RefItem.parentLabel(from: "plain"), "plain")
        XCTAssertNil(RefItem.parentLabel(from: nil))
    }

    func testBacktickTitleParsesToCodeSegments() throws {
        let items = try goldenItems()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let item = try XCTUnwrap(byID["ref/chat/backtick_heuristics.md"])

        XCTAssertEqual(item.rawTitle, "`%auto` Heuristics: When to Split Epics")
        XCTAssertEqual(item.title.text, "%auto Heuristics: When to Split Epics")
        XCTAssertTrue(item.title.segments.contains { $0.kind == .code })
        XCTAssertEqual(item.stem, "backtick_heuristics")
    }

    func testGitAddedMergesOnlyIntoDatelessRows() {
        let dated = RefRecord(
            path: "ref/chat/dated.md",
            link: "[[ref/chat/dated]]",
            title: "Dated",
            added: "2026-10-01",
            addedSource: "created",
            sourcePDF: "lib/chat/dated.pdf"
        )
        let dateless = RefRecord(
            path: "ref/chat/dateless.md",
            link: "[[ref/chat/dateless]]",
            title: "Dateless",
            sourcePDF: "lib/chat/dateless.pdf"
        )
        let git = ["ref/chat/dated.md": "2026-09-01", "ref/chat/dateless.md": "2026-09-02"]

        let datedItem = RefItem.make(from: dated, gitAddedDates: git)!
        XCTAssertEqual(datedItem.added, RefDay(year: 2026, month: 10, day: 1))
        XCTAssertEqual(datedItem.addedSource, "created")
        XCTAssertFalse(datedItem.addedIsApproximate)

        let datelessItem = RefItem.make(from: dateless, gitAddedDates: git)!
        XCTAssertEqual(datelessItem.added, RefDay(year: 2026, month: 9, day: 2))
        XCTAssertEqual(datelessItem.addedSource, "git")
        XCTAssertTrue(datelessItem.addedIsApproximate)
    }

    func testGitFinishedIsIgnored() {
        let record = RefRecord(
            path: "ref/chat/x.md",
            link: "[[ref/chat/x]]",
            title: "X",
            finished: "2026-01-15",
            finishedSource: "git",
            sourcePDF: "lib/chat/x.pdf"
        )

        XCTAssertNil(RefItem.make(from: record, gitAddedDates: [:])!.finished)
    }

    func testNonGitFinishedSurvives() {
        let record = RefRecord(
            path: "ref/chat/x.md",
            link: "[[ref/chat/x]]",
            title: "X",
            finished: "2026-10-03",
            finishedSource: "ref_task",
            sourcePDF: "lib/chat/x.pdf"
        )

        XCTAssertEqual(
            RefItem.make(from: record, gitAddedDates: [:])!.finished,
            RefDay(year: 2026, month: 10, day: 3)
        )
    }

    func testCatalogFiltersUnsafeAndMissingPDFs() {
        func record(path: String, pdf: String?) -> RefRecord {
            RefRecord(
                path: path,
                link: "[[\(path)]]",
                title: path,
                sourcePDF: pdf
            )
        }
        let snapshot = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1),
            records: [
                record(path: "ref/chat/ok.md", pdf: "lib/chat/ok.pdf"),
                record(path: "ref/chat/empty.md", pdf: ""),
                record(path: "ref/chat/missing.md", pdf: nil),
                record(path: "ref/chat/absolute.md", pdf: "/tmp/evil.pdf"),
                record(path: "ref/chat/traversal.md", pdf: "lib/../evil.pdf"),
            ]
        )

        let items = RefsCatalog.items(from: snapshot)

        XCTAssertEqual(items.map(\.id), ["ref/chat/ok.md"])
    }

    func testCatalogSortsByID() throws {
        let items = try goldenItems()
        let ids = items.map(\.id)

        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(ids.first, "ref/blogs/blog00_review.md")
    }

    func testIsAgentReportFollowsOrigin() {
        let report = RefRecord(
            path: "ref/chat/x.md",
            link: "[[ref/chat/x]]",
            title: "X",
            origin: "agent-report",
            sourcePDF: "lib/chat/x.pdf"
        )
        let other = RefRecord(
            path: "ref/chat/y.md",
            link: "[[ref/chat/y]]",
            title: "Y",
            sourcePDF: "lib/chat/y.pdf"
        )

        XCTAssertTrue(RefItem.make(from: report, gitAddedDates: [:])!.isAgentReport)
        XCTAssertFalse(RefItem.make(from: other, gitAddedDates: [:])!.isAgentReport)
    }

    func testPathsNeedingGitDates() throws {
        let response = try JSONDecoder().decode(
            RefsListResponse.self,
            from: Self.fixtureData("refs-list.json")
        )
        let snapshot = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1),
            records: response.refs
        )

        XCTAssertEqual(
            Set(snapshot.pathsNeedingGitDates),
            ["ref/blogs/small_opened.md", "ref/books/small_book.md"]
        )
    }

    func goldenItems() throws -> [RefItem] {
        let response = try JSONDecoder().decode(
            RefsListResponse.self,
            from: Self.fixtureData("refs-list-golden.json")
        )
        return RefsCatalog.items(
            from: RefsSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1),
                records: response.refs
            )
        )
    }

    static func fixtureData(_ name: String) throws -> Data {
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
