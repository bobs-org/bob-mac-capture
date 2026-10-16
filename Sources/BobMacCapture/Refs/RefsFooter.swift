import RefsCore
import SwiftUI

/// The 30 pt footer on the glass: keycap hints on the left, the
/// library status on the right. When the selected row's PDF is
/// missing, the first hint reads "Return opens the note".
///
/// Status priority, top wins: scanning, refresh failed, the scan
/// notice, rename status, updating, updated.
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
            if let card = model.todayLinkCard {
                Text(RefsTodayLinkPresentation.hints(query: card.query))
            } else if model.copyCard != nil {
                Text("Copy — press a key")
            } else {
                ViewThatFits(in: .horizontal) {
                    ForEach(
                        Self.hintVariants(
                            openHint: openHint,
                            tabsFilter: model.tabsFilter
                        ),
                        id: \.self
                    ) {
                        Text($0)
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    static func hintsText(openHint: String, tabsFilter: Bool = false) -> String {
        hintVariants(openHint: openHint, tabsFilter: tabsFilter)[0]
    }

    static func hintVariants(openHint: String, tabsFilter: Bool = false) -> [String] {
        if tabsFilter {
            let core =
                "\(openHint)  ⌃X Close Tab  ⌘↵ Note  ⌥↵ Reveal  ⌘Y Copy  ⌘N Today  ⌘K Actions"
            // Drop Reveal first when the 760 pt footer can no longer
            // hold the full Tabs core; Close Tab stays in every variant.
            let compactCore =
                "\(openHint)  ⌃X Close Tab  ⌘↵ Note  ⌘Y Copy  ⌘N Today  ⌘K Actions"
            return [
                "\(core)  ⌘T Library  ⌘1–5 Scope  esc Close",
                "\(core)  ⌘T Library  esc Close",
                "\(core)  ⌘T Library",
                "\(compactCore)  ⌘T Library",
            ]
        }
        let core = "\(openHint)  ⌘↵ Note  ⌥↵ Reveal  ⌘Y Copy  ⌘N Today  ⌘K Actions"
        return [
            "\(core)  ⌘S Scan  ⌘1–5 Scope  ⌘T Tabs  esc Close",
            "\(core)  ⌘S Scan  esc Close",
            "\(core)  esc Close",
        ]
    }

    private var openHint: String {
        if model.tabsFilter {
            return "↵ Switch"
        }
        guard let selected = model.selectedID,
              let content = model.rowContent(for: selected),
              content.isMissingPDF
        else {
            return "↵ Open in Highlights"
        }
        return "↵ Open note"
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

    /// Whether the rename status shows: only when set and no
    /// higher-priority state (scanning, refresh failure, scan notice)
    /// is active. Pure so tests pin the precedence without building
    /// the view.
    static func showsRenameStatus(
        renameStatus: String?,
        isScanning: Bool,
        refreshFailed: Bool,
        hasScanNotice: Bool
    ) -> Bool {
        guard renameStatus != nil else {
            return false
        }
        return statusPriority(
            isScanning: isScanning,
            refreshFailed: refreshFailed,
            hasScanNotice: hasScanNotice,
            refreshing: false
        ) == .updated
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
            if Self.showsRenameStatus(
                renameStatus: model.renameStatus,
                isScanning: model.isScanning,
                refreshFailed: isRefreshFailed,
                hasScanNotice: model.scanNotice != nil
            ), let renameStatus = model.renameStatus {
                Text(renameStatus)
                    .foregroundStyle(.secondary)
            } else {
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
        if model.scanNotice != nil {
            if let notice = model.scanNotice {
                let text = RefsScanPresentation.footerText(
                    notice,
                    searchMode: searchMode
                )
                return "scan-\(notice.kind)-\(text)"
            }
            return "scan"
        }
        if let renameStatus = model.renameStatus {
            return "rename-\(renameStatus)"
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
