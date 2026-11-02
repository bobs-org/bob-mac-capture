import CaptureCore
import SwiftUI

/// The capsule above a list's results in the preview (`3 tasks → dev.md`,
/// `2 notes → dev.md · ideas`). Bob reports each bullet as its own result; the
/// capsule stacks a list's results under one heading. The text and the
/// VoiceOver phrase come from `CaptureListPreview`, so the view only paints.
@available(macOS 26.0, *)
struct CaptureListGroupCapsule: View {
    let group: CaptureListPreviewGroup

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "list.bullet")
                .accessibilityHidden(true)
            Text(group.title)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.accessibilityLabel)
    }
}
