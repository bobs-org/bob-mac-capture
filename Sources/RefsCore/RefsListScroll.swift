import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Pure list geometry for the Bob Refs list column. The calculations use
/// Foundation types so the reveal contract remains testable on Linux.
public enum RefsListGeometry {
    public static let rowHeight: CGFloat = 44
    public static let sectionHeaderHeight: CGFloat = 26
    public static let verticalPadding: CGFloat = 6
}

/// One row's vertical span, measured from the content top. `pinnedInset`
/// is the pinned section header covering the viewport's top band for
/// this row: `sectionHeaderHeight` when the row's section has a kind,
/// else 0 (search mode's single section has no header).
public struct RefsListRowSpan: Equatable, Sendable {
    public let top: CGFloat
    public let bottom: CGFloat
    public let pinnedInset: CGFloat

    public init(top: CGFloat, bottom: CGFloat, pinnedInset: CGFloat) {
        self.top = top
        self.bottom = bottom
        self.pinnedInset = pinnedInset
    }
}

/// Where a reveal should scroll: the list's top edge, or an offset
/// measured from the content top in the `ScrollGeometry.contentOffset`
/// convention (valid range `0...maxOffset`).
public enum RefsListScrollTarget: Equatable, Sendable {
    case top
    case offset(CGFloat)
}

/// Header-aware reveal for the Refs list. A nil-anchor `scrollTo` scrolls
/// the minimum distance that fits a row inside the scroll view's bounds,
/// which parks a row's top flush with the viewport top, under its own
/// pinned section header. This policy instead treats the pinned header
/// as covering the viewport's top band, so a selected row's title line
/// never hides under the header.
public enum RefsListScrollPolicy {
    /// The full content height: top and bottom padding, one header per
    /// section whose kind is non-nil, and one row per listed id. It
    /// mirrors the view exactly, so an empty section that has a kind
    /// still counts its header.
    public static func contentHeight(of listing: RefsListing) -> CGFloat {
        var height = 2 * RefsListGeometry.verticalPadding
        for section in listing.sections {
            if section.kind != nil {
                height += RefsListGeometry.sectionHeaderHeight
            }
            height += RefsListGeometry.rowHeight * CGFloat(section.ids.count)
        }
        return height
    }

    /// The row's span, using the first section that contains the id and
    /// the id's first index within that section. Nil when the listing
    /// does not contain the id. Every listed id draws a 44 pt row, so
    /// spans need no measured layout.
    public static func rowSpan(for id: String, in listing: RefsListing) -> RefsListRowSpan? {
        guard let sectionIndex = listing.sectionIndex(for: id) else {
            return nil
        }
        let section = listing.sections[sectionIndex]
        guard let rowIndex = section.ids.firstIndex(of: id) else {
            return nil
        }
        var top = RefsListGeometry.verticalPadding
        for prior in listing.sections.prefix(sectionIndex) {
            if prior.kind != nil {
                top += RefsListGeometry.sectionHeaderHeight
            }
            top += RefsListGeometry.rowHeight * CGFloat(prior.ids.count)
        }
        let pinnedInset: CGFloat =
            section.kind != nil ? RefsListGeometry.sectionHeaderHeight : 0
        top += pinnedInset + RefsListGeometry.rowHeight * CGFloat(rowIndex)
        return RefsListRowSpan(
            top: top,
            bottom: top + RefsListGeometry.rowHeight,
            pinnedInset: pinnedInset
        )
    }

    /// The scroll target that fully reveals `id`:
    /// - Nil when the listing does not contain the id, or when `offset`
    ///   or `viewportHeight` is non-finite.
    /// - `.top` when the id is the listing's first row, unconditionally:
    ///   selecting the first row always means "show the top of the list",
    ///   and the measurement can be stale across a re-rank. The view
    ///   applies `.top` idempotently.
    /// - Nil when `viewportHeight <= 0`, because geometry has not been
    ///   measured yet.
    /// - A stale offset from taller, pre-re-rank content is clamped to
    ///   the new content before the decision.
    /// - A row above the pinned band (or partly under it) lands with its
    ///   top just under its section's header. For a section's first row,
    ///   that puts the section header in its natural place.
    /// - A row below the viewport lands with its bottom at the viewport
    ///   bottom; the listing's last row scrolls to the max offset so the
    ///   bottom padding shows.
    /// - Otherwise nil: the row already sits fully below the header.
    ///   The target is clamped to `0...maxOffset`, and a move within
    ///   half a point returns nil. Rule 5 wins over rule 6 when the
    ///   viewport is too short for both the header and the row, so the
    ///   title stays readable.
    public static func reveal(
        _ id: String,
        in listing: RefsListing,
        offset: CGFloat,
        viewportHeight: CGFloat
    ) -> RefsListScrollTarget? {
        guard listing.contains(id: id), offset.isFinite, viewportHeight.isFinite else {
            return nil
        }
        if id == listing.orderedIDs.first {
            return .top
        }
        guard viewportHeight > 0 else {
            return nil
        }
        let maxOffset = max(0, contentHeight(of: listing) - viewportHeight)
        let current = min(max(offset, 0), maxOffset)
        guard let span = rowSpan(for: id, in: listing) else {
            return nil
        }
        if span.top < current + span.pinnedInset - 0.5 {
            let target = min(max(span.top - span.pinnedInset, 0), maxOffset)
            guard abs(target - current) > 0.5 else {
                return nil
            }
            return .offset(target)
        }
        if span.bottom > current + viewportHeight + 0.5 {
            let raw: CGFloat =
                id == listing.orderedIDs.last ? maxOffset : span.bottom - viewportHeight
            let target = min(max(raw, 0), maxOffset)
            guard abs(target - current) > 0.5 else {
                return nil
            }
            return .offset(target)
        }
        return nil
    }
}
