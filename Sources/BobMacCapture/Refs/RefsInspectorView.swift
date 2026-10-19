import AppKit
import RefsCore
import SwiftUI

/// Marker inside the live inspector's scroll content: its
/// `enclosingScrollView` is the inspector's native scroll view.
final class RefsInspectorScrollAnchorView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

struct RefsInspectorScrollAnchor: NSViewRepresentable {
  func makeNSView(context: Context) -> RefsInspectorScrollAnchorView {
    RefsInspectorScrollAnchorView()
  }

  func updateNSView(_ nsView: RefsInspectorScrollAnchorView, context: Context) {}
}

/// Layout marker for the first note of the latest revealed page: the
/// controller converts its frame into document coordinates to pin the
/// follow-tail scroll. Never hit-tests, so the search field keeps
/// focus.
final class RefsInspectorRevealAnchorView: NSView {
  var generation: Int = 0

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

struct RefsInspectorRevealAnchor: NSViewRepresentable {
  var generation: Int

  func makeNSView(context: Context) -> RefsInspectorRevealAnchorView {
    let view = RefsInspectorRevealAnchorView()
    view.generation = generation
    return view
  }

  func updateNSView(_ nsView: RefsInspectorRevealAnchorView, context: Context) {
    nsView.generation = generation
  }
}

/// Layout marker for the disclosure (`+N more`) row: the controller
/// converts its frame into document coordinates to reveal the next
/// notes page as soon as the row is fully visible, instead of
/// waiting for the very bottom. Never hit-tests, so the search
/// field keeps focus.
final class RefsInspectorDisclosureAnchorView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

struct RefsInspectorDisclosureAnchor: NSViewRepresentable {
  func makeNSView(context: Context) -> RefsInspectorDisclosureAnchorView {
    RefsInspectorDisclosureAnchorView()
  }

  func updateNSView(_ nsView: RefsInspectorDisclosureAnchorView, context: Context) {}
}

/// Fades revealed notes in once: opacity 0→1 plus a 6 pt rise,
/// `easeOut(0.22)`, staggered by batch position. Layout is never
/// animated, so the follow-scroll measures the final height at once.
/// First-page notes, Reduce Motion, and design-fixture previews render
/// fully visible at once.
private struct RefsInspectorNoteFade: ViewModifier {
  let isRevealed: Bool
  let delay: Double
  let previewMode: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared: Bool

  init(isRevealed: Bool, delay: Double, previewMode: Bool) {
    self.isRevealed = isRevealed
    self.delay = delay
    self.previewMode = previewMode
    _appeared = State(initialValue: !isRevealed || previewMode)
  }

  func body(content: Content) -> some View {
    if !isRevealed || reduceMotion || previewMode {
      content
    } else {
      content
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
          withAnimation(.easeOut(duration: 0.22).delay(delay)) {
            appeared = true
          }
        }
    }
  }
}

/// The full inspector column (§10): it fills instantly from the list
/// item and upgrades lazily as the loader hydrates summaries,
/// outlines, notes, and thumbnails. Papers, articles, and docs show a
/// thumbnail slot (112 x 145 pt compact, 150 x 194 pt wide; reserved
/// even while loading, so nothing jumps); chats keep the kind tile
/// and lead with the outline. Absence stays absence: missing facts
/// omit their row.
@available(macOS 26.0, *)
struct RefsInspectorView: View {
  let content: RefsRowContent
  let signals: RefsSignals
  var inspector: RefsInspectorContent? = nil
  var thumbnail: NSImage? = nil
  /// Decoded annotation images; design fixtures install them through
  /// `installForPreviews(..., images:)`.
  var imageStore: RefsInspectorImageStore? = nil
  /// The pure width mode, computed once per panel width by
  /// `RefsPanelView.columns(panelWidth:)`. Defaults to the compact
  /// layout, so existing call sites and fixtures keep today's look.
  var layout: RefsInspectorLayout = RefsPanelGeometry.inspectorLayout(
    panelWidth: RefsVisualTokens.panelWidth
  )
  /// Design fixtures lay the column out statically: `ImageRenderer`
  /// snapshots `ScrollView` content blank, so the live scroll view
  /// never appears in a fixture.
  var previewMode = false
  /// The revealed-notes page for the selected id, value-driven from
  /// the model. Defaults to the first page.
  var notesPage: RefsNotesPage = RefsNotesPage(size: RefsNotesPage.defaultSize)
  /// Runs the model's reveal; the controller follows the tail for
  /// keyboard and click reveals alike.
  var onRevealMoreNotes: () -> Void = {}
  /// Collision and unmatched inspector hint: switch and close.
  static let tabFallbackHint = "↵ switches to this tab · ⌃X closes it"
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var disclosureHover = false

  var body: some View {
    if previewMode {
      column
    } else {
      ScrollView(.vertical) {
        column.background(RefsInspectorScrollAnchor())
      }
    }
  }

  /// Whether the wide reading-room layout applies.
  private var isWide: Bool {
    layout.mode == .wide
  }

  /// Body copy in the wide layout, today's size in compact.
  private var bodyFont: Font {
    isWide ? .body : .callout
  }

  private var column: some View {
    VStack(
      alignment: .leading,
      spacing: isWide ? RefsVisualTokens.wideInspectorSpacing : RefsVisualTokens.inspectorSpacing
    ) {
      if let item = content.item {
        hero(for: item)
        if !isWide {
          byline(for: item)
          facts(for: item)
        }
        summarySection
        contentsSection
        highlightsSection
        if content.isMissingPDF {
          missingCallout(for: item)
        }
        footer(for: item)
      } else if let openTab = content.openTab {
        tabFallbackCard(for: openTab)
      } else if content.isUnavailable {
        VStack(alignment: .leading, spacing: 8) {
          Text(content.title)
            .font(.title3.weight(.semibold))
            .lineLimit(4)
          Text(content.caption)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.title), \(content.caption)")
      } else {
        Text(content.caption)
          .font(.callout)
          .foregroundStyle(.secondary)
          .accessibilityLabel(content.caption)
      }
    }
    .frame(
      width: isWide ? layout.contentWidth : nil,
      alignment: .leading
    )
    .padding(layout.padding)
    .frame(maxWidth: .infinity, alignment: isWide ? .center : .leading)
  }

  /// The minimal card for collision and unmatched Tabs rows: the
  /// file name with the neutral tile, the library verdict, the
  /// candidate notes with their note paths (plus the Highlights
  /// document path when known), and the switch-and-close hint.
  /// Matched rows keep the full inspector above.
  private func tabFallbackCard(for tab: RefsOpenTab) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        RefsTabDocTile(size: RefsVisualTokens.heroTileSize)
        VStack(alignment: .leading, spacing: 8) {
          Text(content.title)
            .font(.title3.weight(.semibold))
            .lineLimit(4)
          Text(content.caption)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        "\(content.title), \(content.caption), open in Highlights"
      )
      ForEach(content.candidateItems, id: \.id) { candidate in
        VStack(alignment: .leading, spacing: 1) {
          Text(candidate.title.text)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
          Text(candidate.id)
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      if let documentPath = tab.documentPath {
        Text(documentPath)
          .font(.caption.monospaced())
          .foregroundStyle(.tertiary)
          .lineLimit(2)
          .truncationMode(.middle)
      }
      Text(Self.tabFallbackHint)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private func hero(for item: RefItem) -> some View {
    HStack(alignment: .top, spacing: 12) {
      if showsThumbnailSlot(for: item) {
        thumbnailSlot
      } else {
        RefsKindTile(kind: item.kind, size: RefsVisualTokens.heroTileSize)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 8) {
        chips(for: item)
        titleView(for: item)
        // Wide pairs the taller thumbnail with content instead of
        // whitespace: the byline and facts sit beside it.
        if isWide {
          byline(for: item)
          facts(for: item)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(item.title.text), \(item.kind.label)")
  }

  private func titleView(for item: RefItem) -> some View {
    Text(
      CapturePickerRichText.displayText(
        item.title.text,
        segments: item.title.segments,
        matches: content.match?.titleRanges ?? []
      )
    )
    .font(
      isWide
        ? .title2.weight(.semibold) : .title3.weight(.semibold)
    )
    .lineLimit(
      isWide ? RefsVisualTokens.wideInspectorTitleLineLimit : 4
    )
  }

  /// The thumbnail point size for the layout: both draw from the
  /// loader's one 300 x 388 px image.
  private var thumbnailPointSize: CGSize {
    isWide
      ? CGSize(
        width: RefsVisualTokens.wideThumbnailWidth,
        height: RefsVisualTokens.wideThumbnailHeight
      )
      : CGSize(
        width: RefsVisualTokens.thumbnailWidth,
        height: RefsVisualTokens.thumbnailHeight
      )
  }

  /// Papers, articles, and docs show the page-1 thumbnail; every
  /// other kind keeps the tile.
  private func showsThumbnailSlot(for item: RefKind) -> Bool {
    item == .paper || item == .article || item == .doc
  }

  private func showsThumbnailSlot(for item: RefItem) -> Bool {
    showsThumbnailSlot(for: item.kind)
  }

  private var thumbnailSlot: some View {
    Group {
      if let thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(
            width: thumbnailPointSize.width,
            height: thumbnailPointSize.height
          )
          .clipShape(
            RoundedRectangle(
              cornerRadius: RefsVisualTokens.thumbnailRadius
            )
          )
          .overlay(
            RoundedRectangle(
              cornerRadius: RefsVisualTokens.thumbnailRadius
            )
            .stroke(.primary.opacity(0.08), lineWidth: 0.5)
          )
          .shadow(radius: 3)
          .accessibilityHidden(true)
      } else if let message = inspector?.previewMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .multilineTextAlignment(.center)
          .frame(
            width: thumbnailPointSize.width,
            height: thumbnailPointSize.height
          )
          .background(
            .secondary.opacity(0.08),
            in: RoundedRectangle(
              cornerRadius: RefsVisualTokens.thumbnailRadius
            )
          )
          .overlay(
            RoundedRectangle(
              cornerRadius: RefsVisualTokens.thumbnailRadius
            )
            .stroke(.primary.opacity(0.08), lineWidth: 0.5)
          )
      } else {
        RoundedRectangle(cornerRadius: RefsVisualTokens.thumbnailRadius)
          .fill(.secondary.opacity(0.08))
          .frame(
            width: thumbnailPointSize.width,
            height: thumbnailPointSize.height
          )
          .overlay(
            RoundedRectangle(
              cornerRadius: RefsVisualTokens.thumbnailRadius
            )
            .stroke(.primary.opacity(0.08), lineWidth: 0.5)
          )
          .accessibilityHidden(true)
      }
    }
  }

  private func chips(for item: RefItem) -> some View {
    HStack(spacing: 6) {
      kindChip(for: item)
      stateChip(for: item)
      if content.isNew {
        newChip
          .transition(.opacity)
      }
      if let name = todayName(for: item) {
        RefsTodayPill(pomodoroName: name)
      }
    }
    .animation(newChipAnimation, value: content.isNew)
  }

  private var newChipAnimation: Animation {
    if reduceMotion {
      return .easeOut(duration: RefsVisualTokens.newDotReduceMotionDuration)
    }
    return content.isNew
      ? .spring(
        response: RefsVisualTokens.newDotAppearResponse,
        dampingFraction: RefsVisualTokens.newDotAppearDamping
      )
      : .easeOut(duration: RefsVisualTokens.newDotDisappearDuration)
  }

  private var newChip: some View {
    HStack(spacing: 4) {
      Image(systemName: "circle.fill")
        .font(.system(size: 6))
      Text("New")
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(Color.accentColor)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.accentColor.opacity(0.16), in: Capsule())
    .accessibilityLabel("New")
  }

  private func kindChip(for item: RefItem) -> some View {
    let tint = RefsVisualTokens.tint(for: item.kind)
    return Label(item.kind.label, systemImage: item.kind.symbolName)
      .font(.caption.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(tint.opacity(0.16), in: Capsule())
  }

  private func stateChip(for item: RefItem) -> some View {
    let resolved = CaptureEditorPalette.taskStatus(
      RefsVisualTokens.paletteStatus(for: item)
    )
    return Label(RefsCaption.stateLabel(item), systemImage: resolved.symbol)
      .font(.caption.weight(.semibold))
      .foregroundStyle(resolved.color)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(resolved.color.opacity(0.12), in: Capsule())
  }

  private func todayName(for item: RefItem) -> String? {
    signals.today.entry(for: item)?.pomodoroName
  }

  private func byline(for item: RefItem) -> some View {
    Text(bylineText(for: item))
      .font(.callout)
      .foregroundStyle(.secondary)
      .accessibilityLabel(bylineText(for: item))
  }

  private func bylineText(for item: RefItem) -> String {
    if item.kind == .chat {
      var parts = ["Agent report"]
      if let parent = item.parentLabel, !parent.isEmpty {
        parts.append(parent)
      }
      parts.append(contentsOf: reportSuffix(for: item.stem))
      return parts.joined(separator: " · ")
    }
    var parts: [String] = []
    if let author = item.author, !author.isEmpty {
      parts.append(author)
    }
    if let published = item.published, !published.isEmpty {
      parts.append(published)
    }
    if let host = sourceHost(for: item) {
      parts.append(host)
    }
    if let arxiv = item.arxivID, !arxiv.isEmpty {
      parts.append("arXiv:\(arxiv)")
    } else if let doi = item.doi, !doi.isEmpty {
      parts.append(doi)
    }
    return parts.joined(separator: " · ")
  }

  /// Chats add "Consolidated report" for a stem ending in `__final`,
  /// or "Researcher draft (`x`)" for any other `__x` suffix.
  private func reportSuffix(for stem: String) -> [String] {
    let parts = stem.split(separator: "_", omittingEmptySubsequences: false)
    guard parts.count >= 2, parts[parts.count - 2].isEmpty else {
      return []
    }
    let suffix = String(parts.last ?? "")
    guard !suffix.isEmpty else {
      return []
    }
    if suffix == "final" {
      return ["Consolidated report"]
    }
    return ["Researcher draft (\(suffix))"]
  }

  private func sourceHost(for item: RefItem) -> String? {
    guard let first = item.urls.first,
      let host = URL(string: first)?.host,
      !host.isEmpty
    else {
      return nil
    }
    return host
  }

  private func facts(for item: RefItem) -> some View {
    Grid(alignment: .leading, verticalSpacing: 6) {
      // Absence stays absence: a fact row with no value is
      // omitted, never printed as "Unknown" or "0 open". The
      // Added value carries no label repeat: the row's label
      // already says Added.
      if item.added != nil {
        factRow(label: "Added", value: addedText(for: item))
      }
      if item.finished != nil {
        factRow(label: "Finished", value: finishedText(for: item))
      }
      if let pages = inspector?.pageCount ?? signals.pageCounts[item.id] {
        factRow(label: "Pages", value: pagesText(pages))
      }
      factRow(label: "Opened", value: openedText(for: item))
      factRow(label: "Notes", value: notesText(for: item))
      if item.task != nil {
        readingTaskRow(for: item)
      }
      if let inspector, !inspector.showFailed, inspector.openTaskCount > 0 {
        factRow(
          label: "Tasks",
          value: "\(inspector.openTaskCount) open"
        )
      }
      if item.audioPath != nil {
        factRow(label: "Narration", value: "Available")
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func pagesText(_ pages: Int) -> String {
    guard let readingTime = inspector?.readingTime else {
      return "\(pages)"
    }
    return "\(pages) · \(readingTime.formatted)"
  }

  private func factRow(label: String, value: String) -> some View {
    GridRow {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: RefsVisualTokens.factLabelWidth, alignment: .trailing)
        .gridColumnAlignment(.trailing)
      Text(value)
        .font(.callout)
        .gridColumnAlignment(.leading)
    }
  }

  /// The located reading task: the book symbol, the real parent
  /// route, and the lane label (`sase · Next`), or the archive file
  /// when the task already archived (`Archived · done/sase_done`).
  /// Rows from an older `bob` carry no task and omit the row.
  private func readingTaskRow(for item: RefItem) -> some View {
    GridRow {
      Text("Reading task")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: RefsVisualTokens.factLabelWidth, alignment: .trailing)
        .gridColumnAlignment(.trailing)
      HStack(spacing: 4) {
        Image(systemName: "book")
          .font(.callout)
          .foregroundStyle(.secondary)
        Text(readingTaskText(for: item))
          .font(.callout)
      }
      .gridColumnAlignment(.leading)
    }
    .accessibilityLabel("Reading task, \(readingTaskText(for: item))")
  }

  private func readingTaskText(for item: RefItem) -> String {
    guard let task = item.task else {
      return ""
    }
    if task.archived {
      return "Archived · \(task.path)"
    }
    let parent = item.parentLabel ?? task.path
    return "\(parent) · \(RefsCaption.stateLabel(item))"
  }

  private func addedText(for item: RefItem) -> String {
    guard let added = item.added else {
      return ""
    }
    let day = RefsCaption.absoluteMonthDay(
      added, now: signals.now, calendar: signals.calendar
    )
    var text = item.addedIsApproximate ? "≈ \(day)" : day
    if let at = item.addedAt {
      text += " at \(RefsCaption.shortTime(at, calendar: signals.calendar))"
    }
    if let source = item.addedSource, !source.isEmpty, source != "git" {
      text += " (\(source))"
    }
    return text
  }

  private func finishedText(for item: RefItem) -> String {
    guard let finished = item.finished else {
      return ""
    }
    return RefsCaption.absoluteMonthDay(
      finished, now: signals.now, calendar: signals.calendar
    )
  }

  private func openedText(for item: RefItem) -> String {
    let count = signals.opens.count(item.id)
    if let opened = RefsRanker.lastOpened(item, signals: signals) {
      let when = RefsCaption.relativeLong(opened, now: signals.now)
      if count > 1 {
        return "\(when) · \(count) times"
      }
      return when
    }
    return "Never opened"
  }

  private func notesText(for item: RefItem) -> String {
    var parts: [String] = []
    if item.annotationCount > 0 {
      let word = item.annotationCount == 1 ? "highlight" : "highlights"
      parts.append("\(item.annotationCount) \(word)")
    }
    if item.commentCount > 0 {
      let word = item.commentCount == 1 ? "comment" : "comments"
      parts.append("\(item.commentCount) \(word)")
    }
    if parts.isEmpty {
      return "None"
    }
    return parts.joined(separator: " · ")
  }

  @ViewBuilder
  private var summarySection: some View {
    if let summary = inspector?.summary {
      VStack(alignment: .leading, spacing: 6) {
        sectionLabel(summary.label)
        if let paragraph = summary.paragraph {
          Text(paragraph)
            .font(bodyFont)
        }
        ForEach(summary.bullets.indices, id: \.self) { index in
          Text("•  \(summary.bullets[index])")
            .font(bodyFont)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  @ViewBuilder
  private var contentsSection: some View {
    if let outline = inspector?.outline, !outline.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        sectionLabel("CONTENTS")
        ForEach(outline, id: \.self) { heading in
          Label {
            Text(heading)
              .font(.callout)
              .lineLimit(1)
              .truncationMode(.tail)
          } icon: {
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  @ViewBuilder
  private var highlightsSection: some View {
    if let inspector {
      let feed = inspector.feed
      let visible = notesPage.visibleCount(total: feed.total)
      let entries = feed.entries(visible: visible)
      let nextBatch = notesPage.nextBatchCount(total: feed.total)
      let more = feed.moreText(visible: visible, nextBatch: nextBatch)
      let hiddenLabel = feed.hiddenAccessibilityLabel(visible: visible)
      if !entries.isEmpty {
        VStack(
          alignment: .leading,
          spacing: isWide
            ? RefsVisualTokens.wideInspectorEntrySpacing
            : RefsVisualTokens.inspectorEntrySpacing
        ) {
          HStack(spacing: 6) {
            Text("HIGHLIGHTS")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text("\(feed.total)")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.tertiary)
            if feed.notedCount > 0 {
              noteChip(count: feed.notedCount)
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(feed.headerAccessibilityLabel)
          .accessibilityAddTraits(.isHeader)
          ForEach(entries, id: \.index) { entry in
            highlightEntryView(entry)
              .padding(.top, pageRunTopPadding(entry, in: entries))
              .modifier(
                RefsInspectorNoteFade(
                  isRevealed: entry.index >= notesPage.size,
                  delay: revealDelay(for: entry.index),
                  previewMode: previewMode
                )
              )
              .background {
                if !previewMode, notesPage.batchStart == entry.index {
                  RefsInspectorRevealAnchor(
                    generation: notesPage.generation
                  )
                }
              }
          }
          if let more {
            disclosureRow(text: more, hiddenLabel: hiddenLabel)
          }
        }
      } else if inspector.showFailed {
        Text("Notes unavailable")
          .font(.callout)
          .foregroundStyle(.tertiary)
          .accessibilityLabel("Notes unavailable")
      }
    }
  }

  private func revealDelay(for index: Int) -> Double {
    let batchStart = notesPage.batchStart ?? notesPage.size
    return index >= batchStart ? Double(index - batchStart) * 0.04 : 0
  }

  private func pageRunTopPadding(
    _ entry: RefsInspectorFeed.Entry,
    in entries: [RefsInspectorFeed.Entry]
  ) -> CGFloat {
    guard entry.showsPageLabel, entry.index != entries.first?.index else {
      return 0
    }
    return RefsVisualTokens.inspectorPageRunGap
  }

  private func disclosureRow(text: String, hiddenLabel: String?) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "chevron.down")
        .font(.caption2.weight(.semibold))
      Text(text)
        .font(.caption.monospacedDigit())
    }
    .background {
      if !previewMode {
        RefsInspectorDisclosureAnchor()
      }
    }
    .foregroundStyle(disclosureHover ? .secondary : .tertiary)
    .pointerStyle(.link)
    .onHover { disclosureHover = $0 }
    .onTapGesture {
      onRevealMoreNotes()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(hiddenLabel ?? text)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(named: "Show more") {
      onRevealMoreNotes()
    }
  }

  private func highlightEntryView(_ entry: RefsInspectorFeed.Entry) -> some View {
    let annotation = entry.annotation
    let quote = visibleQuote(annotation)
    return VStack(alignment: .leading, spacing: 4) {
      if entry.showsPageLabel, let pageLabel = annotation.displayPageLabel {
        Text(pageLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      switch entry.kind {
      case .highlight:
        if let quote {
          quoteView(quote)
        }
      case .image:
        imageHighlightBody(entry)
      case .note:
        EmptyView()
      }
      if entry.hasNoteCard {
        noteCard(entry)
          .padding(
            .top,
            needsNoteGap(entry) ? RefsVisualTokens.inspectorNoteGap - 4 : 0
          )
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(entry.accessibilityLabel)
  }

  private func needsNoteGap(_ entry: RefsInspectorFeed.Entry) -> Bool {
    switch entry.kind {
    case .highlight:
      return visibleQuote(entry.annotation) != nil
    case .image:
      return true
    case .note:
      return false
    }
  }

  /// The image takes the quote's slot, with the same 2 pt yellow
  /// rule on its left. A missing file is a one-line unavailable row,
  /// never a reserved box.
  @ViewBuilder
  private func imageHighlightBody(_ entry: RefsInspectorFeed.Entry) -> some View {
    if let path = entry.imagePath, let metrics = imageMetrics(for: path) {
      fittedImage(path: path, metrics: metrics, maxWidth: quoteSlotWidth)
        .padding(.leading, RefsVisualTokens.inspectorQuoteInset)
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(.yellow)
            .frame(width: RefsVisualTokens.inspectorQuoteRuleWidth)
        }
    } else if let path = entry.imagePath {
      RefsInspectorImageUnavailableRow(fileName: imageFileName(path))
        .padding(.leading, RefsVisualTokens.inspectorQuoteInset)
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(.yellow)
            .frame(width: RefsVisualTokens.inspectorQuoteRuleWidth)
        }
    }
  }

  private var quoteSlotWidth: CGFloat {
    max(1, layout.contentWidth - RefsVisualTokens.inspectorQuoteInset)
  }

  private var noteCardInnerWidth: CGFloat {
    max(1, layout.contentWidth - 2 * RefsVisualTokens.inspectorQuoteInset)
  }

  private func visibleQuote(_ annotation: RefsShowAnnotation) -> String? {
    guard let quote = annotation.quote,
      !quote.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
    else {
      return nil
    }
    return quote
  }

  private func quoteView(_ quote: String) -> some View {
    Text(RefsQuoteText.attributed(RefsQuoteExcerpt.preview(quote)))
      .font(bodyFont)
      .foregroundStyle(.primary)
      .lineSpacing(
        isWide ? RefsVisualTokens.wideInspectorQuoteLineSpacing : 2
      )
      .lineLimit(
        isWide
          ? RefsVisualTokens.wideInspectorQuoteLineLimit
          : RefsVisualTokens.inspectorHighlightLineLimit
      )
      .truncationMode(.tail)
      .padding(.leading, RefsVisualTokens.inspectorQuoteInset)
      .overlay(alignment: .leading) {
        Rectangle()
          .fill(.yellow)
          .frame(width: RefsVisualTokens.inspectorQuoteRuleWidth)
      }
      .help(RefsQuoteEmphasis.plainText(quote))
  }

  private func noteCard(_ entry: RefsInspectorFeed.Entry) -> some View {
    let stroke =
      colorSchemeContrast == .increased
      ? RefsVisualTokens.inspectorNoteStrokeOpacityIncreased
      : RefsVisualTokens.inspectorNoteStrokeOpacity
    let shape = RoundedRectangle(
      cornerRadius: RefsVisualTokens.inspectorNoteRadius,
      style: .continuous
    )
    let comment =
      entry.annotation.comment?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ) ?? ""
    return VStack(alignment: .leading, spacing: RefsVisualTokens.inspectorImageStackSpacing) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: RefsVisualTokens.inspectorNoteSymbol)
          .font(.callout.weight(.medium))
          .imageScale(.small)
          .foregroundStyle(RefsVisualTokens.inspectorNoteTint)
        if !comment.isEmpty {
          Text(comment)
            .font(bodyFont)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      ForEach(entry.attachedImages, id: \.self) { path in
        if let metrics = imageMetrics(for: path) {
          fittedImage(path: path, metrics: metrics, maxWidth: noteCardInnerWidth)
        } else {
          RefsInspectorImageUnavailableRow(fileName: imageFileName(path))
        }
      }
      ForEach(entry.unresolvedImages, id: \.self) { path in
        RefsInspectorImageUnavailableRow(fileName: imageFileName(path))
      }
    }
    .padding(.horizontal, RefsVisualTokens.inspectorQuoteInset)
    .padding(.vertical, RefsVisualTokens.inspectorNoteVerticalPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      shape.fill(
        Color.yellow.opacity(RefsVisualTokens.inspectorNoteFillOpacity)
      )
    )
    .overlay(
      shape.strokeBorder(Color.yellow.opacity(stroke), lineWidth: 0.5)
    )
  }

  private func fittedImage(
    path: String,
    metrics: RefsImageMetrics,
    maxWidth: CGFloat
  ) -> some View {
    let size = RefsImageFit.displaySize(
      pointSize: metrics.pointSize,
      maxWidth: maxWidth,
      maxHeight: layout.imageMaxHeight
    )
    return RefsInspectorImageView(
      path: path,
      metrics: metrics,
      displaySize: size,
      store: imageStore,
      previewMode: previewMode
    )
  }

  private func imageMetrics(for path: String) -> RefsImageMetrics? {
    inspector?.images[path]
  }

  private func imageFileName(_ path: String) -> String {
    URL(fileURLWithPath: path).lastPathComponent
  }

  private func noteChip(count: Int) -> some View {
    HStack(spacing: 3) {
      Image(systemName: RefsVisualTokens.inspectorNoteSymbol)
      Text("\(count)")
    }
    .font(.caption2.weight(.semibold).monospacedDigit())
    .foregroundStyle(RefsVisualTokens.inspectorNoteTint)
    .padding(.horizontal, 6)
    .padding(.vertical, 1.5)
    .background(
      Capsule().fill(
        Color.yellow.opacity(RefsVisualTokens.inspectorNoteFillOpacity)
      )
    )
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .accessibilityAddTraits(.isHeader)
  }

  private func missingCallout(for item: RefItem) -> some View {
    Label(
      "The PDF this note points to is missing: \(item.pdfPath). "
        + "↵ opens the note instead.",
      systemImage: "exclamationmark.triangle.fill"
    )
    .font(.callout)
    .foregroundStyle(.orange)
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityLabel("The PDF this note points to is missing.")
  }

  private func footer(for item: RefItem) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(content.whyHere)
        .font(.caption)
        .foregroundStyle(.tertiary)
      Text(item.pdfPath)
        .font(.caption.monospaced())
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
        .accessibilityLabel("PDF path \(item.pdfPath)")
    }
  }
}
