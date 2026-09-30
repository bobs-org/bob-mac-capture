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
    /// Floor for the live-preview card. The pane always takes its natural height;
    /// this only keeps a tiny preview or the loading spinner from collapsing.
    static let previewMinimumHeight: CGFloat = 92

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
    /// Top safe-area inset imposed by the full-size-content panel's titlebar strip.
    /// Read from AppKit and published through the model; 0 until the controller
    /// observes a panel.
    var safeAreaTopInset: CGFloat = 0
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

    /// Persistent chrome excluding the editor: titlebar safe-area inset, titlebar
    /// drag inset, inter-section spacing, footer, and root padding. Shared with
    /// `CaptureEditorHeightBudget` so the editor ceiling and the panel metrics
    /// agree on spacing count.
    func nonEditorChromeHeight(footerHeight: CGFloat, hasAuxiliary: Bool) -> CGFloat {
        let spacingCount = hasAuxiliary ? 2 : 1
        return sanitizedHeight(safeAreaTopInset)
            + titlebarDragInset
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

/// Steady-height policy for the live-preview card. Every keystroke replaces the
/// rendered card with a spinner; without a hold the pane would collapse to its
/// floor and regrow on each keystroke, visibly resizing the window. While
/// loading, the pane keeps its last settled height so the window stays steady.
struct CapturePreviewPaneHeightPolicy: Equatable {
    /// Returns the pane's minimum height for the given preview state and the
    /// last settled pane height. `.ready` and `.failed` always return the
    /// floor; `.loading` holds the settled height when it exceeds the floor.
    static func minimumHeight(
        for state: CapturePreviewState,
        settledHeight: CGFloat?
    ) -> CGFloat {
        let floor = CapturePanelLayout.previewMinimumHeight
        switch state {
        case .loading:
            guard let settledHeight, settledHeight.isFinite else {
                return floor
            }
            return max(floor, settledHeight)
        case .idle, .ready, .failed:
            return floor
        }
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
            .onChange(of: model.pickerVisible) { _, _ in
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
            .onChange(of: model.titlebarSafeAreaInset) { _, _ in
                reportContentMetrics()
            }
            .onChange(of: measuredFooterHeight) { _, _ in
                reportContentMetrics()
            }
    }

    private var editorHeightPolicy: CaptureEditorHeightPolicy {
        let contentPolicy = CapturePanelContentHeightPolicy(
            safeAreaTopInset: model.titlebarSafeAreaInset,
            displayScale: displayScale
        )
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
            ZStack(alignment: .topLeading) {
                AutosizingCaptureEditor(
                    model: model,
                    selection: $model.editorSelection,
                    focus: $focusedControl,
                    heightPolicy: editorHeightPolicy
                )
                .opacity(model.pickerVisible ? 0.5 : 1)
                .allowsHitTesting(!model.pickerVisible)
                if model.pickerVisible {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.cancelPicker()
                        }
                        .accessibilityLabel("Cancel task picker")
                        .accessibilityHint("Cancels picking and returns to the editor.")
                }
            }
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

            if model.pickerVisible {
                CapturePickerKeyHints(source: model.picker?.source ?? .activeTask)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        updateMeasuredFooterHeight(height)
                    }
            } else {
                CapturePanelFooter(model: model)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        updateMeasuredFooterHeight(height)
                    }
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
            || model.inlinePromptVisible
            || model.pickerVisible
            || model.pickerChipVisible
            || model.completionVisible
            || model.destinationSummary != nil
            || model.errorMessage != nil
            || model.previewState != .idle
    }

    @ViewBuilder
    private var auxiliaryRegion: some View {
        if model.pickerVisible {
            CapturePickerCard(model: model)
                .layoutPriority(0)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    updateMeasuredAuxiliaryContentHeight(height)
                }
        } else if model.isStashPickerPresented {
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
            if model.pickerChipVisible {
                CapturePickerChip(model: model)
                    .id(AuxiliarySection.pickerChip)
            }
            if model.taskIDPromptVisible {
                TaskIDPromptCard(model: model)
                    .frame(width: 430)
                    .padding(.leading, 14)
                    .layoutPriority(0)
                    .id(AuxiliarySection.taskIDPrompt)
            } else if model.pomodoroNamePromptVisible {
                PomodoroNamePromptCard(model: model)
                    .frame(width: 430)
                    .padding(.leading, 14)
                    .layoutPriority(0)
                    .id(AuxiliarySection.pomodoroNamePrompt)
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
                    // A strict plan-budget refusal carries
                    // `code == "plan_theme_cap_exceeded"`: the message names
                    // the themes, and this hint names the gestures that keep
                    // the plan closed.
                    if model.errorCode == "plan_theme_cap_exceeded" {
                        Text("Queue it with ^, keep it this week with #now, or defer with p:<N>.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityLabel(
                                "Plan hint: Queue it with ^, keep it this week with #now, or defer with p:<N>."
                            )
                    }
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

        let policy = CapturePanelContentHeightPolicy(
            safeAreaTopInset: model.titlebarSafeAreaInset,
            displayScale: displayScale
        )
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
        // Only `.editor` is resolved by SwiftUI. Prompt and filter targets are
        // owned by AppKit (`BlockIDField` / `PomodoroNameField` /
        // `CapturePickerFilterField`), so SwiftUI's stored focus value is cleared
        // while the AppKit field claims first responder directly.
        focusedControl = request.target == .editor ? .editor : nil
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

        if model.pickerVisible {
            let explicit = CapturePickerHeightPolicy(
                visibleRowBudget: model.picker?.visibleRowBudget ?? 4,
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
        case pomodoroNamePrompt
        case completion
        case pickerChip
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
            .disabled(model.isSubmitting || model.inlinePromptVisible || model.pickerVisible)
            Button("Discard") {
                model.discardDraftAndClose()
            }
            .help("Permanently discards the draft and closes the panel.")
            .disabled(
                !model.hasDraft
                    || model.isSubmitting
                    || model.taskIDPrompt?.isSaving == true
                    || model.pomodoroNamePrompt?.isSaving == true
                    || model.pickerVisible
            )
            Button("Preview") {
                model.preview()
            }
            .help("Resolves the current clipboard/history and shows the exact destination without writing anything.")
            .disabled(
                !model.hasDraft || model.isSubmitting || model.isPreviewing || model.inlinePromptVisible
                    || model.pickerVisible
            )
            Button(model.primaryActionTitle) {
                model.submit(openAfterCapture: false)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                !model.hasDraft || model.isSubmitting || model.inlinePromptVisible
                    || model.pickerVisible || model.isClosePending
            )
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
                    .onReceive(model.$editorSelection.dropFirst()) { selection in
                        model.editorSelectionDidChange(to: selection)
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
            // transaction. Its `focus.wrappedValue != target` guard also makes it a
            // no-op if an eager mirror already stored the target, so this remains an
            // editor-specific bridge rather than a general focus repair.
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
    @State private var blockIDFieldIsFocused = false

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
                    BlockIDField(
                        text: Binding(
                            get: { model.taskIDPrompt?.authoredID ?? "" },
                            set: { model.updateTaskIDPromptBlockID($0) }
                        ),
                        isEnabled: !prompt.isSaving,
                        focusRequest: model.focusRequest,
                        focusDidChange: { blockIDFieldIsFocused = $0 }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 6)
                }
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            blockIDFieldIsFocused ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.24),
                            lineWidth: blockIDFieldIsFocused ? 1 : 0.5
                        )
                )
                .onDisappear {
                    blockIDFieldIsFocused = false
                }

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
private struct PomodoroNamePromptCard: View {
    @ObservedObject var model: CapturePanelModel
    @State private var nameFieldIsFocused = false

    private var prompt: CapturePomodoroNamePromptState? {
        model.pomodoroNamePrompt
    }

    var body: some View {
        if let prompt {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Name Pomodoro", systemImage: "square.and.pencil")
                        .font(.headline)
                    Spacer(minLength: 8)
                    if prompt.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                pomodoroSummary(prompt)

                HStack(spacing: 0) {
                    Text("\u{2014}")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(CaptureEditorPalette.color(for: .section))
                        .padding(.leading, 8)
                    PomodoroNameField(
                        text: Binding(
                            get: { model.pomodoroNamePrompt?.authoredName ?? "" },
                            set: { model.updatePomodoroNamePromptName($0) }
                        ),
                        isEnabled: !prompt.isSaving,
                        focusRequest: model.focusRequest,
                        focusDidChange: { nameFieldIsFocused = $0 }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 6)
                }
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            nameFieldIsFocused ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.24),
                            lineWidth: nameFieldIsFocused ? 1 : 0.5
                        )
                )
                .onDisappear {
                    nameFieldIsFocused = false
                }

                if let canonical = model.pomodoroNamePromptCanonicalName {
                    Text("Saves as \(canonical)")
                        .font(.caption)
                        .foregroundStyle(CaptureEditorPalette.color(for: .section))
                }

                Text("Letters, numbers, spaces, and & ' ( ) , . / -")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = prompt.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityLabel("Pomodoro name error: \(error)")
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        model.cancelPomodoroNamePrompt()
                    }
                    .disabled(prompt.isSaving)
                    Button("Name & Select") {
                        model.submitPomodoroNamePrompt()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.pomodoroNamePromptCanSubmit)
                }
            }
            .padding(10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 12, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Name Pomodoro")
        }
    }

    private func pomodoroSummary(_ prompt: CapturePomodoroNamePromptState) -> some View {
        let candidate = prompt.candidate
        let childCount = candidate.childCount ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let timeRange = candidate.timeRange, !timeRange.isEmpty {
                    Text(timeRange)
                        .font(.system(.callout, design: .monospaced))
                } else {
                    Text(candidate.placeholder ? "Planned" : "Unnamed Pomodoro")
                        .font(.system(.callout, design: .monospaced))
                }
            }
            Text(childCount == 0 ? "Empty" : "\(childCount) links")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
                + "Press Shift-D to permanently remove all retained drafts."
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
            "Permanently removes all retained canceled drafts. "
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
                    // Ready-to-use / Needs-block-ID grouping is specific to the `task`
                    // context. Task-section rows stay a plain ungrouped list.
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
                            badgeView(badge)
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

    private func badgeView(_ badge: String) -> some View {
        let fill: Color = badgeFill(for: badge)
        let stroke: Color = isOutlinedBadge(badge) ? tint.opacity(0.55) : Color.clear
        let foreground: Color = isOverCapBadge(badge) ? Color.red : tint
        return Text(badge)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fill, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(stroke, lineWidth: 0.7)
            )
            .foregroundStyle(foreground)
    }

    private func badgeFill(for badge: String) -> Color {
        if isOutlinedBadge(badge) {
            return Color.clear
        }
        if isOverCapBadge(badge) {
            return Color.red.opacity(0.15)
        }
        return tint.opacity(0.15)
    }

    private func isOutlinedBadge(_ badge: String) -> Bool {
        badge == "Add ID" || badge == "Name it"
    }

    /// A `pomodoro_name` create row that would push the plan past its theme
    /// cap carries an `after/cap` badge (e.g. `4/3`); it renders red. No
    /// other completion badge uses the bare `N/M` shape (`H2`, `2 items`,
    /// `^id` all differ), so the shape alone identifies it.
    private func isOverCapBadge(_ badge: String) -> Bool {
        let parts = badge.split(separator: "/")
        guard parts.count == 2,
              let after = Int(parts[0]),
              let cap = Int(parts[1])
        else {
            return false
        }
        return after > cap
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
struct PreviewPane: View {
    @ObservedObject var model: CapturePanelModel
    @State private var settledPaneHeight: CGFloat?

    private var paneMinimumHeight: CGFloat {
        CapturePreviewPaneHeightPolicy.minimumHeight(
            for: model.previewState,
            settledHeight: settledPaneHeight
        )
    }

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
            minHeight: paneMinimumHeight,
            alignment: .topLeading
        )
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            guard height.isFinite, height > 0 else {
                return
            }
            switch model.previewState {
            case .ready, .failed:
                settledPaneHeight = height
            case .idle, .loading:
                break
            }
        }
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
        if let globalDestination = success.globalDestination {
            Text("All items \u{2192} \(globalDestination.scopeSummary)")
                .fontWeight(.semibold)
                .accessibilityLabel("All items to \(globalDestination.scopeSummary)")
        }

        // The plan-budget meter is batch-level: `plan_budget` lives on the
        // outer success, not per item. Render it once above the items from
        // Bob's resolved object — no Swift-side ledger math.
        if let budget = CapturePlanBudgetPresentation(capture: success) {
            planBudgetMeterRow(budget)
        } else if captures.count == 1, let first = captures.first,
                  let budget = CapturePlanBudgetPresentation(capture: first)
        {
            planBudgetMeterRow(budget)
        }

        ForEach(Array(captures.enumerated()), id: \.offset) { index, capture in
            if index > 0 {
                Divider()
            }
            previewItem(
                capture,
                index: index,
                total: captures.count,
                globalDestination: success.globalDestination
            )
        }

        if model.livePreviewUsesLiteralClipboard {
            Text("Clipboard markers stay literal in live preview")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    /// The two plan-budget meter capsules (`Themes 3/3`, `Links 8/10`),
    /// green within the cap and red over it, plus the `+N NAME` delta chip
    /// whenever the batch grew the themes meter and the orange warning
    /// captions. Straight from Bob's resolved `plan_budget` object.
    @ViewBuilder
    private func planBudgetMeterRow(_ budget: CapturePlanBudgetPresentation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(budget.themesCapsuleText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (budget.themesOverCap ? Color.red : Color.green).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(budget.themesOverCap ? Color.red : Color.green)
                Text(budget.linksCapsuleText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (budget.linksOverCap ? Color.red : Color.green).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(budget.linksOverCap ? Color.red : Color.green)
                if let delta = budget.deltaChipText {
                    Text(delta)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(budget.warningTexts.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan budget: \(budget.accessibilitySummary)")
    }

    /// The destination row above the preview items (`→ GOALS · next up`,
    /// `→ running GOALS 0945–1015`, `→ new Pomodoro BOB`), straight from
    /// Bob's resolved `pomodoro_link_destination` and its plan-budget
    /// `role`. Nil when Bob reported no destination.
    @ViewBuilder
    private func planDestinationRow(for capture: CaptureCommandSuccess) -> some View {
        if let text = CapturePlanBudgetPresentation.destinationRowText(
            for: capture.pomodoroLinkDestination
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Destination: \(text)")
        }
    }

    @ViewBuilder
    private func previewItem(
        _ success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        globalDestination: CaptureGlobalDestination?
    ) -> some View {
        let isLocalOverride = globalDestination.map {
            !captureUsesGlobalDestination(success, $0)
        } ?? false
        // The destination row sits above the per-kind preview item, so every
        // link landing names where its Task Link went without disturbing the
        // existing card below.
        planDestinationRow(for: success)
        if let close = CapturePomodoroClosePresentation(capture: success) {
            closePreviewItem(close, success: success, index: index, total: total)
        } else if CapturePomodoroStartPresentation.isSessionStart(success),
                  let start = CapturePomodoroStartPresentation(capture: success)
        {
            startPreviewItem(start, success: success, index: index, total: total)
        } else if let toggle = CaptureTogglePresentation(capture: success) {
            togglePreviewItem(
                toggle,
                success: success,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            )
        } else if let link = CapturePomodoroLinkPresentation(capture: success) {
            linkPreviewItem(
                link,
                success: success,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            )
        } else {
            standardPreviewItem(
                success,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            )
        }
    }

    @ViewBuilder
    private func closePreviewItem(
        _ close: CapturePomodoroClosePresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int
    ) -> some View {
        // The close card renders Bob's resolved `pomodoro_close` object exactly
        // as the presentation words it: no Swift-side clock or ledger math.
        // The locator truncates first at narrow widths, so the task text and
        // transition always stay legible.
        let sessionTint = CaptureEditorPalette.color(for: .pomodoroStart)
        // A pending list previews the trimmed draft: the card stays live but
        // dimmed, and Close is disabled until a task number is typed.
        let isPending = model.closePendingText != nil
        let showsBadges = close.taskRows.contains { $0.index != nil }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if total > 1 {
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "stop.circle.fill")
                    .foregroundStyle(sessionTint)
                    .accessibilityHidden(true)
                Text(close.title)
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    Text(close.sessionPlannedText)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                    if let decrement = close.sessionDecrementText {
                        Text(" \(decrement)")
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(sessionTint)
                    }
                }
                .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(close.destinationText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(close.timingText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(closeTimingChipColor(close.timingTone))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            if let viaText = close.viaText {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(
                        systemName: close.variant == .newTask
                            ? "plus.circle" : "link"
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    Text(viaText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            if close.taskRows.isEmpty {
                Text(close.emptyText)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(close.visibleTaskRows.enumerated()), id: \.offset) {
                        _, row in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if showsBadges {
                                    closeNumberBadge(for: row)
                                }
                                closeTaskGlyph(for: row)
                                Text(row.taskText)
                                    .strikethrough(row.isStruck)
                                    .layoutPriority(1)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                                if let tag = row.tag {
                                    Text(tag)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Text(row.locatorText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .textSelection(.enabled)
                            }
                            ForEach(
                                Array(row.workLogPreviews.enumerated()),
                                id: \.offset
                            ) { _, entry in
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                    Text(entry)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .textSelection(.enabled)
                                }
                            }
                            if let warning = row.warning {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                        .opacity(row.isDimmed ? 0.5 : 1)
                    }
                    if close.overflowTaskCount > 0 {
                        Text("+\(close.overflowTaskCount) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // The teaching hint (before a selection is typed), the outcome
            // summary (after), or the pending notice (while a list dangles):
            // one caption row under the task rows.
            if let pending = model.closePendingText {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "number.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(pending)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else if let summary = close.selectionSummary {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "list.number")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else if let hint = close.teachingHint {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "number.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    // Example tokens share the editor span colors of the
                    // badges they select; prose stays secondary.
                    Text(
                        hint.tokens.map { token in
                            var part = AttributedString(token.text)
                            part.foregroundColor = token.category == .neutral
                                ? .secondary
                                : CaptureEditorPalette.color(for: token.category)
                            return part
                        }.reduce(AttributedString()) { $0 + $1 }
                    )
                    .font(.caption)
                    .textSelection(.enabled)
                }
            }

            if let notesText = close.notesText {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(notesText)
                        .foregroundStyle(.secondary)
                }
            }

            if let nextText = close.nextText {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(nextText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            ForEach(Array(close.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isPending ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isPending ? "\(close.accessibilitySummary), \(model.closePendingText ?? "")"
                : close.accessibilitySummary
        )
    }

    /// The fixed-width leading number badge for a close row: a filled
    /// `N.circle` when the row is listed, an open one otherwise, tinted by
    /// outcome (in progress orange, complete green, deferred secondary) and
    /// dimmed when unlisted. Numbers above 50 fall back to monospaced digits
    /// in a capsule; unnumbered rows get an equal-width clear spacer so text
    /// stays aligned.
    @ViewBuilder
    private func closeNumberBadge(
        for row: CapturePomodoroClosePresentation.TaskRow
    ) -> some View {
        let badgeWidth: CGFloat = 26
        if row.usesNumericBadgeFallback, let index = row.index {
            Text("\(index)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(closeOutcomeColor(for: row))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .frame(width: badgeWidth + 14, alignment: .center)
                .opacity(row.isDimmed ? 0.5 : 1)
                .accessibilityHidden(true)
        } else if let symbolName = row.badgeSymbolName {
            Image(systemName: symbolName)
                .foregroundStyle(closeOutcomeColor(for: row))
                .frame(width: badgeWidth, alignment: .center)
                .opacity(row.isDimmed ? 0.5 : 1)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: badgeWidth, height: 1)
                .accessibilityHidden(true)
        }
    }

    private func closeOutcomeColor(
        for row: CapturePomodoroClosePresentation.TaskRow
    ) -> Color {
        switch row.outcome {
        case .inProgress:
            return .orange
        case .complete:
            return .green
        case .deferred, nil:
            return .secondary
        }
    }

    @ViewBuilder
    private func closeTaskGlyph(
        for row: CapturePomodoroClosePresentation.TaskRow
    ) -> some View {
        switch row.glyph {
        case .transition:
            Text(row.transitionText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        case .deferred:
            Image(systemName: "arrow.uturn.forward")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .struck:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .embedded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(row.outcome == .complete ? .green : .secondary)
                .accessibilityHidden(true)
        case .unresolved:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
        case .neutral:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func closeTimingChipColor(
        _ tone: CapturePomodoroClosePresentation.TimingTone
    ) -> Color {
        switch tone {
        case .early:
            return .orange
        case .onTime:
            return .green
        case .over:
            return .secondary
        }
    }

    @ViewBuilder
    private func startPreviewItem(
        _ start: CapturePomodoroStartPresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int
    ) -> some View {
        // The start card renders Bob's resolved `pomodoro_start` object exactly
        // as the presentation words it: no Swift-side clock or ledger math. It
        // is the visual sibling of the close card — a play glyph answering its
        // stop glyph — with the session, the day-file destination, and the
        // queued Task Links Bob reported. The locator truncates first at narrow
        // widths, so the task text always stays legible.
        let sessionTint = CaptureEditorPalette.color(for: .pomodoroStart)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if total > 1 {
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(sessionTint)
                    .accessibilityHidden(true)
                Text(start.title)
                    .fontWeight(.semibold)
                // A created session carries a small pink New/Created capsule
                // next to the title so the fresh entry reads at a glance.
                if let badge = start.createdBadgeText {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.pink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.pink.opacity(0.15), in: Capsule())
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 4)
                Text(start.sessionText)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(start.destinationText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            // A bare `=`/`=<X>` start teaches `#name` under the destination,
            // in the close card's teaching-hint style: the example token
            // shares the editor `pomodoro_name` span color, prose stays
            // secondary. Named starts show no hint.
            if let hint = start.teachingHint {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "number.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(startTeachingHintText(hint))
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            if start.taskRows.isEmpty {
                Text(start.emptyText)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(start.visibleTaskRows.enumerated()), id: \.offset) {
                        _, row in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                startTaskGlyph(for: row)
                                Text(row.taskText)
                                    .layoutPriority(1)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                                Spacer(minLength: 4)
                                Text(row.locatorText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .textSelection(.enabled)
                            }
                            if let warning = row.warning {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                                    .accessibilityLabel("Warning: \(warning)")
                            }
                        }
                    }
                    if start.overflowTaskCount > 0 {
                        Text("+\(start.overflowTaskCount) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(success.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(start.accessibilitySummary)
    }

    /// Tints the `#name` example in the start-card teaching hint like the
    /// editor's `pomodoro_name` span; prose stays secondary, matching the
    /// close card's hint rendering.
    private func startTeachingHintText(_ hint: String) -> AttributedString {
        let marker = "#name"
        guard let range = hint.range(of: marker) else {
            return AttributedString(hint)
        }
        var leading = AttributedString(String(hint[..<range.lowerBound]))
        leading.foregroundColor = .secondary
        var token = AttributedString(String(hint[range]))
        token.foregroundColor = CaptureEditorPalette.color(for: .section)
        var trailing = AttributedString(String(hint[range.upperBound...]))
        trailing.foregroundColor = .secondary
        return leading + token + trailing
    }

    @ViewBuilder
    private func startTaskGlyph(
        for row: CapturePomodoroStartPresentation.TaskRow
    ) -> some View {
        switch row.glyph {
        case .ready:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .next:
            Image(systemName: "circle.inset.filled")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .inProgress:
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .other:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .unresolved:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func standardPreviewItem(
        _ success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if total > 1 {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(success.routeLabel.isEmpty ? success.relativeTarget : success.routeLabel)
                .fontWeight(.semibold)
            if isLocalOverride {
                Text("local override")
                    .foregroundStyle(.secondary)
            }
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

        // The atomic-start session comes straight from Bob's resolved `pomodoro_start`
        // object (dry-run JSON for preview, committed JSON after capture). No Swift-side
        // clock or ledger math: show the 5-minute-rounded start/end, duration, and
        // created-entry state exactly as Bob reported them.
        if let pomodoroStart = CapturePomodoroStartPresentation(capture: success) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(pomodoroStart.sessionText)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                Text(pomodoroStart.destinationText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(pomodoroStart.accessibilitySummary)
        }

        // The duration adjustment comes straight from Bob's resolved
        // `pomodoro_adjust` object (dry-run JSON for preview, committed JSON
        // after capture). No Swift-side clock or ledger math: show the
        // before-to-after timing, signed minute effect, and target line exactly
        // as Bob reported them.
        if let pomodoroAdjust = CapturePomodoroAdjustPresentation(capture: success) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "timer.badge.plus")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(pomodoroAdjust.sessionText)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                Text(pomodoroAdjust.destinationText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(pomodoroAdjust.accessibilitySummary)
        }

        // The whole-session shift comes straight from Bob's resolved
        // `pomodoro_shift` object (dry-run JSON for preview, committed JSON
        // after capture). No Swift-side clock or ledger math: show the
        // before-to-after timing, minute effect with direction, and target
        // line exactly as Bob reported them. The doubled chevron echoes the
        // doubled sign.
        if let pomodoroShift = CapturePomodoroShiftPresentation(capture: success) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: pomodoroShift.symbolName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(pomodoroShift.sessionText)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                Text(pomodoroShift.destinationText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(pomodoroShift.accessibilitySummary)
        }

        // A project note that links tasks into the Pomodoro names them from
        // Bob's resolved `project_note.task_links`: a link symbol, the
        // destination header, then one row per task showing its text and
        // `^id`. No Swift-side ledger math — only Bob's rows and wording.
        if let projectNote = CaptureProjectNotePresentation(capture: success) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(projectNote.headerText)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                }
                ForEach(Array(projectNote.linkedTasks.enumerated()), id: \.offset) { _, task in
                    Text("\(task.text) ^\(task.blockID)")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(projectNote.previewAccessibilitySummary)
        }

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
        .accessibilityLabel(previewAccessibilityLabel(
            for: success,
            index: index,
            total: total,
            isLocalOverride: isLocalOverride
        ))

        Text(success.relativeTarget)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func togglePreviewItem(
        _ toggle: CaptureTogglePresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if total > 1 {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(toggle.routeDestinationLabel)
                .fontWeight(.semibold)
            if isLocalOverride {
                Text("local override")
                    .foregroundStyle(.secondary)
            }
            Text(success.kind)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)

        VStack(alignment: .leading, spacing: 3) {
            Text(toggle.transitionText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            if let dayFileDestinationLabel = toggle.dayFileDestinationLabel {
                Text(dayFileDestinationLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            if let addedLinkText = toggle.addedLinkText {
                toggleLinkLine(prefix: "+", color: .green, text: addedLinkText)
            }
            if let removedLinksText = toggle.removedLinksText {
                toggleLinkLine(prefix: "\u{2212}", color: .red, text: removedLinksText)
            }
            if !toggle.chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(toggle.chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(togglePreviewAccessibilityLabel(
            for: toggle,
            success: success,
            index: index,
            total: total,
            isLocalOverride: isLocalOverride
        ))
    }

    @ViewBuilder
    private func linkPreviewItem(
        _ link: CapturePomodoroLinkPresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if total > 1 {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(link.routeDestinationLabel)
                .fontWeight(.semibold)
            if isLocalOverride {
                Text("local override")
                    .foregroundStyle(.secondary)
            }
            Text(success.kind)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)

        VStack(alignment: .leading, spacing: 3) {
            Text(link.transitionText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            if let dayFileDestinationLabel = link.dayFileDestinationLabel {
                Text(dayFileDestinationLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Text(link.ledgerText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            if !link.chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(link.chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(linkPreviewAccessibilityLabel(
            for: link,
            success: success,
            index: index,
            total: total,
            isLocalOverride: isLocalOverride
        ))

        // The atomic-start session comes straight from Bob's resolved
        // `pomodoro_start` object, exactly like the standard item row above: show
        // the 5-minute-rounded start/end, duration, and created-entry state as Bob
        // reported them.
        if let pomodoroStart = CapturePomodoroStartPresentation(capture: success) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(pomodoroStart.sessionText)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                Text(pomodoroStart.destinationText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(pomodoroStart.accessibilitySummary)
        }
    }

    private func toggleLinkLine(prefix: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(prefix)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func previewAccessibilityLabel(
        for success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> String {
        let position = total > 1 ? "Item \(index + 1) of \(total), " : ""
        let destination = success.routeLabel.isEmpty ? success.relativeTarget : success.routeLabel
        let override = isLocalOverride ? ", local override" : ""
        let startSummary = CapturePomodoroStartPresentation(capture: success)
            .map { ", \($0.accessibilitySummary)" } ?? ""
        let adjustSummary = CapturePomodoroAdjustPresentation(capture: success)
            .map { ", \($0.accessibilitySummary)" } ?? ""
        let shiftSummary = CapturePomodoroShiftPresentation(capture: success)
            .map { ", \($0.accessibilitySummary)" } ?? ""
        let closeSummary = CapturePomodoroClosePresentation(capture: success)
            .map { ", \($0.accessibilitySummary)" } ?? ""
        let projectNoteSummary = CaptureProjectNotePresentation(capture: success)
            .map { ", \($0.previewAccessibilitySummary)" } ?? ""
        return "\(position)\(success.kind), \(destination)\(override)\(startSummary)\(adjustSummary)\(shiftSummary)\(closeSummary)\(projectNoteSummary), \(success.previewBlockLines.joined(separator: ", "))"
    }

    private func togglePreviewAccessibilityLabel(
        for toggle: CaptureTogglePresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> String {
        let position = total > 1 ? "Item \(index + 1) of \(total), " : ""
        let override = isLocalOverride ? ", local override" : ""
        return "\(position)\(success.kind)\(override), \(toggle.previewAccessibilitySummary)"
    }

    private func linkPreviewAccessibilityLabel(
        for link: CapturePomodoroLinkPresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> String {
        let position = total > 1 ? "Item \(index + 1) of \(total), " : ""
        let override = isLocalOverride ? ", local override" : ""
        return "\(position)\(success.kind)\(override), \(link.previewAccessibilitySummary)"
    }
}
