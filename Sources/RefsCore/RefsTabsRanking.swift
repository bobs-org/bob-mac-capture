import Foundation

/// A Tabs-mode listing and the tab metadata for each row.
public struct RefsTabsListing: Equatable, Sendable {
    /// The ordinary listing consumed by the Refs panel.
    public let listing: RefsListing
    /// The tab row associated with each listing id.
    public let tabs: [String: RefsOpenTab]
    /// The row selected when the panel first enters Tabs mode.
    public let preselectedID: String?

    /// Creates a tab listing.
    public init(
        listing: RefsListing,
        tabs: [String: RefsOpenTab],
        preselectedID: String?
    ) {
        self.listing = listing
        self.tabs = tabs
        self.preselectedID = preselectedID
    }
}

/// Builds the scoped, searchable Highlights Tabs listing.
public enum RefsTabsRanker {
    /// Applies the current kind scope, A5 browse order, or existing tiered search.
    public static func listing(
        tabs: [RefsOpenTab],
        items: [RefItem],
        query: String,
        scope: RefScope,
        signals: RefsSignals,
        recency: RefsTabRecency,
        highlightsIsFrontmost: Bool
    ) -> RefsTabsListing {
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inScope = tabs.filter { tab in
            switch tab.match {
            case .path, .fileName:
                guard let itemID = tab.itemID, let item = itemsByID[itemID] else {
                    return false
                }
                return scope.contains(item.kind)
            case .collision:
                return tab.candidateIDs.contains { itemID in
                    guard let item = itemsByID[itemID] else {
                        return false
                    }
                    return scope.contains(item.kind)
                }
            case .none:
                return scope == .all
            }
        }
        let tabMap = Dictionary(inScope.map { ($0.rowID, $0) }, uniquingKeysWith: { first, _ in first })
        let currentIDs = Set(inScope.filter(\.isCurrent).map(\.rowID))
        let openStates: Set<RefState> = [.reading, .next, .ready]
        let openCount = inScope.compactMap { tab in
            tab.itemID.flatMap { itemsByID[$0] }
        }.filter { openStates.contains($0.state) }.count
        let tokens = RefsText.queryTokens(query)

        if tokens.isEmpty {
            let orderedTabs = browseOrder(inScope, recency: recency)
            let ids = orderedTabs.map(\.rowID)
            let listing = RefsListing(
                mode: .browse,
                scope: scope,
                sections: [RefsSection(kind: .inHighlights, ids: ids)],
                orderedIDs: ids,
                matches: [:],
                totalCount: inScope.count,
                openCount: openCount,
                highlightsCurrentIDs: currentIDs,
                highlightsTabIDs: Set(inScope.map(\.rowID))
            )
            let selectedIndex = highlightsIsFrontmost && ids.count > 1 ? 1 : 0
            return RefsTabsListing(
                listing: listing,
                tabs: tabMap,
                preselectedID: ids.indices.contains(selectedIndex) ? ids[selectedIndex] : nil
            )
        }

        let searchItems = inScope.compactMap { tab -> RefItem? in
            if let itemID = tab.itemID, let item = itemsByID[itemID] {
                return item
            }
            return syntheticItem(for: tab)
        }
        let ranked = RefsRanker.searchRows(
            searchItems,
            tokens: tokens,
            rawQuery: query,
            signals: signals
        )
        let ids = ranked.map(\.id)
        let matches = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0.match) })
        let listing = RefsListing(
            mode: .search(query),
            scope: scope,
            sections: ids.isEmpty ? [] : [RefsSection(kind: nil, ids: ids)],
            orderedIDs: ids,
            matches: matches,
            totalCount: inScope.count,
            openCount: openCount,
            highlightsCurrentIDs: currentIDs,
            highlightsTabIDs: Set(inScope.map(\.rowID))
        )
        return RefsTabsListing(
            listing: listing,
            tabs: tabMap,
            preselectedID: ids.first
        )
    }

    private static func browseOrder(
        _ tabs: [RefsOpenTab],
        recency: RefsTabRecency
    ) -> [RefsOpenTab] {
        tabs.sorted { left, right in
            if left.isCurrent != right.isCurrent {
                return left.isCurrent
            }
            let leftIsUnmatched = left.match == .none
            let rightIsUnmatched = right.match == .none
            if leftIsUnmatched != rightIsUnmatched {
                return !leftIsUnmatched
            }
            if !leftIsUnmatched {
                let leftDate = recency.lastActive(left.fileName)
                let rightDate = recency.lastActive(right.fileName)
                switch (leftDate, rightDate) {
                case let (leftDate?, rightDate?) where leftDate != rightDate:
                    return leftDate > rightDate
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    break
                }
            }
            if left.windowOrdinal != right.windowOrdinal {
                return left.windowOrdinal < right.windowOrdinal
            }
            return left.tabOrdinal < right.tabOrdinal
        }
    }

    private static func syntheticItem(for tab: RefsOpenTab) -> RefItem {
        let title = HighlightsTabMatcher.titleStem(forFileName: tab.fileName)
        return RefItem(
            id: tab.rowID,
            link: "",
            rawTitle: title,
            stem: title,
            kind: .other(raw: nil),
            state: .unknown,
            isBlocked: false,
            pdfPath: ""
        )
    }
}

/// The count text for the Tabs filter, whose total is never labelled "open".
public enum RefsTabsCount {
    /// Returns `9 tabs` in browse mode or `2 of 9 tabs` while searching.
    public static func text(shown: Int, total: Int, isSearch: Bool) -> String {
        let shownCount = max(0, shown)
        let totalCount = max(0, total)
        if isSearch {
            return "\(shownCount) of \(totalCount) tabs"
        }
        return "\(totalCount) \(totalCount == 1 ? "tab" : "tabs")"
    }
}
