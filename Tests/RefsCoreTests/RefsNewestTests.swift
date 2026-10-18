import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Tests for the Newest timeline: group boundaries, sort keys, scope and
/// search membership, captions and why-here lines, `added_at` decoding, the
/// git-instant snapshot key, and section jumps. Time is fixed at
/// 2026-10-18 14:00 in `America/New_York` with the `en_US_POSIX` locale.
final class RefsNewestTests: XCTestCase {
    static let zone = TimeZone(identifier: "America/New_York")!

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    static func instant(_ raw: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)!
    }

    /// Sunday 2026-10-18, 2 PM Eastern.
    static let now = instant("2026-10-18T14:00:00-04:00")

    func signals(now: Date = RefsNewestTests.now) -> RefsSignals {
        RefsSignals(
            opens: RefsOpenStats(events: [], now: now),
            now: now,
            calendar: Self.calendar
        )
    }

    func makeItem(
        _ id: String,
        added: String? = nil,
        at: String? = nil,
        source: String? = "created",
        kind: RefKind = .chat,
        title: String? = nil
    ) -> RefItem {
        let stem = id.split(separator: "/").last.map(String.init) ?? id
        return RefItem(
            id: id,
            link: "[[\(id)]]",
            rawTitle: title ?? stem,
            stem: stem,
            kind: kind,
            state: .ready,
            isBlocked: false,
            pdfPath: "lib/\(stem).pdf",
            added: added.flatMap(RefDay.init(parsing:)),
            addedSource: added == nil ? nil : source,
            addedAt: at.map(Self.instant),
            addedIsApproximate: source == "git"
        )
    }

    func newest(
        _ items: [RefItem],
        query: String = "",
        scope: RefScope = .all,
        now: Date = RefsNewestTests.now
    ) -> RefsListing {
        RefsRanker.listing(
            items, query: query, scope: scope, order: .newest, signals: signals(now: now)
        )
    }

    func groups(_ listing: RefsListing) -> [RefsAddedGroup] {
        listing.sections.compactMap { section -> RefsAddedGroup? in
            if case let .added(group)? = section.kind {
                return group
            }
            return nil
        }
    }

    // MARK: Group boundaries

    func testGroupsAroundToday() {
        let items = [
            makeItem("ref/a_future.md", added: "2026-10-25"),
            makeItem("ref/b_today.md", added: "2026-10-18"),
            makeItem("ref/c_yesterday.md", added: "2026-10-17"),
            makeItem("ref/d_two.md", added: "2026-10-16"),
            makeItem("ref/e_six.md", added: "2026-10-12"),
            makeItem("ref/f_seven.md", added: "2026-10-11"),
            makeItem("ref/g_early.md", added: "2026-10-01"),
            makeItem("ref/h_sept.md", added: "2026-09-27"),
            makeItem("ref/i_prior.md", added: "2025-12-05"),
            makeItem("ref/j_none.md"),
        ]
        let listing = newest(items)

        XCTAssertEqual(listing.order, .newest)
        XCTAssertEqual(listing.mode, .browse)
        XCTAssertEqual(
            listing.sections.map(\.ids),
            [
                ["ref/a_future.md", "ref/b_today.md"],
                ["ref/c_yesterday.md"],
                ["ref/d_two.md"],
                ["ref/e_six.md"],
                ["ref/f_seven.md", "ref/g_early.md"],
                ["ref/h_sept.md"],
                ["ref/i_prior.md"],
                ["ref/j_none.md"],
            ]
        )
        XCTAssertEqual(
            groups(listing),
            [
                RefsAddedGroup(
                    id: "day-2026-10-18", title: "Today", detail: "Oct 18",
                    accessibilityLabel: "Added today, October 18", style: .day
                ),
                RefsAddedGroup(
                    id: "day-2026-10-17", title: "Yesterday", detail: "Oct 17",
                    accessibilityLabel: "Added yesterday, October 17", style: .day
                ),
                RefsAddedGroup(
                    id: "day-2026-10-16", title: "Friday", detail: "Oct 16",
                    accessibilityLabel: "Added Friday, October 16", style: .day
                ),
                RefsAddedGroup(
                    id: "day-2026-10-12", title: "Monday", detail: "Oct 12",
                    accessibilityLabel: "Added Monday, October 12", style: .day
                ),
                RefsAddedGroup(
                    id: "month-2026-10", title: "October", detail: nil,
                    accessibilityLabel: "Added in October", style: .month
                ),
                RefsAddedGroup(
                    id: "month-2026-09", title: "September", detail: nil,
                    accessibilityLabel: "Added in September", style: .month
                ),
                RefsAddedGroup(
                    id: "month-2025-12", title: "December 2025", detail: nil,
                    accessibilityLabel: "Added in December 2025", style: .month
                ),
                RefsAddedGroup(
                    id: "undated", title: "Undated", detail: nil,
                    accessibilityLabel: "Undated", style: .undated
                ),
            ]
        )
        XCTAssertEqual(
            listing.sections.compactMap(\.kind).map(\.title),
            [
                "Today", "Yesterday", "Friday", "Monday", "October", "September",
                "December 2025", "Undated",
            ]
        )
        XCTAssertEqual(listing.orderedIDs, listing.sections.flatMap(\.ids))
    }

    func testMonthBoundaryInsideTheWeekdayWindow() {
        // Saturday 2026-10-03: Oct 1 is 2 days back and Sep 30 is 3, so
        // both are weekday groups even though they sit in different
        // months. Sep 26 is 7 days back and falls into the month group.
        let now = Self.instant("2026-10-03T10:00:00-04:00")
        let items = [
            makeItem("ref/a.md", added: "2026-10-01"),
            makeItem("ref/b.md", added: "2026-09-30"),
            makeItem("ref/c.md", added: "2026-09-26"),
        ]
        let listing = newest(items, now: now)

        XCTAssertEqual(
            groups(listing).map(\.title), ["Thursday", "Wednesday", "September"]
        )
        XCTAssertEqual(
            groups(listing).map(\.id), ["day-2026-10-01", "day-2026-09-30", "month-2026-09"]
        )
        XCTAssertEqual(groups(listing).map(\.detail), ["Oct 1", "Sep 30", nil])
    }

    func testWeekdayGroupAcrossNewYearCarriesTheYear() {
        let now = Self.instant("2027-01-02T10:00:00-05:00")
        let listing = newest([makeItem("ref/a.md", added: "2026-12-31")], now: now)

        XCTAssertEqual(
            groups(listing),
            [
                RefsAddedGroup(
                    id: "day-2026-12-31", title: "Thursday", detail: "Dec 31, 2026",
                    accessibilityLabel: "Added Thursday, December 31, 2026", style: .day
                )
            ]
        )
    }

    func testEveningStaysOnTheLocalDay() {
        // 9 PM Eastern on Oct 18 is already Oct 19 in UTC; the panel
        // calendar keeps today at Oct 18.
        let now = Self.instant("2026-10-18T21:00:00-04:00")
        let listing = newest([makeItem("ref/a.md", added: "2026-10-18")], now: now)

        XCTAssertEqual(groups(listing).map(\.id), ["day-2026-10-18"])
        XCTAssertEqual(groups(listing).map(\.title), ["Today"])
    }

    func testEmptyLibraryHasNoGroups() {
        let listing = newest([])

        XCTAssertEqual(listing.sections, [])
        XCTAssertEqual(listing.orderedIDs, [])
        XCTAssertEqual(listing.totalCount, 0)
    }

    // MARK: Sort keys

    func testSortKeys() {
        let items = [
            makeItem("ref/untimed_b.md", added: "2026-10-16"),
            makeItem("ref/untimed_a.md", added: "2026-10-16"),
            makeItem("ref/early.md", added: "2026-10-16", at: "2026-10-16T08:00:00-04:00"),
            makeItem("ref/late.md", added: "2026-10-16", at: "2026-10-16T17:30:00-04:00"),
            makeItem("ref/same_b.md", added: "2026-10-16", at: "2026-10-16T12:00:00-04:00"),
            makeItem("ref/same_a.md", added: "2026-10-16", at: "2026-10-16T12:00:00-04:00"),
            makeItem("ref/newer_day.md", added: "2026-10-17"),
            makeItem("ref/none_b.md"),
            makeItem("ref/none_a.md"),
        ]
        let listing = newest(items)

        XCTAssertEqual(
            listing.orderedIDs,
            [
                "ref/newer_day.md",
                "ref/late.md",
                "ref/same_a.md",
                "ref/same_b.md",
                "ref/early.md",
                "ref/untimed_a.md",
                "ref/untimed_b.md",
                "ref/none_a.md",
                "ref/none_b.md",
            ]
        )
    }

    func testInputOrderDoesNotChangeTheListing() {
        let items = (0..<12).map {
            makeItem(
                "ref/n\($0).md",
                added: "2026-10-\(10 + $0 % 5)",
                at: $0 % 2 == 0 ? "2026-10-\(10 + $0 % 5)T0\($0 % 9):00:00-04:00" : nil
            )
        }

        XCTAssertEqual(newest(items).orderedIDs, newest(items.reversed()).orderedIDs)
    }

    // MARK: Membership

    func testScopeFiltersAndTotalsFollowTheScope() {
        let items = [
            makeItem("ref/chat.md", added: "2026-10-17", kind: .chat),
            makeItem("ref/paper.md", added: "2026-10-18", kind: .paper),
            makeItem("ref/article.md", added: "2026-10-16", kind: .article),
        ]

        XCTAssertEqual(
            newest(items).orderedIDs, ["ref/paper.md", "ref/chat.md", "ref/article.md"]
        )
        let papers = newest(items, scope: .papers)
        XCTAssertEqual(papers.orderedIDs, ["ref/paper.md"])
        XCTAssertEqual(papers.scope, .papers)
        XCTAssertEqual(papers.totalCount, 1)
        XCTAssertEqual(papers.openCount, 1)
        XCTAssertEqual(groups(papers).map(\.title), ["Today"])
    }

    func testNewestBrowseMembershipEqualsRankedBrowseMembership() throws {
        let items = try goldenItems()
        let ranked = RefsRanker.listing(
            items, query: "", scope: .all, signals: signals()
        )
        let timeline = newest(items)

        XCTAssertEqual(Set(timeline.orderedIDs), Set(ranked.orderedIDs))
        XCTAssertEqual(timeline.orderedIDs.count, ranked.orderedIDs.count)
        XCTAssertEqual(timeline.totalCount, ranked.totalCount)
        XCTAssertEqual(timeline.openCount, ranked.openCount)
        XCTAssertEqual(ranked.order, .ranked)
    }

    func testNewestSearchMembershipEqualsRankedSearchMembership() throws {
        let items = try goldenItems()
        // Exact/word (T0, T1), fuzzy (T2), and secondary field (T3) queries.
        let queries = ["omnigent", "harness", "attn", "tolling", "agent", "blog", "zzzz"]
        for query in queries {
            let ranked = RefsRanker.listing(
                items, query: query, scope: .all, signals: signals()
            )
            let timeline = newest(items, query: query)

            XCTAssertEqual(
                Set(timeline.orderedIDs), Set(ranked.orderedIDs), "query \(query)"
            )
            XCTAssertEqual(
                timeline.orderedIDs.count, ranked.orderedIDs.count, "query \(query)"
            )
            XCTAssertEqual(timeline.matches, ranked.matches, "query \(query)")
            XCTAssertEqual(timeline.mode, .search(query))
            XCTAssertEqual(timeline.totalCount, ranked.totalCount)
            XCTAssertEqual(timeline.order, .newest)
        }
        let tiers = Set(
            RefsRanker.listing(items, query: "agent", scope: .all, signals: signals())
                .matches.values.map(\.tier)
        )
        XCTAssertTrue(tiers.contains(.secondary), "the agent query reaches T3")
        let fuzzy = Set(
            RefsRanker.listing(items, query: "attn", scope: .all, signals: signals())
                .matches.values.map(\.tier)
        )
        XCTAssertTrue(fuzzy.contains(.fuzzy), "the attn query reaches T2")
    }

    func testNewestSearchOrdersMatchesByDateNotRelevance() throws {
        let items = try goldenItems()
        let timeline = newest(items, query: "omnigent")
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let days = timeline.orderedIDs.compactMap { byID[$0]?.added }

        XCTAssertGreaterThan(days.count, 1)
        XCTAssertEqual(days, days.sorted(by: >))
        XCTAssertEqual(timeline.orderedIDs, timeline.sections.flatMap(\.ids))
        XCTAssertTrue(timeline.sections.allSatisfy { $0.kind != nil })
    }

    func testNewestSearchRetainsHighlights() throws {
        let items = try goldenItems()
        let ranked = RefsRanker.listing(
            items, query: "omnigent", scope: .all, signals: signals()
        )
        let timeline = newest(items, query: "omnigent")

        let withTitleRanges = timeline.matches.filter { !$0.value.titleRanges.isEmpty }
        XCTAssertFalse(withTitleRanges.isEmpty)
        for (id, match) in ranked.matches {
            XCTAssertEqual(timeline.matches[id]?.titleRanges, match.titleRanges, id)
            XCTAssertEqual(timeline.matches[id]?.stemRanges, match.stemRanges, id)
            XCTAssertEqual(timeline.matches[id]?.secondary, match.secondary, id)
        }
    }

    func testNewestSearchWithNoMatchesHasNoGroups() throws {
        let timeline = newest(try goldenItems(), query: "qqqzzz")

        XCTAssertEqual(timeline.sections, [])
        XCTAssertEqual(timeline.orderedIDs, [])
        XCTAssertEqual(timeline.order, .newest)
    }

    func testRefreshingContentKeepsTheOrder() {
        let items = [
            makeItem("ref/a.md", added: "2026-10-17"),
            makeItem("ref/b.md", added: "2026-10-16"),
        ]
        let listing = newest(items)

        let refreshed = listing.refreshingContent(availableIDs: ["ref/a.md"])

        XCTAssertEqual(refreshed.listing.order, .newest)
        XCTAssertEqual(refreshed.listing.orderedIDs, listing.orderedIDs)
        XCTAssertEqual(refreshed.unavailable, ["ref/b.md"])
    }

    // MARK: Captions

    func testDayGroupCaptionsShowTheTime() {
        let timed = makeItem(
            "ref/timed.md", added: "2026-10-18", at: "2026-10-18T09:41:00-04:00"
        )
        let afternoon = makeItem(
            "ref/pm.md", added: "2026-10-17", at: "2026-10-17T15:12:00-04:00"
        )
        let untimed = makeItem("ref/untimed.md", added: "2026-10-18")
        let listing = newest([timed, afternoon, untimed])
        let section = listing.sections[0].kind

        XCTAssertEqual(
            RefsCaption.caption(for: timed, in: section, signals: signals()),
            "Chat · added 9:41 AM"
        )
        XCTAssertEqual(
            RefsCaption.caption(for: untimed, in: section, signals: signals()),
            "Chat"
        )
        XCTAssertEqual(
            RefsCaption.caption(for: afternoon, in: listing.sections[1].kind, signals: signals()),
            "Chat · added 3:12 PM"
        )
    }

    func testMonthGroupCaptionsShowTheMonthAndDay() {
        let item = makeItem(
            "ref/oct.md", added: "2026-10-07", at: "2026-10-07T09:41:00-04:00"
        )
        let prior = makeItem("ref/dec.md", added: "2025-12-05")
        let listing = newest([item, prior])

        XCTAssertEqual(
            RefsCaption.caption(for: item, in: listing.sections[0].kind, signals: signals()),
            "Chat · added Oct 7"
        )
        XCTAssertEqual(
            RefsCaption.caption(for: prior, in: listing.sections[1].kind, signals: signals()),
            "Chat · added Dec 5, 2025"
        )
    }

    func testUndatedCaptionHasNoDatePhrase() {
        let item = makeItem("ref/none.md")
        let listing = newest([item])

        XCTAssertEqual(
            RefsCaption.caption(for: item, in: listing.sections[0].kind, signals: signals()),
            "Chat"
        )
    }

    func testGitDatedCaptionsKeepTheApproximateMark() {
        let timed = makeItem(
            "ref/g1.md", added: "2026-10-18", at: "2026-10-18T15:12:00-04:00", source: "git"
        )
        let monthly = makeItem("ref/g2.md", added: "2026-09-27", source: "git")
        let listing = newest([timed, monthly])

        XCTAssertEqual(
            RefsCaption.caption(for: timed, in: listing.sections[0].kind, signals: signals()),
            "Chat · added ≈ 3:12 PM"
        )
        XCTAssertEqual(
            RefsCaption.caption(for: monthly, in: listing.sections[1].kind, signals: signals()),
            "Chat · added ≈ Sep 27"
        )
    }

    func testCaptionKeepsAuthorAndPagesAroundTheDatePhrase() {
        var item = makeItem(
            "ref/paper.md", added: "2026-10-18", at: "2026-10-18T09:41:00-04:00",
            kind: .paper
        )
        item = RefItem(
            id: item.id, link: item.link, rawTitle: item.rawTitle, stem: item.stem,
            kind: .paper, state: .ready, isBlocked: false, pdfPath: item.pdfPath,
            author: "Vaswani", added: item.added, addedSource: "created",
            addedAt: item.addedAt
        )
        var signals = signals()
        signals.pageCounts = [item.id: 15]
        let listing = newest([item])

        XCTAssertEqual(
            RefsCaption.caption(for: item, in: listing.sections[0].kind, signals: signals),
            "Paper · Vaswani · added 9:41 AM · 15 pp"
        )
    }

    func testNewestSearchCaptionAppendsTheMatchedPart() throws {
        let items = try goldenItems()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        var sawMatchedPart = false
        // Title, author, and kind queries: the matched stem or secondary
        // part is the same in both orders.
        for query in ["omnigent", "agent", "chat", "harness", "vaswani", "blog_post"] {
            let timeline = newest(items, query: query)
            let ranked = RefsRanker.listing(
                items, query: query, scope: .all, signals: signals()
            )
            for section in timeline.sections {
                for id in section.ids {
                    let item = try XCTUnwrap(byID[id])
                    let (text, range) = RefsCaption.captionWithMatch(
                        for: item, in: section.kind, signals: signals(),
                        match: timeline.matches[id]
                    )
                    let (rankedText, rankedRange) = RefsCaption.captionWithMatch(
                        for: item, in: nil, signals: signals(), match: ranked.matches[id]
                    )
                    XCTAssertEqual(range == nil, rankedRange == nil, "\(query) \(id)")
                    if let range, let rankedRange {
                        sawMatchedPart = true
                        let suffix = String(text.dropFirst(range.lowerBound))
                        let rankedSuffix = String(rankedText.dropFirst(rankedRange.lowerBound))
                        XCTAssertEqual(suffix, rankedSuffix, "\(query) \(id)")
                    }
                }
            }
        }
        XCTAssertTrue(sawMatchedPart)
    }

    func testRankedCaptionsAreUnchangedWithoutAMatch() {
        let item = makeItem("ref/a.md", added: "2026-10-18")
        let match = RefsMatch(
            tier: .word, score: 1,
            breakdown: RefsScoreBreakdown(m: 1, p: 0, w: 0, l: 0, f: 0, r: 0),
            stemRanges: [0..<1]
        )

        // A browse section never shows the matched stem, even if handed one
        // without a match; search (no section) still appends it.
        XCTAssertEqual(
            RefsCaption.caption(for: item, in: .ready, signals: signals()),
            "Chat · added today"
        )
        XCTAssertEqual(
            RefsCaption.caption(for: item, in: nil, signals: signals(), match: match),
            "Chat · added today · a.md"
        )
    }

    func testShortTimeUsesThePanelTimeZoneAndPlainSpaces() {
        let evening = Self.instant("2026-10-18T21:05:00-04:00")
        let utcCalendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            calendar.locale = Locale(identifier: "en_US_POSIX")
            return calendar
        }()

        XCTAssertEqual(RefsCaption.shortTime(evening, calendar: Self.calendar), "9:05 PM")
        XCTAssertEqual(RefsCaption.shortTime(evening, calendar: utcCalendar), "1:05 AM")
        XCTAssertFalse(
            RefsCaption.shortTime(evening, calendar: Self.calendar).contains("\u{202F}")
        )
    }

    // MARK: Why-here

    func testWhyHereForNewestRows() {
        let timed = makeItem(
            "ref/t.md", added: "2026-10-16", at: "2026-10-16T09:41:00-04:00"
        )
        let untimed = makeItem("ref/u.md", added: "2026-10-15")
        let git = makeItem(
            "ref/g.md", added: "2026-09-27", at: "2026-09-27T15:12:00-04:00", source: "git"
        )
        let gitUntimed = makeItem("ref/gu.md", added: "2026-09-26", source: "git")
        let none = makeItem("ref/n.md")
        let prior = makeItem("ref/p.md", added: "2025-12-05")
        let items = [timed, untimed, git, gitUntimed, none, prior]
        let listing = newest(items)
        let signals = signals()

        func why(_ item: RefItem) -> String {
            RefsExplanation.whyHere(item, listing: listing, signals: signals)
        }
        XCTAssertEqual(why(timed), "Added Oct 16 at 9:41 AM")
        XCTAssertEqual(why(untimed), "Added Oct 15")
        XCTAssertEqual(why(git), "Added ≈ Sep 27 at 3:12 PM · from vault history")
        XCTAssertEqual(why(gitUntimed), "Added ≈ Sep 26 · from vault history")
        XCTAssertEqual(why(none), "Undated · bob has no added date for this note")
        XCTAssertEqual(why(prior), "Added Dec 5, 2025")
    }

    func testNewestSearchWhyHereIsTheMatchReason() throws {
        let items = try goldenItems()
        let timeline = newest(items, query: "omnigent")
        let ranked = RefsRanker.listing(
            items, query: "omnigent", scope: .all, signals: signals()
        )
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        XCTAssertFalse(timeline.orderedIDs.isEmpty)
        for id in timeline.orderedIDs {
            let item = try XCTUnwrap(byID[id])
            XCTAssertEqual(
                RefsExplanation.whyHere(item, listing: timeline, signals: signals()),
                RefsExplanation.whyHere(item, listing: ranked, signals: signals()),
                id
            )
        }
    }

    // MARK: Section jumps

    func testSectionJumpsWorkInNewestSearch() throws {
        let items = try goldenItems()
        let timeline = newest(items, query: "omnigent")
        let ids = timeline.orderedIDs
        XCTAssertGreaterThan(timeline.sections.count, 2)

        let firstOfSecond = timeline.sections[1].ids[0]
        XCTAssertEqual(
            RefsSelectionPolicy.moveSection(.nextSection, from: ids[0], in: timeline),
            firstOfSecond
        )
        XCTAssertEqual(
            RefsSelectionPolicy.moveSection(.previousSection, from: firstOfSecond, in: timeline),
            timeline.sections[0].ids[0]
        )
        XCTAssertEqual(
            RefsSelectionPolicy.move(.nextSection, from: ids[0], in: timeline, pageSize: 5),
            firstOfSecond
        )
        // Wraps around both ends.
        XCTAssertEqual(
            RefsSelectionPolicy.moveSection(.previousSection, from: ids[0], in: timeline),
            timeline.sections.last?.ids.first
        )
    }

    func testSectionJumpsWorkInNewestBrowse() throws {
        let timeline = newest(try goldenItems())

        XCTAssertEqual(
            RefsSelectionPolicy.moveSection(
                .nextSection, from: timeline.orderedIDs[0], in: timeline
            ),
            timeline.sections[1].ids[0]
        )
    }

    func testSectionJumpsStayNoOpsInRankedSearch() throws {
        let items = try goldenItems()
        let ranked = RefsRanker.listing(
            items, query: "omnigent", scope: .all, signals: signals()
        )
        let id = ranked.orderedIDs[0]

        XCTAssertEqual(RefsSelectionPolicy.moveSection(.nextSection, from: id, in: ranked), id)
    }

    // MARK: Decoding

    func testAddedAtDecodesPresentAbsentAndNull() throws {
        let present = try decodeRecord(
            #"{"added":"2026-10-17","added_source":"created","added_at":"2026-10-17T09:12:44-04:00"}"#
        )
        let absent = try decodeRecord(#"{"added":"2026-10-17","added_source":"created"}"#)
        let null = try decodeRecord(
            #"{"added":"2026-10-17","added_source":"zorg_block","added_at":null}"#
        )

        XCTAssertEqual(present.addedAt, "2026-10-17T09:12:44-04:00")
        XCTAssertNil(absent.addedAt)
        XCTAssertNil(null.addedAt)
    }

    func testAddedAtParsesOnceIntoAnInstant() throws {
        let record = try decodeRecord(
            #"{"added":"2026-10-17","added_source":"created","added_at":"2026-10-17T09:12:44-04:00"}"#
        )
        let item = try XCTUnwrap(RefItem.make(from: record, gitAddedDates: [:]))

        XCTAssertEqual(item.addedAt, Self.instant("2026-10-17T13:12:44Z"))
        XCTAssertEqual(item.added, RefDay(year: 2026, month: 10, day: 17))
    }

    func testMalformedAddedAtBecomesNilWithoutFailingDecoding() throws {
        for raw in ["yesterday", "2026-10-17", "2026-10-17T09:12:44", ""] {
            let record = try decodeRecord(
                #"{"added":"2026-10-17","added_source":"created","added_at":"\#(raw)"}"#
            )
            let item = try XCTUnwrap(RefItem.make(from: record, gitAddedDates: [:]))

            XCTAssertEqual(record.addedAt, raw)
            XCTAssertNil(item.addedAt, raw)
            XCTAssertEqual(item.added, RefDay(year: 2026, month: 10, day: 17), raw)
        }
    }

    func testAddedAtRoundTripsThroughTheRecordEncoder() throws {
        let record = try decodeRecord(
            #"{"added":"2026-10-17","added_source":"created","added_at":"2026-10-17T09:12:44-04:00"}"#
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(RefRecord.self, from: data)

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.addedAt, "2026-10-17T09:12:44-04:00")
    }

    func testAnOlderBobDecodesEveryGoldenRowWithoutAddedAt() throws {
        let response = try JSONDecoder().decode(
            RefsListResponse.self,
            from: RefsModelTests.fixtureData("refs-list-golden.json")
        )

        XCTAssertTrue(response.refs.allSatisfy { $0.addedAt == nil })
        XCTAssertTrue(try goldenItems().allSatisfy { $0.addedAt == nil })
    }

    // MARK: Git instants

    func testGitRowsTakeTheirInstantFromTheSnapshot() throws {
        let record = RefRecord(
            path: "ref/chat/g.md", link: "[[ref/chat/g]]", title: "G",
            sourcePDF: "lib/chat/g.pdf"
        )
        let snapshot = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1),
            records: [record],
            gitAddedDates: ["ref/chat/g.md": "2026-09-27"],
            gitAddedAt: ["ref/chat/g.md": "2026-09-27T15:12:00-04:00"]
        )

        let item = try XCTUnwrap(RefsCatalog.items(from: snapshot).first)

        XCTAssertEqual(item.added, RefDay(year: 2026, month: 9, day: 27))
        XCTAssertEqual(item.addedSource, "git")
        XCTAssertEqual(item.addedAt, Self.instant("2026-09-27T15:12:00-04:00"))
        XCTAssertTrue(item.addedIsApproximate)
    }

    func testSnapshotInstantIsIgnoredWhenTheRecordIsAlreadyDated() throws {
        let record = RefRecord(
            path: "ref/chat/d.md", link: "[[ref/chat/d]]", title: "D",
            added: "2026-10-01", addedSource: "created", sourcePDF: "lib/chat/d.pdf"
        )
        let item = try XCTUnwrap(
            RefItem.make(
                from: record,
                gitAddedDates: ["ref/chat/d.md": "2026-09-01"],
                gitAddedAt: ["ref/chat/d.md": "2026-09-01T10:00:00-04:00"]
            )
        )

        XCTAssertEqual(item.added, RefDay(year: 2026, month: 10, day: 1))
        XCTAssertNil(item.addedAt)
    }

    func testCatalogKeepsAddedAtThroughTheDisambiguatorRebuild() throws {
        let records = ["a", "b"].map {
            RefRecord(
                path: "ref/chat/\($0).md", link: "[[ref/chat/\($0)]]", title: "Same Title",
                added: "2026-10-17", addedSource: "created",
                addedAt: "2026-10-17T09:12:44-04:00", sourcePDF: "lib/chat/\($0).pdf"
            )
        }
        let items = RefsCatalog.items(
            from: RefsSnapshot(fetchedAt: Date(timeIntervalSince1970: 1), records: records)
        )

        XCTAssertEqual(items.map(\.titleDisambiguator), ["a", "b"])
        XCTAssertEqual(
            items.map(\.addedAt),
            [Self.instant("2026-10-17T09:12:44-04:00"), Self.instant("2026-10-17T09:12:44-04:00")]
        )
    }

    func testSnapshotRoundTripsWithAndWithoutGitAddedAt() throws {
        let record = RefRecord(
            path: "ref/chat/g.md", link: "[[ref/chat/g]]", title: "G",
            sourcePDF: "lib/chat/g.pdf"
        )
        let with = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
            records: [record],
            gitAddedDates: ["ref/chat/g.md": "2026-09-27"],
            gitAddedAt: ["ref/chat/g.md": "2026-09-27T15:12:00-04:00"]
        )
        let without = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
            records: [record],
            gitAddedDates: ["ref/chat/g.md": "2026-09-27"]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(RefsSnapshot.self, from: encoder.encode(with)), with)
        XCTAssertEqual(
            try decoder.decode(RefsSnapshot.self, from: encoder.encode(without)), without
        )

        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(with)) as? [String: Any]
        )
        XCTAssertEqual(
            encoded["git_added_at"] as? [String: String],
            ["ref/chat/g.md": "2026-09-27T15:12:00-04:00"]
        )

        // A cache written before `git_added_at` existed still decodes.
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(with)) as? [String: Any]
        )
        legacy.removeValue(forKey: "git_added_at")
        let old = try decoder.decode(
            RefsSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertEqual(old.gitAddedAt, [:])
        XCTAssertEqual(old.gitAddedDates, ["ref/chat/g.md": "2026-09-27"])
    }

    func testPathsNeedingGitDatesRefillsRowsWithoutAnInstant() {
        let dated = RefRecord(
            path: "ref/dated.md", link: "[[ref/dated]]", title: "Dated",
            added: "2026-10-01", addedSource: "created"
        )
        let dateless = RefRecord(path: "ref/dateless.md", link: "[[ref/dateless]]", title: "No")
        let covered = RefRecord(path: "ref/covered.md", link: "[[ref/covered]]", title: "Yes")
        let datesOnly = RefRecord(path: "ref/old.md", link: "[[ref/old]]", title: "Old")
        let snapshot = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1),
            records: [dated, dateless, covered, datesOnly],
            gitAddedDates: ["ref/covered.md": "2026-09-01", "ref/old.md": "2026-09-02"],
            gitAddedAt: ["ref/covered.md": "2026-09-01T10:00:00-04:00"]
        )

        XCTAssertEqual(
            Set(snapshot.pathsNeedingGitDates), ["ref/dateless.md", "ref/old.md"]
        )
    }

    func testMergingGitDatesFillsOnlyStillDatelessPaths() {
        let dateless = RefRecord(path: "ref/a.md", link: "[[ref/a]]", title: "A")
        let refill = RefRecord(path: "ref/b.md", link: "[[ref/b]]", title: "B")
        let covered = RefRecord(path: "ref/c.md", link: "[[ref/c]]", title: "C")
        let datedNow = RefRecord(
            path: "ref/d.md", link: "[[ref/d]]", title: "D",
            added: "2026-10-02", addedSource: "created"
        )
        let snapshot = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1),
            records: [dateless, refill, covered, datedNow],
            gitAddedDates: ["ref/b.md": "2026-08-01", "ref/c.md": "2026-08-02"],
            gitAddedAt: ["ref/c.md": "2026-08-02T10:00:00-04:00"]
        )
        func gitRow(
            _ path: String, added: String?, at: String?, source: String = "git"
        ) -> RefRecord {
            RefRecord(
                path: path, link: "[[x]]", title: "T", added: added, addedSource: source,
                addedAt: at
            )
        }
        let response = [
            gitRow("ref/a.md", added: "2026-09-27", at: "2026-09-27T15:12:00-04:00"),
            gitRow("ref/b.md", added: "2026-08-01", at: "2026-08-01T09:00:00-04:00"),
            // Covered at snapshot time and not in `needing`: untouched.
            gitRow("ref/c.md", added: "2026-01-01", at: "2026-01-01T09:00:00-04:00"),
            // Dated by a plain refresh in the meantime: untouched.
            gitRow("ref/d.md", added: "2026-05-05", at: "2026-05-05T09:00:00-04:00"),
            // Not git-sourced in the response: ignored.
            gitRow("ref/e.md", added: "2026-05-05", at: nil, source: "created"),
            // Unknown path: ignored.
            gitRow("ref/zzz.md", added: "2026-05-05", at: nil),
        ]

        let merged = snapshot.mergingGitDates(
            from: response,
            needing: ["ref/a.md", "ref/b.md", "ref/d.md", "ref/e.md"]
        )

        XCTAssertEqual(
            merged.gitAddedDates,
            ["ref/a.md": "2026-09-27", "ref/b.md": "2026-08-01", "ref/c.md": "2026-08-02"]
        )
        XCTAssertEqual(
            merged.gitAddedAt,
            [
                "ref/a.md": "2026-09-27T15:12:00-04:00",
                "ref/b.md": "2026-08-01T09:00:00-04:00",
                "ref/c.md": "2026-08-02T10:00:00-04:00",
            ]
        )
        XCTAssertEqual(merged.records, snapshot.records)
        XCTAssertEqual(merged.fetchedAt, snapshot.fetchedAt)
        XCTAssertEqual(merged.pathsNeedingGitDates, [])
        // The receiver is a value: the merge returns a new snapshot.
        XCTAssertEqual(snapshot.gitAddedDates.count, 2)
    }

    func testMergingGitDatesFromAnOlderBobKeepsTheDateOnly() {
        let record = RefRecord(path: "ref/a.md", link: "[[ref/a]]", title: "A")
        let snapshot = RefsSnapshot(fetchedAt: Date(timeIntervalSince1970: 1), records: [record])
        let response = [
            RefRecord(
                path: "ref/a.md", link: "[[ref/a]]", title: "A",
                added: "2026-09-27", addedSource: "git"
            )
        ]

        let merged = snapshot.mergingGitDates(from: response, needing: ["ref/a.md"])

        XCTAssertEqual(merged.gitAddedDates, ["ref/a.md": "2026-09-27"])
        XCTAssertEqual(merged.gitAddedAt, [:])
    }

    // MARK: Fixtures

    func decodeRecord(_ extra: String) throws -> RefRecord {
        let fields = String(extra.dropFirst().dropLast())
        let json =
            #"{"path":"ref/chat/x.md","link":"[[ref/chat/x]]","title":"X","#
            + #""source_pdf":"lib/chat/x.pdf","# + fields + "}"
        return try JSONDecoder().decode(RefRecord.self, from: Data(json.utf8))
    }

    func goldenItems() throws -> [RefItem] {
        let response = try JSONDecoder().decode(
            RefsListResponse.self,
            from: RefsModelTests.fixtureData("refs-list-golden.json")
        )
        return RefsCatalog.items(
            from: RefsSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1),
                records: response.refs,
                gitAddedDates: ["ref/chat/git_added_note.md": "2026-09-02"]
            )
        )
    }
}
