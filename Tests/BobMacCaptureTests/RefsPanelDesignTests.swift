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
    func testRefsPanelStatesToPNG() async throws {
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
        try renderInspectorChat(model: model, now: now)
        try renderInspectorPaper(model: model, now: now)
        try renderInspectorEncrypted(model: model, now: now)
        try await renderUnavailable(model: model, now: now)
        try renderStemMatch(model: model, now: now)
        try renderReduceTransparency(model: model, now: now)
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

    /// The full inspector for a chat: the tile hero, the Bottom-line
    /// bullets, the outline (the main visual for chats), and commented
    /// highlights.
    private func renderInspectorChat(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        let id = "ref/chat/today_report.md"
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: id,
            banner: nil,
            refreshState: .idle,
            inspector: [id: RefsInspectorContent(
                summary: RefsSummary(
                    label: "SUMMARY",
                    bullets: [
                        "Retrieval quality beats index size here.",
                        "Prefetch while the child runs.",
                        "Cap the snapshot payload.",
                    ]
                ),
                outline: ["Review question", "Evidence", "Risks", "Decision"],
                notes: [
                    RefsShowAnnotation(
                        pageLabel: "3",
                        kind: "highlight",
                        quote: "The pipeline drains while the child runs.",
                        comment: "Key insight for the fetcher."
                    ),
                    RefsShowAnnotation(
                        pageLabel: "5",
                        kind: "highlight",
                        quote: "A weak fuzzy match never beats a title word.",
                        comment: "Keep the tier invariant."
                    ),
                ],
                remainingNoteCount: 1,
                openTaskCount: 2,
                readingTime: RefsReadingTime(minutes: 70, pomodoros: 3),
                pageCount: 11
            )]
        )
        XCTAssertNotNil(model.inspectorContent(for: id))
        try write(model: model, name: "refs-inspector-chat-880", width: 880)
    }

    /// The full inspector for a paper: the thumbnail stand-in, the
    /// abstract, and the notes.
    private func renderInspectorPaper(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        let id = "ref/papers/harness_buy.md"
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: id,
            banner: nil,
            refreshState: .idle,
            inspector: [id: RefsInspectorContent(
                summary: RefsSummary(
                    label: "ABSTRACT",
                    paragraph: "We study harness reuse across three agent "
                        + "workloads and find that shared scaffolding pays "
                        + "for itself within a week."
                ),
                outline: ["Introduction", "Method", "Results"],
                notes: [RefsShowAnnotation(
                    pageLabel: "7",
                    kind: "highlight",
                    quote: "Shared scaffolding pays for itself within a week.",
                    comment: "Cite this in the rollout note."
                )],
                openTaskCount: 1,
                readingTime: RefsReadingTime(minutes: 17, pomodoros: 1),
                pageCount: 22
            )],
            thumbnails: [id: standInThumbnail()]
        )
        XCTAssertNotNil(model.inspectorThumbnail(for: id))
        try write(model: model, name: "refs-inspector-paper-880", width: 880)
    }

    /// The encrypted inspector: the thumbnail slot carries the
    /// unavailability message while the note content still fills in.
    private func renderInspectorEncrypted(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        let id = "ref/papers/old_finished.md"
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: id,
            banner: nil,
            refreshState: .idle,
            inspector: [id: RefsInspectorContent(
                notes: [RefsShowAnnotation(
                    pageLabel: "2",
                    kind: "highlight",
                    quote: "Machines take me by surprise with great frequency.",
                    comment: "Still true seventy years later."
                )],
                previewMessage: "Preview unavailable: encrypted"
            )]
        )
        XCTAssertEqual(
            model.inspectorContent(for: id)?.previewMessage,
            "Preview unavailable: encrypted"
        )
        try write(model: model, name: "refs-inspector-encrypted-880", width: 880)
    }

    /// A solid thumbnail stand-in: `ImageRenderer` never hosts PDFKit,
    /// so the paper render draws this instead of a real page image.
    private func standInThumbnail() -> NSImage {
        let size = NSSize(width: 224, height: 290)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemTeal.withAlphaComponent(0.25).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.tertiaryLabelColor.setFill()
        for index in 0..<8 {
            let bar = NSRect(
                x: 20,
                y: 30 + index * 28,
                width: 184 - index * 12,
                height: 10
            )
            NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5).fill()
        }
        image.unlockFocus()
        return image
    }

    /// A vanished row keeps its index and dims at 0.45 opacity with
    /// the "No longer in your library" caption, and the inspector
    /// shows its title plus that message (§5.5).
    private func renderUnavailable(model: RefsPanelModel, now: Date) async throws {
        let fixture = makeFixture(now: now)
        let vanished = "ref/chat/morning_notes.md"
        model.installForPreviews(
            items: fixture.items,
            signals: fixture.signals,
            query: "",
            scope: .all,
            selectedID: vanished,
            banner: nil,
            refreshState: .idle
        )
        model.previewLibrary.installSnapshotForPreviews(
            items: fixture.items.filter { $0.id != vanished },
            signals: fixture.signals,
            refreshState: .idle
        )
        let deadline = Date().addingTimeInterval(5)
        while !model.unavailableIDs.contains(vanished), Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(model.unavailableIDs.contains(vanished))
        XCTAssertEqual(
            model.rowContent(for: vanished)?.caption,
            "No longer in your library"
        )
        try write(model: model, name: "refs-unavailable-880", width: 880)
    }

    /// A stem-only search match: the caption carries the stem with its
    /// ranges in the accent color, and the title stays unmarked.
    private func renderStemMatch(model: RefsPanelModel, now: Date) throws {
        let fixture = makeFixture(now: now)
        let stemOnly = RefItem(
            id: "ref/chat/weekly_links.md",
            link: "[[ref/chat/weekly_links]]",
            rawTitle: "Weekly links roundup",
            stem: "scaffolding_notes",
            kind: .chat,
            state: .ready,
            isBlocked: false,
            pdfPath: "lib/chat/weekly_links.pdf",
            parentLabel: "sase",
            added: day(now, offset: 0),
            addedSource: "created",
            isAgentReport: true
        )
        model.installForPreviews(
            items: [stemOnly],
            signals: fixture.signals,
            query: "scaffold",
            scope: .all,
            selectedID: stemOnly.id,
            banner: nil,
            refreshState: .idle
        )
        guard case .search = model.listing.mode else {
            XCTFail("expected search mode")
            return
        }
        let match = model.listing.matches[stemOnly.id]
        XCTAssertNotNil(match)
        XCTAssertTrue(match?.titleRanges.isEmpty ?? false)
        XCTAssertFalse(match?.stemRanges.isEmpty ?? true)
        let content = try XCTUnwrap(model.rowContent(for: stemOnly.id))
        XCTAssertTrue(content.caption.hasSuffix("scaffolding_notes"))
        XCTAssertNotNil(content.captionMatch)
        try write(model: model, name: "refs-search-stem-880", width: 880)
    }

    /// The browse state under Reduce Transparency: an opaque window
    /// background sits beneath the content (§6).
    private func renderReduceTransparency(model: RefsPanelModel, now: Date) throws {
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
        try write(
            model: model,
            name: "refs-reduce-transparency-880",
            width: 880,
            reduceTransparency: true
        )
    }

    private func write(
        model: RefsPanelModel,
        name: String,
        width: CGFloat,
        reduceTransparency: Bool = false
    ) throws {
        // Width only: the static preview list sizes to its content so
        // every section shows, while the live panel keeps its fixed
        // window height. The width rides along explicitly because a
        // GeometryReader cannot negotiate a height while the snapshot
        // sizes to content.
        let view = RefsPanelView(
            model: model,
            animatePresentation: false,
            previewMode: true,
            previewWidth: width,
            reduceTransparencyOverride: reduceTransparency ? true : nil
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
