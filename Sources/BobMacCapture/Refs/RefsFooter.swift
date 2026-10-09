import RefsCore
import SwiftUI

/// The 30 pt footer on the glass: keycap hints on the left, the
/// library status on the right. When the selected row's PDF is
/// missing, the first hint reads "Return opens the note".
///
/// Status priority, top wins: scanning, refresh failed, the scan
/// notice, updating, updated.
@available(macOS 26.0, *)
struct RefsFooter: View {
    @ObservedObject var model: RefsPanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    static func hintsText(openHint: String) -> String {
        "\(openHint)  ⌘↵ Note  ⌥↵ Reveal  ⌘K Actions  ⌘S Scan  ⌘1–5 Scope  esc Close"
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
        return Self.hintsText(openHint: openHint)
    }

    private var searchMode: Bool {
        if case .search = model.listing.mode {
            return true
        }
        return false
    }

    /// The status decision, top wins: scanning, refresh failed, the
    /// scan notice, updating, updated. Pure so tests pin the order
    /// without building the view.
    enum StatusPriority: Equatable {
        case scanning
        case refreshFailed
        case scan
        case updating
        case updated
    }

    static func statusPriority(
        isScanning: Bool,
        refreshFailed: Bool,
        hasScanNotice: Bool,
        refreshing: Bool
    ) -> StatusPriority {
        if isScanning {
            return .scanning
        }
        if refreshFailed {
            return .refreshFailed
        }
        if hasScanNotice {
            return .scan
        }
        if refreshing {
            return .updating
        }
        return .updated
    }

    private var status: some View {
        Group {
            switch Self.statusPriority(
                isScanning: model.isScanning,
                refreshFailed: isRefreshFailed,
                hasScanNotice: model.scanNotice != nil,
                refreshing: isRefreshing
            ) {
            case .scanning:
                scanningStatus
            case .refreshFailed:
                Text("Update failed · ⌘R to retry")
                    .foregroundStyle(.orange)
            case .scan:
                if let notice = model.scanNotice {
                    scanStatus(notice)
                }
            case .updating, .updated:
                refreshStatus
            }
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.15),
            value: statusKey
        )
    }

    private var isRefreshFailed: Bool {
        if case .failed = model.refreshState {
            return true
        }
        return false
    }

    private var isRefreshing: Bool {
        if case .refreshing = model.refreshState {
            return true
        }
        return false
    }

    private var statusKey: String {
        if model.isScanning {
            return "scanning"
        }
        if case .failed = model.refreshState {
            return "refresh-failed"
        }
        if let notice = model.scanNotice {
            let text = RefsScanPresentation.footerText(
                notice,
                searchMode: searchMode
            )
            return "scan-\(notice.kind)-\(text)"
        }
        return "refresh-\(String(describing: model.refreshState))"
    }

    private var scanningStatus: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text(scanText(at: context.date))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scanText(at date: Date) -> String {
        let started = model.scanStartedAt ?? date
        return RefsScanPresentation.scanningText(elapsed: date.timeIntervalSince(started))
    }

    private func scanStatus(_ outcome: RefsScanOutcome) -> some View {
        let text = RefsScanPresentation.footerText(outcome, searchMode: searchMode)
        switch outcome.kind {
        case .succeeded:
            return AnyView(
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(text)
                        .foregroundStyle(.secondary)
                }
            )
        case .partial, .failed:
            return AnyView(
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(text)
                        .foregroundStyle(.orange)
                }
            )
        }
    }

    private var refreshStatus: some View {
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
    }
}
