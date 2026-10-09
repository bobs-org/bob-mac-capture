import RefsCore
import SwiftUI

/// A 26 pt pinned section header: the uppercase title plus the count.
/// A Just scanned header adds a trailing relative time ("just now",
/// "4m ago"), refreshed each minute.
@available(macOS 26.0, *)
struct RefsSectionHeader: View {
    let kind: RefsSectionKind
    let count: Int
    /// When the scan finished, for the `.justScanned` trailing time.
    /// Nil for every other section.
    let at: Date?

    init(kind: RefsSectionKind, count: Int, at: Date? = nil) {
        self.kind = kind
        self.count = count
        self.at = at
    }

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
            if kind == .justScanned, let at {
                TimelineView(.everyMinute) { context in
                    Text(RefsCaption.relativeCompact(at, now: context.date))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: RefsVisualTokens.sectionHeaderHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    private var accessibilityLabel: String {
        if kind == .justScanned, let at {
            let when = RefsCaption.relativeCompact(at, now: Date())
            return "Just scanned, \(count) references, \(when)"
        }
        return "\(kind.title), \(count) references"
    }
}

/// The list column: a scroll view of pinned sections whose selection
/// stays visible without animation. Reports its visible row budget to
/// the model so paging moves by one less than fits.
@available(macOS 26.0, *)
struct RefsListView: View {
    @ObservedObject var model: RefsPanelModel
    /// Design fixtures lay the same rows out in a static stack:
    /// `ImageRenderer` snapshots `ScrollView` content blank, so the
    /// live scroll view never appears in a fixture.
    var previewMode = false

    var body: some View {
        if previewMode {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.listing.sections, id: \.sectionID) { section in
                    Section {
                        ForEach(section.ids, id: \.self) { id in
                            row(for: id)
                        }
                    } header: {
                        if let kind = section.kind {
                            RefsSectionHeader(
                                kind: kind,
                                count: section.ids.count,
                                at: headerScanDate(for: kind)
                            )
                        }
                    }
                }
            }
            .padding(.vertical, RefsVisualTokens.listVerticalPadding)
            .accessibilityLabel("References")
        } else {
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(.vertical) {
                        LazyVStack(
                            alignment: .leading,
                            spacing: 0,
                            pinnedViews: [.sectionHeaders]
                        ) {
                            ForEach(model.listing.sections, id: \.sectionID) { section in
                                Section {
                                    ForEach(section.ids, id: \.self) { id in
                                        row(for: id)
                                            .id(id)
                                    }
                                } header: {
                                    if let kind = section.kind {
                                        RefsSectionHeader(
                                            kind: kind,
                                            count: section.ids.count,
                                            at: headerScanDate(for: kind)
                                        )
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
    }

    private func headerScanDate(for kind: RefsSectionKind) -> Date? {
        guard kind == .justScanned else {
            return nil
        }
        return model.signals.scan?.at
    }

    private func row(for id: String) -> some View {
        guard let content = model.rowContent(for: id) else {
            return AnyView(EmptyView())
        }
        // The selected row keeps its frame live in the panel-root
        // coordinate space, so the ⌘K menu pops below it. Deselected
        // rows report nil, which never clears the current rect: the
        // next selection overwrites it, and a fresh presentation
        // clears it.
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
            .onGeometryChange(for: CGRect?.self) { proxy in
                model.selectedID == id
                    ? proxy.frame(in: .named("refsPanel")) : nil
            } action: { rect in
                if let rect {
                    model.selectedRowRect = rect
                }
            }
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
