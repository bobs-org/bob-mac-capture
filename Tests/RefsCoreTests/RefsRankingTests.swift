import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Golden tests for RefsCore ranking over the synthetic library
/// (`refs-list-golden.json`): browse sections, tiered search, captions,
/// why-here lines, frozen-listing refresh, selection, and a performance
/// guard. Fixtures use synthetic titles and paths.
final class RefsRankingTests: XCTestCase {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static let fixedNow: Date = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: "2026-10-08T12:00:00Z")!
    }()

    func makeSignals(
        now: Date? = nil,
        today: [(String, String)] = [],
        opens: [RefsOpenEvent] = [],
        headings: [String: [String]] = [:],
        pages: [String: Int] = [:],
        missing: Set<String> = []
    ) -> RefsSignals {
        let now = now ?? Self.fixedNow
        var entries: [String: RefsTodayEntry] = [:]
        for (index, pair) in today.enumerated() {
            entries[pair.0] = RefsTodayEntry(order: index, pomodoroName: pair.1)
        }
        return RefsSignals(
            today: RefsToday(entries: entries),
            opens: RefsOpenStats(events: opens, now: now),
            pageCounts: pages,
            missingPDFs: missing,
            outlineHeadings: headings,
            now: now,
            calendar: Self.utcCalendar
        )
    }

    func makeItem(
        id: String,
        title: String,
        kind: RefKind = .chat,
        state: RefState = .read,
        blocked: Bool = false,
        stem: String? = nil,
        author: String? = nil,
        parentLabel: String? = nil,
        added: String? = "2026-08-01",
        addedApproximate: Bool = false,
        finished: String? = nil,
        arxiv: String? = nil,
        doi: String? = nil,
        annotations: Int = 0
    ) -> RefItem {
        let stem = stem ?? id.split(separator: "/").last.map(String.init) ?? id
        return RefItem(
            id: id,
            link: "[[\(id)]]",
            rawTitle: title,
            stem: stem,
            kind: kind,
            state: state,
            isBlocked: blocked,
            pdfPath: "lib/\(stem).pdf",
            parentLabel: parentLabel,
            author: author,
            added: added.flatMap(RefDay.init(parsing:)),
            addedSource: added == nil ? nil : "created",
            addedIsApproximate: addedApproximate,
            finished: finished.flatMap(RefDay.init(parsing:)),
            annotationCount: annotations,
            arxivID: arxiv,
            doi: doi
        )
    }

    func fixtureData(_ name: String) throws -> Data {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/\(name)")
        )
    }

    func goldenItems() throws -> [RefItem] {
        let response = try JSONDecoder().decode(
            RefsListResponse.self,
            from: fixtureData("refs-list-golden.json")
        )
        return RefsCatalog.items(
            from: RefsSnapshot(fetchedAt: Self.fixedNow, records: response.refs)
        )
    }

    func goldenSignals() throws -> RefsSignals {
        let plan = try JSONDecoder().decode(
            RefsPlanResponse.self,
            from: fixtureData("refs-plan.json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let log = try decoder.decode(
            RefsOpenLogFile.self,
            from: fixtureData("refs-open-log-golden.json")
        )
        return makeSignals(
            today: plan.todayTasks
                .filter { $0.path.hasPrefix("ref/") }
                .map { ($0.path, $0.entryName) },
            opens: log.opens,
            missing: ["ref/chat/missing_pdf_note.md"]
        )
    }

    // MARK: Browse

    func testBrowseSectionsMembershipAndOrder() throws {
        let listing = RefsRanker.listing(
            try goldenItems(), query: "", scope: .all,
            signals: try goldenSignals()
        )

        XCTAssertEqual(listing.mode, .browse)
        XCTAssertEqual(listing.totalCount, 42)
        XCTAssertEqual(listing.openCount, 24)
        let sections = Dictionary(
            uniqueKeysWithValues: listing.sections.map { ($0.kind, $0.ids) }
        )
        XCTAssertEqual(sections[.today], [
            "ref/chat/omnigent_review_notes.md",
            "ref/chat/blog_post_retrospective.md",
            "ref/chat/shipping_second_post.md",
        ])
        XCTAssertEqual(sections[.justAdded], [
            "ref/papers/just_added_attention.md",
            "ref/papers/just_added_router.md",
            "ref/blogs/just_added_weekly.md",
            "ref/docs/just_added_runbook.md",
            "ref/chat/just_added_debrief.md",
        ])
        XCTAssertEqual(sections[.reading], [
            "ref/chat/reading_deep_dive.md",
            "ref/papers/revisiting_attention.md",
            "ref/docs/reading_api_notes.md",
        ])
        XCTAssertEqual(sections[.next], [
            "ref/chat/backtick_heuristics.md",
            "ref/chat/missing_pdf_note.md",
            "ref/chat/next_migration.md",
            "ref/docs/next_blocked_runbook.md",
        ])
        XCTAssertEqual(sections[.ready]?[0], "ref/blogs/morning_roundup.md")
        XCTAssertEqual(sections[.ready]?.last, "ref/blogs/ready_blocked_post.md")
        XCTAssertEqual(sections[.ready]?.count, 9)
        XCTAssertEqual(sections[.recentlyOpened], [
            "ref/blogs/harness_engineering.md",
            "ref/chat/omnigent_launch_review.md",
            "ref/chat/omnigent_internals.md",
            "ref/chat/belated_post.md",
            "ref/blogs/blog00_review.md",
        ])
        XCTAssertEqual(sections[.library]?[0], "ref/papers/old_finished.md")
        XCTAssertEqual(sections[.library]?.count, 13)
        XCTAssertEqual(
            listing.orderedIDs,
            listing.sections.flatMap(\.ids),
            "every item appears once, in section order"
        )
    }

    func testBrowseCapsAndFallThrough() throws {
        let listing = RefsRanker.listing(
            try goldenItems(), query: "   ", scope: .all,
            signals: try goldenSignals()
        )

        XCTAssertEqual(listing.mode, .browse, "whitespace-only input means browse")
        let sections = Dictionary(
            uniqueKeysWithValues: listing.sections.map { ($0.kind, $0.ids) }
        )
        // Seven just-added candidates, capped at five; the annotated
        // morning row is never a candidate.
        XCTAssertEqual(sections[.justAdded]?.count, 5)
        XCTAssertFalse(sections[.justAdded]?.contains("ref/blogs/morning_roundup.md") ?? true)
        // Overflow falls through to the next admitting lane.
        XCTAssertTrue(sections[.ready]?.contains("ref/chat/just_added_standup.md") ?? false)
        XCTAssertTrue(sections[.ready]?.contains("ref/papers/just_added_survey.md") ?? false)
        // Six recently-opened candidates, capped at five; the oldest
        // falls through to the Library head.
        XCTAssertEqual(sections[.recentlyOpened]?.count, 5)
        XCTAssertEqual(sections[.library]?[0], "ref/papers/old_finished.md")
    }

    func testBrowseScopeFilter() throws {
        let listing = RefsRanker.listing(
            try goldenItems(), query: "", scope: .chats,
            signals: try goldenSignals()
        )

        XCTAssertEqual(listing.scope, .chats)
        XCTAssertTrue(listing.totalCount < 42)
        XCTAssertTrue(listing.orderedIDs.allSatisfy { $0.hasPrefix("ref/chat/") })
    }

    // MARK: Search golden expectations

    func searchListing(_ items: [RefItem], query: String, signals: RefsSignals) -> RefsListing {
        RefsRanker.listing(items, query: query, scope: .all, signals: signals)
    }

    func testTodayBeatsTitlePrefix() {
        let items = [
            makeItem(
                id: "a", title: "Field notes on the new Omnigent",
                state: .reading, added: "2026-10-07"
            ),
            makeItem(
                id: "b", title: "Omnigent launch review",
                added: "2026-09-01", finished: "2026-10-03"
            ),
            makeItem(id: "c", title: "Notes on Omnigent internals", added: "2026-08-20"),
        ]
        let signals = makeSignals(today: [("a", "BLOG")])
        let listing = searchListing(items, query: "omnigent", signals: signals)

        XCTAssertEqual(listing.orderedIDs, ["a", "b", "c"])
        XCTAssertTrue(listing.matches.values.allSatisfy { $0.tier == .word })
    }

    func testBlogPostKeepsBothWords() {
        let items = [
            makeItem(
                id: "t1", title: "What the First Blog Post Taught Us",
                state: .reading, added: "2026-10-06"
            ),
            makeItem(
                id: "t2", title: "Shipping the Second Blog Post",
                state: .reading, added: "2026-10-05"
            ),
            makeItem(id: "fin", title: "Blog00 launch post review", added: "2026-08-25"),
            makeItem(id: "dr", title: "A belated blog post", state: .dropped, added: "2026-08-15"),
            makeItem(
                id: "art", title: "Weekly links roundup", kind: .article,
                parentLabel: "Post Hoc Notes", added: "2026-07-01"
            ),
        ]
        let signals = makeSignals(today: [("t1", "BLOG"), ("t2", "BLOG")])
        let listing = searchListing(items, query: "blog post", signals: signals)

        // Both Today rows lead (as a set); then the finished row, then
        // the dropped row, then the kind-word Article row in T3. Chats
        // match a query holding "blog": kind words never hard-filter.
        XCTAssertEqual(Set(listing.orderedIDs.prefix(2)), ["t1", "t2"])
        XCTAssertEqual(Array(listing.orderedIDs.dropFirst(2)), ["fin", "dr", "art"])
        XCTAssertEqual(listing.matches["art"]?.tier, .secondary)
        XCTAssertEqual(listing.matches["art"]?.secondary?.field, .kind)
    }

    func testHarnessSeparatesKindsAndSinksDropped() {
        let items = [
            makeItem(
                id: "p", title: "Harness Engineering for Agent Evals", kind: .paper,
                state: .ready, stem: "harness_engineering", added: "2026-09-05"
            ),
            makeItem(
                id: "ar", title: "Harness Notes From the Field", kind: .article,
                stem: "harness_engineering", added: "2026-08-20"
            ),
            makeItem(
                id: "nz", title: "A Meta-Harness Study of Agents", kind: .paper,
                state: .ready, added: "2026-09-02"
            ),
            makeItem(
                id: "dh", title: "Harness for Breakfast", kind: .paper,
                state: .dropped, added: "2026-08-01"
            ),
        ]
        let listing = searchListing(items, query: "harness", signals: makeSignals())

        XCTAssertEqual(listing.orderedIDs, ["p", "ar", "nz", "dh"])
        XCTAssertTrue(listing.matches.values.allSatisfy { $0.tier == .word })
    }

    func testOmnimetaIsFuzzyOnly() {
        let items = [
            makeItem(
                id: "mh", title: "Introducing Omnigent: A Meta-Harness for Agent Tooling",
                kind: .paper, added: "2026-07-15"
            ),
            makeItem(
                id: "sc", title: "The book campaign engine with drama phoenix after swan song",
                stem: "scattered_notes", added: "2026-07-10"
            ),
        ]
        let listing = searchListing(items, query: "omnimeta", signals: makeSignals())

        XCTAssertEqual(listing.orderedIDs, ["mh"])
        XCTAssertEqual(listing.matches["mh"]?.tier, .fuzzy)
    }

    func testLiuReachesT3ThroughAuthor() {
        let items = [
            makeItem(
                id: "l1", title: "Liu on attention budgets",
                state: .reading, added: "2026-10-01"
            ),
            makeItem(id: "l2", title: "Light UI kit", added: "2026-08-01"),
            makeItem(
                id: "l3", title: "Attention Budgets for Long Contexts", kind: .paper,
                state: .reading, author: "Yangze Liu", added: "2026-10-08"
            ),
        ]
        let listing = searchListing(items, query: "liu", signals: makeSignals())

        XCTAssertEqual(listing.orderedIDs, ["l1", "l2", "l3"])
        XCTAssertEqual(listing.matches["l1"]?.tier, .word)
        XCTAssertEqual(listing.matches["l2"]?.tier, .fuzzy)
        XCTAssertEqual(listing.matches["l3"]?.tier, .secondary)
        XCTAssertEqual(listing.matches["l3"]?.secondary?.field, .author)
    }

    func testIdentityIsExact() {
        let items = [
            makeItem(
                id: "x", title: "A Preprint on Tool Use", kind: .paper,
                added: "2026-06-15", arxiv: "2401.12345"
            ),
            makeItem(
                id: "d", title: "A Published Follow-Up", kind: .paper,
                added: "2026-06-10", doi: "10.1000/xyz123"
            ),
            makeItem(
                id: "o", title: "Another Tool Paper", kind: .paper,
                state: .reading, added: "2026-10-08"
            ),
        ]
        let signals = makeSignals(today: [("o", "BLOG")])

        let arxivListing = searchListing(items, query: "arXiv:2401.12345v2", signals: signals)
        XCTAssertEqual(arxivListing.orderedIDs.first, "x")
        XCTAssertEqual(arxivListing.matches["x"]?.tier, .exact)

        let doiListing = searchListing(items, query: "10.1000/XYZ123", signals: signals)
        XCTAssertEqual(doiListing.orderedIDs.first, "d")
        XCTAssertEqual(doiListing.matches["d"]?.tier, .exact)
    }

    // MARK: Search policy

    func testShortQueryPolicy() {
        let items = [
            makeItem(id: "A", title: "Omnigent launch review"),
            makeItem(id: "B", title: "Deep Dive: the Capture Pipeline"),
            makeItem(id: "C", title: "Bloom filter notes"),
        ]
        let signals = makeSignals()

        let one = searchListing(items, query: "o", signals: signals)
        XCTAssertEqual(one.orderedIDs, ["A"])
        XCTAssertEqual(one.matches["A"]?.tier, .word)

        let two = searchListing(items, query: "om", signals: signals)
        XCTAssertEqual(two.orderedIDs, ["A", "C"])
        XCTAssertTrue(two.matches.values.allSatisfy { $0.tier == .fuzzy })

        let three = searchListing(items, query: "omn", signals: signals)
        XCTAssertEqual(three.orderedIDs, ["A", "C"])
        XCTAssertEqual(three.matches["A"]?.tier, .word)
        XCTAssertEqual(three.matches["C"]?.tier, .fuzzy)
    }

    func testANDSemantics() {
        let items = [
            makeItem(id: "only", title: "Blogroll proviso", stem: "blogroll_proviso"),
        ]
        let listing = searchListing(items, query: "blog post", signals: makeSignals())

        XCTAssertTrue(listing.orderedIDs.isEmpty, "every token must match somewhere")
    }

    func testTiersNeverCross() {
        let items = [
            makeItem(id: "r1", title: "Harness Engineering", state: .reading, added: "2026-10-07"),
            makeItem(id: "r2", title: "Harnss Tools", state: .dropped, added: "2020-01-01"),
        ]
        let signals = makeSignals(today: [("r1", "BLOG")])
        let listing = searchListing(items, query: "harnss", signals: signals)

        let fuzzyScore = listing.matches["r1"]?.score ?? 0
        let wordScore = listing.matches["r2"]?.score ?? 0
        XCTAssertGreaterThan(fuzzyScore, wordScore)
        XCTAssertEqual(listing.orderedIDs, ["r2", "r1"], "rows never cross tiers")
    }

    func testDeterministicTies() {
        let items = [
            makeItem(id: "b", title: "The Same Title Twice", added: "2026-08-10"),
            makeItem(id: "a", title: "The Same Title Twice", added: "2026-08-10"),
        ]
        let signals = makeSignals()
        let first = searchListing(items, query: "same title", signals: signals)
        let second = searchListing(items, query: "same title", signals: signals)

        XCTAssertEqual(first.orderedIDs, ["a", "b"], "the final tie-break is id ascending")
        XCTAssertEqual(first, second, "identical inputs produce identical order")
    }

    func testHighlightRanges() {
        let items = [
            makeItem(id: "a", title: "Omnigent launch review"),
            makeItem(id: "s", title: "Weekly links roundup", stem: "omnigent_notes"),
            makeItem(
                id: "t", title: "Attention Budgets for Long Contexts",
                kind: .paper, author: "Yangze Liu"
            ),
        ]
        let signals = makeSignals()
        let titleListing = searchListing(items, query: "omnigent", signals: signals)
        XCTAssertEqual(titleListing.matches["a"]?.titleRanges, [0..<8])
        XCTAssertTrue(titleListing.matches["a"]?.stemRanges.isEmpty ?? false)

        let stemListing = searchListing(items, query: "omnigent", signals: signals)
        XCTAssertTrue((stemListing.matches["s"]?.titleRanges.isEmpty) ?? false)
        XCTAssertEqual(stemListing.matches["s"]?.stemRanges, [0..<8])

        let authorListing = searchListing(items, query: "liu", signals: signals)
        XCTAssertEqual(authorListing.matches["t"]?.secondary?.field, .author)
        XCTAssertEqual(authorListing.matches["t"]?.secondary?.text, "Yangze Liu")
    }

    // MARK: Captions and explanations

    func testCaptions() {
        let paper = makeItem(
            id: "p", title: "Attention Budgets", kind: .paper,
            state: .reading, author: "M. Chen", added: "2026-09-20"
        )
        var signals = makeSignals(pages: ["p": 22])
        XCTAssertEqual(
            RefsCaption.caption(for: paper, in: .reading, signals: signals),
            "Paper · M. Chen · added Sep 20 · 22 pp"
        )

        let approx = makeItem(
            id: "g", title: "A Note With Only Git Dates", state: .ready,
            added: "2026-09-12", addedApproximate: true
        )
        XCTAssertEqual(
            RefsCaption.caption(for: approx, in: .ready, signals: signals),
            "Chat · added ≈ Sep 12"
        )

        let opened = makeItem(
            id: "r", title: "Deep Dive", state: .reading, added: "2026-09-20"
        )
        signals = makeSignals(
            opens: [RefsOpenEvent(path: "r", at: Self.fixedNow.addingTimeInterval(-2 * 3_600))]
        )
        XCTAssertEqual(
            RefsCaption.caption(for: opened, in: .reading, signals: signals),
            "Chat · opened 2h ago"
        )

        let missing = makeItem(id: "m", title: "A Gone PDF", state: .next, added: "2026-09-11")
        signals = makeSignals(missing: ["m"])
        XCTAssertEqual(
            RefsCaption.caption(for: missing, in: .next, signals: signals),
            "Chat · added Sep 11 · PDF missing"
        )
    }

    func testSearchCaptionsShowStemOrSecondary() {
        let stemOnly = makeItem(id: "s", title: "Weekly links roundup", stem: "omnigent_notes")
        let signals = makeSignals()
        let listing = searchListing([stemOnly], query: "omnigent", signals: signals)
        let match = listing.matches["s"]
        XCTAssertNotNil(match)
        XCTAssertTrue(match?.titleRanges.isEmpty ?? false)
        XCTAssertEqual(
            RefsCaption.caption(for: stemOnly, in: nil, signals: signals, match: match),
            "Chat · added Aug 1 · omnigent_notes"
        )

        let authorRow = makeItem(
            id: "t", title: "Attention Budgets for Long Contexts",
            kind: .paper, author: "Yangze Liu"
        )
        let authorListing = searchListing([authorRow], query: "liu", signals: signals)
        let authorMatch = authorListing.matches["t"]
        XCTAssertEqual(
            RefsCaption.caption(for: authorRow, in: nil, signals: signals, match: authorMatch),
            "Paper · Yangze Liu · added Aug 1 · Yangze Liu"
        )
    }

    func testWhyHereBrowseForms() {
        let now = Self.fixedNow
        let items = [
            makeItem(id: "today", title: "Field notes", state: .reading, added: "2026-10-07"),
            makeItem(id: "added", title: "Fresh arrival", state: .ready, added: "2026-10-08"),
            makeItem(id: "reading", title: "Deep Dive", state: .reading, added: "2026-09-20"),
            makeItem(
                id: "next", title: "Blocked runbook", state: .next,
                blocked: true, added: "2026-09-08"
            ),
            makeItem(id: "ready", title: "A Ready Survey", state: .ready, added: "2026-10-03"),
            makeItem(
                id: "recent", title: "Old review",
                added: "2026-09-01", finished: "2026-10-03"
            ),
            makeItem(id: "lib", title: "Old paper", kind: .paper, added: "2026-09-02"),
        ]
        let signals = makeSignals(
            today: [("today", "BLOG")],
            opens: [
                RefsOpenEvent(path: "reading", at: now.addingTimeInterval(-2 * 3_600)),
                RefsOpenEvent(path: "recent", at: now.addingTimeInterval(-3 * 86_400)),
            ]
        )
        let listing = RefsRanker.listing(items, query: "", scope: .all, signals: signals)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        XCTAssertEqual(
            RefsExplanation.whyHere(byID["today"]!, listing: listing, signals: signals),
            "In Today · BLOG Pomodoro"
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(byID["added"]!, listing: listing, signals: signals),
            "Just added Oct 8 · never opened"
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(byID["reading"]!, listing: listing, signals: signals),
            "Reading · opened 2 hours ago"
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(byID["next"]!, listing: listing, signals: signals),
            "In your Next lane · blocked"
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(byID["ready"]!, listing: listing, signals: signals),
            "Ready · added Oct 3"
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(byID["recent"]!, listing: listing, signals: signals),
            "Opened 3 days ago"
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(byID["lib"]!, listing: listing, signals: signals),
            "Library · last activity Sep 2"
        )
    }

    func testWhyHereSearchForms() {
        let signals = makeSignals(
            today: [("w", "BLOG")],
            headings: ["h": ["Outline heading here"]]
        )
        let word = makeItem(id: "w", title: "Omnigent launch review", state: .reading)
        XCTAssertEqual(
            RefsExplanation.whyHere(
                word, listing: searchListing([word], query: "omnigent", signals: signals),
                signals: signals
            ),
            "Title word match · Reading"
        )

        let fuzzy = makeItem(id: "f", title: "Introducing Omnigent: A Meta-Harness")
        XCTAssertEqual(
            RefsExplanation.whyHere(
                fuzzy, listing: searchListing([fuzzy], query: "omnimeta", signals: signals),
                signals: signals
            ),
            "Fuzzy title match"
        )

        let author = makeItem(id: "a", title: "Attention Budgets", author: "Yangze Liu")
        XCTAssertEqual(
            RefsExplanation.whyHere(
                author, listing: searchListing([author], query: "liu", signals: signals),
                signals: signals
            ),
            "Matched author"
        )

        let area = makeItem(id: "r", title: "Weekly links roundup", parentLabel: "Post Hoc Notes")
        XCTAssertEqual(
            RefsExplanation.whyHere(
                area, listing: searchListing([area], query: "hoc", signals: signals),
                signals: signals
            ),
            "Matched area"
        )

        let kind = makeItem(id: "k", title: "Deep Dive: the Capture Pipeline")
        XCTAssertEqual(
            RefsExplanation.whyHere(
                kind, listing: searchListing([kind], query: "agent", signals: signals),
                signals: signals
            ),
            "Matched kind"
        )

        let heading = makeItem(id: "h", title: "Deep Dive: the Capture Pipeline")
        XCTAssertEqual(
            RefsExplanation.whyHere(
                heading, listing: searchListing([heading], query: "outline", signals: signals),
                signals: signals
            ),
            "Matched heading"
        )

        let arxiv = makeItem(id: "x", title: "A Preprint on Tool Use", arxiv: "2401.12345")
        XCTAssertEqual(
            RefsExplanation.whyHere(
                arxiv,
                listing: searchListing([arxiv], query: "arXiv:2401.12345v2", signals: signals),
                signals: signals
            ),
            "Exact arXiv id"
        )
    }

    // MARK: Stability and selection

    func testRefreshingContentKeepsOrderAndReportsUnavailable() throws {
        let listing = RefsRanker.listing(
            try goldenItems(), query: "", scope: .all,
            signals: try goldenSignals()
        )

        let gone: Set<String> = [
            "ref/chat/omnigent_review_notes.md",
            "ref/papers/old_finished.md",
        ]
        let available = Set(listing.orderedIDs).subtracting(gone)
        let (refreshed, unavailable) = listing.refreshingContent(availableIDs: available)

        XCTAssertEqual(unavailable, gone)
        XCTAssertEqual(refreshed.orderedIDs, listing.orderedIDs.filter { available.contains($0) })
        XCTAssertEqual(refreshed.mode, listing.mode)
        // The Today section loses a row but keeps its order; no header
        // stands alone on an emptied section.
        XCTAssertTrue(refreshed.sections.allSatisfy { !$0.ids.isEmpty })
        XCTAssertEqual(refreshed.totalCount, listing.totalCount)
    }

    func testSelectionPolicy() throws {
        let listing = RefsRanker.listing(
            try goldenItems(), query: "", scope: .all,
            signals: try goldenSignals()
        )

        XCTAssertEqual(
            RefsSelectionPolicy.initial(in: listing),
            "ref/chat/omnigent_review_notes.md"
        )
        // Wrapping navigation over the frozen order.
        XCTAssertEqual(
            RefsSelectionPolicy.move(
                .next, from: listing.orderedIDs.last, in: listing, pageSize: 10
            ),
            listing.orderedIDs.first
        )
        XCTAssertEqual(
            RefsSelectionPolicy.move(
                .previous, from: listing.orderedIDs.first, in: listing,
                pageSize: 10
            ),
            listing.orderedIDs.last
        )
        // Unknown selections resolve to the first row.
        XCTAssertEqual(
            RefsSelectionPolicy.move(.next, from: "ref/chat/gone.md", in: listing, pageSize: 10),
            listing.orderedIDs.first
        )
        // Paging clamps to the ends.
        XCTAssertEqual(
            RefsSelectionPolicy.move(
                .pageDown, from: listing.orderedIDs.first, in: listing,
                pageSize: 10_000
            ),
            listing.orderedIDs.last
        )
        // Section jumps land on section heads in browse mode.
        XCTAssertEqual(
            RefsSelectionPolicy.move(
                .nextSection, from: "ref/chat/omnigent_review_notes.md",
                in: listing, pageSize: 10
            ),
            "ref/papers/just_added_attention.md"
        )
        XCTAssertEqual(
            RefsSelectionPolicy.move(
                .previousSection, from: "ref/papers/just_added_attention.md",
                in: listing, pageSize: 10
            ),
            "ref/chat/omnigent_review_notes.md"
        )
        // Section jumps are a no-op in search mode.
        let search = RefsRanker.listing(
            try goldenItems(), query: "harness", scope: .all,
            signals: try goldenSignals()
        )
        let selected = search.orderedIDs.first
        XCTAssertEqual(
            RefsSelectionPolicy.move(.nextSection, from: selected, in: search, pageSize: 10),
            selected
        )
    }





    func testPerformanceGuard() {
        var items: [RefItem] = []
        items.reserveCapacity(10_000)
        for index in 0..<10_000 {
            items.append(makeItem(
                id: String(format: "ref/chat/synthetic_%05d.md", index),
                title: "Synthetic agent report number \(index) on harness engineering",
                state: index % 3 == 0 ? .reading : .ready,
                added: "2026-09-\(String(format: "%02d", index % 28 + 1))"
            ))
        }
        let signals = makeSignals()
        let start = Date()
        let listing = RefsRanker.listing(
            items, query: "harness engineering", scope: .all, signals: signals
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(listing.orderedIDs.count, 10_000)
        XCTAssertLessThan(elapsed, 1.0, "10,000 synthetic items rank in under 1 s")
    }
}
