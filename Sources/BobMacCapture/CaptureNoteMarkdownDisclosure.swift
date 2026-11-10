import AppKit
import SwiftUI

/// Shared exact-Markdown disclosure used by planned record and notebook
/// previews. The identifier prefix preserves each card's UI-test hooks.
@available(macOS 26.0, *)
struct CaptureNoteMarkdownDisclosure: View {
    let markdown: String
    let identifierPrefix: String
    @State private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(markdown: String, identifierPrefix: String, expanded: Bool = false) {
        self.markdown = markdown
        self.identifierPrefix = identifierPrefix
        _isExpanded = State(initialValue: expanded)
    }

    var body: some View {
        DisclosureGroup("View Markdown", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(markdown)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Exact note Markdown")
                Button("Copy Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifierPrefix)-copy-markdown")
                .accessibilityLabel("Copy exact note Markdown")
                .accessibilityHint("Copies the exact Markdown Bob will write")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("\(identifierPrefix)-view-markdown")
        .accessibilityLabel("View Markdown")
        .accessibilityHint(
            isExpanded ? "Hides the exact note Markdown" : "Shows the exact note Markdown"
        )
        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isExpanded)
    }
}
