import AppKit
import RefsCore
import SwiftUI

/// The search field behind `RefsSearchBar`: capture's borderless
/// single-line field with the Refs accessibility identifier, a 20 pt
/// font, and the same focus-repair behavior.
@available(macOS 26.0, *)
struct RefsFilterField: NSViewRepresentable {
    @Binding var text: String
    let onTextChange: (String) -> Void

    func makeNSView(context: Context) -> CapturePickerFilterNSTextField {
        let field = CapturePickerFilterNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.placeholderString = "Search references"
        field.font = NSFont.systemFont(ofSize: 20)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(refsFilterFieldAccessibilityIdentifier)
        field.setAccessibilityLabel("Search references")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.requestFirstResponder()
        return field
    }

    func updateNSView(_ field: CapturePickerFilterNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RefsFilterField

        init(parent: RefsFilterField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            parent.onTextChange(field.stringValue)
        }
    }
}

/// The 52 pt search bar drawn directly on the glass: a magnifying
/// glass, the search field, the Newest or Tabs token, the scope token
/// when the scope is not All, and the trailing count plus a refresh
/// spinner.
@available(macOS 26.0, *)
struct RefsSearchBar: View {
    @ObservedObject var model: RefsPanelModel
    /// When true, draws the query as text so `ImageRenderer` design
    /// tests never host an `NSViewRepresentable`.
    var previewMode = false
    @StateObject private var announcer = RefsCountAnnouncer()

    /// The filter field exactly as the bar wires it: the binding mirrors
    /// `model.query`, and every keystroke reaches the model before the
    /// re-rank, so the next `updateNSView` never wipes the field. Exposed
    /// so tests drive the real wiring.
    func makeFilterField() -> RefsFilterField {
        RefsFilterField(
            text: Binding(
                get: { model.query },
                set: { model.query = $0 }
            )
        ) { model.setQuery($0) }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
            if previewMode {
                Text(model.query.isEmpty ? "Search references" : model.query)
                    .font(.system(size: 20))
                    .foregroundStyle(model.query.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                makeFilterField()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if model.listOrder == .newest {
                newestToken
            } else if model.tabsFilter {
                tabsToken
            }
            if model.scope != .all {
                scopeToken
            }
            count
            if model.refreshState == .refreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: RefsVisualTokens.searchBarHeight)
    }

    /// The Newest token, drawn in the Tabs token's slot before the
    /// scope token. Activating it turns Newest off.
    private var newestToken: some View {
        Button {
            model.perform(.setNewest(false))
        } label: {
            HStack(spacing: 5) {
                Image(systemName: RefsNewestToken.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                Text("Newest")
                    .font(.callout.weight(.semibold))
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Sorted newest first. Activate to show library sections."
        )
    }

    /// The Tabs filter token, drawn before the scope token in the
    /// same capsule style. Activating it leaves Tabs mode.
    private var tabsToken: some View {
        Button {
            model.perform(.setTabsFilter(false))
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 12, weight: .semibold))
                Text("Tabs")
                    .font(.callout.weight(.semibold))
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tabs filter. Activate to clear.")
    }

    private var scopeToken: some View {
        let kind = RefsVisualTokens.kind(for: model.scope)
        let tint = RefsVisualTokens.tint(for: kind)
        return Button {
            model.perform(.deleteBackwardOnEmpty)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                Text(model.scope.label)
                    .font(.callout.weight(.semibold))
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scope \(model.scope.label). Activate to clear.")
    }

    private var count: some View {
        Text(countText)
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel(countAccessibilityLabel)
            .onChange(of: model.query) { _, _ in
                announcer.schedule(countAnnouncement)
            }
            .onChange(of: model.listing.orderedIDs.count) { _, _ in
                announcer.schedule(countAnnouncement)
            }
            .onChange(of: model.tabsFilter) { _, _ in
                announcer.schedule(countAnnouncement)
            }
            .onChange(of: model.listOrder) { _, _ in
                announcer.schedule(countAnnouncement)
            }
    }

    private var countText: String {
        if model.tabsFilter {
            let isSearch: Bool
            if case .search = model.listing.mode {
                isSearch = true
            } else {
                isSearch = false
            }
            return RefsTabsCount.text(
                shown: model.listing.orderedIDs.count,
                total: model.listing.totalCount,
                isSearch: isSearch
            )
        }
        if case .search = model.listing.mode {
            return "\(model.listing.orderedIDs.count) of \(model.listing.totalCount)"
        }
        return "\(model.listing.openCount) open · \(model.listing.totalCount)"
    }

    private var countAccessibilityLabel: String {
        if model.tabsFilter {
            return countText
        }
        return "\(model.listing.totalCount) references"
    }

    private var countAnnouncement: String {
        if model.tabsFilter {
            return countText
        }
        return "\(model.listing.orderedIDs.count) of \(model.listing.totalCount) references"
    }
}

/// The Newest search-bar token's SF Symbol, with a calendar fallback
/// when `calendar.day.timeline.left` is missing on this OS.
enum RefsNewestToken {
    static let preferredSymbolName = "calendar.day.timeline.left"
    static let fallbackSymbolName = "calendar"

    static var symbolName: String {
        if NSImage(
            systemSymbolName: preferredSymbolName,
            accessibilityDescription: nil
        ) != nil {
            return preferredSymbolName
        }
        return fallbackSymbolName
    }
}

/// Debounces result-count announcements through the same post helper
/// capture's picker uses: the announcement goes out 600 ms after
/// typing stops, so counts are never announced on every keystroke.
@MainActor
private final class RefsCountAnnouncer: ObservableObject {
    private var generation = 0

    func schedule(_ message: String) {
        generation += 1
        let current = generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, current == self.generation else {
                return
            }
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
