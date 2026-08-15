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
    static let editorMaximumVisibleLines = 6
    static let completionVisibleRows = 5
    static let completionRowHeight: CGFloat = 48
    static let completionViewportHeight = completionRowHeight * CGFloat(completionVisibleRows) + 12
    static let stashVisibleRows = 5
    static let stashRowHeight: CGFloat = 58
    static let stashViewportHeight = stashRowHeight * CGFloat(stashVisibleRows) + 12
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
            .onChange(of: displayScale) { _, _ in
                reportContentMetrics()
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CapturePanelLayout.sectionSpacing) {
            AutosizingCaptureEditor(model: model, selection: $model.editorSelection, focus: $focusedControl)
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
        model.isStashPickerPresented
            || model.taskIDPromptVisible
            || model.completionVisible
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
            if model.isStashPickerPresented {
                CanceledDraftStashPicker(model: model)
                    .frame(width: 520)
                    .padding(.leading, 14)
                    .layoutPriority(0)
                    .id(AuxiliarySection.stash)
            } else {
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

    private func applyFocusRequest(_ request: CapturePanelFocusRequest) {
        focusedControl = request.target
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
                    .disabled(model.isSubmitting || model.taskIDPromptVisible)
                    .focused(focus, equals: .editor)
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
                    .focused(focus, equals: .taskIDPromptBlockID)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
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
                    .padding(6)
                }
                .frame(maxHeight: CapturePanelLayout.stashViewportHeight, alignment: .top)
                .onAppear {
                    scrollSelectionIntoView(proxy)
                }
                .onChange(of: model.selectedStashIndex) { _, _ in
                    scrollSelectionIntoView(proxy)
                }
            }

            clearAllButton
        }
        .padding(6)
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
                    .frame(width: 58, height: 22)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .accessibilityLabel("Shift-D Delete All")
        .accessibilityHint(
            "Permanently removes all retained canceled drafts from the current app session. "
                + "Lowercase d does not delete."
        )
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
        .frame(minHeight: CapturePanelLayout.stashRowHeight - 8, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
