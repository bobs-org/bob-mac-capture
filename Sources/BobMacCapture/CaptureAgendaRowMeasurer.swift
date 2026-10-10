import AppKit
import CaptureCore
import SwiftUI

/// Offscreen agenda row measurer: one reusable `NSHostingView` whose
/// `rootView` is swapped per row. Heights are cached by (row key,
/// width rounded to pixel) and reused across snapshots, so unchanged
/// rows are never re-measured. It measures the same row views the
/// agenda renders, so the planner's total matches the laid-out height.
@MainActor
final class CaptureAgendaRowMeasurer {
    struct CacheKey: Hashable {
        let key: CaptureAgendaRowKey
        let widthPixels: Int
        let role: CaptureAgendaRole
    }

    /// Upper bound for the cache. `noteSnapshotChange()` clears it
    /// only past this size.
    static let cacheBound = 2_000

    private var cache: [CacheKey: CGFloat] = [:]
    private var host: NSHostingView<AnyView>?

    var cachedCount: Int { cache.count }

    func height(
        for row: CaptureAgendaRow,
        role: CaptureAgendaRole,
        at width: CGFloat,
        displayScale: CGFloat = 2
    ) -> CGFloat {
        let pixels = max(1, Int((width * displayScale).rounded()))
        let cacheKey = CacheKey(key: row.key, widthPixels: pixels, role: role)
        if let hit = cache[cacheKey] {
            return hit
        }
        let measured = renderHeight(for: row, role: role, at: width)
        cache[cacheKey] = measured
        return measured
    }

    /// Conditional clear on snapshot change: the cache survives when
    /// it is small enough to still be useful.
    func noteSnapshotChange() {
        if cache.count > Self.cacheBound {
            cache = [:]
        }
    }

    func clear() {
        cache = [:]
    }

    private func renderHeight(
        for row: CaptureAgendaRow,
        role: CaptureAgendaRole,
        at width: CGFloat
    ) -> CGFloat {
        // The no-op expand keeps the measured tree identical to the
        // rendered one: chips measure as buttons, never as plain text.
        let content = CaptureAgendaRowView(
            row: row,
            role: role,
            expands: CaptureAgendaRowView.showsChip(for: row),
            chipUnit: nil,
            onExpand: { _ in }
        )
        .frame(width: width, alignment: .topLeading)
        if let host {
            host.rootView = AnyView(content)
        } else {
            host = NSHostingView(rootView: AnyView(content))
        }
        guard let host else {
            return CGFloat(CaptureAgendaLayoutMetrics.defaultRowHeight)
        }
        host.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.height.isFinite, size.height > 0 else {
            return CGFloat(CaptureAgendaLayoutMetrics.defaultRowHeight)
        }
        return size.height
    }
}

/// One measuring path for the model and the height-consistency
/// tests: measures what is missing, then plans to a fixpoint. A
/// freshly folded plan can surface new row variants (notes chips,
/// strips) that need measuring before the final plan, so planning
/// repeats until no new keys appear.
@MainActor
enum CaptureAgendaHeightResolver {
    static func resolve(
        presentation: CaptureAgendaPresentation,
        budget: Double,
        expanded: Set<CaptureAgendaUnitID>,
        width: CGFloat,
        measurer: CaptureAgendaRowMeasurer
    ) -> CaptureAgendaPlan {
        var heights: [CaptureAgendaRowKey: Double] = [:]
        measureMissing(
            presentation: presentation,
            plan: nil,
            width: width,
            measurer: measurer,
            heights: &heights
        )
        var plan = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: heights,
            budget: budget,
            expanded: expanded
        )
        for _ in 0..<8 {
            let known = heights.count
            measureMissing(
                presentation: presentation,
                plan: plan,
                width: width,
                measurer: measurer,
                heights: &heights
            )
            guard heights.count > known else {
                break
            }
            plan = CaptureAgendaFitPlanner.plan(
                presentation: presentation,
                heights: heights,
                budget: budget,
                expanded: expanded
            )
        }
        return plan
    }

    /// The width a role's rows render at: current-group rows sit
    /// inside the Now card, narrowed by its rail, gutter, and inner
    /// padding. Every other row renders at the full rows width.
    static func width(for role: CaptureAgendaRole, rowsWidth: CGFloat) -> CGFloat {
        guard role == .current else {
            return rowsWidth
        }
        return max(
            1,
            rowsWidth - CGFloat(CaptureAgendaLayoutMetrics.nowCardHorizontalChrome)
        )
    }

    static func measureMissing(
        presentation: CaptureAgendaPresentation,
        plan: CaptureAgendaPlan?,
        width: CGFloat,
        measurer: CaptureAgendaRowMeasurer,
        heights: inout [CaptureAgendaRowKey: Double]
    ) {
        for (row, role) in rowsWithRoles(presentation) {
            guard heights[row.key] == nil else {
                continue
            }
            heights[row.key] = Double(
                measurer.height(for: row, role: role, at: Self.width(for: role, rowsWidth: width))
            )
        }
        let strip = presentation.stripFullRow
        if heights[strip.key] == nil {
            heights[strip.key] = Double(
                measurer.height(for: strip, role: .later, at: Self.width(for: .later, rowsWidth: width))
            )
        }
        guard let plan else {
            return
        }
        for row in plan.rows {
            guard heights[row.key] == nil else {
                continue
            }
            // Chipped headers and rendered strips are planner-built
            // variants absent from the presentation lists; their role
            // comes from the same value match the view uses. Only
            // headers read the role, so the fallback is harmless.
            let role = CaptureAgendaSections.owner(of: row, in: presentation)?.role
                ?? .later
            heights[row.key] = Double(
                measurer.height(for: row, role: role, at: Self.width(for: role, rowsWidth: width))
            )
        }
    }

    static func rowsWithRoles(
        _ presentation: CaptureAgendaPresentation
    ) -> [(CaptureAgendaRow, CaptureAgendaRole)] {
        // One entry per row is enough: row heights never depend on
        // position. The role selects the measure width (the Now card
        // narrows current-group rows) and only otherwise affects group
        // headers, whose keys are unique per group outside
        // pathological vaults.
        var out: [(CaptureAgendaRow, CaptureAgendaRole)] = []
        out.append((presentation.titleRow, .later))
        if let warning = presentation.warningRow {
            out.append((warning, .later))
        }
        if let state = presentation.stateRow {
            out.append((state, .later))
        }
        for group in presentation.groups {
            out.append((group.headerRow, group.role))
            for row in group.sessionNoteRows {
                out.append((row, group.role))
            }
            for task in group.tasks {
                for row in task.fullRows {
                    out.append((row, group.role))
                }
                for row in task.noLogsRows {
                    out.append((row, group.role))
                }
                out.append((task.oneLineRow, group.role))
            }
            if let retired = group.retiredRow {
                out.append((retired, group.role))
            }
            if let empty = group.emptyRow {
                out.append((empty, group.role))
            }
            out.append((group.oneRowRow, group.role))
        }
        return out
    }
}
