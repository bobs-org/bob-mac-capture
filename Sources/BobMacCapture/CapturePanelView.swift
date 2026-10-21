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
    /// Template rows show a parent line, optional child, and metadata, so they
    /// are taller than stash rows. Five visible rows, then scroll.
    static let templateShelfRowContentMinimumHeight: CGFloat = 72
    static let templateShelfRowHeight = templateShelfRowContentMinimumHeight + stashRowVerticalPadding * 2
    static let templateShelfViewportHeight = stashListPadding * 2
        + templateShelfRowHeight * CGFloat(stashVisibleRows)
        + stashRowSpacing * CGFloat(stashVisibleRows - 1)
    static let templateShelfHintKeyHeight: CGFloat = 22
    static let templateShelfSlotDotSize: CGFloat = 7
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

struct SavedTemplateShelfPickerHeightPolicy: Equatable {
    var entryCount: Int
    var visibleRowLimit: Int = CapturePanelLayout.stashVisibleRows
    var displayScale: CGFloat = 1

    var visibleRowCount: Int {
        min(max(entryCount, 0), max(visibleRowLimit, 0))
    }

    var rowViewportHeight: CGFloat {
        let rows = visibleRowCount
        let rowHeight = CapturePanelLayout.templateShelfRowHeight * CGFloat(rows)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .onChange(of: model.isTemplateShelfPresented) { _, _ in
                measuredAuxiliaryContentHeight = 0
                reportContentMetrics()
            }
            .onChange(of: model.pickerVisible) { _, _ in
                measuredAuxiliaryContentHeight = 0
                reportContentMetrics()
            }
            .onChange(of: model.pullInChoiceVisible) { _, _ in
                measuredAuxiliaryContentHeight = 0
                reportContentMetrics()
            }
            .onChange(of: model.stashCount) { _, _ in
                reportContentMetrics()
            }
            .onChange(of: model.templateShelfCount) { _, _ in
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
            .onChange(of: model.agendaVisible) { oldVisible, newVisible in
                if oldVisible, !newVisible {
                    model.noteAgendaStoppedShowing()
                    measuredAuxiliaryContentHeight = 0
                }
                // When the agenda becomes visible the steady-state height
                // comes from the already-measured plan
                // (`currentAuxiliaryHeight`), not from a fresh geometry
                // callback: resetting to zero here would publish an
                // agenda height of zero while a positive-height plan owns
                // the region and clip the editor/footer until the next
                // callback fires (if one fires at all). Stale preview or
                // picker measurements are discarded structurally by the
                // plan-derived height, never reused as the agenda height.
                reportContentMetrics()
            }
            .onChange(of: model.agendaPlan) { _, _ in
                reportContentMetrics()
            }
            .onChange(of: model.similarTasks) { _, _ in
                reportContentMetrics()
            }
            .onChange(of: model.similarTasksParseItems) { _, _ in
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

            if model.pullInChoiceVisible {
                CapturePullInChoiceFooter(model: model)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        updateMeasuredFooterHeight(height)
                    }
            } else if model.pickerVisible {
                CapturePickerKeyHints(
                    source: model.picker?.source ?? .activeTask,
                    showOperatorHint: model.pickerFilterIsEmpty
                )
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        updateMeasuredFooterHeight(height)
                    }
            } else if model.isSimilarRowFocused {
                SimilarTasksFooterHints(model: model)
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
                    .overlay(alignment: .topTrailing) {
                        CaptureOpenHintCapsule(model: model)
                    }
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        updateMeasuredFooterHeight(height)
                    }
            }
        }
        .padding(.top, CapturePanelLayout.titlebarDragInset)
        .padding([.horizontal, .bottom], CapturePanelLayout.rootPadding)
        // Fill the host vertically and anchor the stack at the top: when
        // the host is transiently smaller than the content (budget
        // re-plan, screen change), oversized content must clip at the
        // bottom, never centre so the editor and footer are lost at both
        // ends (see `NSHostingView.sizingOptions` in the controller).
        .frame(
            minWidth: CapturePanelLayout.panelMinimumContentWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var hasAuxiliaryContent: Bool {
        model.isStashPickerPresented
            || model.isTemplateShelfPresented
            || model.inlinePromptVisible
            || model.pickerVisible
            || model.pickerChipVisible
            || model.completionVisible
            || model.destinationSummary != nil
            || model.errorMessage != nil
            || model.previewState != .idle
            || model.agendaVisible
            || model.pullInCapabilityNote != nil
            || model.relationCapabilityWarning != nil
            || model.pullInChoiceVisible
    }

    @ViewBuilder
    private var auxiliaryRegion: some View {
        if model.pullInChoiceVisible, let choice = model.pullInChoice {
            CapturePullInChoiceCard(model: model, choice: choice)
                .layoutPriority(0)
                .focused($focusedControl, equals: .pullInOfferList)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    updateMeasuredAuxiliaryContentHeight(height)
                }
        } else if model.pickerVisible {
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
        } else if model.isTemplateShelfPresented {
            SavedTemplateShelfPicker(model: model)
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
        } else if model.agendaVisible {
            agendaPane
        } else {
            auxiliaryScrollRegion
        }
    }

    @ViewBuilder
    private var agendaPane: some View {
        if let plan = model.agendaPlan, let presentation = model.agendaPresentation {
            if model.agendaHasLiveCountdown, model.panelVisible {
                TimelineView(.everyMinute) { context in
                    agendaContent(plan: plan, presentation: presentation)
                        .onChange(of: context.date) { _, _ in
                            model.refreshAgendaPlan()
                        }
                }
            } else {
                agendaContent(plan: plan, presentation: presentation)
            }
        }
    }

    private func agendaContent(
        plan: CaptureAgendaPlan,
        presentation: CaptureAgendaPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: CapturePanelLayout.sectionSpacing) {
            pullInCapabilityNotice
            CaptureAgendaPaneView(
                plan: plan,
                presentation: presentation,
                onExpand: { model.expandAgendaUnit($0) },
                onContentWidthChange: { width in
                    guard model.agendaContentWidth != width else {
                        return
                    }
                    model.agendaContentWidth = width
                }
            )
        }
        .layoutPriority(0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's Pomodoros")
        .opacity(model.agendaDimmed ? CaptureAgendaHold.dimmedOpacity : 1)
        .animation(agendaDimAnimation, value: model.agendaDimmed)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            updateMeasuredAuxiliaryContentHeight(height)
        }
    }

    private var agendaDimAnimation: Animation? {
        // Reduce Motion disables the fade; the dim still applies.
        reduceMotion ? nil : .easeOut(duration: CaptureAgendaHold.dimFadeSeconds)
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
            } else if model.relationLabelPromptVisible {
                RelationLabelPromptCard(model: model)
                    .frame(width: 430)
                    .padding(.leading, 14)
                    .layoutPriority(0)
                    .id(AuxiliarySection.relationLabelPrompt)
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
                        Text("Queue it with ^ or defer with $<N>.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityLabel(
                                "Plan hint: Queue it with ^ or defer with $<N>."
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
            pullInCapabilityNotice
        }
    }

    @ViewBuilder
    private var pullInCapabilityNotice: some View {
        if let note = model.pullInCapabilityNote {
            Label(note, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(note)
        }
        if let warning = model.relationCapabilityWarning {
            Label(warning, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(warning)
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
        // The controller derives the compact panel's top (the fixed
        // eye line) from the footer; publish it the way the screen
        // height and safe-area inset are published.
        if model.footerHeight != height {
            model.footerHeight = height
        }
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
        updateSimilarTasksFolded()
        onContentMetricsChange(metrics)
    }

    /// Fold every similar-tasks band before the auxiliary region would
    /// scroll. Heights come from fixed row metrics, so the comparison
    /// against the screen budget cannot oscillate.
    private func updateSimilarTasksFolded() {
        let items = SimilarTasksBandPolicy.visibleItems(
            in: model.similarTasks,
            parseItems: model.similarTasksParseItems
        )
        guard !items.isEmpty else {
            if model.similarTasksFolded {
                model.similarTasksFolded = false
            }
            return
        }
        let contentPolicy = CapturePanelContentHeightPolicy(
            safeAreaTopInset: model.titlebarSafeAreaInset,
            displayScale: displayScale
        )
        let persistent = contentPolicy.nonEditorChromeHeight(
            footerHeight: measuredFooterHeight,
            hasAuxiliary: true
        ) + measuredEditorHeight
        let screenLimit: CGFloat
        if let available = model.availableScreenHeight {
            screenLimit = max(1, available - 2 * CapturePanelLayout.panelScreenMargin)
        } else {
            screenLimit = CapturePanelLayout.panelMaximumContentHeight
        }
        let availableAuxiliary = max(0, screenLimit - persistent)
        let folded = SimilarTasksBandMetrics.shouldFold(
            items: items,
            currentlyFolded: model.similarTasksFolded,
            measuredAuxiliaryHeight: Double(measuredAuxiliaryContentHeight),
            availableAuxiliaryHeight: Double(availableAuxiliary)
        )
        if model.similarTasksFolded != folded {
            model.similarTasksFolded = folded
        }
    }

    private func applyFocusRequest(_ request: CapturePanelFocusRequest) {
        // Only `.editor` is resolved by SwiftUI. Prompt and filter targets are
        // owned by AppKit (`BlockIDField` / `PomodoroNameField` /
        // `CapturePickerFilterField`), so SwiftUI's stored focus value is cleared
        // while the AppKit field claims first responder directly.
        focusedControl = request.target == .editor || request.target == .pullInOfferList
            ? request.target : nil
    }

    private var currentAuxiliaryHeight: CapturePanelAuxiliaryHeight? {
        guard hasAuxiliaryContent else {
            return nil
        }

        if model.pullInChoiceVisible, let choice = model.pullInChoice {
            let policy = CapturePullInChoiceHeightPolicy(choice: choice, displayScale: displayScale)
            return CapturePanelAuxiliaryHeight(
                idealHeight: max(policy.idealHeight, measuredAuxiliaryContentHeight),
                minimumVisibleHeight: policy.minimumVisibleHeight
            )
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

        if model.isTemplateShelfPresented {
            let explicit = SavedTemplateShelfPickerHeightPolicy(
                entryCount: model.templateShelfCount,
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

        // While the agenda owns the auxiliary region, the reported
        // height is the authoritative shared viewport derived from the
        // already-measured plan (`CaptureAgendaViewport.paneHeight`),
        // exactly what `CaptureAgendaPaneView` renders. It is available
        // synchronously from the cached plan even when no new geometry
        // event fires, so first show and clear-to-blank never publish a
        // zero height while a positive-height plan owns the region. The
        // observed rendered height stays as a consistency signal only;
        // it never decides how much room the measured agenda receives,
        // and no stale preview measurement feeds this path.
        if model.agendaVisible {
            if let plan = model.agendaPlan {
                return .overflow(
                    idealHeight: CGFloat(
                        CaptureAgendaViewport.paneHeight(
                            planTotalHeight: plan.totalHeight,
                            budget: plan.budget
                        )
                    )
                )
            }
            return .overflow(idealHeight: measuredAuxiliaryContentHeight)
        }

        return .overflow(idealHeight: measuredAuxiliaryContentHeight)
    }

    private enum AuxiliarySection: Hashable {
        case stash
        case templateShelf
        case taskIDPrompt
        case pomodoroNamePrompt
        case relationLabelPrompt
        case completion
        case pickerChip
        case destination
        case error
        case preview
    }
}

@available(macOS 26.0, *)
private struct SimilarTasksFooterHints: View {
    @ObservedObject var model: CapturePanelModel

    var body: some View {
        HStack(spacing: 12) {
            Text(
                SimilarTasksBandPresentation.focusedFooterHint(
                    defaultAction: model.focusedSimilarDefaultAction()
                )
            )
            .font(.caption.monospaced())
            .foregroundStyle(.primary)
            Spacer(minLength: 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            SimilarTasksBandPresentation.focusedFooterHint(
                defaultAction: model.focusedSimilarDefaultAction()
            )
        )
    }
}

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
            ViewThatFits(in: .horizontal) {
                actionRow(includeOpenChip: true)
                actionRow(includeOpenChip: false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture actions")
    }

    private func actionRow(includeOpenChip: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if model.savedTemplatesFooterVisible {
                Button {
                    model.toggleTemplateShelf()
                } label: {
                    Label("Templates \(model.templateShelfCount)", systemImage: "square.stack.3d.down.right")
                }
                .help(
                    model.templateOrigin == nil
                        ? "Reuse a saved @@template: draft (Control-T). Type @@@ to start a new one."
                        : "1 template is in this draft; it returns when you capture or discard"
                )
                .disabled(model.isSubmitting || model.inlinePromptVisible || model.pickerVisible)
            }
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
            if includeOpenChip, model.openHintChipVisible {
                CaptureOpenHintChip(model: model)
            }
            Button(model.primaryActionTitle) {
                model.submit(openAfterCapture: false)
            }
            .keyboardShortcut(.defaultAction)
            .tint(model.primaryActionIsOverride ? .orange : nil)
            .disabled(!model.primaryActionEnabled)
        }
    }
}

@available(macOS 26.0, *)
private struct CaptureOpenHintChip: View {
    @ObservedObject var model: CapturePanelModel

    private var presentation: CaptureOpenHintPresentation {
        model.openHintPresentation
    }

    var body: some View {
        Button {
            model.submit(openAfterCapture: true)
        } label: {
            HStack(spacing: 4) {
                Text("⌃↩")
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        .background.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                Text("Open")
                    .font(.caption)
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(model.openHintRevealed ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(presentation.helpText)
        .accessibilityLabel(presentation.accessibilityLabel)
        .disabled(!model.primaryActionEnabled)
    }
}

@available(macOS 26.0, *)
private struct CaptureOpenHintCapsule: View {
    @ObservedObject var model: CapturePanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: CaptureOpenHintPresentation {
        model.openHintPresentation
    }

    private var revealed: Bool {
        model.openHintChipVisible && model.openHintRevealed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Opens in Obsidian")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(presentation.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Image(systemName: row.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(row.label)
                        .font(.caption)
                    if let detail = row.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let overflowText = presentation.overflowText {
                Text(overflowText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 12, y: 6)
        .fixedSize()
        .alignmentGuide(.top) { $0[.bottom] }
        .offset(y: reduceMotion || !revealed ? 0 : -4)
        .opacity(revealed ? 1 : 0)
        .animation(.easeInOut(duration: 0.16), value: revealed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

                if isIDLinkMode, !prompt.linkSuggestions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(prompt.linkSuggestions, id: \.self) { suggestion in
                            Button {
                                model.updateTaskIDPromptBlockID(suggestion)
                            } label: {
                                Text("✦ \(suggestion)")
                                    .font(.caption)
                            }
                            .buttonStyle(.link)
                            .disabled(prompt.isSaving)
                        }
                    }
                }

                if isIDLinkMode {
                    linkInsertsText(for: prompt)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                    Button(linkSubmitTitle(for: prompt)) {
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

    private var isTaskLink: Bool {
        guard let prompt else {
            return false
        }
        if case .taskLink = prompt.purpose {
            return true
        }
        return false
    }

    private var isDependencyPrompt: Bool {
        guard let prompt else {
            return false
        }
        if case .dependency = prompt.purpose {
            return true
        }
        if case .blockedTask = prompt.purpose {
            return true
        }
        if case .relation = prompt.purpose {
            return true
        }
        return false
    }

    private var isParentTaskPickerPrompt: Bool {
        guard let prompt else {
            return false
        }
        if case .parentTaskPicker = prompt.purpose {
            return true
        }
        return false
    }

    private var isTaskCompletePrompt: Bool {
        guard let prompt else {
            return false
        }
        if case .taskComplete = prompt.purpose {
            return true
        }
        return false
    }

    /// Either link-mode prompt (task-link, dependency, Complete, or
    /// parent-task card): all show suggestion chips and the inserts line.
    private var isIDLinkMode: Bool {
        isTaskLink || isDependencyPrompt || isTaskCompletePrompt || isParentTaskPickerPrompt
    }

    private func linkSubmitTitle(for prompt: CaptureTaskIDPromptState) -> String {
        switch prompt.purpose {
        case .taskLink(_, _, _, let followUp, _):
            switch followUp {
            case .none:
                return "Add ID & Link"
            case .start:
                return "Add ID & Start"
            case .submit:
                return "Add ID & Capture"
            case .submitAndOpen:
                return "Add ID, Capture & Open"
            }
        case .dependency(_, _, _, let followUp, _, _):
            switch followUp {
            case .submit, .submitAndOpen:
                return "Add ID & Capture"
            case .none, .start:
                return "Add ID & Use"
            }
        case .blockedTask(_, _, _, let followUp, _):
            return followUp == .submit || followUp == .submitAndOpen
                ? "Add ID & Capture"
                : "Add ID & Use"
        case .relation(_, _, _, let followUp, _, _):
            switch followUp {
            case .submit, .submitAndOpen:
                return "Add ID & Capture"
            case .none, .start:
                return "Add ID & Use"
            }
        case .taskComplete(_, _, _, let followUp, _):
            switch followUp {
            case .submit, .submitAndOpen:
                return "Add ID & Complete"
            case .none, .start:
                return "Add ID & Insert"
            }
        case .parentTask:
            return "Add & Select"
        case .parentTaskPicker(_, _, _, let followUp, _, _):
            switch followUp {
            case .submit, .submitAndOpen:
                return "Add ID & Capture"
            case .none, .start:
                return "Add ID & Select"
            }
        }
    }

    private func linkInsertsLine(for prompt: CaptureTaskIDPromptState) -> String {
        let typed = prompt.authoredID.isEmpty ? "…" : prompt.authoredID
        switch prompt.purpose {
        case .taskLink(let route, _, _, let followUp, _):
            let suffix = followUp == .start ? "=" : ""
            return "Inserts @\(route):\(typed)\(suffix)"
        case .dependency(let notePath, _, _, _, _, _):
            return "Inserts &\(notePath):\(typed)"
        case .blockedTask(let notePath, _, _, _, _):
            return "Inserts *\(notePath):\(typed)"
        case .relation(let notePath, _, _, _, _, let direction):
            return "Inserts \(direction.leadingSigil)\(notePath):\(typed)"
        case .taskComplete(let notePath, _, _, _, _):
            return "Inserts !\(taskCompleteLocator(for: prompt, fallback: notePath)):\(typed)"
        case .parentTask:
            return ""
        case .parentTaskPicker(let route, _, _, _, _, _):
            return "Inserts @\(route)+\(typed)"
        }
    }

    /// Bob's candidate locator for the Complete ID prompt (for example
    /// `sase`), never the file name. Falls back to the stored note path for
    /// older snapshots without a locator.
    private func taskCompleteLocator(for prompt: CaptureTaskIDPromptState, fallback: String) -> String {
        if let locator = prompt.candidate.locator, !locator.isEmpty {
            return locator
        }
        return fallback
    }

    private func linkInsertsText(for prompt: CaptureTaskIDPromptState) -> Text {
        let typed = prompt.authoredID.isEmpty ? "…" : prompt.authoredID
        switch prompt.purpose {
        case .taskLink(let route, _, _, let followUp, _):
            let suffix = followUp == .start ? "=" : ""
            return Text("\(Text("Inserts @").foregroundStyle(.secondary))\(Text(route).foregroundStyle(CaptureEditorPalette.color(for: .route)))\(Text(":").foregroundStyle(.secondary))\(Text(typed).foregroundStyle(CaptureEditorPalette.color(for: .blockID)))\(Text(suffix).foregroundStyle(.secondary))")
        case .dependency(let notePath, _, _, _, _, _):
            return Text("\(Text("Inserts &").foregroundStyle(.secondary))\(Text(notePath).foregroundStyle(CaptureEditorPalette.color(for: .route)))\(Text(":").foregroundStyle(.secondary))\(Text(typed).foregroundStyle(CaptureEditorPalette.color(for: .blockID)))")
        case .blockedTask(let notePath, _, _, _, _):
            return Text("\(Text("Inserts *").foregroundStyle(CaptureEditorPalette.color(for: .blockedTaskSigil)))\(Text(notePath).foregroundStyle(CaptureEditorPalette.color(for: .route)))\(Text(":").foregroundStyle(.secondary))\(Text(typed).foregroundStyle(CaptureEditorPalette.color(for: .blockID)))")
        case .relation(let notePath, _, _, _, _, let direction):
            return Text("\(Text("Inserts \(direction.leadingSigil)").foregroundStyle(CaptureEditorPalette.color(for: .relationSigil)))\(Text(notePath).foregroundStyle(CaptureEditorPalette.color(for: .route)))\(Text(":").foregroundStyle(.secondary))\(Text(typed).foregroundStyle(CaptureEditorPalette.color(for: .blockID)))")
        case .taskComplete(let notePath, _, _, _, _):
            return Text("\(Text("Inserts !").foregroundStyle(.secondary))\(Text(taskCompleteLocator(for: prompt, fallback: notePath)).foregroundStyle(CaptureEditorPalette.color(for: .route)))\(Text(":").foregroundStyle(.secondary))\(Text(typed).foregroundStyle(CaptureEditorPalette.color(for: .blockID)))")
        case .parentTask:
            return Text("")
        case .parentTaskPicker(let route, _, _, _, _, _):
            return Text("\(Text("Inserts @").foregroundStyle(.secondary))\(Text(route).foregroundStyle(CaptureEditorPalette.color(for: .route)))\(Text("+").foregroundStyle(.secondary))\(Text(typed).foregroundStyle(CaptureEditorPalette.color(for: .blockID)))")
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
private struct RelationLabelPromptCard: View {
    @ObservedObject var model: CapturePanelModel
    @FocusState private var fieldFocused: Bool

    private var prompt: CaptureRelationLabelPromptState? {
        model.relationLabelPrompt
    }

    var body: some View {
        if let prompt {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("🪢 Relation", systemImage: "arrow.left.arrow.right")
                        .font(.headline)
                    Spacer(minLength: 8)
                    if prompt.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(model.relationLabelSentence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Relation sentence: \(model.relationLabelSentence)")

                TextField(
                    "follow-up of",
                    text: Binding(
                        get: { model.relationLabelPrompt?.authoredLabel ?? "" },
                        set: { model.updateRelationLabelPromptLabel($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .disabled(prompt.isSaving)
                .onAppear { fieldFocused = true }
                .accessibilityLabel("Relation label")

                if !prompt.suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(prompt.suggestions.enumerated()), id: \.offset) { index, candidate in
                                let title: String = {
                                    let label = candidate.label ?? candidate.replacement
                                    if let count = candidate.count, count > 0 {
                                        return "\(label) · \(count)"
                                    }
                                    return label
                                }()
                                Button(title) {
                                    model.insertRelationLabelSuggestion(id: candidate.replacement)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(prompt.isSaving)
                                .accessibilityLabel("Use relation label \(candidate.label ?? candidate.replacement)")
                            }
                        }
                    }
                    .accessibilityLabel("Relation suggestions")
                }

                if let inserts = model.relationLabelInsertsText {
                    Text(inserts)
                        .font(.caption)
                        .foregroundStyle(CaptureEditorPalette.color(for: .relationSigil))
                }

                Text("Tab cycles suggestions · esc back to picker")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = prompt.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityLabel("Relation label error: \(error)")
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        model.cancelRelationLabelPrompt()
                    }
                    .disabled(prompt.isSaving)
                    Button("Insert") {
                        model.submitRelationLabelPrompt()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.relationLabelPromptCanSubmit)
                }
            }
            .padding(10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 12, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Relation label")
        }
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
struct SavedTemplateShelfPicker: View {
    @ObservedObject var model: CapturePanelModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: CapturePanelLayout.stashPickerContentSpacing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: CapturePanelLayout.stashRowSpacing) {
                        ForEach(Array(model.templateEntries.enumerated()), id: \.element.id) {
                            index, template in
                            SavedTemplateShelfRow(
                                template: template,
                                accelerator: CapturePickerHelpers.accelerator(for: index) ?? "",
                                selected: index == model.selectedTemplateIndex,
                                armed: model.armedDeleteTemplateID == template.id,
                                now: Date()
                            )
                            .id(template.id)
                            .onTapGesture {
                                model.useTemplate(id: template.id)
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
                .onChange(of: model.selectedTemplateIndex) { _, _ in
                    scrollSelectionIntoView(proxy)
                }
            }

            hintRow
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
            "Use arrows, Control-N, Control-P, Return, or a shown key to use a template. "
                + "Press Delete twice to delete it."
        )
    }

    @ViewBuilder
    private var hintRow: some View {
        if model.armedDeleteTemplateID != nil {
            Text("⌫ again deletes · any other key keeps it")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CapturePanelLayout.stashClearButtonHorizontalPadding)
                .padding(.vertical, CapturePanelLayout.stashClearButtonVerticalPadding)
                .frame(height: CapturePanelLayout.stashClearButtonHeight, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                hintKeycap("↩", action: "use")
                hintKeycap("⌫", action: "delete")
                hintKeycap("⌃S", action: "stash")
                hintKeycap("esc", action: "close")
                Spacer(minLength: 8)
                Text(capacityCaption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, CapturePanelLayout.stashClearButtonHorizontalPadding)
            .padding(.vertical, CapturePanelLayout.stashClearButtonVerticalPadding)
            .frame(height: CapturePanelLayout.stashClearButtonHeight, alignment: .leading)
        }
    }

    private func hintKeycap(_ keys: String, action: String) -> some View {
        TemplateShelfHintKeycap(keys: keys, action: action)
    }

    private var capacityCaption: String {
        if !model.savedTemplateShelf.saving {
            return "saving off"
        }
        return "\(model.templateShelfCount) of \(model.savedTemplateShelf.capacity)"
    }

    private var sizing: SavedTemplateShelfPickerHeightPolicy {
        SavedTemplateShelfPickerHeightPolicy(
            entryCount: model.templateShelfCount,
            displayScale: displayScale
        )
    }

    private var listAccessibilityLabel: String {
        let count = model.templateShelfCount
        return "Saved templates, \(count) \(count == 1 ? "entry" : "entries")"
    }

    private func scrollSelectionIntoView(_ proxy: ScrollViewProxy) {
        guard let entry = model.selectedTemplateEntry else {
            return
        }
        proxy.scrollTo(entry.id, anchor: .center)
    }
}

@available(macOS 26.0, *)
struct SavedTemplateShelfRow: View {
    let template: CaptureSavedTemplate
    let accelerator: String
    let selected: Bool
    let armed: Bool
    let now: Date
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var presentation: CaptureSavedTemplatePresentation {
        CaptureSavedTemplatePresentation(template: template, now: now)
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
                Text(attributedLine(presentation.parentLine, secondary: false))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                if let child = presentation.firstChildLine {
                    Text(attributedLine(child, secondary: true))
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if presentation.moreLinesCount > 0 {
                    Text("+\(presentation.moreLinesCount) more lines")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(presentation.metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailingAccessory
        }
        .frame(
            minHeight: CapturePanelLayout.templateShelfRowContentMinimumHeight,
            alignment: .topLeading
        )
        .padding(.horizontal, CapturePanelLayout.stashRowHorizontalPadding)
        .padding(.vertical, CapturePanelLayout.stashRowVerticalPadding)
        .background(rowFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if armed {
            Text("Delete?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.red.opacity(colorSchemeContrast == .increased ? 0.24 : 0.12), in: Capsule())
        } else {
            HStack(spacing: 3) {
                ForEach(presentation.slotDotFields, id: \.self) { field in
                    Circle()
                        .fill(CaptureEditorPalette.templateSlotColor(field: field))
                        .frame(
                            width: CapturePanelLayout.templateShelfSlotDotSize,
                            height: CapturePanelLayout.templateShelfSlotDotSize
                        )
                }
                if presentation.slotOverflowCount > 0 {
                    Text("+\(presentation.slotOverflowCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func attributedLine(
        _ segments: [CaptureSavedTemplateSegment],
        secondary: Bool
    ) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            if segment.category == .neutral && secondary {
                part.foregroundColor = .secondary
            } else {
                part.foregroundColor = CaptureEditorPalette.color(for: segment.category)
            }
            if segment.category.isUnderlined {
                part.underlineStyle = .single
            }
            result.append(part)
        }
        return result
    }

    private var rowFill: Color {
        if armed {
            return Color.red.opacity(colorSchemeContrast == .increased ? 0.24 : 0.12)
        }
        guard selected else {
            return .clear
        }
        return Color.accentColor.opacity(colorSchemeContrast == .increased ? 0.32 : 0.18)
    }
}

private struct TemplateShelfHintKeycap: View {
    let keys: String
    let action: String
    var accessibilityLabel: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .frame(height: CapturePanelLayout.templateShelfHintKeyHeight)
                .padding(.horizontal, 6)
                .background(.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.secondary.opacity(0.28), lineWidth: 0.5)
                )
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel ?? "\(keys) \(action)")
    }
}

@available(macOS 26.0, *)
private struct CompletionList: View {
    @ObservedObject var model: CapturePanelModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // The File-under parent picker for a bare-URL reference
                    // draft headers its synthesized route list so the choice
                    // reads as a filing decision, not a destination edit.
                    if model.fileUnderActive {
                        Text("File under")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            .accessibilityAddTraits(.isHeader)
                    } else if model.templateStartHintVisible {
                        TemplateShelfHintKeycap(
                            keys: "@",
                            action: "again to start a template",
                            accessibilityLabel: "Type @ again to start a template"
                        )
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    }
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

        return Text("\(Text(prefix))\(Text(matched).fontWeight(.semibold))\(Text(suffix))")
    }
}

@available(macOS 26.0, *)
struct PreviewPane: View {
    @ObservedObject var model: CapturePanelModel
    @State private var settledPaneHeight: CGFloat?
    @State private var lastAnnouncedSimilarKeys: [String] = []

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
        .onAppear {
            announceSimilarTasksIfNeeded()
        }
        .onChange(of: similarTasksAnnouncementSignature) { _, _ in
            announceSimilarTasksIfNeeded()
        }
    }

    private var similarTasksAnnouncementSignature: String {
        if model.similarTasks.pending {
            return "pending"
        }
        return SimilarTasksBandPolicy.visibleItems(
            in: model.similarTasks,
            parseItems: model.similarTasksParseItems
        ).flatMap(\.rows).map(\.match.key).joined(separator: "\u{1e}")
    }

    private func announceSimilarTasksIfNeeded() {
        guard !model.similarTasks.pending else { return }
        let items = SimilarTasksBandPolicy.visibleItems(
            in: model.similarTasks,
            parseItems: model.similarTasksParseItems
        )
        let keys = SimilarTasksBandPresentation.identityKeys(items: items)
        if keys.isEmpty {
            lastAnnouncedSimilarKeys = []
            return
        }
        guard keys != lastAnnouncedSimilarKeys else { return }
        lastAnnouncedSimilarKeys = keys
        guard let text = SimilarTasksBandPresentation.settledAnnouncement(items: items) else {
            return
        }
        AccessibilityNotification.Announcement(text).post()
    }

    @ViewBuilder
    private func previewContent(_ success: CaptureCommandSuccess) -> some View {
        let captures = success.normalizedCaptures
        let orderedTaskBlocks = taskBlocksForPreview(
            captures: captures,
            blocks: success.taskBlocks
        )
        let suppressRelationshipLines = captures.contains {
            !$0.dependencyUpdates.isEmpty || !$0.relationUpdates.isEmpty
        }
        if captures.count > 1 || success.template != nil {
            HStack(spacing: 6) {
                Text(captures.count == 1 ? "1 capture" : "\(captures.count) captures")
                    .fontWeight(.semibold)
                    .accessibilityLabel(captures.count == 1 ? "1 capture item" : "\(captures.count) capture items")
                if let template = success.template {
                    Text(template.previewChipTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(template.previewAccessibilityLabel)
                }
            }
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
            CapturePlanBudgetMeterRow(budget: budget)
        } else if captures.count == 1, let first = captures.first,
                  let budget = CapturePlanBudgetPresentation(capture: first)
        {
            CapturePlanBudgetMeterRow(budget: budget)
        }

        ForEach(Array(captures.enumerated()), id: \.offset) { index, capture in
            if index > 0 {
                Divider()
            }
            previewItem(
                capture,
                index: index,
                total: captures.count,
                globalDestination: success.globalDestination,
                blocks: success.pomodoroBlocks,
                taskBlocks: orderedTaskBlocks
            )
        }

        // Batch-level task blocks render once, after the item stack and
        // before the Pomodoro blocks: each card shows the parent task's final
        // state with Bob's cumulative diff. They dim together with the close
        // card while a close-list selection dangles. An older Bob omits
        // `task_blocks` and the pane renders exactly as before.
        if !orderedTaskBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(orderedTaskBlocks.enumerated()), id: \.offset) { _, block in
                    TaskBlockView(
                        block: block,
                        dryRun: success.dryRun,
                        suppressRelationshipLines: suppressRelationshipLines
                    ) {
                        model.requestFocus(.editor)
                    }
                }
            }
            .padding(.top, 4)
            .opacity(model.closePendingText != nil ? 0.6 : 1)
        }

        // Batch-level Pomodoro blocks render once, after the item stack:
        // each block shows the Pomodoro's final state with Bob's cumulative
        // diff. They dim together with the close card while a close-list
        // selection dangles. An older Bob omits `pomodoro_blocks` and the
        // pane renders exactly as before.
        if !success.pomodoroBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(success.pomodoroBlocks.enumerated()), id: \.offset) { _, block in
                    PomodoroBlockView(block: block, dryRun: success.dryRun)
                }
            }
            .padding(.top, 4)
            .opacity(model.closePendingText != nil ? 0.6 : 1)
        }

        if model.livePreviewUsesLiteralClipboard {
            Text("Clipboard markers stay literal in live preview")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
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

    private func taskBlocksForPreview(
        captures: [CaptureCommandSuccess],
        blocks: [CaptureTaskBlock]
    ) -> [CaptureTaskBlock] {
        guard captures.count == 1, let capture = captures.first else {
            return blocks
        }
        return CaptureRelationshipPresentation.ownerFirstTaskBlocks(
            for: capture,
            blocks: blocks
        )
    }

    @ViewBuilder
    private func previewItem(
        _ success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        globalDestination: CaptureGlobalDestination?,
        blocks: [CapturePomodoroBlock],
        taskBlocks: [CaptureTaskBlock] = []
    ) -> some View {
        let isLocalOverride = globalDestination.map {
            !captureUsesGlobalDestination(success, $0)
        } ?? false
        // The destination row sits above the per-kind preview item, so every
        // link landing names where its Task Link went without disturbing the
        // existing card below.
        planDestinationRow(for: success)
        if let complete = success.taskComplete {
            pullInPreviewSummary(for: complete.unblocked)
        }
        if let close = success.pomodoroClose {
            pullInPreviewSummary(for: close.unblocked)
        }
        if let ref = CaptureRefPresentation(capture: success) {
            refPreviewItem(
                ref,
                success: success,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            )
        } else if let reset = CapturePomodoroResetPresentation(capture: success) {
            resetPreviewItem(reset, success: success, index: index, total: total)
        } else if let close = CapturePomodoroClosePresentation(capture: success) {
            closePreviewItem(close, success: success, index: index, total: total)
        } else if CapturePomodoroStartPresentation.isSessionStart(success),
                  let start = CapturePomodoroStartPresentation(capture: success)
        {
            startPreviewItem(start, success: success, index: index, total: total)
        } else if let complete = CaptureTaskCompletePresentation(capture: success) {
            completePreviewItem(
                complete,
                success: success,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            )
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
        } else if let linkGuard = CaptureLinkGuardPresentation(capture: success) {
            linkGuardPreviewItem(
                linkGuard,
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
                isLocalOverride: isLocalOverride,
                blocks: blocks,
                taskBlocks: taskBlocks
            )
        }
    }

    @ViewBuilder
    private func pullInPreviewSummary(for items: [TaskCompleteUnblocked]) -> some View {
        let offers = items.filter { $0.offer?.key.isEmpty == false }
        if !offers.isEmpty {
            let rows = offers.map { item in
                CapturePullInChoiceRow(
                    offerRow: item,
                    blockedRow: nil,
                    group: item.offer?.group ?? "",
                    project: item.offer?.project
                )
            }
            let grouped = CapturePullInChoiceState(
                draftSnapshot: "",
                processClientIdentity: "",
                openAfterCapture: false,
                priorityRollSeed: "",
                generation: 0,
                requestID: nil,
                pullIn: CapturePullIn(supported: true, offerCount: offers.count),
                planBudget: nil,
                rows: rows,
                highlightedKey: nil
            )
            VStack(alignment: .leading, spacing: 4) {
                ForEach(grouped.sections) { section in
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(section.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Offer \(row.offerNumber ?? 0)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(row.text)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let destination = row.destinationText {
                                Text(destination)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if row.needsBlockID {
                                Text("needs ^id")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        if let detail = row.detailText {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("↩ choose what to pull in")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Press Return to choose what to pull in")
            }
            .padding(.leading, 20)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func resetPreviewItem(
        _ reset: CapturePomodoroResetPresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int
    ) -> some View {
        // The reset card renders Bob's resolved `pomodoro_reset` object
        // exactly as the presentation words it: no Swift-side clock or ledger
        // math, no completed/started-task counts, no early/overrun badge.
        let sessionTint = CaptureEditorPalette.color(for: .pomodoroStart)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if total > 1 {
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .foregroundStyle(sessionTint)
                    .accessibilityHidden(true)
                Text(reset.title)
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(reset.destinationText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            if let moved = reset.movedText {
                Text(moved)
                    .foregroundStyle(.secondary)
            }
            if let viaText = reset.viaText {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: reset.variant == .newTask ? "plus.circle" : "link")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(viaText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            Text(reset.entryLine)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            Text("Now the first future Pomodoro with its contents kept")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reset.accessibilitySummary)
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
        // The badge, transition, and tag never shrink; at narrow widths the
        // locator truncates first, then the one-line task title.
        let sessionTint = CaptureEditorPalette.color(for: .pomodoroStart)
        let logTint = CaptureEditorPalette.color(for: .pomodoroCloseLog)
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
            if let droppedChip = close.droppedDependenciesChip {
                Text(droppedChip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
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
                                Text(row.displayTitle.text)
                                    .strikethrough(row.isStruck)
                                    .layoutPriority(1)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                                if let tag = row.tag {
                                    Text(tag)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
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
                                Array(row.typedWorkLogPreviews.enumerated()),
                                id: \.offset
                            ) { index, entry in
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundStyle(logTint)
                                        .accessibilityHidden(true)
                                    Text(entry)
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .textSelection(.enabled)
                                }
                                let details =
                                    index < row.typedWorkLogDetails.count
                                    ? row.typedWorkLogDetails[index] : []
                                ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Image(systemName: "square.and.pencil")
                                            .foregroundStyle(.clear)
                                            .accessibilityHidden(true)
                                        Text(detail)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .textSelection(.enabled)
                                    }
                                }
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
                            if let caption = row.caption {
                                if row.outcome == .parked {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Image(systemName: "pause.circle")
                                            .foregroundStyle(.teal)
                                            .accessibilityHidden(true)
                                        Text(caption)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                } else {
                                    Text(caption)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
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

            if close.unblockedRows.contains(where: { $0.kind != .offered })
                || !close.stillBlockedRows.isEmpty
            {
                // The Unblocked section under the task rows, with the same
                // row views as the `!` card: destination capsules and
                // minted-ID captions on linked rows, reason captions on
                // recovered rows, muted rows for what stays blocked.
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Unblocked")
                            .fontWeight(.semibold)
                            .textSelection(.enabled)
                    }
                    ForEach(Array(close.unblockedRows.filter { $0.kind != .offered }.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "lock.open.fill")
                                    .foregroundStyle(row.kind == .linked ? .green : .secondary)
                                    .accessibilityHidden(true)
                                Text(row.transitionText)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer(minLength: 4)
                                if let destination = row.destinationText {
                                    Text(destination)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.quaternary, in: Capsule())
                                }
                                if row.isInbox {
                                    Text("inbox")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.quaternary, in: Capsule())
                                }
                                Text(row.locatorText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .textSelection(.enabled)
                            }
                            if let caption = row.captionText {
                                Text(caption)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    ForEach(Array(close.stillBlockedRows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                                Text(row.text)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Spacer(minLength: 4)
                                Text(row.locatorText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .textSelection(.enabled)
                            }
                            Text(row.captionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
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
        case .parked:
            return .teal
        case .complete:
            return .green
        case .dropped:
            return .gray
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .textSelection(.enabled)
        case .deferred:
            Image(systemName: "arrow.uturn.forward")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .struck:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .dropped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.gray)
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
        // numbered queued Task Links Bob reported, dropped rows struck and
        // dimmed in place. The locator truncates first at narrow widths, so
        // the task text always stays legible.
        let sessionTint = CaptureEditorPalette.color(for: .pomodoroStart)
        // A pending list previews the trimmed draft: the card stays live but
        // dimmed, and Start is disabled until a task number is typed.
        let isPending = model.closePendingText != nil
        let showsBadges = start.taskRows.contains { $0.index != nil }
        VStack(alignment: .leading, spacing: 6) {
            if let warning = start.overrideWarning {
                overrideWarningBanner(warning, sessionTint: sessionTint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if total > 1 {
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: startIconName(for: start.variant))
                    .foregroundStyle(sessionTint)
                    .accessibilityHidden(true)
                Text(start.title)
                    .fontWeight(.semibold)
                // A created session carries a small pink New/Created capsule
                // next to the title so the fresh entry reads at a glance; a
                // kept-ledger swap adds a Takes over capsule the same way.
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
                if let takesOver = start.takesOverBadgeText {
                    Text(takesOver)
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

            // Override captions under the destination: the pre-image range a
            // restart leaves behind, or the session a swap returns to first
            // future. The orange banner above the title is the warning.
            if let was = start.restartWasText {
                Text(was)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let demoted = start.demotedText {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.uturn.down")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(demoted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // The teaching hint (before a drop is typed), the drop summary
            // (after), or the pending notice (while a list dangles): one
            // caption row under the destination. Example tokens share the
            // editor span colors of the badges they select; prose stays
            // secondary.
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
            } else if let summary = start.dropSummary {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "list.number")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else if let hint = start.teachingHint {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "number.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(startHintText(hint))
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
                                if showsBadges {
                                    startNumberBadge(for: row)
                                }
                                startTaskGlyph(for: row)
                                Text(row.displayTitle.text)
                                    .strikethrough(row.isStruck)
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
                            if let caption = row.caption {
                                Text(caption)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .opacity(row.isDimmed ? 0.5 : 1)
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
        .opacity(isPending ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isPending ? "\(start.accessibilitySummary), \(model.closePendingText ?? "")"
                : start.accessibilitySummary
        )
    }

    /// The start-card glyph. Restarts and swaps keep the start pink but
    /// answer the play glyph with their own: a restart re-runs the clock, a
    /// swap exchanges it. A plain function, not a `@ViewBuilder` switch,
    /// because result builders reject statement-only `switch` branches.
    private func startIconName(
        for variant: CapturePomodoroStartPresentation.Variant
    ) -> String {
        switch variant {
        case .restart:
            return "arrow.clockwise.circle.fill"
        case .swap:
            return "arrow.left.arrow.right.circle.fill"
        case .start:
            return "play.circle.fill"
        }
    }

    /// The orange override banner: triangle glyph, headline with the
    /// session range on the right, a secondary detail line, and an optional
    /// `Type` / chip / `to close it first` row from Bob's `close_first`.
    private func overrideWarningBanner(
        _ warning: CapturePomodoroStartPresentation.OverrideWarning,
        sessionTint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(warning.headline)
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
                if !warning.rangeText.isEmpty {
                    Text(warning.rangeText)
                        .font(.system(.callout, design: .monospaced))
                }
            }
            Text(warning.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let closeFirst = warning.closeFirst {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Type")
                    Text(closeFirst)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .foregroundStyle(sessionTint)
                        .background(
                            sessionTint.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                    Text("to close it first")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.4))
        )
        .accessibilityHidden(true)
    }

    /// Renders the start-card teaching-hint tokens: example tokens share the
    /// editor span colors of the badges they select (`~N` the drop gray,
    /// `#name` the name color); prose stays secondary, matching the close
    /// card's hint rendering.
    private func startHintText(
        _ hint: CapturePomodoroStartPresentation.TeachingHint
    ) -> AttributedString {
        hint.tokens.map { token in
            var part = AttributedString(token.text)
            part.foregroundColor = token.category == .neutral
                ? .secondary
                : CaptureEditorPalette.color(for: token.category)
            return part
        }.reduce(AttributedString()) { $0 + $1 }
    }

    /// The fixed-width leading number badge for a start row: an open
    /// `N.circle` for kept rows, a filled one for dropped (listed) rows.
    /// Numbers above 50 fall back to monospaced digits in a capsule;
    /// unnumbered rows get an equal-width clear spacer so text stays aligned.
    @ViewBuilder
    private func startNumberBadge(
        for row: CapturePomodoroStartPresentation.TaskRow
    ) -> some View {
        let badgeWidth: CGFloat = 26
        if row.usesNumericBadgeFallback, let index = row.index {
            Text("\(index)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(row.isDropped ? .gray : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .frame(width: badgeWidth + 14, alignment: .center)
                .opacity(row.isDimmed ? 0.5 : 1)
                .accessibilityHidden(true)
        } else if let symbolName = row.badgeSymbolName {
            Image(systemName: symbolName)
                .foregroundStyle(row.isDropped ? .gray : .secondary)
                .frame(width: badgeWidth, alignment: .center)
                .opacity(row.isDimmed ? 0.5 : 1)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: badgeWidth, height: 1)
                .accessibilityHidden(true)
        }
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
        case .dropped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.gray)
                .accessibilityHidden(true)
        case .unresolved:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
        }
    }

    private func standardHeader(
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
    }

    private func subBulletHeader(
        _ subBullet: CaptureSubBulletPresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> some View {
        // A covered sub-bullet item names what it did; the task card below
        // names where it landed. Wire words (`placement`, `kind`) and the
        // route label stay off: the caption names the note.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if total > 1 {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Sub-bullet")
                .fontWeight(.semibold)
            Text(subBullet.headerDetail)
                .foregroundStyle(.secondary)
            if isLocalOverride {
                Text("local override")
                    .foregroundStyle(.secondary)
            }
            if let scheduled = success.scheduled {
                Text(scheduled)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private func taskDependencyHeader(
        _ owner: CaptureTaskDependencyOwnerHeader,
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
            Text(owner.text)
                .fontWeight(.semibold)
            if !owner.locationText.isEmpty {
                Text(owner.locationText)
                    .foregroundStyle(.secondary)
            }
            if !owner.statusText.isEmpty {
                Text(owner.statusText)
                    .foregroundStyle(.secondary)
            }
            if isLocalOverride {
                Text("local override")
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(owner.accessibilitySummary)
    }

    @ViewBuilder
    private func standardPreviewItem(
        _ success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool,
        blocks: [CapturePomodoroBlock],
        taskBlocks: [CaptureTaskBlock] = []
    ) -> some View {
        let relationship = CaptureRelationshipPresentation(capture: success)
        // When the batch blocks already show every verbatim preview line,
        // the item omits its `previewBlockLines` stack so the headline never
        // prints twice. VoiceOver still announces the item summary once,
        // from the header row.
        let covered = CapturePomodoroBlockPresentation.covers(success, blocks: blocks)
        // A covered sub-bullet item switches to the compact header and drops
        // both the verbatim stack and the trailing `relativeTarget` line;
        // the task card below shows where it landed.
        let taskCovered = CaptureTaskBlockPresentation.covers(success, blocks: taskBlocks)
        let subBullet = CaptureSubBulletPresentation(capture: success)
        let compactSubBullet = taskCovered && subBullet != nil
        let taskDependencyCovered = relationship.ownerHeader != nil && taskCovered
        if let owner = relationship.ownerHeader {
            taskDependencyHeader(
                owner,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            )
        } else if compactSubBullet, let subBullet {
            subBulletHeader(
                subBullet,
                success: success,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(subBulletAccessibilityLabel(
                for: success,
                subBullet: subBullet,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            ))
        } else if covered {
            standardHeader(
                success,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(previewAccessibilityLabel(
                for: success,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride,
                includeBlockLines: false
            ))
        } else {
            standardHeader(
                success,
                index: index,
                total: total,
                isLocalOverride: isLocalOverride
            )
        }

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

        // Dependency effects come from Bob's ordered `dependency_updates[]`;
        // the normalized model falls back to the legacy singular key.
        if !relationship.rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(relationship.rows.enumerated()), id: \.offset) { _, row in
                    Text(row.text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityLabel(row.accessibilityLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !success.dependencyUpdates.isEmpty {
            // Older Bob versions may send the summary without the resolved
            // relationship rows. Keep their previous copy as a tolerant
            // fallback until the CLI supplies the additive details.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(success.dependencyUpdates.enumerated()), id: \.offset) { _, dependency in
                    if dependency.role == "blocked_task" {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("🧱 Blocks \"\(dependency.dependentText)\" · [\(dependency.previousStatus)] → [\(dependency.dependentStatus)] \(dependency.dependentStatusName)")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.semibold)
                            Text("⛓️ \(dependency.managedLineText)")
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                            if dependency.blockedResidents > 0 {
                                let noun = dependency.blockedResidents == 1 ? "task" : "tasks"
                                Text("· blocks \(dependency.blockedResidents) project \(noun)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "link")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text(dependency.headline)
                                    .font(.system(.callout, design: .monospaced))
                                    .fontWeight(.semibold)
                            }
                            Text("⛓️ \(dependency.managedLineText)")
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                            Text(dependency.waitingText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(dependency.previewAccessibilitySummary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let minted = success.mintedBlockerBlockID {
            Text("🧱 New blocker ID · \(minted.path) ^\(minted.blockID)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        if !success.mintedRelationBlockIDs.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(success.mintedRelationBlockIDs.enumerated()), id: \.offset) { _, minted in
                    Text("🪢 New relation ID · \(minted.path) ^\(minted.blockID) (\(minted.role))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !success.consumedLinks.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(success.consumedLinks.enumerated()), id: \.offset) { _, consumed in
                    Text(consumed.previewText(dryRun: success.dryRun))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(consumed.pomodoro.removed ? .red : .secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel(consumed.previewText(dryRun: success.dryRun))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // `previewBlockLines` is the parent line, the authored children, the clipboard
        // children, and the schedule log in the exact order Bob writes them, already
        // carrying the target note's indentation. Lines the batch blocks
        // already cover are omitted: the block view below shows them.
        // Covered sub-bullet items omit the stack too: the task card shows
        // where the bullet landed.
        if !covered, !compactSubBullet, !taskDependencyCovered {
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
        }

        // Covered sub-bullet items drop the trailing `relativeTarget` line:
        // the task card caption already names the note.
        if !compactSubBullet, !taskDependencyCovered {
            Text(success.relativeTarget)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }

        similarTasksBand(forCaptureIndex: index)
    }

    @ViewBuilder
    private func similarTasksBand(forCaptureIndex index: Int) -> some View {
        if let item = SimilarTasksBandPolicy.visibleItem(
            in: model.similarTasks,
            captureIndex: index,
            parseItems: model.similarTasksParseItems
        ) {
            SimilarTasksBandView(
                item: item,
                folded: model.similarTasksFolded,
                focusedRowID: model.similarTasks.focusedRowID,
                chosenAction: model.similarChosenAction,
                onFocusRow: { row in
                    model.focusSimilarRow(id: row.id)
                },
                onApplyAction: { row, action in
                    if model.similarTasks.focusedRowID != row.id {
                        model.focusSimilarRow(id: row.id)
                    }
                    model.similarApply(action)
                }
            )
        }
    }

    @ViewBuilder
    private func refPreviewItem(
        _ ref: CaptureRefPresentation,
        success _: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> some View {
        // The reference card renders Bob's resolved `ref` object exactly as
        // the presentation words it: a link glyph, the display URL (or the
        // library path when already known), bob's own detail line, the route
        // or reading-state chips, and the inbox fallback hint. No Swift-side
        // library or network math — only Bob's verdict and wording.
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if total > 1 {
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(ref.headline)
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
                Text(ref.destinationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                if isLocalOverride {
                    Text("local override")
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)

            Text(ref.detailText)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            // A queued link names its resolved parent (`📖 Queue ·
            // example.com/essay → sase`, or `→ mac_inbox · file it later`
            // for the default inbox); an explicit `@route` also names the
            // parent's kind. Older-Bob payloads without a parent show
            // neither line.
            if let queueSummary = ref.queueSummary {
                Text(queueSummary)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let parentCaption = ref.parentCaption {
                Text(parentCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !ref.chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(ref.chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }

            if let fallbackHint = ref.fallbackHint {
                Text(fallbackHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ref.previewAccessibilitySummary)
    }

    @ViewBuilder
    private func completePreviewItem(
        _ complete: CaptureTaskCompletePresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> some View {
        // The completion card renders Bob's resolved `task_complete` object
        // exactly as the presentation words it: no Swift-side status or
        // ledger math. The locator truncates first at narrow widths, so the
        // task text and transition always stay legible.
        let sealColor: Color = complete.isAlreadyDone ? .gray : .green
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if total > 1 {
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(sealColor)
                    .accessibilityHidden(true)
                Text(complete.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(complete.isAlreadyDone ? .gray : .primary)
                Spacer(minLength: 4)
                Text(complete.destinationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                if isLocalOverride {
                    Text("local override")
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)

            completeTransitionLine(complete)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)

            ForEach(Array(complete.subtaskRows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(row.transitionText)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    Text(row.locatorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }

            ForEach(Array(complete.leftOpenRows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(row.displayText)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    Text(row.locatorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }

            if let ledgerText = complete.ledgerText {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(ledgerText)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            ForEach(Array(complete.unblockedRows.filter { $0.kind != .offered }.enumerated()), id: \.offset) { _, row in
                // Linked rows wear the Next tint with a trailing destination
                // capsule; recovered rows stay secondary with a reason
                // caption. The locator truncates first at narrow widths.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(row.kind == .linked ? .green : .secondary)
                            .accessibilityHidden(true)
                        Text(row.transitionText)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer(minLength: 4)
                        if let destination = row.destinationText {
                            Text(destination)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                        if row.isInbox {
                            Text("inbox")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(row.locatorText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                    if let caption = row.captionText {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            ForEach(Array(complete.stillBlockedRows.enumerated()), id: \.offset) { _, row in
                // Still-blocked rows stay muted: tertiary lock, plain text,
                // and a `stays …` caption.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(row.text)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer(minLength: 4)
                        Text(row.locatorText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                    Text(row.captionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(completePreviewAccessibilityLabel(
            for: complete,
            success: success,
            index: index,
            total: total,
            isLocalOverride: isLocalOverride
        ))
    }

    private func completeTransitionLine(
        _ complete: CaptureTaskCompletePresentation
    ) -> some View {
        // Only the post-arrow task text is struck and dimmed; the status
        // markers stay legible. The presentation guarantees `transitionText`
        // ends with `previewText` except when the preview is empty.
        let transition = complete.transitionText
        let preview = complete.previewText
        if !preview.isEmpty, transition.hasSuffix(preview) {
            let prefix = String(transition.dropLast(preview.count))
            return AnyView(HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(prefix)
                Text(preview)
                    .strikethrough(true)
                    .foregroundStyle(.secondary)
            })
        }
        return AnyView(Text(transition)
            .strikethrough(true)
            .foregroundStyle(complete.isAlreadyDone ? .gray : .secondary))
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
        isLocalOverride: Bool,
        includeBlockLines: Bool = true
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
        let resetSummary = CapturePomodoroResetPresentation(capture: success)
            .map { ", \($0.accessibilitySummary)" } ?? ""
        let closeSummary = CapturePomodoroClosePresentation(capture: success)
            .map { ", \($0.accessibilitySummary)" } ?? ""
        let projectNoteSummary = CaptureProjectNotePresentation(capture: success)
            .map { ", \($0.previewAccessibilitySummary)" } ?? ""
        let summary = "\(position)\(success.kind), \(destination)\(override)\(startSummary)\(adjustSummary)\(shiftSummary)\(resetSummary)\(closeSummary)\(projectNoteSummary)"
        guard includeBlockLines else {
            return summary
        }
        return "\(summary), \(success.previewBlockLines.joined(separator: ", "))"
    }

    private func subBulletAccessibilityLabel(
        for success: CaptureCommandSuccess,
        subBullet: CaptureSubBulletPresentation,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> String {
        // VoiceOver announces the compact item once, from the header: the
        // sub-bullet phrase plus the item text, with position and override.
        let position = total > 1 ? "Item \(index + 1) of \(total), " : ""
        let override = isLocalOverride ? ", local override" : ""
        return "\(position)\(subBullet.accessibilityText)\(override), \(success.taskLine)"
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

    private func completePreviewAccessibilityLabel(
        for complete: CaptureTaskCompletePresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> String {
        let position = total > 1 ? "Item \(index + 1) of \(total), " : ""
        let override = isLocalOverride ? ", local override" : ""
        return "\(position)\(success.kind)\(override), \(complete.previewAccessibilitySummary)"
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

    @ViewBuilder
    private func linkGuardPreviewItem(
        _ linkGuard: CaptureLinkGuardPresentation,
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
            Image(systemName: linkGuard.glyphName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(linkGuard.headline)
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
            if !linkGuard.detail.isEmpty {
                Text(linkGuard.detail)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ForEach(linkGuard.promoted, id: \.self) { identity in
                Text(identity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(linkGuardPreviewAccessibilityLabel(
            for: linkGuard,
            success: success,
            index: index,
            total: total,
            isLocalOverride: isLocalOverride
        ))
    }

    private func linkGuardPreviewAccessibilityLabel(
        for linkGuard: CaptureLinkGuardPresentation,
        success: CaptureCommandSuccess,
        index: Int,
        total: Int,
        isLocalOverride: Bool
    ) -> String {
        let position = total > 1 ? "Item \(index + 1) of \(total), " : ""
        let override = isLocalOverride ? ", local override" : ""
        return "\(position)\(success.kind)\(override), \(linkGuard.previewAccessibilitySummary)"
    }
}
