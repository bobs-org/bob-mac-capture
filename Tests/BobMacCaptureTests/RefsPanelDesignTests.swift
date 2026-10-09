import AppKit
import CaptureCore
import Foundation
import SwiftUI
import XCTest

@testable import BobMacCapture
@testable import RefsCore

/// Rendered-image review for the Refs panel: one PNG per panel state at
/// 880 pt (and the list-only 700 pt width), in both appearances, through
/// the shared `RenderFixtureWriter`. `BOB_MAC_CAPTURE_RENDER_DIR` points
/// at a writable directory; when unset, the render test skips. Inspect
/// the PNGs with an image reader and iterate on baselines, the state
/// glyph column, pill crowding, code spans in titles, secondary-text
/// contrast on the material in dark mode, and clean pinned-header
/// occlusion.
@MainActor
final class RefsPanelDesignTests: XCTestCase {
    func testRefsPanelStatesToPNG() throws {
        let now = fixedNow()
        let library = makeLibrary(now: now)
        let model = RefsPanelModel(
            library: library,
            opener: StubOpener(),
            highlights: StubLocator()
        )

        try renderBrowse(model: model, now: now)
        try renderSearch(model: model, now: now)
        try renderScopedEmpty(model: model, now: now)
        try renderMissingPDFSelected(model: model, now: now)
        try renderRefreshFailed(model: model, now: now)
        try renderLoadFailed(now: now)
        try renderSkeleton(now: now)
        try renderBanner(model: model, now: now)
        try renderNarrowBrowse(model: model, now: now)
        try renderPieces(model: model, now: now)
    }

    // MARK: - Renders

    private func renderBrowse(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: "ref/chat/today_report.md",
            banner: nil,
            refreshState: .idle
        )
        XCTAssertEqual(model.listing.orderedIDs.first, "ref/chat/today_report.md")
        let kinds = model.listing.sections.compactMap(\.kind)
        XCTAssertTrue(kinds.contains(.today))
        XCTAssertTrue(kinds.contains(.justAdded))
        XCTAssertTrue(kinds.contains(.reading))
        XCTAssertTrue(kinds.contains(.next))
        XCTAssertTrue(kinds.contains(.ready))
        XCTAssertTrue(kinds.contains(.recentlyOpened))
        XCTAssertTrue(kinds.contains(.library))
        try write(model: model, name: "refs-browse-880", width: 880)
    }

    private func renderSearch(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "omni",
            scope: .all,
            selectedID: nil,
            banner: nil,
            refreshState: .idle
        )
        guard case .search = model.listing.mode else {
            XCTFail("expected search mode")
            return
        }
        let match = model.listing.matches["ref/chat/omni_review.md"]
        XCTAssertNotNil(match)
        XCTAssertFalse(match?.titleRanges.isEmpty ?? true)
        // The Today row carries the same title word but wins on the
        // lane prior, per the "Today beats a title prefix" golden rule.
        XCTAssertEqual(
            model.listing.orderedIDs.first,
            "ref/chat/today_report.md"
        )
        XCTAssertTrue(
            model.listing.orderedIDs.prefix(2).contains("ref/chat/omni_review.md")
        )
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "omni",
            scope: .all,
            selectedID: "ref/chat/omni_review.md",
            banner: nil,
            refreshState: .idle
        )
        try write(model: model, name: "refs-search-880", width: 880)
    }

    private func renderScopedEmpty(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "zzz-no-match",
            scope: .articles,
            selectedID: nil,
            banner: nil,
            refreshState: .idle
        )
        XCTAssertTrue(model.listing.orderedIDs.isEmpty)
        try write(model: model, name: "refs-scoped-empty-880", width: 880)
    }

    private func renderMissingPDFSelected(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: "ref/chat/missing_pdf.md",
            banner: nil,
            refreshState: .idle
        )
        let content = model.rowContent(for: "ref/chat/missing_pdf.md")
        XCTAssertEqual(content?.isMissingPDF, true)
        try write(model: model, name: "refs-missing-pdf-selected-880", width: 880)
    }

    private func renderRefreshFailed(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: "ref/chat/today_report.md",
            banner: nil,
            refreshState: .failed(message: "boom", at: now)
        )
        try write(model: model, name: "refs-refresh-failed-880", width: 880)
    }

    private func renderLoadFailed(now: Date) throws {
        let fixture = makeFixture(now: now)
        let library = makeLibrary(now: now)
        let failed = RefsPanelModel(
            library: library,
            opener: StubOpener(),
            highlights: StubLocator()
        )
        failed.installForPreviews(
            items: [],
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: nil,
            banner: nil,
            refreshState: .failed(message: "Bob is not available", at: now)
        )
        XCTAssertFalse(failed.hasSnapshot)
        try write(model: failed, name: "refs-load-failed-880", width: 880)
    }

    private func renderSkeleton(now: Date) throws {
        let fixture = makeFixture(now: now)
        let library = makeLibrary(now: now)
        let loading = RefsPanelModel(
            library: library,
            opener: StubOpener(),
            highlights: StubLocator()
        )
        loading.installForPreviews(
            items: [],
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: nil,
            banner: nil,
            refreshState: .refreshing
        )
        try write(model: loading, name: "refs-skeleton-880", width: 880)
    }

    private func renderBanner(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: "ref/chat/today_report.md",
            banner: RefsBanner(
                kind: .error,
                message: "Highlights couldn’t open “Today Report”.",
                actions: [.tryAgain, .openInDefaultApp]
            ),
            refreshState: .idle
        )
        XCTAssertNotNil(model.banner)
        try write(model: model, name: "refs-banner-880", width: 880)
    }

    private func renderNarrowBrowse(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: "ref/chat/today_report.md",
            banner: nil,
            refreshState: .idle
        )
        XCTAssertFalse(RefsVisualTokens.showsInspector(width: 700))
        try write(model: model, name: "refs-browse-700", width: 700)
    }

    /// Standalone piece renders: each panel piece alone in a fixed
    /// frame, both appearances, for close review of baselines, the
    /// glyph column, pills, and code spans.
    private func renderPieces(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "omni",
            scope: .all,
            selectedID: "ref/chat/today_report.md",
            banner: nil,
            refreshState: .idle
        )
        let pieces: [(String, AnyView)] = [
            ("refs-piece-searchbar", AnyView(
                RefsSearchBar(model: model, previewMode: true)
            )),
            ("refs-piece-footer", AnyView(RefsFooter(model: model))),
            ("refs-piece-empty", AnyView(
                RefsEmptyStateView(model: model).frame(width: 880, height: 300)
            )),
            ("refs-piece-skeleton", AnyView(RefsSkeletonList().frame(width: 880))),
            ("refs-piece-banner", AnyView(
                RefsBannerView(
                    model: model,
                    banner: RefsBanner(kind: .error, message: "Boom.", actions: [.retry])
                ).frame(width: 880)
            )),
        ]
        var all = pieces
        if let content = model.rowContent(for: "ref/chat/today_report.md") {
            all.append((
                "refs-piece-row",
                AnyView(RefsRowView(
                    content: content,
                    isSelected: true,
                    pomodoroName: "BLOG",
                    onSelect: {},
                    onActivate: {}
                ).frame(width: 458))
            ))
            all.append((
                "refs-piece-inspector",
                AnyView(RefsInspectorView(
                    content: content,
                    signals: fixture.signals,
                    previewMode: true
                ).frame(width: 414))
            ))
        }
        for (name, view) in all {
            for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
                try RenderFixtureWriter.write(view, name: name, width: 880, appearance: appearance)
            }
        }
    }

    private func write(model: RefsPanelModel, name: String, width: CGFloat) throws {
        // Width only: the static preview list sizes to its content so
        // every section shows, while the live panel keeps its fixed
        // window height. The width rides along explicitly because a
        // GeometryReader cannot negotiate a height while the snapshot
        // sizes to content.
        let view = RefsPanelView(
            model: model,
            animatePresentation: false,
            previewMode: true,
            previewWidth: width
        )
        .frame(width: width)
        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            try RenderFixtureWriter.write(
                view,
                name: name,
                width: width,
                appearance: appearance
            )
        }
    }

    // MARK: - Fixture

    private struct Fixture {
        var items: [RefItem]
        var signals: RefsSignals
    }

    private func fixedNow() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 8, hour: 12
        )) ?? Date()
    }

    private func day(_ date: Date, offset: Int) -> RefDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let shifted = calendar.date(
            byAdding: .day, value: offset, to: date
        ) ?? date
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return RefDay(year: parts.year ?? 2026, month: parts.month ?? 10, day: parts.day ?? 8)
    }

    private func makeLibrary(now: Date) -> RefsLibrary {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return RefsLibrary(
            fetcher: nil,
            snapshotStore: RefsSnapshotStore(
                fileURL: root.appendingPathComponent("refs-snapshot.json")
            ),
            openLogStore: RefsOpenLogStore(
                fileURL: root.appendingPathComponent("refs-open-log.json")
            ),
            vaultRoot: { root.appendingPathComponent("vault") },
            fileExists: { _ in true },
            spotlight: StubSpotlight(),
            now: { now }
        )
    }

    private func makeFixture(now: Date) -> Fixture {
        let today = day(now, offset: 0)
        let items = [
            RefItem(
                id: "ref/chat/today_report.md",
                link: "[[ref/chat/today_report]]",
                rawTitle: "Team Fit Review, After `Omnigent`",
                stem: "team_fit_review",
                kind: .chat,
                state: .reading,
                isBlocked: false,
                pdfPath: "lib/chat/team_fit_review.pdf",
                parentLabel: "sase",
                added: day(now, offset: -1),
                addedSource: "created",
                annotationCount: 3,
                commentCount: 1,
                isAgentReport: true
            ),
            RefItem(
                id: "ref/chat/morning_notes.md",
                link: "[[ref/chat/morning_notes]]",
                rawTitle: "Morning Notes on Retrieval",
                stem: "morning_notes",
                kind: .chat,
                state: .ready,
                isBlocked: false,
                pdfPath: "lib/chat/morning_notes.pdf",
                parentLabel: "sase",
                added: today,
                addedSource: "created",
                audioPath: "lib/chat/morning_notes.m4a",
                isAgentReport: true
            ),
            RefItem(
                id: "ref/papers/harness_buy.md",
                link: "[[ref/papers/harness_buy]]",
                rawTitle: "What Does a Harness Buy You?",
                stem: "harness_buy",
                kind: .paper,
                state: .ready,
                isBlocked: false,
                pdfPath: "lib/papers/harness_buy.pdf",
                author: "Yangze Liu",
                published: "2026",
                added: today,
                addedSource: "created"
            ),
            RefItem(
                id: "ref/chat/omni_review.md",
                link: "[[ref/chat/omni_review]]",
                rawTitle: "Introducing Omnigent: A Meta-Harness Review",
                stem: "omni_review",
                kind: .chat,
                state: .reading,
                isBlocked: false,
                pdfPath: "lib/chat/omni_review.pdf",
                parentLabel: "sase",
                added: day(now, offset: -9),
                addedSource: "created",
                isAgentReport: true
            ),
            RefItem(
                id: "ref/papers/harness_engineering_paper.md",
                link: "[[ref/papers/harness_engineering_paper]]",
                rawTitle: "Harness Engineering at Scale",
                stem: "harness_engineering",
                titleDisambiguator: "harness_engineering",
                kind: .paper,
                state: .ready,
                isBlocked: false,
                pdfPath: "lib/papers/harness_engineering.pdf",
                author: "Ada Lovelace",
                added: day(now, offset: -30),
                addedSource: "created"
            ),
            RefItem(
                id: "ref/blogs/harness_engineering_article.md",
                link: "[[ref/blogs/harness_engineering_article]]",
                rawTitle: "Harness Engineering at Scale",
                stem: "harness_engineering",
                titleDisambiguator: "harness_engineering",
                kind: .article,
                state: .read,
                isBlocked: false,
                pdfPath: "lib/blogs/harness_engineering.pdf",
                author: "Grace Hopper",
                added: day(now, offset: -60),
                addedSource: "created",
                finished: day(now, offset: -40)
            ),
            RefItem(
                id: "ref/chat/teacher_notes.md",
                link: "[[ref/chat/teacher_notes]]",
                rawTitle: "Teacher Notes on Evals",
                stem: "teacher_notes",
                kind: .chat,
                state: .next,
                isBlocked: false,
                pdfPath: "lib/chat/teacher_notes.pdf",
                parentLabel: "sase",
                added: day(now, offset: -5),
                addedSource: "created",
                isAgentReport: true
            ),
            RefItem(
                id: "ref/papers/next_blocked.md",
                link: "[[ref/papers/next_blocked]]",
                rawTitle: "Blocked Follow-up Methods",
                stem: "next_blocked",
                kind: .paper,
                state: .next,
                isBlocked: true,
                pdfPath: "lib/papers/next_blocked.pdf",
                author: "Edsger Dijkstra",
                added: day(now, offset: -4),
                addedSource: "created"
            ),
            RefItem(
                id: "ref/docs/ready_blocked.md",
                link: "[[ref/docs/ready_blocked]]",
                rawTitle: "Migration Guide Draft",
                stem: "ready_blocked",
                kind: .doc,
                state: .ready,
                isBlocked: true,
                pdfPath: "lib/docs/ready_blocked.pdf",
                author: "Bob Saget",
                added: day(now, offset: -6),
                addedSource: "created"
            ),
            RefItem(
                id: "ref/chat/recent_finish.md",
                link: "[[ref/chat/recent_finish]]",
                rawTitle: "Recently Finished Deep Dive",
                stem: "recent_finish",
                kind: .chat,
                state: .read,
                isBlocked: false,
                pdfPath: "lib/chat/recent_finish.pdf",
                parentLabel: "sase",
                added: day(now, offset: -20),
                addedSource: "created",
                finished: day(now, offset: -4),
                annotationCount: 2,
                isAgentReport: true
            ),
            RefItem(
                id: "ref/papers/old_finished.md",
                link: "[[ref/papers/old_finished]]",
                rawTitle: "An Old Finished Paper",
                stem: "old_finished",
                kind: .paper,
                state: .read,
                isBlocked: false,
                pdfPath: "lib/papers/old_finished.pdf",
                author: "Alan Turing",
                published: "1950",
                added: day(now, offset: -200),
                addedSource: "created",
                finished: day(now, offset: -100),
                arxivID: "1950.12345"
            ),
            RefItem(
                id: "ref/docs/git_dated.md",
                link: "[[ref/docs/git_dated]]",
                rawTitle: "Undated Handbook Entry",
                stem: "git_dated",
                kind: .doc,
                state: .read,
                isBlocked: false,
                pdfPath: "lib/docs/git_dated.pdf",
                added: day(now, offset: -26),
                addedSource: "git",
                addedIsApproximate: true
            ),
            RefItem(
                id: "ref/chat/missing_pdf.md",
                link: "[[ref/chat/missing_pdf]]",
                rawTitle: "Notes With a Missing PDF",
                stem: "missing_pdf",
                kind: .chat,
                state: .ready,
                isBlocked: false,
                pdfPath: "lib/chat/gone.pdf",
                parentLabel: "sase",
                added: day(now, offset: -10),
                addedSource: "created",
                isAgentReport: true
            ),
            RefItem(
                id: "ref/books/handbook.md",
                link: "[[ref/books/handbook]]",
                rawTitle: "The Big Handbook",
                stem: "handbook",
                kind: .book,
                state: .read,
                isBlocked: false,
                pdfPath: "lib/books/handbook.pdf",
                added: day(now, offset: -300),
                addedSource: "created"
            ),
        ]
        let todayEntries = [
            "ref/chat/today_report.md": RefsTodayEntry(order: 0, pomodoroName: "BLOG"),
        ]
        let signals = RefsSignals(
            today: RefsToday(entries: todayEntries),
            opens: RefsOpenStats(
                events: [
                    RefsOpenEvent(
                        path: "ref/chat/today_report.md",
                        at: now.addingTimeInterval(-2 * 3_600)
                    ),
                    RefsOpenEvent(
                        path: "ref/chat/recent_finish.md",
                        at: now.addingTimeInterval(-3 * 86_400)
                    ),
                ],
                now: now
            ),
            pageCounts: [
                "ref/chat/today_report.md": 11,
                "ref/papers/harness_buy.md": 22,
            ],
            missingPDFs: ["ref/chat/missing_pdf.md"],
            now: now,
            calendar: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                return calendar
            }()
        )
        return Fixture(items: items, signals: signals)
    }
}

private struct StubOpener: RefsOpening {
    func openInHighlights(
        _ pdf: URL,
        app: URL,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }

    func openNote(_ url: URL) {}

    func reveal(_ url: URL) {}

    func openWithDefaultApp(
        _ url: URL,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }
}

private struct StubLocator: RefsHighlightsLocating {
    func highlightsAppURL() -> URL? {
        nil
    }
}

private struct StubSpotlight: RefsSpotlightProviding {
    func sweep(_ requests: [RefsSpotlightRequest]) async -> [String: RefsSpotlightFacts] {
        [:]
    }
}
