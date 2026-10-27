import AppKit
import RefsCore
import SwiftUI

/// The editable stem and fixed PDF suffix for Bob Refs' rename flow.
@available(macOS 26.0, *)
struct RefsRenameCardView: View {
    let card: RefsRenameCard
    let focusSequence: UInt64
    let onDraftChange: (String) -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RENAME")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(card.title)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 5) {
                Text("File name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    RefsRenameStemField(
                        text: Binding(
                            get: { card.draftStem },
                            set: onDraftChange
                        ),
                        isEnabled: card.phase != .running,
                        focusSequence: focusSequence
                    )
                    .frame(minWidth: 40)
                    Text(RefsRenameCard.pdfSuffix)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(.background.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(.primary.opacity(contrast == .increased ? 0.28 : 0.12))
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("File name")
            }

            Text(RefsRenamePresentation.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch card.phase {
            case .idle:
                EmptyView()
            case .running:
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Renaming…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Renaming reference")
            case .failed(let message, let hint):
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint, !hint.isEmpty {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)
            Text(card.phase == .running ? "Rename in progress" : "Return renames · Esc cancels")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(RefsVisualTokens.inspectorPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rename reference")
    }
}

@available(macOS 26.0, *)
private struct RefsRenameStemField: NSViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let focusSequence: UInt64

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(refsRenameFieldAccessibilityIdentifier)
        field.setAccessibilityLabel("File name without extension")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.isEnabled = isEnabled
        guard context.coordinator.appliedFocusSequence != focusSequence else {
            return
        }
        context.coordinator.appliedFocusSequence = focusSequence
        requestFocus(in: field)
        DispatchQueue.main.async { [weak field] in
            guard let field, !field.holdsRenameFirstResponder else { return }
            self.requestFocus(in: field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func requestFocus(in field: NSTextField) {
        guard let window = field.window else { return }
        _ = window.makeFirstResponder(field)
        field.selectText(nil)
        (field.currentEditor() as? NSTextView)?.selectAll(nil)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RefsRenameStemField
        var appliedFocusSequence: UInt64?

        init(parent: RefsRenameStemField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

private extension NSTextField {
    var holdsRenameFirstResponder: Bool {
        guard let window else { return false }
        return window.firstResponder === self || window.firstResponder === currentEditor()
    }
}
