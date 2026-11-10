import CaptureCore
import SwiftUI

/// Read-only preview for notebook note bullets and notebook creation.
/// All paths, ancestry, sections, and Markdown come from Bob's result.
@available(macOS 26.0, *)
struct CaptureNotebookPreviewView: View {
    let item: CaptureCommandSuccess
    let file: CaptureNoteFile?

    private var headline: String {
        CaptureNotebookPresentation.headline(for: item)
    }

    private var bodyText: String {
        return CaptureNotebookPresentation.contentText(for: item)
    }

    private var seedBody: String? {
        guard item.kind == "notebook_create",
              let body = file?.body,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return body
    }

    private var breadcrumb: String? {
        guard let components = item.notebook?.breadcrumb, !components.isEmpty else {
            return nil
        }
        return components.joined(separator: " › ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headingRow
            if let breadcrumb, !breadcrumb.isEmpty {
                Text(breadcrumb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel("Notebook path: \(breadcrumb)")
            }
            if let badge = CaptureNotebookPresentation.newSectionBadge(for: item) {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel(badge)
            }
            if !bodyText.isEmpty {
                Text(bodyText)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Notebook note content: \(bodyText)")
            }
            if let seedBody {
                Text(seedBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Seed notes: \(seedBody)")
            }
            if !item.subBullets.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(item.subBullets.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.subBullets.joined(separator: "\n"))
            }
            if item.kind == "notebook_create",
               let file,
               file.isUsable
            {
                CaptureNoteMarkdownDisclosure(
                    markdown: file.markdown,
                    identifierPrefix: "notebook-note"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var headingRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "book.closed")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(headline)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headline)
            Text(item.relativeTarget)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("Path \(item.relativeTarget)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilitySummary: String {
        var parts = [headline]
        if let breadcrumb, !breadcrumb.isEmpty {
            parts.append(breadcrumb)
        }
        if !bodyText.isEmpty {
            parts.append(bodyText)
        }
        return parts.joined(separator: ". ")
    }
}
