import RefsCore
import SwiftUI

/// A 26 pt pinned section header: the uppercase title plus the count.
/// A Just scanned header adds a trailing relative time ("just now",
/// "4m ago"), refreshed each minute.
@available(macOS 26.0, *)
struct RefsSectionHeader: View {
    let kind: RefsSectionKind
    let count: Int
    /// When the scan finished, for the `.justScanned` trailing time.
    /// Nil for every other section.
    let at: Date?
    /// Trailing ⌥N hint on the NEW header while its row is selected.
    let newHint: String?

    init(
        kind: RefsSectionKind,
        count: Int,
        at: Date? = nil,
        newHint: String? = nil
    ) {
        self.kind = kind
        self.count = count
        self.at = at
        self.newHint = newHint
    }

    var body: some View {
        HStack(spacing: 6) {
            if kind == .new {
                Circle()
                    .fill(Color.accentColor)
                    .frame(
                        width: RefsVisualTokens.newDotSize,
                        height: RefsVisualTokens.newDotSize
                    )
            }
            Text(kind.title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if kind == .new, let newHint {
                Text(newHint)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            } else if case .added(let group) = kind, let detail = group.detail {
                Text(detail)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            } else if kind == .justScanned, let at {
                TimelineView(.everyMinute) { context in
                    Text(RefsCaption.relativeCompact(at, now: context.date))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: RefsVisualTokens.sectionHeaderHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    private var accessibilityLabel: String {
        if case .added(let group) = kind {
            return "\(group.accessibilityLabel), \(count) references"
        }
        if kind == .justScanned, let at {
            let when = RefsCaption.relativeCompact(at, now: Date())
            return "Just scanned, \(count) references, \(when)"
        }
        return "\(kind.title), \(count) references"
    }
}

/// The list column: a scroll view of pinned sections whose selection
/// stays fully visible below the pinned header without animation.
/// A show keeps the selected row when it remains listed, unless a newly
/// added reference resets the view; a re-rank that selects the first row
/// returns the list to its top. Moving up lands
/// the selected row just under its section header. Reports its visible row budget to
/// the model so paging moves by one less than fits. Tab-close
/// removals fold out through a short transition; query re-ranks stay
/// unanimated because only the model's close path wraps in
/// `withAnimation`. A re-rank that moves a row to another section
/// rebuilds it, so its highlight and caption always match the new
/// listing.
@available(macOS 26.0, *)
struct RefsListView: View {
    @ObservedObject var model: RefsPanelModel
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// Reference box for the viewport measurement. A class held in
    /// `@State` so per-frame scroll updates never re-evaluate the list
    /// body.
    @State private var viewportBox = ViewportBox()
    @State private var pendingListRestore: (generation: Int, offset: CGFloat)?
    /// Design fixtures lay the same rows out in a static stack:
    /// `ImageRenderer` snapshots `ScrollView` content blank, so the
    /// live scroll view never appears in a fixture.
    var previewMode = false
    /// Dims every row for stale Tabs rows after a failed re-read, on
    /// top of each row's own treatment.
    var dimRows = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if previewMode {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.listing.sections, id: \.sectionID) { section in
                    Section {
                        ForEach(section.ids, id: \.self) { id in
                            previewRow(for: id)
                        }
                    } header: {
                        if let kind = section.kind {
                            RefsSectionHeader(
                                kind: kind,
                                count: section.ids.count,
                                at: headerScanDate(for: kind),
                                newHint: kind == .new ? model.newSectionHint : nil
                            )
                        }
                    }
                }
            }
            .padding(.vertical, RefsVisualTokens.listVerticalPadding)
            .accessibilityLabel("References")
        } else {
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 0,
                        pinnedViews: [.sectionHeaders]
                    ) {
                        ForEach(model.listing.sections, id: \.sectionID) { section in
                            Section {
                                ForEach(section.rowKeys, id: \.self) { key in
                                    row(for: key.id)
                                }
                            } header: {
                                if let kind = section.kind {
                                    RefsSectionHeader(
                                        kind: kind,
                                        count: section.ids.count,
                                        at: headerScanDate(for: kind),
                                        newHint: kind == .new
                                            ? model.newSectionHint : nil
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, RefsVisualTokens.listVerticalPadding)
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: Viewport.self) { scrollGeometry in
                    Viewport(
                        offset: scrollGeometry.contentOffset.y + scrollGeometry.contentInsets.top,
                        height: scrollGeometry.containerSize.height,
                        topInset: scrollGeometry.contentInsets.top
                    )
                } action: { old, new in
                    viewportBox.offset = new.offset
                    viewportBox.height = new.height
                    viewportBox.topInset = new.topInset
                    model.noteListOffset(new.offset)
                    if old.height <= 0, new.height > 0 {
                        applyPendingListRestore()
                        revealSelection()
                    }
                }
                .onChange(of: model.selectedID) { _, _ in
                    revealSelection()
                }
                .onChange(of: model.listing.orderedIDs) { _, _ in
                    applyPendingListRestore()
                    revealSelection()
                }
                .onChange(of: model.presentationCount) { _, _ in
                    revealSelection()
                }
                .onChange(of: model.listRestoreGeneration) { _, _ in
                    applyPendingListRestore()
                    revealSelection()
                }
                .onChange(of: model.listResetGeneration) { _, _ in
                    pendingListRestore = nil
                    scrollPosition.scrollTo(edge: .top)
                    revealSelection()
                }
                .onAppear {
                    reportBudget(height: geometry.size.height)
                }
                .onChange(of: geometry.size.height) { _, height in
                    reportBudget(height: height)
                }
                .accessibilityLabel("References")
            }
        }
    }

    /// Applies a pending Highlights-key list restore once the content can
    /// reach the offset, or clamps it when the content is final, mirroring
    /// the inspector anchor. Updates the viewport box so the restored
    /// selection stays visible whatever order the change handlers fire in.
    private func applyPendingListRestore() {
        let generation = model.listRestoreGeneration
        if pendingListRestore?.generation != generation, generation > 0 {
            pendingListRestore = (generation, model.listRestoreOffset)
        }
        guard let pending = pendingListRestore else { return }
        guard viewportBox.height > 0 else { return }
        let contentHeight = RefsListScrollPolicy.contentHeight(of: model.listing)
        let maxOffset = max(0, contentHeight - viewportBox.height)
        let clamped = min(max(pending.offset, 0), maxOffset)
        if contentHeight <= viewportBox.height + 1 {
            viewportBox.offset = clamped
            scrollPosition.scrollTo(y: clamped - viewportBox.topInset)
            pendingListRestore = nil
            return
        }
        if pending.offset <= maxOffset + 0.5 {
            viewportBox.offset = clamped
            scrollPosition.scrollTo(y: clamped - viewportBox.topInset)
            pendingListRestore = nil
        } else if maxOffset.isFinite {
            viewportBox.offset = maxOffset
            scrollPosition.scrollTo(y: maxOffset - viewportBox.topInset)
        }
    }

    /// Scrolls the selected row fully below the pinned section header.
    /// A first-row selection always returns the list to its top; any
    /// other row scrolls the minimum distance that clears the header
    /// band above and the viewport bottom below. It inherits the
    /// caller's transaction exactly as `scrollTo` did, so the tab-close
    /// path stays animated and everything else stays instant.
    private func revealSelection() {
        guard let selected = model.selectedID else {
            return
        }
        guard
            let target = RefsListScrollPolicy.reveal(
                selected,
                in: model.listing,
                offset: viewportBox.offset,
                viewportHeight: viewportBox.height
            )
        else {
            return
        }
        switch target {
        case .top:
            if scrollPosition == ScrollPosition(edge: .top) {
                scrollPosition.scrollTo(y: -viewportBox.topInset)
            } else {
                scrollPosition.scrollTo(edge: .top)
            }
        case .offset(let y):
            scrollPosition.scrollTo(y: y - viewportBox.topInset)
        }
    }

    private func headerScanDate(for kind: RefsSectionKind) -> Date? {
        guard kind == .justScanned else {
            return nil
        }
        return model.signals.scan?.at
    }

    private func row(for id: String) -> some View {
        let content = model.rowContent(for: id)
        let isSelected = model.selectedID == id
        let pomodoroName = model.pomodoroName(for: id)
        let onSelect: () -> Void = {
            model.perform(.select(id: id))
        }
        let onActivate: () -> Void = {
            model.perform(.activate(id: id))
        }
        let onClose = closeHandler(for: id)

        return ZStack(alignment: .topLeading) {
            if let content {
                RefsRowView(
                    content: content,
                    isSelected: isSelected,
                    pomodoroName: pomodoroName,
                    onSelect: onSelect,
                    onActivate: onActivate,
                    onClose: onClose
                )
                .opacity(dimRows ? 0.6 : 1)
                // The selected row keeps its frame live in the panel-root
                // coordinate space, so the ⌘K menu pops below it. Deselected
                // rows report nil, which never clears the current rect.
                .onGeometryChange(for: CGRect?.self) { proxy in
                    model.selectedID == id
                        ? proxy.frame(in: .named("refsPanel")) : nil
                } action: { rect in
                    if let rect {
                        model.selectedRowRect = rect
                    }
                }
                .onChange(
                    of: RefsRowRenderState(
                        isSelected: isSelected,
                        section: content.section,
                        caption: content.caption
                    ),
                    initial: true
                ) { _, state in
                    model.rowRenderProbeForTests?.record(id, state)
                }
            }
        }
        .transition(removalTransition)
    }

    /// Preview fixtures keep their previous static-stack rendering path.
    private func previewRow(for id: String) -> some View {
        guard let content = model.rowContent(for: id) else {
            return AnyView(EmptyView())
        }
        // The selected row keeps its frame live in the panel-root
        // coordinate space, so the ⌘K menu pops below it. Deselected
        // rows report nil, which never clears the current rect: the
        // next selection overwrites it, and a fresh presentation
        // clears it.
        return AnyView(
            RefsRowView(
                content: content,
                isSelected: model.selectedID == id,
                pomodoroName: model.pomodoroName(for: id),
                onSelect: {
                    model.perform(.select(id: id))
                },
                onActivate: {
                    model.perform(.activate(id: id))
                },
                onClose: closeHandler(for: id)
            )
            .opacity(dimRows ? 0.6 : 1)
            .transition(removalTransition)
            .onGeometryChange(for: CGRect?.self) { proxy in
                model.selectedID == id
                    ? proxy.frame(in: .named("refsPanel")) : nil
            } action: { rect in
                if let rect {
                    model.selectedRowRect = rect
                }
            }
        )
    }

    /// The row close button, or nil when this id is not a closable tab.
    private func closeHandler(for id: String) -> (() -> Void)? {
        guard model.canCloseTab(id: id) else {
            return nil
        }
        return { _ = model.perform(.closeTab(id: id)) }
    }

    /// Close removals fade and collapse so the rows below glide up.
    /// Reduce Motion keeps the fade and drops the collapse. Insertions
    /// are identity so a query re-rank never animates in.
    private var removalTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .identity,
            removal: .opacity.combined(with: .scale(scale: 0.35, anchor: .top))
        )
    }

    private func reportBudget(height: CGFloat) {
        let budget = max(1, Int(height / RefsVisualTokens.rowHeight))
        if model.visibleRowBudget != budget {
            model.visibleRowBudget = budget
        }
    }
}

/// The list viewport tracked by `onScrollGeometryChange`: the offset
/// measured from the content top, the viewport height, and the top
/// content inset for the `contentOffset` conversion.
private struct Viewport: Equatable {
    var offset: CGFloat
    var height: CGFloat
    var topInset: CGFloat
}

/// Reference box for the viewport measurement. A class so per-frame
/// scroll updates never re-evaluate the list body.
private final class ViewportBox {
    var offset: CGFloat = 0
    var height: CGFloat = 0
    var topInset: CGFloat = 0
}

extension RefsSection {
    /// A stable identity for `ForEach`: the kind, or "search" for the
    /// single ranked section. Newest groups use their stable group id.
    fileprivate var sectionID: String {
        switch kind {
        case .some(.added(let group)):
            return "section-\(group.id)"
        case .some(let kind):
            return "section-\(kind)"
        case .none:
            return "search"
        }
    }

    fileprivate var rowKeys: [RefsListRowKey] {
        ids.map { RefsListRowKey(section: sectionID, id: $0) }
    }
}

/// Live-list row identity: the same ref in a new section is a new
/// subview, so a cross-section re-rank cannot keep a stale highlight
/// or caption.
private struct RefsListRowKey: Hashable {
    let section: String
    let id: String
}
