import SwiftUI

@available(macOS 26.0, *)
struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel
    @State private var selection = AttributedTextSelection()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $model.attributedDraft, selection: $selection)
                .font(.system(.body, design: .monospaced))
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 190)
                .padding(10)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text(model.statusText.isEmpty ? "Ready" : model.statusText)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.pendingDiscardConfirmation {
                    Button("Discard") {
                        model.discardDraft()
                    }
                    Button("Keep Draft") {
                        model.pendingDiscardConfirmation = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Button("Capture") {
                    model.submit(openAfterCapture: false)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 300)
    }
}
