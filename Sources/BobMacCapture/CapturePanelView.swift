import CaptureCore
import Combine
import SwiftUI

enum CapturePanelLayout {
    static let rootPadding: CGFloat = 18
    static let titlebarDragInset: CGFloat = 28
    static let sectionSpacing: CGFloat = 12

    static let panelInitialContentWidth: CGFloat = 760
    static let panelMinimumContentWidth: CGFloat = 620

    static let editorContentPadding: CGFloat = 10
    static let editorLineHeight: CGFloat = 22
    static let completionVisibleRows = 5
    static let completionRowHeight: CGFloat = 48
    static let completionViewportHeight = completionRowHeight * CGFloat(completionVisibleRows) + 12
    static let stashVisibleRows = 5
    static let stashListPadding: CGFloat = 6
    static let stashRowSpacing: CGFloat = 2
    static let stashRowContentMinimumHeight: CGFloat = 50
    static let stashRowHorizontalPadding: CGFloat = 8
    static let stashRowVerticalPadding: CGFloat = 6
    static let stashRowHeight = stashRowContentMinimumHeight + stashRowVerticalPadding * 2
    static let stashViewportHeight = stashListPadding * 2
        + stashRowHeight * CGFloat(stashVisibleRows)
        + stashRowSpacing * CGFloat(stashVisibleRows - 1)
    static let stashPickerContentSpacing: CGFloat = 4
    static let stashPickerPadding: CGFloat = 6
    static let stashClearButtonKeyWidth: CGFloat = 58
    static let stashClearButtonKeyHeight: CGFloat = 22
    static let stashClearButtonHorizontalPadding: CGFloat = 8
    static let stashClearButtonVerticalPadding: CGFloat = 5
    static let stashClearButtonHeight = stashClearButtonKeyHeight + stashClearButtonVerticalPadding * 2
    static let previewIdealHeight: CGFloat = 92

    /// First-frame fallback used only until SwiftUI reports rendered editor/footer
    /// metrics. The steady-state panel size is always measured, not inferred.
    static let panelFallbackContentHeight: CGFloat = 160

    /// Hard floor guarding only against a degenerate measurement; deliberately below the
    /// real compact height so a correct measurement is never inflated.
    static let panelMinimumContentHeight: CGFloat = 96
    /// Fallback content-height ceiling used only when no screen is known (headless
    /// tests, a panel that has not yet been placed). A live panel on a real screen is
    /// limited solely by that screen's visible frame minus `panelScreenMargin`.
    static let panelMaximumContentHeight: CGFloat = 720
    static let panelScreenMargin: CGFloat = 24
    /// Minimum height reserved for the auxiliary region (completion, destination,
    /// preview, error) when the editor budget binds. Roughly a two-line destination
    /// summary plus spacing; a shorter auxiliary never over-reserves, and the stash
    /// picker keeps its own `minimumVisibleHeight` floor.
    static let auxiliaryReservedHeight: CGFloat = 88

    static let panelInitialContentSize = CGSize(
        width: panelInitialContentWidth,
        height: panelFallbackContentHeight
    )
    static let panelMinimumContentSize = CGSize(width: panelMinimumContentWidth, height: panelMinimumContentHeight)
}

struct CaptureEditorHeightPolicy: Equatable {
    var lineHeight: CGFloat = CapturePanelLayout.editorLineHeight
    var verticalPadding: CGFloat = CapturePanelLayout.editorContentPadding * 2
    /// Injected ceiling. `nil` means unbounded; `CapturePanelView` always supplies a
    /// screen-derived (or no-screen fallback) budget so the live editor is never
    /// unbounded.
    var maximumHeight: CGFloat? = nil
    var displayScale: CGFloat = 1

    var minimumHeight: CGFloat {
        roundedToPixel(lineHeight + verticalPadding)
    }

    func resolvedHeight(forMeasuredTextHeight measuredTextHeight: CGFloat) -> CGFloat {
        let measuredHeight = max(measuredTextHeight, lineHeight)
        let unclampedHeight = measuredHeight + verticalPadding
        let floored = max(unclampedHeight, minimumHeight)
        let rounded = roundedToPixel(floored)
        guard let maximumHeight else {
            return rounded
        }
        // Never clamp below the one-line minimum, even if the injected ceiling is
        // smaller than that minimum (a degenerate short-screen budget).
        let ceiling = max(maximumHeight, minimumHeight)
        return min(rounded, ceiling)
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

struct CapturePanelAuxiliaryHeight: Equatable {
    var idealHeight: CGFloat
    var minimumVisibleHeight: CGFloat

    static func overflow(idealHeight: CGFloat) -> Self {
        Self(idealHeight: idealHeight, minimumVisibleHeight: 0)
    }
}

struct CanceledDraftStashPickerHeightPolicy: Equatable {
    var entryCount: Int
    var visibleRowLimit: Int = CapturePanelLayout.stashVisibleRows
    var displayScale: CGFloat = 1

    var visibleRowCount: Int {
        min(max(entryCount, 0), max(visibleRowLimit, 0))
    }

    var rowViewportHeight: CGFloat {
        let rows = visibleRowCount
        let rowHeight = CapturePanelLayout.stashRowHeight * CGFloat(rows)
        let spacingHeight = CapturePanelLayout.stashRowSpacing * CGFloat(max(rows - 1, 0))
        return roundedToPixel(CapturePanelLayout.stashListPadding * 2 + rowHeight + spacingHeight)
    }

    var actionChromeHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.stashPickerPadding * 2
                + CapturePanelLayout.stashPickerContentSpacing
                + CapturePanelLayout.stashClearButtonHeight
        )
    }

    var idealHeight: CGFloat {
        roundedToPixel(rowViewportHeight + actionChromeHeight)
    }

    var minimumVisibleHeight: CGFloat {
        actionChromeHeight
    }

    var auxiliaryHeight: CapturePanelAuxiliaryHeight {
        CapturePanelAuxiliaryHeight(
            idealHeight: idealHeight,
            minimumVisibleHeight: minimumVisibleHeight
        )
    }

    private func roundedToPixel(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded(.up) / scale
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
        metrics(
            editorHeight: editorHeight,
            auxiliary: auxiliaryHeight.map { CapturePanelAuxiliaryHeight.overflow(idealHeight: $0) },
            footerHeight: footerHeight
        )
    }

    func metrics(
        editorHeight: CGFloat,
        auxiliary: CapturePanelAuxiliaryHeight?,
        footerHeight: CGFloat
    ) -> CapturePanelContentMetrics {
        let editorHeight = sanitizedHeight(editorHeight)
        let footerHeight = sanitizedHeight(footerHeight)
        let auxiliary = auxiliary.map(sanitizedAuxiliaryHeight)
        let persistentHeight = nonEditorChromeHeight(
            footerHeight: footerHeight,
            hasAuxiliary: auxiliary != nil
        ) + editorHeight
        let idealHeight = persistentHeight + (auxiliary?.idealHeight ?? 0)
        let minimumVisibleHeight = persistentHeight + (auxiliary?.minimumVisibleHeight ?? 0)

        return CapturePanelContentMetrics(
            idealContentHeight: roundedToPixel(idealHeight),
            minimumVisibleContentHeight: roundedToPixel(minimumVisibleHeight)
        )
    }

    /// Persistent chrome excluding the editor: titlebar inset, inter-section spacing,
    /// footer, and root padding. Shared with `CaptureEditorHeightBudget` so the editor
    /// ceiling and the panel metrics agree on spacing count.
    func nonEditorChromeHeight(footerHeight: CGFloat, hasAuxiliary: Bool) -> CGFloat {
        let spacingCount = hasAuxiliary ? 2 : 1
        return titlebarDragInset
            + sectionSpacing * CGFloat(spacingCount)
            + sanitizedHeight(footerHeight)
            + rootPadding
    }

    private func sanitizedHeight(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 0
        }
        return max(0, value)
    }

    private func sanitizedAuxiliaryHeight(_ value: CapturePanelAuxiliaryHeight) -> CapturePanelAuxiliaryHeight {
        let minimumVisibleHeight = sanitizedHeight(value.minimumVisibleHeight)
        return CapturePanelAuxiliaryHeight(
            idealHeight: max(sanitizedHeight(value.idealHeight), minimumVisibleHeight),
            minimumVisibleHeight: minimumVisibleHeight
        )
    }

    private func roundedToPixel(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded(.up) / scale
    }
}

/// Screen-derived ceiling for the capture editor. Given the available screen height,
/// measured footer, and auxiliary state, answers how tall the editor may grow.
struct CaptureEditorHeightBudget: Equatable {
    var availableScreenHeight: CGFloat?
    var footerHeight: CGFloat
    var auxiliary: CapturePanelAuxiliaryHeight?
    var contentPolicy: CapturePanelContentHeightPolicy = CapturePanelContentHeightPolicy()
    var screenMargin: CGFloat = CapturePanelLayout.panelScreenMargin
    var auxiliaryReservedHeight: CGFloat = CapturePanelLayout.auxiliaryReservedHeight
    var minimumEditorHeight: CGFloat = CaptureEditorHeightPolicy().minimumHeight
    var fallbackMaximumContentHeight: CGFloat = CapturePanelLayout.panelMaximumContentHeight

    var maximumHeight: CGFloat {
        let screenLimit: CGFloat
        if let availableScreenHeight {
            screenLimit = max(1, availableScreenHeight - 2 * screenMargin)
        } else {
            screenLimit = fallbackMaximumContentHeight
        }

        let chrome = contentPolicy.nonEditorChromeHeight(
            footerHeight: footerHeight,
            hasAuxiliary: auxiliary != nil
        )
        let auxiliaryReserve: CGFloat
        if let auxiliary {
            let floor = max(auxiliaryReservedHeight, auxiliary.minimumVisibleHeight)
            auxiliaryReserve = min(max(auxiliary.idealHeight, 0), floor)
        } else {
            auxiliaryReserve = 0
        }

        return max(minimumEditorHeight, screenLimit - chrome - auxiliaryReserve)
    }
}

@available(macOS 26.0, *)
struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel
    var onContentMetricsChange: (CapturePanelContentMetrics) -> Void = { _ in }
    @FocusState private var focusedControl: CapturePanelFocusTarget?
    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var measuredEditorHeight = CaptureEditorHeightPolicy().minimumHeight
    @State private var measuredAuxiliaryContentHeight: CGFloat = 0
    @State private var measuredFooterHeight: CGFloat = 0

    var body: some View {
        content
            .onAppear {
                applyFocusRequest(model.focusRequest)
            }
            .onChange(of: model.focusRequest) { _, request in
                applyFocusRequest(request)
            }
            .onChange(of: hasAuxiliaryContent) { _, hasContent in
                if !hasContent {
                    measuredAuxiliaryContentHeight = 0
                }
                reportContentMetrics()
            }
            .onChange(of: model.isStashPickerPresented) { _, _ in
                measuredAuxiliaryContentHeight = 0
                reportContentMetrics()
            }
            .onChange(of: model.stashCount) { _, _ in
                reportContentMetrics()
            }
            .onChange(of: displayScale) { _, _ in
                reportContentMetrics()
            }
            .onChange(of: model.availableScreenHeight) { _, _ in
                reportContentMetrics()
            }
            .onChange(of: measuredFooterHeight) { _, _ in
                reportContentMetrics()
            }
    }

    private var editorHeightPolicy: CaptureEditorHeightPolicy {
        let contentPolicy = CapturePanelContentHeightPolicy(displayScale: displayScale)
        let budget = CaptureEditorHeightBudget(
            availableScreenHeight: model.availableScreenHeight,
            footerHeight: measuredFooterHeight,
            auxiliary: currentAuxiliaryHeight,
            contentPolicy: contentPolicy,
            minimumEditorHeight: CaptureEditorHeightPolicy(displayScale: displayScale).minimumHeight
        )
        return CaptureEditorHeightPolicy(
            maximumHeight: budget.maximumHeight,
            displayScale: displayScale
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CapturePanelLayout.sectionSpacing) {
            AutosizingCaptureEditor(
                model: model,
                selection: $model.editorSelection,
                focus: $focusedControl,
                heightPolicy: editorHeightPolicy
            )
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                updateMeasuredEditorHeight(height)
            }

            if hasAuxiliaryContent {
                auxiliaryRegion
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
        model.isStashPickerPresented
            || model.taskIDPromptVisible
            || model.completionVisible
            || model.destinationSummary != nil
            || model.errorMessage != nil
            || model.previewState != .idle
    }

    @ViewBuilder
    private var auxiliaryRegion: some View {
        if model.isStashPickerPresented {
            CanceledDraftStashPicker(model: model)
                .frame(width: 520)
                .padding(.leading, 14)
                .layoutPriority(0)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Capture details")
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    updateMeasuredAuxiliaryContentHeight(height)
                }
        } else {
            auxiliaryScrollRegion
        }
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
            if model.taskIDPromptVisible {
                TaskIDPromptCard(model: model, focus: $focusedControl)
                    .frame(width: 430)
                    .padding(.leading, 14)
                    .layoutPriority(0)
                    .id(AuxiliarySection.taskIDPrompt)
            } else if model.completionVisible {
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
            auxiliary: currentAuxiliaryHeight,
            footerHeight: measuredFooterHeight
        )
        guard metrics.isValid else {
            return
        }
        onContentMetricsChange(metrics)
    }

    private func applyFocusRequest(_ request: CapturePanelFocusRequest) {
        focusedControl = request.target
    }

    private var currentAuxiliaryHeight: CapturePanelAuxiliaryHeight? {
        guard hasAuxiliaryContent else {
            return nil
        }

        if model.isStashPickerPresented {
            let explicit = CanceledDraftStashPickerHeightPolicy(
                entryCount: model.stashCount,
                displayScale: displayScale
            ).auxiliaryHeight
            return CapturePanelAuxiliaryHeight(
                idealHeight: max(explicit.idealHeight, measuredAuxiliaryContentHeight),
                minimumVisibleHeight: explicit.minimumVisibleHeight
            )
        }

        return .overflow(idealHeight: measuredAuxiliaryContentHeight)
    }

    private enum AuxiliarySection: Hashable {
        case stash
        case taskIDPrompt
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
                .onChange(of: model.statusAnnouncementTick) { _, _ in
                    statusIsFocused = true
                }
            Spacer(minLength: 12)
            Button {
                model.toggleStashPicker()
            } label: {
                Label("Stash \(model.stashCount)", systemImage: "tray")
            }
            .help("Restore a draft canceled with Control-C (Control-S).")
            .disabled(model.isSubmitting || model.taskIDPromptVisible)
            Button("Discard") {
                model.discardDraftAndClose()
            }
            .help("Permanently discards the draft and closes the panel.")
            .disabled(!model.hasDraft || model.isSubmitting || model.taskIDPrompt?.isSaving == true)
            Button("Preview") {
                model.preview()
            }
            .help("Resolves the current clipboard/history and shows the exact destination without writing anything.")
            .disabled(!model.hasDraft || model.isSubmitting || model.isPreviewing || model.taskIDPromptVisible)
            Button("Capture") {
                model.submit(openAfterCapture: false)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.hasDraft || model.isSubmitting || model.taskIDPromptVisible)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture actions")
    }
}

@available(macOS 26.0, *)
private struct AutosizingCaptureEditor: View {
    @ObservedObject var model: CapturePanelModel
    @Binding var selection: AttributedTextSelection
    var focus: FocusState<CapturePanelFocusTarget?>.Binding
    var heightPolicy: CaptureEditorHeightPolicy
    @State private var editorHeight = CaptureEditorHeightPolicy().minimumHeight
    @State private var measuredTextHeight: CGFloat = 0

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
                    .frame(height: max(heightPolicy.lineHeight, editorHeight - textInset * 2))
                    .padding(textInset)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(model.isSubmitting || model.editorInputLocked)
                    .modifier(
                        CaptureFocusAdoption(
                            target: .editor,
                            request: model.focusRequest,
                            focus: focus
                        )
                    )
                    .accessibilityLabel("Capture draft")
                    .onChange(of: String(model.attributedDraft.characters)) { _, _ in
                        model.editorTextDidChange(cursorUTF8Offset: model.collapsedSelectionUTF8Offset())
                    }
                    .onReceive(model.$editorSelection.dropFirst()) { _ in
                        model.editorSelectionDidChange(cursorUTF8Offset: model.collapsedSelectionUTF8Offset())
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
        .onChange(of: heightPolicy) { _, _ in
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
        self.measuredTextHeight = measuredTextHeight
        let nextHeight = heightPolicy.resolvedHeight(forMeasuredTextHeight: measuredTextHeight)
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
private struct CaptureFocusAdoption: ViewModifier {
    let target: CapturePanelFocusTarget
    let request: CapturePanelFocusRequest
    var focus: FocusState<CapturePanelFocusTarget?>.Binding

    func body(content: Content) -> some View {
        content
            .focused(focus, equals: target)
            // `.task(id:)` runs after this control is installed and after the update
            // that installed it commits, so it can claim a request published in the
            // same transaction that created the control, and can re-claim one that was
            // dropped when another control resigned first responder in that
            // transaction. `id:` re-runs it for every later request (validation error,
            // Bob failure) without re-stealing focus the control already holds.
            .task(id: request) {
                guard request.target == target, focus.wrappedValue != target else {
                    return
                }
                focus.wrappedValue = target
                CaptureSignpost.event("focus-adopted")
            }
    }
}

@available(macOS 26.0, *)
private struct TaskIDPromptCard: View {
    @ObservedObject var model: CapturePanelModel
    var focus: FocusState<CapturePanelFocusTarget?>.Binding

    private var prompt: CaptureTaskIDPromptState? {
        model.taskIDPrompt
    }

    var body: some View {
        if let prompt {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Add block ID", systemImage: "link.badge.plus")
                        .font(.headline)
                    Spacer(minLength: 8)
                    if prompt.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                taskSummary(prompt)

                HStack(spacing: 0) {
                    Text("^")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(CaptureEditorPalette.color(for: .blockID))
                        .padding(.leading, 8)
                    TextField(
                        "block-id",
                        text: Binding(
                            get: { model.taskIDPrompt?.authoredID ?? "" },
                            set: { model.updateTaskIDPromptBlockID($0) }
                        )
                    )
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 6)
                    .modifier(
                        CaptureFocusAdoption(
                            target: .taskIDPromptBlockID,
                            request: model.focusRequest,
                            focus: focus
                        )
                    )
                    .disabled(prompt.isSaving)
                    .onSubmit {
                        model.submitTaskIDPrompt()
                    }
                    .accessibilityLabel("Block ID")
                }
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.secondary.opacity(0.24), lineWidth: 0.5)
                )

                Text("Letters, numbers, and hyphens")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = prompt.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityLabel("Block ID error: \(error)")
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        model.cancelTaskIDPrompt()
                    }
                    .disabled(prompt.isSaving)
                    Button("Add & Select") {
                        model.submitTaskIDPrompt()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.taskIDPromptCanSubmit)
                }
            }
            .padding(10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 12, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Add block ID")
        }
    }

    private func taskSummary(_ prompt: CaptureTaskIDPromptState) -> some View {
        let candidate = prompt.candidate
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let symbol = candidate.statusSymbol {
                    Text("[\(symbol)]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(candidate.text ?? "Selected task")
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let section = candidate.section {
                Text(section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@available(macOS 26.0, *)
private struct CanceledDraftStashPicker: View {
    @ObservedObject var model: CapturePanelModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: CapturePanelLayout.stashPickerContentSpacing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: CapturePanelLayout.stashRowSpacing) {
                        ForEach(Array(model.stashEntries.enumerated()), id: \.element.id) { index, entry in
                            CanceledDraftStashRow(
                                entry: entry,
                                accelerator: CanceledDraftStash.accelerator(for: index) ?? "",
                                selected: index == model.selectedStashIndex,
                                now: Date()
                            )
                            .id(entry.id)
                            .onTapGesture {
                                model.restoreStashEntry(id: entry.id)
                            }
                        }
                    }
                    .padding(CapturePanelLayout.stashListPadding)
                }
                .frame(
                    minHeight: 0,
                    idealHeight: sizing.rowViewportHeight,
                    maxHeight: sizing.rowViewportHeight,
                    alignment: .top
                )
                .layoutPriority(0)
                .onAppear {
                    scrollSelectionIntoView(proxy)
                }
                .onChange(of: model.selectedStashIndex) { _, _ in
                    scrollSelectionIntoView(proxy)
                }
            }

            clearAllButton
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
        }
        .padding(CapturePanelLayout.stashPickerPadding)
        .frame(
            minHeight: sizing.minimumVisibleHeight,
            idealHeight: sizing.idealHeight,
            maxHeight: sizing.idealHeight,
            alignment: .topLeading
        )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(listAccessibilityLabel)
        .accessibilityHint(
            "Use arrows, Control-N, Control-P, Return, or a shown key to restore a canceled draft. "
                + "Press Shift-D to permanently remove all retained drafts from this app session."
        )
    }

    private var clearAllButton: some View {
        Button(role: .destructive) {
            model.clearCanceledDraftStashFromPicker()
        } label: {
            HStack(spacing: 8) {
                Text("Shift-D")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(
                        width: CapturePanelLayout.stashClearButtonKeyWidth,
                        height: CapturePanelLayout.stashClearButtonKeyHeight
                    )
                    .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.red.opacity(0.35), lineWidth: 0.5)
                    )
                    .accessibilityHidden(true)
                Text("Delete All")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CapturePanelLayout.stashClearButtonHorizontalPadding)
            .padding(.vertical, CapturePanelLayout.stashClearButtonVerticalPadding)
            .frame(height: CapturePanelLayout.stashClearButtonHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .accessibilityLabel("Shift-D Delete All")
        .accessibilityHint(
            "Permanently removes all retained canceled drafts from the current app session. "
                + "Lowercase d does not delete."
        )
    }

    private var sizing: CanceledDraftStashPickerHeightPolicy {
        CanceledDraftStashPickerHeightPolicy(entryCount: model.stashCount, displayScale: displayScale)
    }

    private var listAccessibilityLabel: String {
        let count = model.stashCount
        return "Canceled draft stash, \(count) \(count == 1 ? "entry" : "entries")"
    }

    private func scrollSelectionIntoView(_ proxy: ScrollViewProxy) {
        guard let entry = model.selectedStashEntry else {
            return
        }
        proxy.scrollTo(entry.id, anchor: .center)
    }
}

@available(macOS 26.0, *)
private struct CanceledDraftStashRow: View {
    let entry: CanceledDraftEntry
    let accelerator: String
    let selected: Bool
    let now: Date
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var preview: String {
        CanceledDraftStash.previewLine(for: entry.text, maxCharacters: 96)
    }

    private var metadata: String {
        CanceledDraftStash.metadataDescription(for: entry, now: now)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(accelerator)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 24, height: 22)
                .background(.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.secondary.opacity(0.28), lineWidth: 0.5)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(preview)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .frame(minHeight: CapturePanelLayout.stashRowContentMinimumHeight, alignment: .topLeading)
        .padding(.horizontal, CapturePanelLayout.stashRowHorizontalPadding)
        .padding(.vertical, CapturePanelLayout.stashRowVerticalPadding)
        .background(selectionFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Canceled draft \(accelerator), \(preview), \(metadata)")
        .accessibilityHint("Press \(accelerator) or Return to restore this draft.")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var selectionFill: Color {
        guard selected else {
            return .clear
        }
        return Color.accentColor.opacity(colorSchemeContrast == .increased ? 0.32 : 0.18)
    }
}

@available(macOS 26.0, *)
private struct CompletionList: View {
    @ObservedObject var model: CapturePanelModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if model.completionResponse?.context == "task" {
                        taskGroup(title: "Ready to use", rows: taskRows(requiresBlockID: false))
                        taskGroup(title: "Needs block ID", rows: taskRows(requiresBlockID: true))
                    } else {
                        ForEach(indexedCandidates) { row in
                            completionRow(row)
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
        .accessibilityLabel(listAccessibilityLabel)
    }

    private var listAccessibilityLabel: String {
        guard let candidates = model.completionResponse?.candidates, !candidates.isEmpty else {
            return "Completion suggestions"
        }
        let contextLabel = model.rowContent(for: candidates[0]).contextLabel
        let noun = contextLabel.isEmpty ? "Completion" : contextLabel
        let count = candidates.count
        return "\(noun) suggestions, \(count) result\(count == 1 ? "" : "s")"
    }

    private var indexedCandidates: [IndexedCompletionCandidate] {
        (model.completionResponse?.candidates ?? []).enumerated().map {
            IndexedCompletionCandidate(index: $0.offset, candidate: $0.element)
        }
    }

    private func taskRows(requiresBlockID: Bool) -> [IndexedCompletionCandidate] {
        indexedCandidates.filter { $0.candidate.requiresBlockID == requiresBlockID }
    }

    @ViewBuilder
    private func taskGroup(title: String, rows: [IndexedCompletionCandidate]) -> some View {
        if !rows.isEmpty {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                completionRow(row)
            }
        }
    }

    private func completionRow(_ row: IndexedCompletionCandidate) -> some View {
        CompletionRow(
            content: model.rowContent(for: row.candidate),
            selected: row.index == model.selectedCompletionIndex
        )
        .id(row.index)
        .onTapGesture {
            model.selectedCompletionIndex = row.index
            model.acceptSelectedCompletion()
        }
    }

    private struct IndexedCompletionCandidate: Identifiable {
        let index: Int
        let candidate: CaptureCompletionCandidate

        var id: Int { index }
    }
}

@available(macOS 26.0, *)
private struct CompletionRow: View {
    let content: CompletionRowContent
    let selected: Bool
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// Character budget for the secondary (path) line before it truncates from the middle,
    /// chosen to comfortably fit the list's fixed 430pt width alongside any badges.
    private static let secondaryMaxLength = 46

    private var tint: Color {
        CaptureEditorPalette.color(for: content.category)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: content.symbolName)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    emphasizedPrimaryText
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    if !content.contextLabel.isEmpty {
                        Text(content.contextLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                }

                if content.secondaryText != nil || !content.badges.isEmpty {
                    HStack(spacing: 6) {
                        if let secondaryText = content.secondaryText {
                            Text(middleTruncatedPath(secondaryText, maxLength: Self.secondaryMaxLength))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        ForEach(Array(content.badges.enumerated()), id: \.offset) { _, badge in
                            Text(badge)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(badge == "Add ID" ? Color.clear : tint.opacity(0.15), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(badge == "Add ID" ? tint.opacity(0.55) : Color.clear, lineWidth: 0.7)
                                )
                                .foregroundStyle(tint)
                        }
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(selectionFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint(content.accessibilityHint)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var selectionFill: Color {
        guard selected else {
            return .clear
        }
        return tint.opacity(colorSchemeContrast == .increased ? 0.32 : 0.18)
    }

    private var emphasizedPrimaryText: Text {
        guard let matchRange = content.primaryMatchRange else {
            return Text(content.primaryText)
        }

        let characters = Array(content.primaryText)
        guard matchRange.lowerBound >= 0, matchRange.upperBound <= characters.count else {
            return Text(content.primaryText)
        }

        let prefix = String(characters[0..<matchRange.lowerBound])
        let matched = String(characters[matchRange.lowerBound..<matchRange.upperBound])
        let suffix = String(characters[matchRange.upperBound...])

        return Text(prefix) + Text(matched).fontWeight(.semibold) + Text(suffix)
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
        let captures = success.normalizedCaptures
        if captures.count > 1 {
            Text("\(captures.count) captures")
                .fontWeight(.semibold)
                .accessibilityLabel("\(captures.count) capture items")
        }

        ForEach(Array(captures.enumerated()), id: \.offset) { index, capture in
            if index > 0 {
                Divider()
            }
            previewItem(capture, index: index, total: captures.count)
        }

        if model.livePreviewUsesLiteralClipboard {
            Text("Clipboard markers stay literal in live preview")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func previewItem(
        _ success: CaptureCommandSuccess,
        index: Int,
        total: Int
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if total > 1 {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

        // `previewBlockLines` is the parent line, the authored children, the clipboard
        // children, and the schedule log in the exact order Bob writes them, already
        // carrying the target note's indentation.
        let blockLines = success.previewBlockLines
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(blockLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(previewAccessibilityLabel(for: success, index: index, total: total))

        Text(success.relativeTarget)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .textSelection(.enabled)
    }

    private func previewAccessibilityLabel(
        for success: CaptureCommandSuccess,
        index: Int,
        total: Int
    ) -> String {
        let position = total > 1 ? "Item \(index + 1) of \(total), " : ""
        let destination = success.routeLabel.isEmpty ? success.relativeTarget : success.routeLabel
        return "\(position)\(success.kind), \(destination), \(success.previewBlockLines.joined(separator: ", "))"
    }
}
