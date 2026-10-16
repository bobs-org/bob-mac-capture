import RefsCore
import SwiftUI

/// The Tabs-mode content well: state cards, the delayed skeleton, and
/// the stale-rows notice, all styled like `RefsLoadFailedView` and
/// `RefsEmptyStateView`. They render only what `tabs-model` publishes
/// (`tabsFilter`, `tabsState`); the rows themselves reuse the shared
/// list, row, and inspector views.
@available(macOS 26.0, *)
enum RefsTabsViews {
    /// The retry line shared by the failed notice and the failed card.
    static let readFailedText = "Couldn't read Highlights' tabs · ⌘R to retry"
}

/// The centered card shell for every Tabs state card: an orange glyph
/// over message text and action buttons, on the same material card as
/// `RefsLoadFailedView`.
@available(macOS 26.0, *)
private struct RefsTabsCard<Content: View>: View {
    let systemImage: String
    let content: Content

    init(systemImage: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        )
        .padding(16)
    }
}

/// The permission card: explains the Accessibility need, offers the
/// prompting check behind an explicit button press, and offers the way
/// back to the library. The hint explains how to recover a missing or
/// stale grant for either signing style.
@available(macOS 26.0, *)
struct RefsTabsPermissionCard: View {
    @ObservedObject var model: RefsPanelModel
    let adHoc: Bool

    var body: some View {
        RefsTabsCard(systemImage: "hand.raised") {
            Text("Bob Refs needs Accessibility access to see Highlights' tabs.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(AccessibilityTrust.permissionHint(isAdHocBuild: adHoc))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Open Accessibility Settings") {
                    model.perform(.requestTabsPermission)
                }
                Button("Show library (⌘T)") {
                    model.perform(.setTabsFilter(false))
                }
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let label = "Bob Refs needs Accessibility access to see Highlights' tabs."
        return "\(label) \(AccessibilityTrust.permissionHint(isAdHocBuild: adHoc))"
    }
}

/// The card when Highlights is not running.
@available(macOS 26.0, *)
struct RefsTabsNotRunningCard: View {
    var body: some View {
        RefsTabsCard(systemImage: "moon.zzz") {
            Text("Highlights isn't running.")
                .font(.headline)
            Text("⌘T shows the library")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Highlights isn't running. ⌘T shows the library")
    }
}

/// The card when Highlights runs with no open documents.
@available(macOS 26.0, *)
struct RefsTabsNoDocumentsCard: View {
    var body: some View {
        RefsTabsCard(systemImage: "square.on.square") {
            Text("No documents are open in Highlights.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No documents are open in Highlights.")
    }
}

/// The card when a tab read failed and no stale rows survive: the same
/// text as the stale-rows notice.
@available(macOS 26.0, *)
struct RefsTabsFailedCard: View {
    var body: some View {
        RefsTabsCard(systemImage: "exclamationmark.triangle") {
            Text(RefsTabsViews.readFailedText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(RefsTabsViews.readFailedText)
    }
}

/// The banner-style notice above dimmed stale rows after a failed
/// re-read: orange card, callout text, no buttons. A ⌘R retry or a new
/// snapshot replaces it.
@available(macOS 26.0, *)
struct RefsTabsFailedNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
            Text(RefsTabsViews.readFailedText)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(RefsTabsViews.readFailedText)
    }
}

/// The empty well in Tabs mode: a centered magnifying glass plus what
/// missed. A typed query that matches nothing names the query; an
/// empty query under a kind scope names the scope; anything else is
/// the no-documents line. Never the library scan hint: ⌘S scans the
/// library, not Highlights.
@available(macOS 26.0, *)
struct RefsTabsEmptyView: View {
    let query: String
    let scope: RefScope

    /// The empty-well message. Pure so tests pin the wording without
    /// building the view.
    static func message(query: String, scope: RefScope) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return "No tabs match “\(trimmed)”"
        }
        if scope != .all {
            return "No \(scope.label) tabs open · ⌘1 shows All"
        }
        return "No documents are open in Highlights."
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(Self.message(query: query, scope: scope))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.message(query: query, scope: scope))
    }
}

/// The Tabs loading state: nothing for about 150 ms, then the shared
/// skeleton rows, so a fast read never flashes a skeleton. Design
/// fixtures pass `previewMode` to render the skeleton at once, keeping
/// renders deterministic.
@available(macOS 26.0, *)
struct RefsTabsDelayedSkeleton: View {
    var previewMode = false
    @State private var revealed = false

    var body: some View {
        Group {
            if previewMode || revealed {
                RefsSkeletonList()
            } else {
                Color.clear
            }
        }
        .accessibilityLabel("Loading Highlights tabs")
        .task {
            guard !previewMode else {
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            revealed = true
        }
    }
}
