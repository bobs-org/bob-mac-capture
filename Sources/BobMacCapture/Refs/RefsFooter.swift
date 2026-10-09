import RefsCore
import SwiftUI

/// The 30 pt footer on the glass: keycap hints on the left, the
/// library status on the right. When the selected row's PDF is
/// missing, the first hint reads "Return opens the note".
@available(macOS 26.0, *)
struct RefsFooter: View {
    @ObservedObject var model: RefsPanelModel
    @State private var now = Date()

    private let minute = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            hints
            Spacer(minLength: 8)
            status
        }
        .padding(.horizontal, 14)
        .frame(height: RefsVisualTokens.footerHeight)
        .onReceive(minute) { now = $0 }
    }

    private var hints: some View {
        Group {
            if let toast = model.toast {
                Text(toast)
            } else {
                Text(hintsText)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var hintsText: String {
        let openHint: String = {
            guard let selected = model.selectedID,
                  let content = model.rowContent(for: selected),
                  content.isMissingPDF
            else {
                return "↵ Open in Highlights"
            }
            return "↵ Open note"
        }()
        return "\(openHint)  ⌘↵ Note  ⌥↵ Reveal  ⌘K Actions  ⌘1–5 Scope  esc Close"
    }

    private var status: some View {
        Group {
            switch model.refreshState {
            case .refreshing:
                Text("Updating…")
                    .foregroundStyle(.secondary)
            case .failed:
                Text("Update failed · ⌘R to retry")
                    .foregroundStyle(.orange)
            case .idle:
                if let last = model.lastSuccessAt {
                    Text("Updated \(RefsCaption.relativeCompact(last, now: now))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never updated")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}
