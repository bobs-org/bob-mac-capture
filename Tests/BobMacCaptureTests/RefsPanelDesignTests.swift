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
  /// Long enough to overflow four callout lines at the inspector
  /// width, so the highlight truncates with a trailing ellipsis.
  private static let longHighlightQuote =
    "Agents that write down what they know, and then read it back "
    + "before they act, stay consistent across a long session. The "
    + "median uncommented highlight is about one hundred thirty "
    + "characters, and this excerpt is longer still so the four-line "
    + "cap has to clip it and end in an ellipsis the reader can "
    + "recover from the hover tooltip."

  /// Long enough to overflow six body lines at the wide inspector
  /// width, so the wide highlight truncates with a trailing
  /// ellipsis. The readable column is ~720 pt of body type, so this
  /// passage is several times the six-line budget.
  private static let wideLongHighlightQuote =
    "Agents that write down what they know, and then read it back "
    + "before they act, stay consistent across a long session, and the "
    + "reading room gives those notes a wider column so six body lines "
    + "carry far more of the thought before the line cap has to clip it. "
    + "The median uncommented highlight is about one hundred thirty "
    + "characters, and this excerpt runs several times that length on "
    + "purpose: only a genuinely long passage proves the wide cap clips "
    + "where it should and ends in an ellipsis the reader can still "
    + "recover from the hover tooltip. "
    + "A second pass through the same idea keeps the column full: the "
    + "agent rereads the stored note, checks the hinge of the argument, "
    + "and only then writes the next step, so the six-line cap has to "
    + "bite well before this sentence finishes describing the loop."

  func testLiveListBuildsOnlyRowsNearViewport() throws {
    let now = fixedNow()
    let items = (0..<1_000).map { index in
      let stem = "lazy-row-\(index)"
      return RefItem(
        id: "ref/chat/\(stem).md",
        link: "[[ref/chat/\(stem)]]",
        rawTitle: "Lazy list row \(index)",
        stem: stem,
        kind: .chat,
        state: .read,
        isBlocked: false,
        pdfPath: "lib/\(stem).pdf",
        added: day(now, offset: -index)
      )
    }
    let library = makeLibrary(now: now)
    library.installSnapshotForPreviews(
      items: items,
      signals: RefsSignals(now: now),
      refreshState: .idle
    )
    let model = RefsPanelModel(
      library: library,
      opener: StubOpener(),
      highlights: StubLocator()
    )
    let host = NSHostingView(rootView: RefsListView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 700, height: 620)
    host.layoutSubtreeIfNeeded()

    XCTAssertGreaterThan(model.rowContentEvaluationsForTests, 0)
    XCTAssertLessThan(model.rowContentEvaluationsForTests, 150)
  }

  func testRefsPanelStatesToPNG() async throws {
    let now = fixedNow()
    let library = makeLibrary(now: now)
    let model = RefsPanelModel(
      library: library,
      opener: StubOpener(),
      highlights: StubLocator()
    )

    try renderBrowse(model: model, now: now)
    try renderNewSeenInPlace(model: model, now: now)
    try renderSearch(model: model, now: now)
    try renderScopedEmpty(model: model, now: now)
    try renderMissingPDFSelected(model: model, now: now)
    try renderRefreshFailed(model: model, now: now)
    try renderLoadFailed(now: now)
    try renderSkeleton(now: now)
    try renderBanner(model: model, now: now)
    try renderScanRunning(model: model, now: now)
    try renderScanAdded(model: model, now: now)
    try renderScanAddedSearch(model: model, now: now)
    try renderScanNothingNew(model: model, now: now)
    try renderScanPartial(model: model, now: now)
    try renderScanFailed(model: model, now: now)
    try renderNoMatchesScanHint(model: model, now: now)
    try renderScanAddedNarrow(model: model, now: now)
    try renderNarrowBrowse(model: model, now: now)
    try renderInspectorChat(model: model, now: now)
    try renderInspectorNotesRevealed(model: model, now: now)
    try renderInspectorPaper(model: model, now: now)
    try renderInspectorEncrypted(model: model, now: now)
    try await renderUnavailable(model: model, now: now)
    try renderStemMatch(model: model, now: now)
    try renderReduceTransparency(model: model, now: now)
    try renderCopyCard(model: model, now: now, width: 880)
    try renderCopyCard(model: model, now: now, width: 700)
    try renderCopyCard(model: model, now: now, width: 1344)
    try renderInspectorImages(model: model, now: now, width: 880)
    try renderInspectorImages(model: model, now: now, width: 1344)
    try renderInspectorImagesRevealed(model: model, now: now, width: 880)
    try renderInspectorImagesRevealed(model: model, now: now, width: 1344)
    try renderNewestTimeline(model: model, now: now)
    try renderNewestSearchScoped(model: model, now: now)
    try renderNewestNarrow(model: model, now: now)
    try renderTabsLoaded(model: model, now: now)
    try renderTabsCollisionSelected(model: model, now: now)
    try renderTabsSearch(model: model, now: now)
    try renderTabsPermission(now: now, adHoc: false)
    try renderTabsPermission(now: now, adHoc: true)
    try renderTabsNotRunning(now: now)
    try renderTabsNoDocuments(now: now)
    try renderTabsFailedStale(model: model, now: now)
    try renderTabsWithoutLibrarySnapshot(now: now)
    try renderTabsCloseSelected(model: model, now: now)
    try renderTabsCloseHoverRow(model: model, now: now)
    try renderTabsFooter(model: model, now: now)
    try renderClosedTabToasts()
  }

  // MARK: - Renders

  private func renderBrowse(model: RefsPanelModel, now: Date, width: CGFloat = 880) throws {
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
    XCTAssertEqual(model.listing.orderedIDs.first, "ref/chat/morning_notes.md")
    let kinds = model.listing.sections.compactMap(\.kind)
    XCTAssertEqual(kinds.first, .new)
    XCTAssertTrue(kinds.contains(.today))
    XCTAssertTrue(kinds.contains(.new))
    XCTAssertTrue(kinds.contains(.reading))
    XCTAssertTrue(kinds.contains(.next))
    XCTAssertTrue(kinds.contains(.ready))
    XCTAssertTrue(kinds.contains(.recentlyOpened))
    XCTAssertTrue(kinds.contains(.library))
    try write(model: model, name: "refs-browse-\(Int(width))", width: width)
  }

  private func renderNewSeenInPlace(model: RefsPanelModel, now: Date) throws {
    let fixture = makeFixture(now: now)
    let id = "ref/chat/morning_notes.md"
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: id,
      banner: nil,
      refreshState: .idle
    )
    XCTAssertEqual(model.listing.sectionKind(for: id), .new)
    XCTAssertTrue(model.perform(.toggleNew))
    XCTAssertEqual(model.listing.sectionKind(for: id), .new)
    XCTAssertEqual(model.rowContent(for: id)?.isNew, false)
    XCTAssertEqual(model.newSectionHint, "⌥N Mark New")
    try write(model: model, name: "refs-new-seen-880", width: 880)
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

  /// The running scan: the footer spinner with a fixed elapsed
  /// time. The elapsed comes from a live startedAt, so this render
  /// asserts nothing about the text — review the PNG for it.
  private func renderScanRunning(model: RefsPanelModel, now: Date) throws {
    let fixture = makeFixture(now: now)
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: "ref/chat/today_report.md",
      banner: nil,
      refreshState: .idle,
      scanState: .scanning(startedAt: Date().addingTimeInterval(-7))
    )
    XCTAssertTrue(model.isScanning)
    try write(model: model, name: "refs-scan-running-880", width: 880)
  }

  /// Three scanned rows on top in a Just scanned section, the first
  /// row selected, a code-span title, and the added footer.
  private func renderScanAdded(model: RefsPanelModel, now: Date) throws {
    let fixture = makeScanFixture(now: now)
    let outcome = RefsScanOutcome(
      response: RefsScanResponse(
        ok: true,
        notes: [
          RefsScanNote(
            action: "create",
            path: "ref/chat/scan_alpha.md",
            title: "Scan Brings `harness` Home"
          ),
          RefsScanNote(
            action: "create",
            path: "ref/papers/scan_beta.md",
            title: "Scan Beta Findings"
          ),
          RefsScanNote(
            action: "create",
            path: "ref/chat/scan_gamma.md",
            title: "Scan Gamma Notes"
          ),
        ]
      ),
      finishedAt: now
    )
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: "ref/chat/scan_alpha.md",
      banner: nil,
      refreshState: .idle,
      scanNotice: outcome
    )
    XCTAssertEqual(
      model.listing.orderedIDs.first,
      "ref/chat/scan_alpha.md"
    )
    XCTAssertEqual(model.listing.sections.first?.kind, .justScanned)
    try write(model: model, name: "refs-scan-added-880", width: 880)
  }

  private func renderScanAddedSearch(model: RefsPanelModel, now: Date) throws {
    let fixture = makeScanFixture(now: now)
    let outcome = RefsScanOutcome(
      response: RefsScanResponse(
        ok: true,
        notes: [
          RefsScanNote(
            action: "create",
            path: "ref/chat/scan_alpha.md",
            title: "Scan Brings `harness` Home"
          )
        ]
      ),
      finishedAt: now
    )
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "scan",
      scope: .all,
      selectedID: "ref/chat/scan_alpha.md",
      banner: nil,
      refreshState: .idle,
      scanNotice: outcome
    )
    guard case .search = model.listing.mode else {
      XCTFail("expected search mode")
      return
    }
    try write(model: model, name: "refs-scan-added-search-880", width: 880)
  }

  private func renderScanNothingNew(model: RefsPanelModel, now: Date) throws {
    let fixture = makeFixture(now: now)
    let outcome = RefsScanOutcome(
      response: RefsScanResponse(
        ok: true,
        notes: [
          RefsScanNote(
            action: "update",
            path: "ref/papers/harness_buy.md",
            title: "What Does a Harness Buy You?"
          ),
          RefsScanNote(
            action: "update",
            path: "ref/chat/morning_notes.md",
            title: "Morning Notes on Retrieval"
          ),
        ]
      ),
      finishedAt: now
    )
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: "ref/chat/today_report.md",
      banner: nil,
      refreshState: .idle,
      scanNotice: outcome
    )
    XCTAssertEqual(
      RefsScanPresentation.footerText(outcome, searchMode: false),
      "No new references · 2 notes synced"
    )
    try write(model: model, name: "refs-scan-nothing-new-880", width: 880)
  }

  private func renderScanPartial(model: RefsPanelModel, now: Date) throws {
    let fixture = makeFixture(now: now)
    let outcome = RefsScanOutcome(
      response: RefsScanResponse(
        ok: false,
        notes: [
          RefsScanNote(
            action: "create",
            path: "ref/chat/scan_alpha.md",
            title: "Scan Alpha Report"
          )
        ],
        failures: [
          RefsScanFailure(
            pdf: "lib/papers/blank_scan.pdf",
            stage: "plan",
            message: "no extractable text on pages 1-3"
          ),
          RefsScanFailure(
            pdf: "lib/chat/noisy_report.pdf",
            stage: "write",
            message: "reference note changed during sync; rerun"
          ),
        ]
      ),
      finishedAt: now
    )
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: "ref/chat/today_report.md",
      banner: RefsBanner(
        kind: .warning,
        message: RefsScanPresentation.bannerMessage(outcome) ?? "",
        actions: [.copyDiagnostic]
      ),
      refreshState: .idle,
      scanNotice: outcome
    )
    XCTAssertNotNil(model.banner)
    try write(model: model, name: "refs-scan-partial-880", width: 880)
  }

  private func renderScanFailed(model: RefsPanelModel, now: Date) throws {
    let fixture = makeFixture(now: now)
    let outcome = RefsScanOutcome(
      problem: RefsScanProblem(
        code: "dirty_targets",
        message: "refusing to modify dirty vault files",
        hint: "commit, stash, or clean those paths, then scan again",
        paths: [
          "ref/chat/omni_report.md",
          "ref/papers/attention_review.md",
          "ref/chat/standup_notes.md",
          "ref/papers/harness_notes.md",
        ]
      ),
      finishedAt: now
    )
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: "ref/chat/today_report.md",
      banner: RefsBanner(
        kind: .error,
        message: RefsScanPresentation.bannerMessage(outcome) ?? "",
        actions: [.scanAgain, .copyDiagnostic]
      ),
      refreshState: .idle,
      scanNotice: outcome
    )
    XCTAssertNotNil(model.banner)
    try write(model: model, name: "refs-scan-failed-880", width: 880)
  }

  private func renderNoMatchesScanHint(model: RefsPanelModel, now: Date) throws {
    let fixture = makeFixture(now: now)
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "zzz-no-match",
      scope: .all,
      selectedID: nil,
      banner: nil,
      refreshState: .idle
    )
    XCTAssertTrue(model.listing.orderedIDs.isEmpty)
    try write(model: model, name: "refs-no-matches-scan-hint-880", width: 880)
  }

  /// List-only width: the footer hints and scan status share one
  /// line without colliding or clipping.
  private func renderScanAddedNarrow(model: RefsPanelModel, now: Date) throws {
    let fixture = makeScanFixture(now: now)
    let outcome = RefsScanOutcome(
      response: RefsScanResponse(
        ok: true,
        notes: [
          RefsScanNote(
            action: "create",
            path: "ref/chat/scan_alpha.md",
            title: "Scan Brings `harness` Home"
          ),
          RefsScanNote(
            action: "create",
            path: "ref/papers/scan_beta.md",
            title: "Scan Beta Findings"
          ),
          RefsScanNote(
            action: "create",
            path: "ref/chat/scan_gamma.md",
            title: "Scan Gamma Notes"
          ),
        ]
      ),
      finishedAt: now
    )
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: "ref/chat/scan_alpha.md",
      banner: nil,
      refreshState: .idle,
      scanNotice: outcome
    )
    XCTAssertFalse(RefsVisualTokens.showsInspector(width: 700))
    try write(model: model, name: "refs-scan-added-700", width: 700)
  }

  /// The browse fixture plus three scanned rows under a Just scanned
  /// mark stamped just now, so the section renders first.
  private func makeScanFixture(now: Date) -> Fixture {
    let base = makeFixture(now: now)
    let scanned = [
      RefItem(
        id: "ref/chat/scan_alpha.md",
        link: "[[ref/chat/scan_alpha]]",
        rawTitle: "Scan Brings `harness` Home",
        stem: "scan_alpha",
        kind: .chat,
        state: .ready,
        isBlocked: false,
        pdfPath: "lib/chat/scan_alpha.pdf",
        parentLabel: "sase",
        added: day(now, offset: 0),
        addedSource: "created",
        isAgentReport: true
      ),
      RefItem(
        id: "ref/papers/scan_beta.md",
        link: "[[ref/papers/scan_beta]]",
        rawTitle: "Scan Beta Findings",
        stem: "scan_beta",
        kind: .paper,
        state: .ready,
        isBlocked: false,
        pdfPath: "lib/papers/scan_beta.pdf",
        author: "Ada Lovelace",
        added: day(now, offset: 0),
        addedSource: "created"
      ),
      RefItem(
        id: "ref/chat/scan_gamma.md",
        link: "[[ref/chat/scan_gamma]]",
        rawTitle: "Scan Gamma Notes",
        stem: "scan_gamma",
        kind: .chat,
        state: .ready,
        isBlocked: false,
        pdfPath: "lib/chat/scan_gamma.pdf",
        parentLabel: "sase",
        added: day(now, offset: 0),
        addedSource: "created",
        isAgentReport: true
      ),
    ]
    var signals = base.signals
    signals.scan = RefsScanMark(
      ids: [
        "ref/chat/scan_alpha.md",
        "ref/papers/scan_beta.md",
        "ref/chat/scan_gamma.md",
      ],
      at: now
    )
    return Fixture(items: base.items + scanned, signals: signals)
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
  private func renderInspectorChat(model: RefsPanelModel, now: Date, width: CGFloat = 880) throws {
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
      inspector: [
        id: RefsInspectorContent(
          summary: RefsSummary(
            label: "SUMMARY",
            bullets: [
              "Retrieval quality beats index size here.",
              "Prefetch while the child runs.",
              "Cap the snapshot payload.",
            ]
          ),
          outline: ["Review question", "Evidence", "Risks", "Decision"],
          highlights: [
            RefsShowAnnotation(
              pageLabel: "Page 1",
              kind: "highlight",
              quote: "The pipeline drains while the child runs.",
              comment: "Key insight for the fetcher."
            ),
            RefsShowAnnotation(
              pageLabel: "2",
              kind: "highlight",
              quote: "A weak fuzzy match never beats a title word.",
              comment: "Keep the tier invariant."
            ),
            RefsShowAnnotation(
              pageLabel: "3",
              kind: "highlight",
              quote: "A third note for the disclosure row.",
              comment: "Third comment."
            ),
            RefsShowAnnotation(
              pageLabel: "5",
              kind: "highlight",
              quote: "A fourth note beyond the first page.",
              comment: "Fourth comment."
            ),
            RefsShowAnnotation(
              pageLabel: "7",
              kind: "highlight",
              quote: "A fifth note beyond the first page.",
              comment: "Fifth comment."
            ),
          ],
          openTaskCount: 2,
          readingTime: RefsReadingTime(minutes: 70, pomodoros: 3),
          pageCount: 11
        )
      ]
    )
    XCTAssertNotNil(model.inspectorContent(for: id))
    try write(model: model, name: "refs-inspector-chat-\(Int(width))", width: width)
  }

  private func renderInspectorNotesRevealed(model: RefsPanelModel, now: Date) throws {
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
      inspector: [
        id: RefsInspectorContent(
          summary: RefsSummary(
            label: "SUMMARY",
            bullets: ["Retrieval quality beats index size here."]
          ),
          outline: ["Review question", "Evidence"],
          highlights: (1...13).map { index in
            RefsShowAnnotation(
              pageLabel: "\(index)",
              kind: "highlight",
              quote: "Quote \(index).",
              comment: "Comment \(index)."
            )
          },
          openTaskCount: 1,
          readingTime: RefsReadingTime(minutes: 17, pomodoros: 1),
          pageCount: 11
        )
      ]
    )
    XCTAssertTrue(model.revealMoreInspectorNotes())
    let page = model.inspectorNotesPage(for: id)
    let content = try XCTUnwrap(model.inspectorContent(for: id))
    XCTAssertEqual(page.visibleCount(total: 13), 10)
    XCTAssertEqual(
      content.feed.moreText(
        visible: page.visibleCount(total: content.feed.total),
        nextBatch: page.nextBatchCount(total: content.feed.total)
      ),
      "+3 more · 3 with notes · ⌃D shows the rest"
    )
    try write(model: model, name: "refs-inspector-notes-revealed-880", width: 880)
  }

  /// The full inspector for a paper: the thumbnail stand-in, the
  /// abstract, and the notes.
  private func renderInspectorPaper(model: RefsPanelModel, now: Date, width: CGFloat = 880) throws {
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
      inspector: [
        id: RefsInspectorContent(
          summary: RefsSummary(
            label: "ABSTRACT",
            paragraph: "We study harness reuse across three agent "
              + "workloads and find that shared scaffolding pays "
              + "for itself within a week."
          ),
          outline: ["Introduction", "Method", "Results"],
          highlights: [
            RefsShowAnnotation(
              pageLabel: "7",
              kind: "highlight",
              quote: "Shared scaffolding pays for itself within a week.",
              comment: "Cite this in the rollout note."
            )
          ],
          openTaskCount: 1,
          readingTime: RefsReadingTime(minutes: 17, pomodoros: 1),
          pageCount: 22
        )
      ],
      thumbnails: [id: standInThumbnail()]
    )
    XCTAssertNotNil(model.inspectorThumbnail(for: id))
    try write(model: model, name: "refs-inspector-paper-\(Int(width))", width: width)
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
      inspector: [
        id: RefsInspectorContent(
          highlights: [
            RefsShowAnnotation(
              pageLabel: "2",
              kind: "highlight",
              quote: "Machines take me by surprise with great frequency.",
              comment: "Still true seventy years later."
            )
          ],
          previewMessage: "Preview unavailable: encrypted"
        )
      ]
    )
    XCTAssertEqual(
      model.inspectorContent(for: id)?.previewMessage,
      "Preview unavailable: encrypted"
    )
    try write(model: model, name: "refs-inspector-encrypted-880", width: 880)
  }

  private func renderInspectorSections(
    model: RefsPanelModel,
    now: Date,
    width: CGFloat,
    reveal: Bool = false,
    dynamicTypeSize: DynamicTypeSize? = nil
  ) throws {
    let fixture = makeFixture(now: now)
    let id = "ref/blogs/harness_engineering_article.md"
    let longDescription =
      "Everything that belongs in the blog's memory section, including "
      + "the long asides that should clamp in compact mode and wrap a "
      + "little further in the wide column before the help tooltip keeps "
      + "the rest. A second sentence keeps the description long enough "
      + "to prove the line cap."
    let highlights = [
      RefsShowAnnotation(
        pageLabel: "Page 4",
        kind: "highlight",
        quote: "Make a point about how if I were building AI from scratch.",
        section: "memory"
      ),
      RefsShowAnnotation(
        pageLabel: "Page 5",
        kind: "highlight",
        quote: "Mention that you've implemented project memory every wrong way.",
        comment: "Compare with the intro",
        section: "memory"
      ),
      RefsShowAnnotation(
        pageLabel: "Page 4",
        kind: "image",
        comment: "A figure worth keeping.",
        asset: "ref/notes/pic.png",
        section: "visuals"
      ),
      RefsShowAnnotation(
        pageLabel: "Page 4",
        kind: "highlight",
        quote: "POTENTIAL QUOTES: keep these ungrouped."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 8",
        kind: "note",
        comment: "A standalone note in the ungrouped tail."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 9",
        kind: "highlight",
        quote: "A later ungrouped highlight past the first page."
      ),
    ]
    let sections = [
      RefsShowSection(
        id: "intro", title: "Intro", tag: "@intro", count: 0
      ),
      RefsShowSection(
        id: "memory",
        title: "Memory",
        tag: "@memory",
        description: longDescription,
        count: 2,
        pages: "Pages 4–5"
      ),
      RefsShowSection(
        id: "related", title: "Related", tag: "@related", count: 0
      ),
      RefsShowSection(
        id: "visuals",
        title: "Visuals",
        tag: "@visuals",
        count: 1,
        pages: "Page 4"
      ),
    ]
    model.notesPageSize = 5
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: id,
      banner: nil,
      refreshState: .idle,
      inspector: [
        id: RefsInspectorContent(sections: sections, highlights: highlights)
      ]
    )
    if reveal {
      XCTAssertTrue(model.revealMoreInspectorNotes())
    }
    var name = "refs-inspector-sections-\(Int(width))"
    if reveal { name += "-revealed" }
    if dynamicTypeSize != nil { name += "-ax" }
    try write(
      model: model,
      name: name,
      width: width,
      dynamicTypeSize: dynamicTypeSize
    )
  }

  /// Unified HIGHLIGHTS renders: first page, one reveal, and all
  /// noted. Separate from the monolith so a later failure there
  /// cannot swallow these.
  func testRefsInspectorHighlightsToPNG() async throws {
    let now = fixedNow()
    let library = makeLibrary(now: now)
    let model = RefsPanelModel(
      library: library,
      opener: StubOpener(),
      highlights: StubLocator()
    )
    try renderInspectorHighlightsUnified(model: model, now: now)
    try renderInspectorHighlightsRevealed(model: model, now: now)
    try renderInspectorHighlightsNoted(model: model, now: now)
  }

  func testRefsInspectorSectionsToPNG() throws {
    let now = fixedNow()
    let library = makeLibrary(now: now)
    let model = RefsPanelModel(
      library: library,
      opener: StubOpener(),
      highlights: StubLocator()
    )
    try renderInspectorSections(model: model, now: now, width: 880)
    try renderInspectorSections(model: model, now: now, width: 1344)
    try renderInspectorSections(
      model: model, now: now, width: 880, reveal: true
    )
    try renderInspectorSections(
      model: model,
      now: now,
      width: 880,
      dynamicTypeSize: .accessibility2
    )
  }

  /// Gold underline ink: the screenshot's Page 2/4/5 quotes, a
  /// whole-quote standalone underline, and a descender-heavy run,
  /// at compact 880 and wide 1344, light and dark.
  func testRefsInspectorUnderlinesToPNG() throws {
    let now = fixedNow()
    let library = makeLibrary(now: now)
    let model = RefsPanelModel(
      library: library,
      opener: StubOpener(),
      highlights: StubLocator()
    )
    try renderInspectorUnderlines(model: model, now: now, width: 880)
    try renderInspectorUnderlines(model: model, now: now, width: 1344)
  }

  private func renderInspectorUnderlines(
    model: RefsPanelModel,
    now: Date,
    width: CGFloat
  ) throws {
    let fixture = makeFixture(now: now)
    let id = "ref/blogs/harness_engineering_article.md"
    let highlights = [
      RefsShowAnnotation(
        pageLabel: "Page 2",
        kind: "highlight",
        quote:
          "In order to support this growth, we built Scion, an in-house "
          + "version control system, and fully migrated our monorepo from "
          + "git in five months."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 4",
        kind: "highlight",
        quote:
          "Taking a step back, we noticed that, like most companies, we "
          + "were using git as a centralized system with one authoritative "
          + "copy, but nearly **all of our clients were agents and jobs "
          + "that are online by definition.** The properties that make git "
          + "excellent for distributed, offline work were actively "
          + "undermining our ability to scale as the repo grew. So we "
          + "asked ourselves: if we designed source control with the fact "
          + "that agents are **always online** in mind from the start, "
          + "what would it look like?"
      ),
      RefsShowAnnotation(
        pageLabel: "Page 5",
        kind: "highlight",
        quote:
          "Source control for huge monorepos has **prior art, notably "
          + "Google’s Piper and Meta’s Sapling,2** so we were able to "
          + "build Scion with their hard-won lessons in mind."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 6",
        kind: "highlight",
        quote: "**The entire passage is the underline.**"
      ),
      RefsShowAnnotation(
        pageLabel: "Page 7",
        kind: "highlight",
        quote: "The **typography, quickly** of this line."
      ),
    ]
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: id,
      banner: nil,
      refreshState: .idle,
      inspector: [id: RefsInspectorContent(highlights: highlights)]
    )
    XCTAssertEqual(
      model.inspectorContent(for: id)?.feed.total,
      5
    )
    try write(
      model: model,
      name: "refs-inspector-underlines-\(Int(width))",
      width: width
    )
  }

  /// Seven highlights in page order: a bold run, a one-line note
  /// card, a four-line truncation, a same-page run, and the first
  /// page's disclosure.
  private func renderInspectorHighlightsUnified(
    model: RefsPanelModel,
    now: Date
  ) throws {
    let fixture = makeFixture(now: now)
    let id = "ref/blogs/harness_engineering_article.md"
    let highlights = [
      RefsShowAnnotation(
        pageLabel: "Page 1",
        kind: "highlight",
        quote: "**Factual memory tells the agent what it knows.**"
      ),
      RefsShowAnnotation(
        pageLabel: "Page 2",
        kind: "highlight",
        quote:
          "The pipeline drains while the child runs, so the fetcher never blocks on a full pipe.",
        comment: "Pin this for the memory design doc."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 3",
        kind: "highlight",
        quote: Self.longHighlightQuote
      ),
      RefsShowAnnotation(
        pageLabel: "Page 3",
        kind: "highlight",
        quote: "Same-page highlights share one page label."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 4",
        kind: "highlight",
        quote: "A later highlight still waits behind the row.",
        comment: "Keep the tier invariant. Cite this in the rollout note."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 6",
        kind: "highlight",
        quote: "Sixth highlight is also still hidden."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 7",
        kind: "highlight",
        quote: "Seventh highlight closes the stack."
      ),
    ]
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: id,
      banner: nil,
      refreshState: .idle,
      inspector: [id: RefsInspectorContent(highlights: highlights)]
    )
    let feed = try XCTUnwrap(model.inspectorContent(for: id)?.feed)
    XCTAssertEqual(
      feed.moreText(visible: 3, nextBatch: 3),
      "+4 more · 1 with a note · ⌃D shows 3 more"
    )
    try write(model: model, name: "refs-inspector-highlights-880", width: 880)
  }

  /// The same eleven-highlight article after one reveal: the same-page
  /// run, the second card, and `+1 more · ⌃D shows it`.
  private func renderInspectorHighlightsRevealed(
    model: RefsPanelModel,
    now: Date,
    width: CGFloat = 880
  ) throws {
    let fixture = makeFixture(now: now)
    let id = "ref/blogs/harness_engineering_article.md"
    let highlights = [
      RefsShowAnnotation(
        pageLabel: "Page 1",
        kind: "highlight",
        quote: "**Factual memory tells the agent what it knows.**"
      ),
      RefsShowAnnotation(
        pageLabel: "Page 2",
        kind: "highlight",
        quote:
          "The pipeline drains while the child runs, so the fetcher never blocks on a full pipe.",
        comment: "Pin this for the memory design doc."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 3",
        kind: "highlight",
        quote: Self.longHighlightQuote
      ),
      RefsShowAnnotation(
        pageLabel: "Page 3",
        kind: "highlight",
        quote: "Same-page highlights share one page label."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 4",
        kind: "highlight",
        quote: "A later highlight still waits behind the row.",
        comment: "Keep the tier invariant. Cite this in the rollout note."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 6",
        kind: "highlight",
        quote: "Sixth highlight is also still hidden."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 7",
        kind: "highlight",
        quote: "Seventh highlight closes the stack."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 8",
        kind: "highlight",
        quote: "Eighth highlight follows the same-page run."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 9",
        kind: "highlight",
        quote: "Ninth highlight adds another page."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 10",
        kind: "highlight",
        quote: "Tenth highlight is visible after one reveal."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 11",
        kind: "highlight",
        quote: "Eleventh highlight remains hidden."
      ),
    ]
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: id,
      banner: nil,
      refreshState: .idle,
      inspector: [id: RefsInspectorContent(highlights: highlights)]
    )
    XCTAssertTrue(model.revealMoreInspectorNotes())
    let content = try XCTUnwrap(model.inspectorContent(for: id))
    let page = model.inspectorNotesPage(for: id)
    XCTAssertEqual(
      content.feed.moreText(
        visible: page.visibleCount(total: content.feed.total),
        nextBatch: page.nextBatchCount(total: content.feed.total)
      ),
      "+1 more · ⌃D shows it"
    )
    try write(
      model: model,
      name: "refs-inspector-highlights-revealed-\(Int(width))",
      width: width
    )
  }

  /// Three highlights, all noted: a normal quote, an empty quote
  /// with a multi-line comment, and a bold quote. Header chip 3, no
  /// disclosure.
  private func renderInspectorHighlightsNoted(
    model: RefsPanelModel,
    now: Date,
    width: CGFloat = 880
  ) throws {
    let fixture = makeFixture(now: now)
    let id = "ref/chat/today_report.md"
    let highlights = [
      RefsShowAnnotation(
        pageLabel: "Page 1",
        kind: "highlight",
        quote: "The pipeline drains while the child runs.",
        comment: "Key insight for the fetcher."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 2",
        kind: "highlight",
        quote: "",
        comment:
          "A card sits directly under this page label.\nThe quote was empty, so the note is the whole entry."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 3",
        kind: "highlight",
        quote: "**Factual memory tells the agent what it knows.**",
        comment: "Keep the tier invariant."
      ),
    ]
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: id,
      banner: nil,
      refreshState: .idle,
      inspector: [id: RefsInspectorContent(highlights: highlights)]
    )
    let feed = try XCTUnwrap(model.inspectorContent(for: id)?.feed)
    XCTAssertNil(feed.moreText(visible: 3, nextBatch: 3))
    XCTAssertEqual(feed.notedCount, 3)
    try write(model: model, name: "refs-inspector-highlights-noted-\(Int(width))", width: width)
  }

  /// Reading-room renders at 1344 pt: the wide inspector (hero with
  /// the 150 x 194 thumbnail beside the facts, body typography, the
  /// 720 pt readable column) across browse, chat, paper, and the
  /// highlight feed states. The 880-pt renders stay as the compact
  /// references.
  func testRefsWidePanelToPNG() throws {
    let now = fixedNow()
    let library = makeLibrary(now: now)
    let model = RefsPanelModel(
      library: library,
      opener: StubOpener(),
      highlights: StubLocator()
    )
    try renderBrowse(model: model, now: now, width: 1344)
    try renderInspectorChat(model: model, now: now, width: 1344)
    try renderInspectorPaper(model: model, now: now, width: 1344)
    try renderWideHighlightsUnified(model: model, now: now)
    try renderInspectorHighlightsRevealed(
      model: model, now: now, width: 1344
    )
    try renderInspectorHighlightsNoted(model: model, now: now, width: 1344)
  }

  /// Seven highlights at the wide width: a bold run, a one-line
  /// note card, a six-body-line truncation, a same-page run, and
  /// the first page's disclosure.
  private func renderWideHighlightsUnified(
    model: RefsPanelModel,
    now: Date
  ) throws {
    let fixture = makeFixture(now: now)
    let id = "ref/blogs/harness_engineering_article.md"
    let highlights = [
      RefsShowAnnotation(
        pageLabel: "Page 1",
        kind: "highlight",
        quote: "**Factual memory tells the agent what it knows.**"
      ),
      RefsShowAnnotation(
        pageLabel: "Page 2",
        kind: "highlight",
        quote:
          "The pipeline drains while the child runs, so the fetcher never blocks on a full pipe.",
        comment: "Pin this for the memory design doc."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 3",
        kind: "highlight",
        quote: Self.wideLongHighlightQuote
      ),
      RefsShowAnnotation(
        pageLabel: "Page 3",
        kind: "highlight",
        quote: "Same-page highlights share one page label."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 4",
        kind: "highlight",
        quote: "A later highlight still waits behind the row.",
        comment: "Keep the tier invariant. Cite this in the rollout note."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 6",
        kind: "highlight",
        quote: "Sixth highlight is also still hidden.",
        comment: "Keep this for the disclosure note clause."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 7",
        kind: "highlight",
        quote: "Seventh highlight closes the stack."
      ),
    ]
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: id,
      banner: nil,
      refreshState: .idle,
      inspector: [id: RefsInspectorContent(highlights: highlights)]
    )
    let feed = try XCTUnwrap(model.inspectorContent(for: id)?.feed)
    XCTAssertEqual(
      feed.moreText(visible: 5, nextBatch: 2),
      "+2 more · 1 with a note · ⌃D shows the rest"
    )
    try write(model: model, name: "refs-inspector-highlights-1344", width: 1344)
  }

  /// Image highlights, attached images, a standalone note, an
  /// unavailable row, and a transparent PNG on the white backing.
  private func renderInspectorImages(
    model: RefsPanelModel,
    now: Date,
    width: CGFloat
  ) throws {
    let fixture = makeFixture(now: now)
    let id = "ref/docs/gastown_readme.md"
    let items =
      fixture.items + [
        RefItem(
          id: id,
          link: "[[ref/docs/gastown_readme]]",
          rawTitle: "Gas Town README",
          stem: "gastown_readme",
          kind: .doc,
          state: .ready,
          isBlocked: false,
          pdfPath: "lib/docs/gastown_readme.pdf",
          added: day(now, offset: -2)
        )
      ]
    let crop = "ref/docs/gastown_readme.assets/h-crop.jpg"
    let attached = "ref/docs/gastown_readme.assets/note.png"
    let alpha = "ref/docs/gastown_readme.assets/diagram.png"
    let missing = "ref/docs/gastown_readme.assets/missing.jpg"
    let highlights = [
      RefsShowAnnotation(
        pageLabel: "Page 5",
        kind: "image",
        asset: crop
      ),
      RefsShowAnnotation(
        pageLabel: "Page 9",
        kind: "highlight",
        quote: "Gas Town crew, Mayor, and Beads Crew tmux sessions",
        comment: "Keep this screenshot with the quote.",
        images: [attached, alpha]
      ),
      RefsShowAnnotation(
        pageLabel: "Page 10",
        kind: "highlight",
        quote: "",
        images: [attached]
      ),
      RefsShowAnnotation(
        pageLabel: "Page 12",
        kind: "note",
        comment: "A standalone note sits in the feed in note order."
      ),
      RefsShowAnnotation(
        pageLabel: "Page 14",
        kind: "image",
        asset: missing
      ),
    ]
    let previewImages = [
      crop: makeTestImage(
        size: NSSize(width: 400, height: 160),
        color: .systemOrange
      ),
      attached: makeTestImage(
        size: NSSize(width: 240, height: 80),
        color: .systemBlue
      ),
      alpha: makeTransparentTestImage(size: NSSize(width: 120, height: 60)),
    ]
    model.installForPreviews(
      items: items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: id,
      banner: nil,
      refreshState: .idle,
      inspector: [
        id: RefsInspectorContent(
          outline: ["Setup", "Mayor"],
          highlights: highlights,
          pageCount: 16
        )
      ],
      images: previewImages
    )
    let content = try XCTUnwrap(model.inspectorContent(for: id))
    XCTAssertEqual(
      content.feed.entries(visible: 5).map(\.kind),
      [
        .image, .highlight, .highlight, .note, .image,
      ])
    XCTAssertNotNil(content.images[crop])
    XCTAssertNotNil(content.images[alpha])
    XCTAssertTrue(content.images[alpha]?.hasAlpha ?? false)
    try write(
      model: model,
      name: "refs-inspector-images-\(Int(width))",
      width: width
    )
  }

  /// The second page holds an image highlight: the reserved frame is
  /// already in the snapshot, so a later bitmap cannot jump layout.
  private func renderInspectorImagesRevealed(
    model: RefsPanelModel,
    now: Date,
    width: CGFloat
  ) throws {
    let fixture = makeFixture(now: now)
    let id = "ref/blogs/gas_town_emergency_user_manual.md"
    let items =
      fixture.items + [
        RefItem(
          id: id,
          link: "[[ref/blogs/gas_town_emergency_user_manual]]",
          rawTitle: "Gas Town Emergency User Manual",
          stem: "gas_town_emergency_user_manual",
          kind: .article,
          state: .ready,
          isBlocked: false,
          pdfPath: "lib/blogs/gas_town_emergency_user_manual.pdf",
          added: day(now, offset: -1)
        )
      ]
    let revealed = "ref/blogs/gas_town_emergency_user_manual.assets/shot.png"
    var highlights = (1...5).map { index in
      RefsShowAnnotation(
        pageLabel: "Page \(index)",
        kind: "highlight",
        quote: "Quote \(index) stays on the first page."
      )
    }
    highlights.append(
      RefsShowAnnotation(
        pageLabel: "Page 6",
        kind: "image",
        asset: revealed
      )
    )
    highlights.append(
      RefsShowAnnotation(
        pageLabel: "Page 7",
        kind: "highlight",
        quote: "A later quote after the image."
      )
    )
    model.installForPreviews(
      items: items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: id,
      banner: nil,
      refreshState: .idle,
      inspector: [
        id: RefsInspectorContent(
          highlights: highlights,
          pageCount: 18
        )
      ],
      images: [
        revealed: makeTestImage(
          size: NSSize(width: 360, height: 140),
          color: .systemPurple
        )
      ]
    )
    XCTAssertTrue(model.revealMoreInspectorNotes())
    let content = try XCTUnwrap(model.inspectorContent(for: id))
    let page = model.inspectorNotesPage(for: id)
    XCTAssertEqual(page.visibleCount(total: content.feed.total), 7)
    XCTAssertEqual(content.feed.entries(visible: 7).last?.kind, .highlight)
    try write(
      model: model,
      name: "refs-inspector-images-revealed-\(Int(width))",
      width: width
    )
  }

  private func makeTransparentTestImage(size: NSSize) -> NSImage {
    let pixelsWide = max(1, Int(size.width.rounded()))
    let pixelsHigh = max(1, Int(size.height.rounded()))
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixelsWide,
      pixelsHigh: pixelsHigh,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
    NSColor.systemBlue.setFill()
    let inset = NSRect(
      x: CGFloat(pixelsWide) * 0.15,
      y: CGFloat(pixelsHigh) * 0.15,
      width: CGFloat(pixelsWide) * 0.7,
      height: CGFloat(pixelsHigh) * 0.7
    )
    NSBezierPath(ovalIn: inset).fill()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
  }

  /// A solid thumbnail stand-in: `ImageRenderer` never hosts PDFKit,
  /// so the paper render draws this instead of a real page image.
  /// Sized 300 x 388 px like the loader's thumbnail, so both the
  /// wide (150 x 194 pt) and compact (112 x 145 pt) slots draw from
  /// the same image.
  private func standInThumbnail() -> NSImage {
    let size = NSSize(width: 300, height: 388)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.systemTeal.withAlphaComponent(0.25).setFill()
    NSRect(origin: .zero, size: size).fill()
    NSColor.tertiaryLabelColor.setFill()
    for index in 0..<10 {
      let bar = NSRect(
        x: 24,
        y: 30 + index * 34,
        width: 252 - index * 14,
        height: 12
      )
      NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill()
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

  private func renderCopyCard(
    model: RefsPanelModel,
    now: Date,
    width: CGFloat
  ) throws {
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
    model.openCopyCard()
    XCTAssertNotNil(model.copyCard)
    try write(
      model: model,
      name: width >= 760
        ? "refs-copy-card-wide-\(Int(width))" : "refs-copy-card-narrow-\(Int(width))",
      width: width
    )
    model.panelDidHide()
  }

  // MARK: - Newest

  private func newestTitles(_ model: RefsPanelModel) -> [String] {
    model.listing.sections.compactMap { section in
      guard case .added(let group) = section.kind else {
        return nil
      }
      return group.title.uppercased()
    }
  }

  private func renderNewestTimeline(model: RefsPanelModel, now: Date) throws {
    let fixture = makeFixture(now: now)
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: "ref/chat/morning_notes.md",
      banner: nil,
      refreshState: .idle,
      listOrder: .newest
    )
    XCTAssertEqual(model.listOrder, .newest)
    XCTAssertEqual(model.listing.order, .newest)
    let titles = newestTitles(model)
    XCTAssertTrue(titles.contains("TODAY"))
    XCTAssertTrue(titles.contains("YESTERDAY"))
    XCTAssertTrue(titles.contains("SATURDAY"))
    XCTAssertTrue(titles.contains("OCTOBER"))
    XCTAssertTrue(titles.contains("DECEMBER 2025"))
    XCTAssertTrue(titles.contains("UNDATED"))
    XCTAssertNotNil(
      NSImage(
        systemSymbolName: RefsNewestToken.symbolName,
        accessibilityDescription: nil
      )
    )
    try write(model: model, name: "refs-newest-880", width: 880)
  }

  private func renderNewestSearchScoped(model: RefsPanelModel, now: Date) throws {
    let fixture = makeFixture(now: now)
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "harness",
      scope: .papers,
      selectedID: "ref/papers/harness_buy.md",
      banner: nil,
      refreshState: .idle,
      listOrder: .newest
    )
    guard case .search = model.listing.mode else {
      XCTFail("expected search mode")
      return
    }
    XCTAssertEqual(model.scope, .papers)
    XCTAssertEqual(model.listOrder, .newest)
    let match = model.listing.matches["ref/papers/harness_buy.md"]
    XCTAssertNotNil(match)
    XCTAssertFalse(match?.titleRanges.isEmpty ?? true)
    XCTAssertTrue(
      model.listing.orderedIDs.contains("ref/papers/harness_engineering_paper.md")
    )
    try write(model: model, name: "refs-newest-search-880", width: 880)
  }

  private func renderNewestNarrow(model: RefsPanelModel, now: Date) throws {
    let fixture = makeFixture(now: now)
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: "ref/chat/morning_notes.md",
      banner: nil,
      refreshState: .idle,
      listOrder: .newest
    )
    XCTAssertFalse(RefsVisualTokens.showsInspector(width: 700))
    XCTAssertEqual(model.listOrder, .newest)
    try write(model: model, name: "refs-newest-700", width: 700)
  }

  // MARK: - Tabs

  /// Nine open tabs against the fixture library: seven unique file
  /// names, one `harness_engineering.pdf` collision, and one
  /// unmatched `cv.pdf`. The first tab is current with a page
  /// caption, so the Current pill renders.
  private func makeTabsSnapshot(frontmost: Bool) -> HighlightsTabsSnapshot {
    func tab(_ fileName: String, selected: Bool = false)
      -> HighlightsTabsSnapshot.Tab
    {
      HighlightsTabsSnapshot.Tab(
        fileName: fileName,
        isSelected: selected
      )
    }
    return HighlightsTabsSnapshot(
      windows: [
        HighlightsTabsSnapshot.Window(
          isMain: true,
          pageCaption: "p. 5/25",
          tabs: [
            tab("team_fit_review.pdf", selected: true),
            tab("morning_notes.pdf"),
            tab("harness_buy.pdf"),
            tab("omni_review.pdf"),
            tab("harness_engineering.pdf"),
            tab("teacher_notes.pdf"),
            tab("next_blocked.pdf"),
            tab("ready_blocked.pdf"),
            tab("cv.pdf"),
          ]
        )
      ],
      highlightsIsFrontmost: frontmost
    )
  }

  /// Installs the fixture library, then the 9-tab snapshot, for a
  /// Tabs render.
  private func installTabs(
    model: RefsPanelModel,
    now: Date,
    state: RefsTabsState,
    frontmost: Bool,
    query: String = ""
  ) {
    let fixture = makeFixture(now: now)
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: query,
      scope: .all,
      selectedID: nil,
      banner: nil,
      refreshState: .idle
    )
    model.installTabsForPreviews(
      snapshot: makeTabsSnapshot(frontmost: frontmost),
      state: state,
      frontmost: frontmost
    )
  }

  /// The loaded 9-row list: the current pill on row 1 and, with
  /// Highlights frontmost, row 2 pre-selected.
  private func renderTabsLoaded(model: RefsPanelModel, now: Date) throws {
    installTabs(model: model, now: now, state: .loaded, frontmost: true)
    XCTAssertTrue(model.tabsFilter)
    XCTAssertEqual(model.tabsState, .loaded)
    XCTAssertEqual(model.listing.orderedIDs.count, 9)
    XCTAssertEqual(model.listing.totalCount, 9)
    XCTAssertEqual(
      model.selectedID,
      "ref/chat/morning_notes.md"
    )
    let current = try XCTUnwrap(
      model.rowContent(
        for: "ref/chat/today_report.md"
      ))
    XCTAssertEqual(current.openTab?.isCurrent, true)
    XCTAssertEqual(current.openTab?.pageCaption, "p. 5/25")
    let unmatched = try XCTUnwrap(
      model.rowContent(
        for: "highlights-tab:cv.pdf"
      ))
    XCTAssertEqual(unmatched.caption, "Not in your library")
    try write(model: model, name: "refs-tabs-loaded-880", width: 880)
  }

  /// A selected collision row with its minimal inspector card naming
  /// both candidate notes.
  private func renderTabsCollisionSelected(
    model: RefsPanelModel,
    now: Date
  ) throws {
    installTabs(model: model, now: now, state: .loaded, frontmost: true)
    let collisionID = "highlights-tab:harness_engineering.pdf"
    XCTAssertTrue(model.perform(.select(id: collisionID)))
    XCTAssertEqual(model.selectedID, collisionID)
    let content = try XCTUnwrap(model.rowContent(for: collisionID))
    XCTAssertEqual(content.openTab?.match, .collision)
    XCTAssertEqual(content.candidateItems.count, 2)
    try write(
      model: model,
      name: "refs-tabs-collision-880",
      width: 880
    )
  }

  /// A Tabs search naming two of nine tabs: the count reads
  /// "2 of 9 tabs".
  private func renderTabsSearch(model: RefsPanelModel, now: Date) throws {
    installTabs(model: model, now: now, state: .loaded, frontmost: false)
    model.setQuery("notes")
    guard case .search = model.listing.mode else {
      XCTFail("expected search mode")
      return
    }
    XCTAssertEqual(model.listing.orderedIDs.count, 2)
    XCTAssertEqual(model.listing.totalCount, 9)
    XCTAssertEqual(
      RefsTabsCount.text(shown: 2, total: 9, isSearch: true),
      "2 of 9 tabs"
    )
    try write(model: model, name: "refs-tabs-search-880", width: 880)
  }

  /// The permission card, signed and ad-hoc variants.
  private func renderTabsPermission(now: Date, adHoc: Bool) throws {
    let fixture = makeFixture(now: now)
    let model = RefsPanelModel(
      library: makeLibrary(now: now),
      opener: StubOpener(),
      highlights: StubLocator()
    )
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: nil,
      banner: nil,
      refreshState: .idle
    )
    model.installTabsForPreviews(
      snapshot: nil,
      state: .needsPermission(adHoc: adHoc),
      frontmost: false
    )
    XCTAssertEqual(
      model.tabsState,
      .needsPermission(adHoc: adHoc)
    )
    try write(
      model: model,
      name: adHoc
        ? "refs-tabs-permission-adhoc-880"
        : "refs-tabs-permission-880",
      width: 880
    )
  }

  /// The card when Highlights is not running.
  private func renderTabsNotRunning(now: Date) throws {
    let fixture = makeFixture(now: now)
    let model = RefsPanelModel(
      library: makeLibrary(now: now),
      opener: StubOpener(),
      highlights: StubLocator()
    )
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: nil,
      banner: nil,
      refreshState: .idle
    )
    model.installTabsForPreviews(
      snapshot: nil,
      state: .notRunning,
      frontmost: false
    )
    XCTAssertEqual(model.tabsState, .notRunning)
    try write(model: model, name: "refs-tabs-not-running-880", width: 880)
  }

  /// The card when Highlights runs with no open documents.
  private func renderTabsNoDocuments(now: Date) throws {
    let fixture = makeFixture(now: now)
    let model = RefsPanelModel(
      library: makeLibrary(now: now),
      opener: StubOpener(),
      highlights: StubLocator()
    )
    model.installForPreviews(
      items: fixture.items,
      signals: fixture.signals,
      query: "",
      scope: .all,
      selectedID: nil,
      banner: nil,
      refreshState: .idle
    )
    model.installTabsForPreviews(
      snapshot: nil,
      state: .noDocuments,
      frontmost: false
    )
    XCTAssertEqual(model.tabsState, .noDocuments)
    try write(model: model, name: "refs-tabs-no-documents-880", width: 880)
  }

  /// A failed re-read with stale rows: the rows stay listed under
  /// the retry notice.
  private func renderTabsFailedStale(
    model: RefsPanelModel,
    now: Date
  ) throws {
    installTabs(
      model: model,
      now: now,
      state: .failed(message: "timed out", hasStaleRows: true),
      frontmost: false
    )
    guard case .failed(_, let hasStaleRows) = model.tabsState else {
      XCTFail("expected failed state")
      return
    }
    XCTAssertTrue(hasStaleRows)
    XCTAssertEqual(model.listing.orderedIDs.count, 9)
    try write(model: model, name: "refs-tabs-failed-stale-880", width: 880)
  }

  /// The 9-row Tabs list with the selected row's close button in the
  /// reserved trailing column.
  private func renderTabsCloseSelected(model: RefsPanelModel, now: Date) throws {
    installTabs(model: model, now: now, state: .loaded, frontmost: true)
    let selected = try XCTUnwrap(model.selectedID)
    XCTAssertTrue(model.canCloseTab(id: selected))
    XCTAssertEqual(model.listing.orderedIDs.count, 9)
    try write(model: model, name: "refs-tabs-close-selected-880", width: 880)
  }

  /// An unselected Tabs row with the close button forced on, as if
  /// the pointer were over it. ImageRenderer never drives `onHover`.
  private func renderTabsCloseHoverRow(model: RefsPanelModel, now: Date) throws {
    installTabs(model: model, now: now, state: .loaded, frontmost: true)
    let id = "ref/chat/today_report.md"
    XCTAssertNotEqual(model.selectedID, id)
    XCTAssertTrue(model.canCloseTab(id: id))
    let content = try XCTUnwrap(model.rowContent(for: id))
    let width = RefsVisualTokens.listWidth(panelWidth: 880)
    let view = RefsRowView(
      content: content,
      isSelected: false,
      pomodoroName: model.pomodoroName(for: id),
      onSelect: {},
      onActivate: {},
      onClose: {},
      previewHovering: true
    )
    .frame(width: width, height: RefsVisualTokens.rowHeight)
    for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
      try RenderFixtureWriter.write(
        view,
        name: "refs-tabs-close-hover-row",
        width: width,
        appearance: appearance
      )
    }
  }

  /// The Tabs footer at panel width and at the inspector cutoff, so
  /// ViewThatFits can drop Reveal while keeping Close Tab.
  private func renderTabsFooter(model: RefsPanelModel, now: Date) throws {
    installTabs(model: model, now: now, state: .loaded, frontmost: true)
    XCTAssertTrue(model.tabsFilter)
    for width in [CGFloat(880), CGFloat(760)] {
      let view = RefsFooter(model: model)
        .frame(width: width, height: RefsVisualTokens.footerHeight)
      for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
        try RenderFixtureWriter.write(
          view,
          name: "refs-tabs-footer-\(Int(width))",
          width: width,
          appearance: appearance
        )
      }
    }
  }

  /// Closed-tab toasts with and without the reopen line, and last-tab
  /// toasts with and without the Highlights-quit line.
  private func renderClosedTabToasts() throws {
    let title = "Attention Is All You Need"
    let fixtures: [(String, RefsTabCloseToast)] = [
      (
        "refs-closed-tab-toast-reopen",
        RefsTabClosePresentation.toast(title: title, canReopen: true)
      ),
      (
        "refs-closed-tab-toast",
        RefsTabClosePresentation.toast(title: title, canReopen: false)
      ),
      (
        "refs-closed-last-tab-toast-quit",
        RefsTabClosePresentation.lastToast(title: title, highlightsQuit: true)
      ),
      (
        "refs-closed-last-tab-toast",
        RefsTabClosePresentation.lastToast(title: title, highlightsQuit: false)
      ),
    ]
    for (name, toast) in fixtures {
      XCTAssertEqual(toast.value, title)
      let view = RefsGlassToastView(
        title: toast.title,
        value: toast.value,
        detail: toast.detail,
        style: .closedTab,
        previewMode: true
      )
      .frame(width: 420)
      for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
        try RenderFixtureWriter.write(
          view,
          name: name,
          width: 420,
          appearance: appearance
        )
      }
    }
  }

  /// Tabs mode without a library snapshot yet: every tab reads
  /// unmatched instead of the library skeleton.
  private func renderTabsWithoutLibrarySnapshot(now: Date) throws {
    let model = RefsPanelModel(
      library: makeLibrary(now: now),
      opener: StubOpener(),
      highlights: StubLocator()
    )
    XCTAssertFalse(model.hasSnapshot)
    model.installTabsForPreviews(
      snapshot: makeTabsSnapshot(frontmost: false),
      state: .loaded,
      frontmost: false
    )
    XCTAssertTrue(model.tabsFilter)
    XCTAssertEqual(model.listing.orderedIDs.count, 9)
    XCTAssertEqual(
      model.rowContent(for: "highlights-tab:team_fit_review.pdf")?.caption,
      "Not in your library"
    )
    try write(
      model: model,
      name: "refs-tabs-no-library-880",
      width: 880
    )
  }

  private func write(
    model: RefsPanelModel,
    name: String,
    width: CGFloat,
    reduceTransparency: Bool = false,
    dynamicTypeSize: DynamicTypeSize? = nil
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
    .modifier(OptionalDynamicTypeModifier(size: dynamicTypeSize))
    for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
      try RenderFixtureWriter.write(
        view,
        name: name,
        width: width,
        appearance: appearance
      )
    }
  }

  private struct OptionalDynamicTypeModifier: ViewModifier {
    var size: DynamicTypeSize?

    func body(content: Content) -> some View {
      if let size {
        content.dynamicTypeSize(size)
      } else {
        content
      }
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
    return calendar.date(
      from: DateComponents(
        year: 2026, month: 10, day: 8, hour: 12
      )) ?? Date()
  }

  private func day(_ date: Date, offset: Int) -> RefDay {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    let shifted =
      calendar.date(
        byAdding: .day, value: offset, to: date
      ) ?? date
    let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
    return RefDay(year: parts.year ?? 2026, month: parts.month ?? 10, day: parts.day ?? 8)
  }

  private func time(_ date: Date, hour: Int, minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    var parts = calendar.dateComponents([.year, .month, .day], from: date)
    parts.hour = hour
    parts.minute = minute
    return calendar.date(from: parts) ?? date
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
      newMarkStore: RefsNewMarkStore(
        fileURL: root.appendingPathComponent("refs-new-marks.json")
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
        addedAt: time(now.addingTimeInterval(-86_400), hour: 16, minute: 15),
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
        addedAt: time(now, hour: 9, minute: 41),
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
        addedSource: "created",
        addedAt: time(now, hour: 8, minute: 2)
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
        addedAt: time(now.addingTimeInterval(-26 * 86_400), hour: 15, minute: 12),
        addedIsApproximate: true
      ),
      RefItem(
        id: "ref/docs/october_month.md",
        link: "[[ref/docs/october_month]]",
        rawTitle: "October Month Group Note",
        stem: "october_month",
        kind: .doc,
        state: .ready,
        isBlocked: false,
        pdfPath: "lib/docs/october_month.pdf",
        added: day(now, offset: -7),
        addedSource: "created"
      ),
      RefItem(
        id: "ref/docs/undated.md",
        link: "[[ref/docs/undated]]",
        rawTitle: "Undated Handbook Errata",
        stem: "undated",
        kind: .doc,
        state: .ready,
        isBlocked: false,
        pdfPath: "lib/docs/undated.pdf"
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
      "ref/chat/today_report.md": RefsTodayEntry(order: 0, pomodoroName: "BLOG")
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
