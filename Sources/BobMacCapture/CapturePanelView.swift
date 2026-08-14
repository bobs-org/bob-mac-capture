import CaptureCore
import SwiftUI

enum CapturePanelLayout {
    static let rootPadding: CGFloat = 18
    static let titlebarDragInset: CGFloat = 28
    static let sectionSpacing: CGFloat = 12

    static let panelInitialContentWidth: CGFloat = 760
    static let panelMinimumContentWidth: CGFloat = 620

    static let editorContentPadding: CGFloat = 10
    static let editorLineHeight: CGFloat = 22
    static let editorMaximumVisibleLines = 6
    static let completionVisibleRows = 5
    static let completionRowHeight: CGFloat = 32
    static let completionViewportHeight = completionRowHeight * CGFloat(completionVisibleRows) + 12
    static let previewIdealHeight: CGFloat = 92

    /// First-frame fallback used only until SwiftUI reports rendered editor/footer
    /// metrics. The steady-state panel size is always measured, not inferred.
    static let panelFallbackContentHeight: CGFloat = 160

    /// Hard floor guarding only against a degenerate measurement; deliberately below the
    /// real compact height so a correct measurement is never inflated.
    static let panelMinimumContentHeight: CGFloat = 96
    static let panelMaximumContentHeight: CGFloat = 720
    static let panelScreenMargin: CGFloat = 24

    static let panelInitialContentSize = CGSize(
        width: panelInitialContentWidth,
        height: panelFallbackContentHeight
    )
    static let panelMinimumContentSize = CGSize(width: panelMinimumContentWidth, height: panelMinimumContentHeight)
}

struct CaptureEditorHeightPolicy: Equatable {
    var lineHeight: CGFloat = CapturePanelLayout.editorLineHeight
    var verticalPadding: CGFloat = CapturePanelLayout.editorContentPadding * 2
    var maximumVisibleLines: Int = CapturePanelLayout.editorMaximumVisibleLines
    var displayScale: CGFloat = 1

    var minimumHeight: CGFloat {
        roundedToPixel(lineHeight + verticalPadding)
    }

    var maximumHeight: CGFloat {
        roundedToPixel(lineHeight * CGFloat(maximumVisibleLines) + verticalPadding)
    }

    func resolvedHeight(forMeasuredTextHeight measuredTextHeight: CGFloat) -> CGFloat {
        let measuredHeight = max(measuredTextHeight, lineHeight)
        let unclampedHeight = measuredHeight + verticalPadding
        return roundedToPixel(min(max(unclampedHeight, minimumHeight), maximumHeight))
    }

    func visibleLineCount(forMeasuredTextHeight measuredTextHeight: CGFloat) -> Int {
        let measuredHeight = max(measuredTextHeight, lineHeight)
        let measuredLines = Int(ceil(measuredHeight / lineHeight))
        return min(max(measuredLines, 1), maximumVisibleLines)
    }

    private func roundedToPixel(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded(.up) / scale
    }
}

struct CapturePanelContentMetrics: Equatable {
    var idealContentHeight: CGFloat
    var minimumVisibleContentHeight: CGFloat

    var isValid: Bool {
        idealContentHeight.isFinite
            && minimumVisibleContentHeight.isFinite
            && idealContentHeight > 1
            && minimumVisibleContentHeight > 1
    }
}

struct CapturePanelContentHeightPolicy: Equatable {
    var titlebarDragInset: CGFloat = CapturePanelLayout.titlebarDragInset
    var rootPadding: CGFloat = CapturePanelLayout.rootPadding
    var sectionSpacing: CGFloat = CapturePanelLayout.sectionSpacing
    var displayScale: CGFloat = 1

    func metrics(
        editorHeight: CGFloat,
        auxiliaryHeight: CGFloat?,
        footerHeight: CGFloat
    ) -> CapturePanelContentMetrics {
        let editorHeight = sanitizedHeight(editorHeight)
        let footerHeight = sanitizedHeight(footerHeight)
        let auxiliaryHeight = auxiliaryHeight.map(sanitizedHeight)
        let spacingCount = auxiliaryHeight == nil ? 1 : 2
        let persistentHeight = titlebarDragInset
            + editorHeight
            + sectionSpacing * CGFloat(spacingCount)
            + footerHeight
            + rootPadding
        let idealHeight = persistentHeight + (auxiliaryHeight ?? 0)

        return CapturePanelContentMetrics(
            idealContentHeight: roundedToPixel(idealHeight),
            minimumVisibleContentHeight: roundedToPixel(persistentHeight)
        )
    }

    private func sanitizedHeight(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 0
        }
        return max(0, value)
    }

    private func roundedToPixel(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded(.up) / scale
    }
}

@available(macOS 26.0, *)
struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel
    var onContentMetricsChange: (CapturePanelContentMetrics) -> Void = { _ in }
    @State private var selection = AttributedTextSelection()
    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var measuredEditorHeight = CaptureEditorHeightPolicy().minimumHeight
    @State private var measuredAuxiliaryContentHeight: CGFloat = 0
    @State private var measuredFooterHeight: CGFloat = 0

    var body: some View {
        content
            .onChange(of: hasAuxiliaryContent) { _, hasContent in
                if !hasContent {
                    measuredAuxiliaryContentHeight = 0
                }
                reportContentMetrics()
            }
            .onChange(of: displayScale) { _, _ in
                reportContentMetrics()
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CapturePanelLayout.sectionSpacing) {
            AutosizingCaptureEditor(model: model, selection: $selection)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    updateMeasuredEditorHeight(height)
                }

            if hasAuxiliaryContent {
                auxiliaryScrollRegion
            }

            CapturePanelFooter(model: model)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    updateMeasuredFooterHeight(height)
                }
        }
        .padding(.top, CapturePanelLayout.titlebarDragInset)
        .padding([.horizontal, .bottom], CapturePanelLayout.rootPadding)
        .frame(
            minWidth: CapturePanelLayout.panelMinimumContentWidth,
            maxWidth: .infinity,
            alignment: .topLeading
        )
    }

    private var hasAuxiliaryContent: Bool {
        model.completionVisible
            || model.destinationSummary != nil
            || model.errorMessage != nil
            || model.previewState != .idle
    }

    private var auxiliaryScrollRegion: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                auxiliaryContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        updateMeasuredAuxiliaryContentHeight(height)
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Capture details")
            .onChange(of: model.errorMessage) { _, errorMessage in
                guard errorMessage != nil else {
                    return
                }
                proxy.scrollTo(AuxiliarySection.error, anchor: .center)
            }
        }
        .layoutPriority(0)
    }

    private var auxiliaryContent: some View {
        VStack(alignment: .leading, spacing: CapturePanelLayout.sectionSpacing) {
            if model.completionVisible {
                CompletionList(model: model)
                    .frame(width: 430)
                    .frame(maxHeight: CapturePanelLayout.completionViewportHeight, alignment: .top)
                    .padding(.leading, 14)
                    .layoutPriority(0)
                    .id(AuxiliarySection.completion)
            }

            if let destinationSummary = model.destinationSummary {
                Text(destinationSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .id(AuxiliarySection.destination)
            }

            if let errorMessage = model.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityLabel("Capture error: \(errorMessage)")
                        .accessibilityFocused($errorIsFocused)
                        .onAppear { errorIsFocused = true }
                    HStack {
                        Button("Retry") {
                            model.submit(openAfterCapture: false)
                        }
                        Button("Copy Diagnostic") {
                            model.copyDiagnosticToPasteboard()
                        }
                    }
                }
                .id(AuxiliarySection.error)
            }

            if model.previewState != .idle {
                PreviewPane(model: model)
                    .id(AuxiliarySection.preview)
            }
        }
    }

    private func updateMeasuredEditorHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else {
            return
        }
        measuredEditorHeight = height
        reportContentMetrics()
    }

    private func updateMeasuredAuxiliaryContentHeight(_ height: CGFloat) {
        guard height.isFinite, height >= 0 else {
            return
        }
        measuredAuxiliaryContentHeight = height
        reportContentMetrics()
    }

    private func updateMeasuredFooterHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else {
            return
        }
        measuredFooterHeight = height
        reportContentMetrics()
    }

    private func reportContentMetrics() {
        guard measuredEditorHeight.isFinite,
              measuredEditorHeight > 1,
              measuredFooterHeight.isFinite,
              measuredFooterHeight > 1
        else {
            return
        }

        let policy = CapturePanelContentHeightPolicy(displayScale: displayScale)
        let metrics = policy.metrics(
            editorHeight: measuredEditorHeight,
            auxiliaryHeight: hasAuxiliaryContent ? measuredAuxiliaryContentHeight : nil,
            footerHeight: measuredFooterHeight
        )
        guard metrics.isValid else {
            return
        }
        onContentMetricsChange(metrics)
    }

    private enum AuxiliarySection: Hashable {
        case completion
        case destination
        case error
        case preview
    }
}

@available(macOS 26.0, *)
private struct CapturePanelFooter: View {
    @ObservedObject var model: CapturePanelModel
    @AccessibilityFocusState private var statusIsFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(model.statusText.isEmpty ? "Ready" : model.statusText)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityFocused($statusIsFocused)
                .onChange(of: model.successAnnouncementTick) { _, _ in
                    statusIsFocused = true
                }
            Spacer(minLength: 12)
            Button("Discard") {
                model.discardDraftAndClose()
            }
            .help("Discards the draft and closes the panel (Control-C).")
            .disabled(!model.hasDraft || model.isSubmitting)
            Button("Preview") {
                model.preview()
            }
            .help("Resolves the current clipboard/history and shows the exact destination without writing anything.")
            .disabled(!model.hasDraft || model.isSubmitting || model.isPreviewing)
            Button("Capture") {
                model.submit(openAfterCapture: false)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.hasDraft || model.isSubmitting)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture actions")
    }
}

@available(macOS 26.0, *)
private struct AutosizingCaptureEditor: View {
    @ObservedObject var model: CapturePanelModel
    @Binding var selection: AttributedTextSelection
    @Environment(\.displayScale) private var displayScale
    @State private var editorHeight = CaptureEditorHeightPolicy().minimumHeight

    private var policy: CaptureEditorHeightPolicy {
        CaptureEditorHeightPolicy(displayScale: displayScale)
    }

    private var textInset: CGFloat {
        CapturePanelLayout.editorContentPadding
    }

    private var editorFont: Font {
        .system(.body, design: .monospaced)
    }

    var body: some View {
        GeometryReader { proxy in
            let usableTextWidth = max(1, proxy.size.width - textInset * 2)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.attributedDraft, selection: $selection)
                    .font(editorFont)
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: max(policy.lineHeight, editorHeight - textInset * 2))
                    .padding(textInset)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(model.isSubmitting)
                    .accessibilityLabel("Capture draft")
                    .onChange(of: String(model.attributedDraft.characters)) { _, newText in
                        model.editorTextDidChange(cursorUTF8Offset: newText.utf8.count)
                    }

                if !model.hasDraft {
                    Text("Type to capture\u{2026}")
                        .font(editorFont)
                        .foregroundStyle(.secondary)
                        .padding(.leading, textInset + 5)
                        .padding(.top, textInset + 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                sizingText(width: usableTextWidth)
                    .padding(textInset)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: editorHeight)
        .onPreferenceChange(CaptureEditorMeasuredHeightKey.self) { measuredTextHeight in
            updateHeight(forMeasuredTextHeight: measuredTextHeight)
        }
    }

    private var sizingString: String {
        String(model.attributedDraft.characters) + "\u{200B}"
    }

    private func sizingText(width: CGFloat) -> some View {
        Text(verbatim: sizingString)
            .font(editorFont)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .leading)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: CaptureEditorMeasuredHeightKey.self,
                        value: geometry.size.height
                    )
                }
            )
            .opacity(0)
    }

    private func updateHeight(forMeasuredTextHeight measuredTextHeight: CGFloat) {
        let nextHeight = policy.resolvedHeight(forMeasuredTextHeight: measuredTextHeight)
        guard nextHeight != editorHeight else {
            return
        }
        editorHeight = nextHeight
    }
}

private struct CaptureEditorMeasuredHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@available(macOS 26.0, *)
private struct CompletionList: View {
    @ObservedObject var model: CapturePanelModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(
                        Array((model.completionResponse?.candidates ?? []).enumerated()),
                        id: \.offset
                    ) {
                        index, candidate in
                        CompletionRow(
                            candidate: candidate,
                            detail: model.detailText(
                                for: candidate,
                                context: model.completionResponse?.context
                            ),
                            selected: index == model.selectedCompletionIndex
                        )
                        .id(index)
                        .onTapGesture {
                            model.selectedCompletionIndex = index
                            model.acceptSelectedCompletion()
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selectedCompletionIndex) { _, index in
                proxy.scrollTo(index, anchor: .center)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completion suggestions")
    }
}

@available(macOS 26.0, *)
private struct CompletionRow: View {
    let candidate: CaptureCompletionCandidate
    let detail: String
    let selected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(primaryText)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
            Spacer(minLength: 8)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var primaryText: String {
        candidate.title ?? candidate.text ?? candidate.route ?? candidate.replacement
    }
}

@available(macOS 26.0, *)
private struct PreviewPane: View {
    @ObservedObject var model: CapturePanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.previewState {
            case .idle:
                Text("Preview")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .ready(let response):
                previewContent(response)
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .frame(
            maxWidth: .infinity,
            minHeight: CapturePanelLayout.previewIdealHeight,
            idealHeight: CapturePanelLayout.previewIdealHeight,
            alignment: .leading
        )
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .layoutPriority(1)
    }

    @ViewBuilder
    private func previewContent(_ success: CaptureCommandSuccess) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(success.routeLabel.isEmpty ? success.relativeTarget : success.routeLabel)
                .fontWeight(.semibold)
            Text(success.placement)
                .foregroundStyle(.secondary)
            Text(success.kind)
                .foregroundStyle(.secondary)
            if let scheduled = success.scheduled {
                Text(scheduled)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)

        Text(success.taskLine)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(2)

        Text(success.relativeTarget)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .textSelection(.enabled)

        if model.livePreviewUsesLiteralClipboard {
            Text("Clipboard markers stay literal in live preview")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
