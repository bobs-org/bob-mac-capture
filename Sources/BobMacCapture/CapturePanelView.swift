import CaptureCore
import SwiftUI

@available(macOS 26.0, *)
struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel
    @State private var selection = AttributedTextSelection()
    @AccessibilityFocusState private var errorIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.attributedDraft, selection: $selection)
                    .font(.system(.body, design: .monospaced))
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 190)
                    .padding(10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(model.isSubmitting)
                    .onChange(of: String(model.attributedDraft.characters)) { _, newText in
                        model.editorTextDidChange(cursorUTF8Offset: newText.utf8.count)
                    }

                if model.completionVisible {
                    CompletionList(model: model)
                        .frame(width: 430)
                        .padding(.leading, 14)
                        .padding(.top, 42)
                }
            }

            if let destinationSummary = model.destinationSummary {
                Text(destinationSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
            }

            PreviewPane(model: model)

            HStack(alignment: .center, spacing: 8) {
                Text(model.statusText.isEmpty ? "Ready" : model.statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 12)
                if model.pendingDiscardConfirmation {
                    Button("Discard") {
                        model.discardDraft()
                    }
                    Button("Keep Draft") {
                        model.pendingDiscardConfirmation = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
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
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 420)
    }
}

@available(macOS 26.0, *)
private struct CompletionList: View {
    @ObservedObject var model: CapturePanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((model.completionResponse?.candidates ?? []).enumerated()), id: \.offset) {
                index, candidate in
                CompletionRow(
                    candidate: candidate,
                    detail: model.detailText(
                        for: candidate,
                        context: model.completionResponse?.context
                    ),
                    selected: index == model.selectedCompletionIndex
                )
                .onTapGesture {
                    model.selectedCompletionIndex = index
                    model.acceptSelectedCompletion()
                }
            }
        }
        .padding(6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 12, y: 6)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
