import RefsCore
import SwiftUI

/// A 26 pt pinned section header: the uppercase title plus the count.
@available(macOS 26.0, *)
struct RefsSectionHeader: View {
    let kind: RefsSectionKind
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(kind.title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: RefsVisualTokens.sectionHeaderHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title), \(count) references")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The list column: a scroll view of pinned sections whose selection
/// stays visible without animation. Reports its visible row budget to
/// the model so paging moves by one less than fits.
@available(macOS 26.0, *)
struct RefsListView: View {
    @ObservedObject var model: RefsPanelModel

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(model.listing.sections, id: \.sectionID) { section in
                            Section {
                                ForEach(section.ids, id: \.self) { id in
                                    row(for: id)
                                        .id(id)
                                }
                            } header: {
                                if let kind = section.kind {
                                    RefsSectionHeader(kind: kind, count: section.ids.count)
                                }
                            }
                        }
                    }
                    .padding(.vertical, RefsVisualTokens.listVerticalPadding)
                }
                .onChange(of: model.selectedID) { _, selected in
                    if let selected {
                        proxy.scrollTo(selected)
                    }
                }
                .onChange(of: model.listing.orderedIDs) { _, _ in
                    if let selected = model.selectedID {
                        proxy.scrollTo(selected)
                    }
                }
                .onAppear {
                    reportBudget(height: geometry.size.height)
                }
                .onChange(of: geometry.size.height) { _, height in
                    reportBudget(height: height)
                }
                .accessibilityLabel("References")
            }
        }
    }

    private func row(for id: String) -> some View {
        guard let content = model.rowContent(for: id) else {
            return AnyView(EmptyView())
        }
        return AnyView(
            RefsRowView(
                content: content,
                isSelected: model.selectedID == id,
                pomodoroName: model.pomodoroName(for: id),
                onSelect: {
                    model.perform(.select(id: id))
                },
                onActivate: {
                    model.perform(.activate(id: id))
                }
            )
        )
    }

    private func reportBudget(height: CGFloat) {
        let budget = max(1, Int(height / RefsVisualTokens.rowHeight))
        if model.visibleRowBudget != budget {
            model.visibleRowBudget = budget
        }
    }
}

private extension RefsSection {
    /// A stable identity for `ForEach`: the kind, or "search" for the
    /// single ranked section.
    var sectionID: String {
        kind.map { "section-\($0)" } ?? "search"
    }
}
