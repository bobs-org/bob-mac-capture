import SwiftUI

/// The orange banner above the list, with its action buttons. It is
/// dismissed by the next query edit, Esc, or a successful open — never
/// by a re-rank alone.
@available(macOS 26.0, *)
struct RefsBannerView: View {
    @ObservedObject var model: RefsPanelModel
    let banner: RefsBanner

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(banner.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if !banner.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(banner.actions, id: \.self) { action in
                            Button(actionLabel(for: action)) {
                                model.performBannerAction(action)
                            }
                            // Plain, not link or borderless: those two
                            // button styles snapshot as blank boxes in
                            // ImageRenderer, while plain renders its text.
                            .buttonStyle(.plain)
                            .font(.callout.weight(.semibold))
                            .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(banner.message)
    }

    private func actionLabel(for action: RefsBanner.Action) -> String {
        switch action {
        case .retry:
            return "Retry"
        case .tryAgain:
            return "Try Again"
        case .openInDefaultApp:
            return "Open in Default App"
        case .chooseHighlights:
            return "Choose Highlights…"
        case .copyDiagnostic:
            return "Copy Diagnostic"
        }
    }
}

/// The no-matches state: a centered magnifying glass plus what missed.
/// Return does nothing here.
@available(macOS 26.0, *)
struct RefsEmptyStateView: View {
    @ObservedObject var model: RefsPanelModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var message: String {
        let query = model.query.trimmingCharacters(in: .whitespaces)
        if model.scope == .all {
            return "No references match “\(query)”"
        }
        return "No \(model.scope.label) match “\(query)” · ⌘1 searches All"
    }
}

/// Eight skeleton rows while the first snapshot loads. The field stays
/// interactive, and the first real snapshot replaces this in place.
@available(macOS 26.0, *)
struct RefsSkeletonList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.secondary.opacity(0.2))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(0.25))
                            .frame(width: 220, height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(0.15))
                            .frame(width: 140, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .frame(height: RefsVisualTokens.rowHeight)
            }
        }
        .padding(.vertical, RefsVisualTokens.listVerticalPadding)
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading references")
    }
}

/// The centered callout card when no cache exists and the refresh
/// failed (or `bob` is unresolved): the bounded error plus Retry and
/// Copy Diagnostic.
@available(macOS 26.0, *)
struct RefsLoadFailedView: View {
    @ObservedObject var model: RefsPanelModel
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text("Bob couldn’t load your references")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            HStack(spacing: 12) {
                Button("Retry (⌘R)") {
                    model.perform(.refresh)
                }
                Button("Copy Diagnostic") {
                    model.performBannerAction(.copyDiagnostic)
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        )
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bob couldn’t load your references. \(message)")
    }
}
