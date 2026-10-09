import CaptureCore
import Foundation

/// Selection moves over a frozen listing, wrapping `CapturePickerNavigation`
/// over `listing.orderedIDs`.
public enum RefsMove: Equatable, Sendable {
    case next
    case previous
    case pageUp
    case pageDown
    case first
    case last
    case nextSection
    case previousSection
}

public enum RefsSelectionPolicy {
    /// A query or scope edit selects the first row of the new ranking, and
    /// opening the panel selects the first row of the first section.
    public static func initial(in listing: RefsListing) -> String? {
        listing.orderedIDs.first
    }

    /// Moves `step` from `id`: up/down wraps, paging clamps, section
    /// jumps land on the first row of the next or previous section in
    /// browse mode and are a no-op in search. An unknown or missing
    /// selection resolves to the first row.
    public static func move(
        _ step: RefsMove,
        from id: String?,
        in listing: RefsListing,
        pageSize: Int
    ) -> String? {
        let ids = listing.orderedIDs
        guard !ids.isEmpty else {
            return nil
        }
        guard let id, ids.contains(id) else {
            return ids.first
        }
        switch step {
        case .next:
            return CapturePickerNavigation.next(after: id, in: ids)
        case .previous:
            return CapturePickerNavigation.previous(before: id, in: ids)
        case .pageUp:
            return CapturePickerNavigation.page(from: id, by: -max(pageSize, 1), in: ids)
        case .pageDown:
            return CapturePickerNavigation.page(from: id, by: max(pageSize, 1), in: ids)
        case .first:
            return CapturePickerNavigation.first(in: ids)
        case .last:
            return CapturePickerNavigation.last(in: ids)
        case .nextSection, .previousSection:
            return moveSection(step, from: id, in: listing)
        }
    }

    static func moveSection(_ step: RefsMove, from id: String, in listing: RefsListing) -> String? {
        guard case .browse = listing.mode else {
            return id
        }
        let sections = listing.sections
        guard let current = sections.firstIndex(where: { $0.ids.contains(id) }) else {
            return listing.orderedIDs.first
        }
        let next: Int = {
            switch step {
            case .nextSection:
                return (current + 1) % sections.count
            case .previousSection:
                return (current + sections.count - 1) % sections.count
            default:
                return current
            }
        }()
        return sections[next].ids.first
    }
}
