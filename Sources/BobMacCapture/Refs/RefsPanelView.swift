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
        if !model.hasSnapshot {
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
        } else if let previewWidth {
            columns(panelWidth: previewWidth)
        } else {
            GeometryReader { geometry in
                // The geometry width is post-padding: add the outer
                // padding back so the inspector cutoff and the list
                // width measure the panel width (§6).
                columns(
                    panelWidth: geometry.size.width
                        + RefsVisualTokens.outerPadding * 2
                )
            }
        }
    }

    @ViewBuilder
    private func columns(panelWidth: CGFloat) -> some View {
        if RefsVisualTokens.showsInspector(width: panelWidth) {
            HStack(spacing: 0) {
                RefsListView(model: model, previewMode: previewMode)
                    .frame(width: RefsVisualTokens.listWidth(panelWidth: panelWidth))
                inspectorDivider
                inspector
            }
        } else {
            RefsListView(model: model, previewMode: previewMode)
        }
    }

    private var inspectorDivider: some View {
        Rectangle()
            .fill(.primary.opacity(contrast == .increased ? 0.25 : 0.10))
            .frame(width: 0.5)
    }

    @ViewBuilder
    private var inspector: some View {
        if let selected = model.selectedID,
           let content = model.rowContent(for: selected)
        {
            RefsInspectorView(
                content: content,
                signals: model.signals,
                inspector: model.inspectorContent(for: selected),
                thumbnail: model.inspectorThumbnail(for: selected),
                previewMode: previewMode
            )
            .onAppear { model.inspectorRequested() }
            .onChange(of: selected) { _, _ in model.inspectorRequested() }
        } else {
            Text("Select a reference")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
