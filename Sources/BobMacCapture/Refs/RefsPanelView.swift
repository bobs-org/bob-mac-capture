import RefsCore
import SwiftUI

/// The panel shell: the glass slab, the 8 pt outer padding, the
/// concentric content well, the search bar, the list/inspector column
/// split, and the footer. The height is fixed when the panel opens:
/// filtering never resizes it.
@available(macOS 26.0, *)
public struct RefsPanelView: View {
    @ObservedObject var model: RefsPanelModel
    /// Design tests disable the presentation animation so renders are
    /// deterministic.
    var animatePresentation = true
    /// Design tests draw the query as text so `ImageRenderer` never
    /// hosts an `NSViewRepresentable`.
    var previewMode = false
    /// Design tests fix the layout width explicitly: a `GeometryReader`
    /// cannot negotiate a height while the snapshot sizes to content,
    /// which overlaps the footer.
    var previewWidth: CGFloat?
    /// Design tests force the Reduce Transparency base, whose
    /// environment key is read-only and cannot be injected.
    var reduceTransparencyOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var appeared = false

    public init(
        model: RefsPanelModel,
        animatePresentation: Bool = true,
        previewMode: Bool = false,
        previewWidth: CGFloat? = nil,
        reduceTransparencyOverride: Bool? = nil
    ) {
        self.model = model
        self.animatePresentation = animatePresentation
        self.previewMode = previewMode
        self.previewWidth = previewWidth
        self.reduceTransparencyOverride = reduceTransparencyOverride
    }

    public var body: some View {
        // No glass modifier here: the live panel's glass comes from the
        // hosting `NSGlassEffectView`, because `.glassEffect` blanks
        // `ImageRenderer` snapshots and the design tests must stay
        // reviewable. The render fixtures show this content on an
        // opaque base instead.
        VStack(spacing: 0) {
            RefsSearchBar(model: model, previewMode: previewMode)
            if let banner = model.banner {
                RefsBannerView(model: model, banner: banner)
            }
            well
            RefsFooter(model: model)
        }
        .padding(RefsVisualTokens.outerPadding)
        .background {
            // Under Reduce Transparency the glass goes opaque: paint the
            // window background beneath the content (§6).
            if reduceTransparencyOverride ?? reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
                    .clipShape(RoundedRectangle(
                        cornerRadius: RefsVisualTokens.glassRadius
                    ))
            }
        }
        .scaleEffect(appeared ? 1 : 0.98)
        .onAppear {
            animateIn()
        }
        .onChange(of: model.presentationCount) { _, _ in
            animateIn()
        }
        .coordinateSpace(name: "refsPanel")
    }

    /// Replays the show scale-in. It runs on appear and on every
    /// presentation the model counts — not once per process — and
    /// degrades to an instant paint under Reduce Motion (the AppKit
    /// fade still runs).
    private func animateIn() {
        guard animatePresentation, !reduceMotion else {
            appeared = true
            return
        }
        appeared = false
        withAnimation(.easeOut(duration: 0.12)) {
            appeared = true
        }
    }

    /// The content well (§7): the list and inspector on
    /// `.regularMaterial` at r=12, concentric with the glass, with a
    /// 0.5 pt stroke.
    private var well: some View {
        content
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: RefsVisualTokens.wellRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RefsVisualTokens.wellRadius)
                    .stroke(.primary.opacity(0.08), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var content: some View {
        if model.tabsFilter {
            // Tabs mode never waits for the library snapshot: every
            // tab simply reads unmatched until library data exists.
            tabsContent
        } else if !model.hasSnapshot {
            switch model.refreshState {
            case .refreshing:
                RefsSkeletonList()
            case .failed(let message, _):
                RefsLoadFailedView(model: model, message: message)
            case .idle:
                RefsSkeletonList()
            }
        } else if model.listing.orderedIDs.isEmpty {
            RefsEmptyStateView(model: model)
        } else {
            listContent()
        }
    }

    /// The Tabs-mode well, driven by the published tab read state.
    @ViewBuilder
    private var tabsContent: some View {
        switch model.tabsState {
        case .off, .loaded:
            if model.listing.orderedIDs.isEmpty {
                RefsTabsEmptyView(query: model.query, scope: model.scope)
            } else {
                listContent()
            }
        case .loading:
            if model.listing.orderedIDs.isEmpty {
                RefsTabsDelayedSkeleton(previewMode: previewMode)
            } else {
                listContent()
            }
        case .needsPermission(let adHoc):
            RefsTabsPermissionCard(model: model, adHoc: adHoc)
        case .notRunning:
            RefsTabsNotRunningCard()
        case .noDocuments:
            RefsTabsNoDocumentsCard()
        case .failed(_, let hasStaleRows):
            if hasStaleRows, !model.listing.orderedIDs.isEmpty {
                VStack(spacing: 0) {
                    RefsTabsFailedNotice()
                    listContent(dimRows: true)
                }
            } else {
                RefsTabsFailedCard()
            }
        }
    }

    @ViewBuilder
    private func listContent(dimRows: Bool = false) -> some View {
        if let previewWidth {
            columns(panelWidth: previewWidth, dimRows: dimRows)
        } else {
            GeometryReader { geometry in
                // The geometry width is post-padding: add the outer
                // padding back so the inspector cutoff and the list
                // width measure the panel width (§6).
                columns(
                    panelWidth: geometry.size.width
                        + RefsVisualTokens.outerPadding * 2,
                    dimRows: dimRows
                )
            }
        }
    }

    @ViewBuilder
    private func columns(panelWidth: CGFloat, dimRows: Bool = false) -> some View {
        if RefsVisualTokens.showsInspector(width: panelWidth) {
            let layout = RefsPanelGeometry.inspectorLayout(panelWidth: panelWidth)
            HStack(spacing: 0) {
                RefsListView(model: model, previewMode: previewMode, dimRows: dimRows)
                    .frame(width: RefsVisualTokens.listWidth(panelWidth: panelWidth))
                inspectorDivider
                inspector(layout: layout)
            }
        } else {
            Group {
                if model.todayLinkCard != nil {
                    todayLinkCard
                } else if model.renameCard != nil {
                    renameCard
                } else if model.copyCard != nil {
                    copyCard
                } else {
                    RefsListView(model: model, previewMode: previewMode, dimRows: dimRows)
                        .transition(.opacity)
                }
            }
            .animation(
                copyCardAnimation,
                value: model.copyCard != nil || model.renameCard != nil || model.todayLinkCard != nil
            )
        }
    }

    private var inspectorDivider: some View {
        Rectangle()
            .fill(.primary.opacity(contrast == .increased ? 0.25 : 0.10))
            .frame(width: 0.5)
    }

    @ViewBuilder
    private func inspector(layout: RefsInspectorLayout) -> some View {
        Group {
            if model.todayLinkCard != nil {
                readableCard(todayLinkCard, layout: layout)
            } else if model.renameCard != nil {
                readableCard(renameCard, layout: layout)
            } else if model.copyCard != nil {
                readableCard(copyCard, layout: layout)
            } else if let selected = model.selectedID,
               let content = model.rowContent(for: selected)
            {
                RefsInspectorView(
                    content: content,
                    signals: model.signals,
                    inspector: model.inspectorContent(for: selected),
                    thumbnail: model.inspectorThumbnail(for: selected),
                    imageStore: model.inspectorLoader.imageStore,
                    layout: layout,
                    previewMode: previewMode,
                    notesPage: model.inspectorNotesPage(for: selected),
                    onRevealMoreNotes: { model.revealMoreInspectorNotes() }
                )
                .id("\(selected)#\(model.presentationCount)")
                .onAppear { model.inspectorRequested() }
                .onChange(of: selected) { _, _ in model.inspectorRequested() }
                .transition(.opacity)
            } else {
                Text("Select a reference")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(
            copyCardAnimation,
            value: model.copyCard != nil || model.renameCard != nil || model.todayLinkCard != nil
        )
    }

    /// Constrains the Copy, Rename, and Today Link cards to the same
    /// readable content column as the wide inspector (max 720,
    /// centered), so nothing stretches edge to edge on large
    /// displays. Compact keeps today's full-column cards.
    @ViewBuilder
    private func readableCard<Content: View>(
        _ content: Content,
        layout: RefsInspectorLayout
    ) -> some View {
        if layout.mode == .wide {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content.frame(width: layout.contentWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
        } else {
            content
        }
    }

    private var copyCard: some View {
        Group {
            if let card = model.copyCard {
                RefsCopyCardView(
                    card: card,
                    alternatesActive: model.copyAlternatesActive,
                    previewMode: previewMode,
                    onMeasuredHeight: {
                        model.copyCardNoteCapacity = Self.copyCardNoteCapacity(
                            for: card,
                            height: $0
                        )
                        model.copyCardPickerWindowSize =
                            RefsCopyCardLayout.highlightWindowSize(
                                cardHeight: Double($0),
                                metrics: RefsVisualTokens.copyCardMetrics,
                                rowHeight: Double(
                                    RefsVisualTokens.copyCardPickerRowHeight
                                )
                            )
                    },
                    onRowTap: { model.copyCardRowTapped($0) },
                    onPickerRowTap: { model.copyCardPickerRowTapped($0) }
                )
                .id(card.token)
                .transition(copyCardTransition)
            }
        }
    }

    private var renameCard: some View {
        Group {
            if let card = model.renameCard {
                RefsRenameCardView(
                    card: card,
                    focusSequence: model.renameCardGeneration,
                    onDraftChange: { model.editRenameDraft($0) }
                )
                .id(model.renameCardGeneration)
                .transition(copyCardTransition)
            }
        }
    }

    private var todayLinkCard: some View {
        Group {
            if let card = model.todayLinkCard {
                RefsTodayLinkCardView(
                    card: card,
                    focusSequence: model.todayLinkCardGeneration,
                    previewMode: previewMode,
                    onQueryChange: { model.editTodayLinkQuery($0) },
                    onRowTap: { model.todayLinkRowTapped($0) }
                )
                .id(model.todayLinkCardGeneration)
                .transition(copyCardTransition)
            }
        }
    }

    private var copyCardAnimation: Animation {
        .easeOut(duration: 0.14)
    }

    private var copyCardTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .offset(x: 0, y: 6).combined(with: .opacity),
            removal: .opacity
        )
    }

    static func copyCardNoteCapacity(
        for card: RefsCopyCard,
        height: CGFloat
    ) -> Int {
        var groups = Set(card.rows.map(\.group))
        let hasNotesSection: Bool
        if card.rows.contains(where: { $0.group == .notes }) {
            hasNotesSection = true
        } else {
            switch card.notes {
            case .loading:
                hasNotesSection = card.item.annotationCount > 0
                    || card.item.commentCount > 0
            case .loaded:
                hasNotesSection = false
            case .unavailable:
                hasNotesSection = true
            }
        }
        if hasNotesSection {
            groups.insert(.notes)
        }
        return RefsCopyCardLayout.noteCapacity(
            cardHeight: Double(height),
            nonNoteRowCount: card.rows.filter { row in
                if case .note = row.key { return false }
                return true
            }.count,
            groupCount: groups.count,
            metrics: RefsVisualTokens.copyCardMetrics
        )
    }
}
