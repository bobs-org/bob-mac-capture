import CoreGraphics
import Foundation

/// Half-viewport inspector movement: Control-D is down, Control-U is up.
public enum RefsInspectorScrollDirection: Equatable, Sendable {
    case up
    case down
}

/// The inspector scroll view's measured extents. Offset uses the native
/// content-offset convention: with zero insets the valid range is 0
/// through max(content − viewport, 0); nonzero insets shift that range
/// by the top and bottom inset.
struct RefsInspectorScrollGeometry: Equatable, Sendable {
    var offsetY: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat

    static let invalid = RefsInspectorScrollGeometry(
        offsetY: 0,
        contentHeight: 0,
        viewportHeight: 0,
        topInset: 0,
        bottomInset: 0
    )

    var isValid: Bool {
        viewportHeight > 0
            && viewportHeight.isFinite
            && contentHeight.isFinite
            && offsetY.isFinite
            && topInset.isFinite
            && bottomInset.isFinite
    }

    /// The top rest offset, inset-aware.
    var minOffset: CGFloat {
        -topInset
    }

    /// The bottom rest offset, inset-aware.
    var maxOffset: CGFloat {
        max(contentHeight - viewportHeight + bottomInset, minOffset)
    }

    func clamped(_ offset: CGFloat) -> CGFloat {
        guard isValid else {
            return offset
        }
        return min(max(offset, minOffset), maxOffset)
    }
}

/// Keyboard target and bounds for the inspector scroll view. Successive
/// commands accumulate from an outstanding target until geometry
/// catches up or the user takes over with a trackpad or mouse.
struct RefsInspectorScrollPlanner: Equatable, Sendable {
    private(set) var geometry: RefsInspectorScrollGeometry
    private(set) var pendingTarget: CGFloat?

    /// The offset the next command should start from.
    var offset: CGFloat {
        pendingTarget ?? geometry.offsetY
    }

    init(geometry: RefsInspectorScrollGeometry = .invalid) {
        self.geometry = geometry
        pendingTarget = nil
    }

    mutating func reset() {
        geometry = .invalid
        pendingTarget = nil
    }

    /// Half-viewport movement. Returns the y to jump to, or nil when
    /// geometry is invalid or not yet laid out.
    mutating func command(
        _ direction: RefsInspectorScrollDirection
    ) -> CGFloat? {
        guard geometry.isValid else {
            return nil
        }
        let delta = geometry.viewportHeight / 2
        let raw: CGFloat
        switch direction {
        case .down:
            raw = offset + delta
        case .up:
            raw = offset - delta
        }
        let next = geometry.clamped(raw)
        pendingTarget = next
        return next
    }

    /// Trackpad or mouse scrolling takes over from the measured offset.
    mutating func beginUserScroll(at offset: CGFloat) {
        pendingTarget = nil
        if geometry.isValid {
            geometry.offsetY = geometry.clamped(offset)
        } else {
            geometry.offsetY = offset
        }
    }

    /// Records a measured geometry update. When a keyboard target is
    /// outstanding, the measured offset is ignored unless it has settled
    /// on that target, so a delayed callback cannot replace a newer
    /// command. Returns a y to jump to when the pending or current
    /// offset is now out of bounds.
    @discardableResult
    mutating func applyGeometry(
        _ new: RefsInspectorScrollGeometry
    ) -> CGFloat? {
        if let pending = pendingTarget {
            let clamped = new.clamped(pending)
            var stored = new
            stored.offsetY = clamped
            geometry = stored
            if new.isValid, abs(new.offsetY - clamped) <= 0.5 {
                pendingTarget = nil
                geometry.offsetY = new.offsetY
                return nil
            }
            pendingTarget = clamped
            if new.isValid, abs(clamped - pending) > 0.5 {
                return clamped
            }
            return nil
        }
        geometry = new
        guard new.isValid else {
            return nil
        }
        let clamped = new.clamped(new.offsetY)
        if abs(clamped - new.offsetY) > 0.5 {
            geometry.offsetY = clamped
            return clamped
        }
        return nil
    }
}
