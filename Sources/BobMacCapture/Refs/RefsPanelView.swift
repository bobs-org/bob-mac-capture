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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(
        model: RefsPanelModel,
        animatePresentation: Bool = true,
        previewMode: Bool = false
    ) {
        self.model = model
        self.animatePresentation = animatePresentation
        self.previewMode = previewMode
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
            content
            RefsFooter(model: model)
        }
        .padding(RefsVisualTokens.outerPadding)
        .scaleEffect(appeared || !animatePresentation ? 1 : 0.98)
        .onAppear {
            guard animatePresentation, !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.12)) {
                appeared = true
            }
        }
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
        } else {
            GeometryReader { geometry in
                let width = geometry.size.width
                if RefsVisualTokens.showsInspector(width: width) {
                    HStack(spacing: 0) {
                        RefsListView(model: model)
                            .frame(width: RefsVisualTokens.listWidth(panelWidth: width))
                        inspectorDivider
                        inspector
                    }
                } else {
                    RefsListView(model: model)
                }
            }
        }
    }

    private var inspectorDivider: some View {
        Rectangle()
            .fill(.primary.opacity(0.10))
            .frame(width: 0.5)
    }

    @ViewBuilder
    private var inspector: some View {
        if let selected = model.selectedID,
           let content = model.rowContent(for: selected)
        {
            RefsInspectorView(content: content, signals: model.signals)
        } else {
            Text("Select a reference")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
