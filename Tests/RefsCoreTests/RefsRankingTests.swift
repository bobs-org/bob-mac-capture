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
        // The golden `git_added_note` row carries no `added` date in the
        // plain list (live `bob` never emits one); its date arrives
        // through the `-g` merge path, exercised here.
        return RefsCatalog.items(
            from: RefsSnapshot(
                fetchedAt: Self.fixedNow,
                records: response.refs,
                gitAddedDates: ["ref/chat/git_added_note.md": "2026-09-02"]
            )
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
        // Ready sorts by added desc (§3), blocked rows last, id
        // tie-break — never by last opened.
        XCTAssertEqual(sections[.ready], [
            "ref/blogs/morning_roundup.md",
            "ref/chat/just_added_standup.md",
            "ref/papers/just_added_survey.md",
            "ref/slides/talk_deck.md",
            "ref/papers/harness_engineering.md",
            "ref/chat/git_added_note.md",
            "ref/papers/ready_survey.md",
            "ref/chat/nulltype_note.md",
            "ref/blogs/ready_blocked_post.md",
        ])
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

        // A 2-character token that prefixes a title word is T1; a
        // mid-word contiguous substring is T2.
        let two = searchListing(items, query: "om", signals: signals)
        XCTAssertEqual(two.orderedIDs, ["A", "C"])
        XCTAssertEqual(two.matches["A"]?.tier, .word)
        XCTAssertEqual(two.matches["C"]?.tier, .fuzzy)

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

    func testWeekdayRangeEndsAtSixDays() {
        // fixedNow is 2026-10-08T12:00:00Z; the UTC calendar matches
        // makeSignals. Oct 1 is exactly 7 days before Oct 8: it shows
        // the month and day, never the weekday name of today.
        let seven = makeItem(id: "s", title: "Seven days old", added: "2026-10-01")
        let six = makeItem(id: "x", title: "Six days old", added: "2026-10-02")
        let signals = makeSignals()
        XCTAssertEqual(
            RefsCaption.caption(for: seven, in: .ready, signals: signals),
            "Chat · added Oct 1"
        )
        XCTAssertEqual(
            RefsCaption.caption(for: six, in: .ready, signals: signals),
            "Chat · added Friday"
        )
    }

    func testGoldenGitRowCarriesApproximateCaption() throws {
        let items = try goldenItems()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let git = try XCTUnwrap(byID["ref/chat/git_added_note.md"])
        XCTAssertEqual(git.added, RefDay(year: 2026, month: 9, day: 2))
        XCTAssertEqual(git.addedSource, "git")
        XCTAssertTrue(git.addedIsApproximate)
        XCTAssertTrue(
            RefsCaption.caption(
                for: git, in: .ready, signals: try goldenSignals()
            ).contains("≈ Sep 2")
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
            "Paper · Yangze Liu · added Aug 1"
        )
    }

    func testSearchCaptionsExposeMatchRanges() {
        let stemOnly = makeItem(id: "s", title: "Weekly links roundup", stem: "omnigent_notes")
        let signals = makeSignals()
        let listing = searchListing([stemOnly], query: "omnigent", signals: signals)
        let match = listing.matches["s"]
        let (text, range) = RefsCaption.captionWithMatch(
            for: stemOnly, in: nil, signals: signals, match: match
        )
        XCTAssertEqual(text, "Chat · added Aug 1 · omnigent_notes")
        guard let found = range else {
            XCTFail("stem-only caption carries no match range")
            return
        }
        let hit = text[text.index(text.startIndex, offsetBy: found.lowerBound)..<text.index(
            text.startIndex, offsetBy: found.upperBound
        )]
        XCTAssertEqual(String(hit), "omnigent")

        let authorRow = makeItem(
            id: "t", title: "Attention Budgets for Long Contexts",
            kind: .paper, author: "Yangze Liu"
        )
        let authorListing = searchListing([authorRow], query: "liu", signals: signals)
        let (_, authorRange) = RefsCaption.captionWithMatch(
            for: authorRow, in: nil, signals: signals,
            match: authorListing.matches["t"]
        )
        XCTAssertNil(authorRange)

        let plain = makeItem(id: "p", title: "Deep Dive", added: "2026-09-20")
        let (browseText, browseRange) = RefsCaption.captionWithMatch(
            for: plain, in: .reading, signals: signals, match: nil
        )
        XCTAssertEqual(browseText, "Chat · added Sep 20")
        XCTAssertNil(browseRange)
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
        let items = try goldenItems()
        let listing = RefsRanker.listing(
            items, query: "", scope: .all,
            signals: try goldenSignals()
        )
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        let gone: Set<String> = [
            "ref/chat/omnigent_review_notes.md",
            "ref/papers/old_finished.md",
        ]
        let available = Set(listing.orderedIDs).subtracting(gone)
        let vanishedIndex = listing.orderedIDs.firstIndex(
            of: "ref/chat/omnigent_review_notes.md"
        )
        let (refreshed, unavailable) = listing.refreshingContent(
            availableIDs: available,
            lastKnownItems: byID
        )

        XCTAssertEqual(unavailable, gone)
        XCTAssertEqual(refreshed.unavailableIDs, gone)
        // Vanished ids keep their index and sections, marked unavailable.
        XCTAssertEqual(refreshed.orderedIDs, listing.orderedIDs)
        XCTAssertEqual(
            refreshed.orderedIDs.firstIndex(
                of: "ref/chat/omnigent_review_notes.md"
            ),
            vanishedIndex
        )
        XCTAssertEqual(refreshed.sections, listing.sections)
        XCTAssertEqual(refreshed.mode, listing.mode)
        XCTAssertEqual(
            refreshed.unavailableItems["ref/chat/omnigent_review_notes.md"]?.title.text,
            "Field notes on the new Omnigent"
        )
        XCTAssertEqual(refreshed.totalCount, listing.totalCount)
    }

    func testFreshListingDropsUnavailable() throws {
        let items = try goldenItems()
        let signals = try goldenSignals()
        let listing = RefsRanker.listing(
            items, query: "", scope: .all, signals: signals
        )
        let gone: Set<String> = ["ref/chat/omnigent_review_notes.md"]
        let available = Set(listing.orderedIDs).subtracting(gone)
        let (refreshed, _) = listing.refreshingContent(
            availableIDs: available
        )
        XCTAssertTrue(refreshed.unavailableIDs.contains(
            "ref/chat/omnigent_review_notes.md"
        ))

        // A fresh listing (query or scope edit, ⌘R, next open) drops them.
        let fresh = RefsRanker.listing(
            items.filter { available.contains($0.id) },
            query: "", scope: .all, signals: signals
        )
        XCTAssertFalse(fresh.orderedIDs.contains(
            "ref/chat/omnigent_review_notes.md"
        ))
        XCTAssertTrue(fresh.unavailableIDs.isEmpty)
    }

    func testLocalDaysKeepJustAddedAcrossMidnightUTC() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // 21:00 local on Oct 8 is already Oct 9 in UTC.
        let localEvening = newYork.date(
            from: DateComponents(
                year: 2026, month: 10, day: 8, hour: 21
            )
        )!
        let utc = Calendar(identifier: .gregorian)
        var utcCalendar = utc
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcDay = RefsDates.ordinal(localEvening)
        let localDay = RefsDates.ordinal(
            localEvening, calendar: newYork
        )
        XCTAssertEqual(utcDay - localDay, 1)

        let item = makeItem(
            id: "fresh", title: "Fresh arrival", state: .ready,
            added: "2026-10-08"
        )
        // At the window edge: 3 local days ago is still Just added;
        // in UTC it is already 4 days ago and would fall out.
        let edge = makeItem(
            id: "edge", title: "Edge arrival", state: .ready,
            added: "2026-10-05"
        )
        var signals = makeSignals(now: localEvening)
        signals.calendar = newYork
        let listing = RefsRanker.listing(
            [item, edge], query: "", scope: .all, signals: signals
        )
        let sections = Dictionary(
            uniqueKeysWithValues: listing.sections.map { ($0.kind, $0.ids) }
        )
        XCTAssertEqual(sections[.justAdded], ["fresh", "edge"])

        let breakdown = RefsRanker.scoreBreakdown(
            item: item, qualities: [1], firstStartsAtZero: true,
            wholeWord: true, signals: signals, exactMean: false
        )
        XCTAssertEqual(
            breakdown.r,
            RefsRankingConstants.recencyWeight
                * pow(0.5, 0 / RefsRankingConstants.recencyHalfLifeDays),
            accuracy: 1e-9
        )
    }

    func testPreparedItemsAreCachedPerSnapshot() throws {
        RefsPreparedCache.resetForTests()
        let items = try goldenItems()
        let signals = try goldenSignals()
        _ = RefsRanker.listing(items, query: "harness", scope: .all, signals: signals)
        XCTAssertEqual(RefsPreparedCache.buildCount, 1)
        _ = RefsRanker.listing(items, query: "omnigent", scope: .all, signals: signals)
        XCTAssertEqual(
            RefsPreparedCache.buildCount, 1,
            "two listings over the same snapshot reuse prepared items"
        )
        var changed = signals
        changed.outlineHeadings = ["ref/chat/x.md": ["New heading"]]
        _ = RefsRanker.listing(items, query: "harness", scope: .all, signals: changed)
        XCTAssertEqual(RefsPreparedCache.buildCount, 2)
        RefsPreparedCache.resetForTests()
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
        // Debug (`swift test`) builds on CI rank ~4.6 s; release stays far
        // under 1 s. The guard targets pathological blowups, not frame time.
        XCTAssertLessThan(elapsed, 10.0, "10,000 synthetic items rank in under 10 s")
    }

    // MARK: Just scanned

    func testJustScannedComesFirstInMarkOrder() {
        let items = [
            makeItem(id: "ref/chat/alpha.md", title: "Alpha", state: .ready),
            makeItem(id: "ref/chat/beta.md", title: "Beta", state: .ready),
            makeItem(id: "ref/chat/gamma.md", title: "Gamma", state: .ready),
        ]
        var signals = makeSignals()
        signals.scan = RefsScanMark(
            ids: ["ref/chat/beta.md", "ref/chat/alpha.md"],
            at: Self.fixedNow
        )

        let listing = RefsRanker.listing(items, query: "", scope: .all, signals: signals)

        XCTAssertEqual(listing.sections.first?.kind, .justScanned)
        XCTAssertEqual(
            listing.sections.first?.ids,
            ["ref/chat/beta.md", "ref/chat/alpha.md"]
        )
        XCTAssertEqual(
            listing.orderedIDs,
            listing.sections.flatMap(\.ids),
            "every item appears once, in section order"
        )
    }

    func testJustScannedWindowEdge() {
        let items = [
            makeItem(id: "ref/chat/alpha.md", title: "Alpha", state: .ready),
        ]
        let window = Double(RefsRankingConstants.justScannedWindowMinutes) * 60

        var fresh = makeSignals()
        fresh.scan = RefsScanMark(
            ids: ["ref/chat/alpha.md"],
            at: Self.fixedNow.addingTimeInterval(-window)
        )
        let freshListing = RefsRanker.listing(items, query: "", scope: .all, signals: fresh)
        XCTAssertEqual(freshListing.sections.first?.kind, .justScanned)

        var stale = makeSignals()
        stale.scan = RefsScanMark(
            ids: ["ref/chat/alpha.md"],
            at: Self.fixedNow.addingTimeInterval(-window - 1)
        )
        let staleListing = RefsRanker.listing(items, query: "", scope: .all, signals: stale)
        XCTAssertFalse(staleListing.sections.map(\.kind).contains(.justScanned))
    }

    func testJustScannedScopeFilter() {
        let items = [
            makeItem(id: "ref/chat/alpha.md", title: "Alpha", state: .ready),
            makeItem(
                id: "ref/papers/beta.md", title: "Beta", kind: .paper, state: .ready
            ),
        ]
        var signals = makeSignals()
        signals.scan = RefsScanMark(
            ids: ["ref/chat/alpha.md", "ref/papers/beta.md"],
            at: Self.fixedNow
        )

        let listing = RefsRanker.listing(items, query: "", scope: .chats, signals: signals)

        XCTAssertEqual(listing.sections.first?.kind, .justScanned)
        XCTAssertEqual(listing.sections.first?.ids, ["ref/chat/alpha.md"])
    }

    func testJustScannedSkipsMissingIDs() {
        let items = [
            makeItem(id: "ref/chat/alpha.md", title: "Alpha", state: .ready),
        ]
        var signals = makeSignals()
        signals.scan = RefsScanMark(
            ids: ["ref/chat/gone.md", "ref/chat/alpha.md"],
            at: Self.fixedNow
        )

        let listing = RefsRanker.listing(items, query: "", scope: .all, signals: signals)

        XCTAssertEqual(listing.sections.first?.kind, .justScanned)
        XCTAssertEqual(listing.sections.first?.ids, ["ref/chat/alpha.md"])
    }

    func testJustScannedTakesTodayRowOnce() {
        let items = [
            makeItem(id: "ref/chat/alpha.md", title: "Alpha", state: .ready),
        ]
        var signals = makeSignals(today: [("ref/chat/alpha.md", "Morning")])
        signals.scan = RefsScanMark(ids: ["ref/chat/alpha.md"], at: Self.fixedNow)

        let listing = RefsRanker.listing(items, query: "", scope: .all, signals: signals)
        let sections = Dictionary(
            uniqueKeysWithValues: listing.sections.map { ($0.kind, $0.ids) }
        )

        XCTAssertEqual(sections[.justScanned], ["ref/chat/alpha.md"])
        XCTAssertNil(sections[.today])
        XCTAssertEqual(listing.orderedIDs, ["ref/chat/alpha.md"])
    }

    func testNilOrEmptyMarkAddsNoSection() throws {
        let listing = RefsRanker.listing(
            try goldenItems(), query: "", scope: .all,
            signals: try goldenSignals()
        )
        XCTAssertFalse(listing.sections.map(\.kind).contains(.justScanned))

        var empty = try goldenSignals()
        empty.scan = RefsScanMark(ids: [], at: Self.fixedNow)
        let emptyListing = RefsRanker.listing(
            try goldenItems(), query: "", scope: .all, signals: empty
        )
        XCTAssertFalse(emptyListing.sections.map(\.kind).contains(.justScanned))
    }

    func testSearchModeIgnoresTheScanMark() {
        let items = [
            makeItem(id: "ref/chat/alpha.md", title: "Alpha Harness", state: .ready),
        ]
        var signals = makeSignals()
        signals.scan = RefsScanMark(ids: ["ref/chat/alpha.md"], at: Self.fixedNow)

        let listing = RefsRanker.listing(
            items, query: "harness", scope: .all, signals: signals
        )

        XCTAssertEqual(listing.sections.count, 1)
        XCTAssertNil(listing.sections.first?.kind)
        XCTAssertEqual(listing.orderedIDs, ["ref/chat/alpha.md"])
    }

    func testJustScannedCaptionAndWhyHere() {
        let item = makeItem(
            id: "ref/chat/alpha.md", title: "Alpha", state: .ready, added: "2026-10-08"
        )
        var signals = makeSignals()
        signals.scan = RefsScanMark(ids: ["ref/chat/alpha.md"], at: Self.fixedNow)
        let listing = RefsRanker.listing([item], query: "", scope: .all, signals: signals)

        XCTAssertEqual(
            RefsCaption.datePhrase(for: item, in: .justScanned, signals: signals),
            RefsCaption.datePhrase(for: item, in: .justAdded, signals: signals)
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(item, listing: listing, signals: signals),
            "Added by your scan · just now"
        )

        var older = signals
        older.scan = RefsScanMark(
            ids: ["ref/chat/alpha.md"],
            at: Self.fixedNow.addingTimeInterval(-4 * 60)
        )
        let olderListing = RefsRanker.listing([item], query: "", scope: .all, signals: older)
        XCTAssertEqual(
            RefsExplanation.whyHere(item, listing: olderListing, signals: older),
            "Added by your scan · 4 minutes ago"
        )
    }
}
