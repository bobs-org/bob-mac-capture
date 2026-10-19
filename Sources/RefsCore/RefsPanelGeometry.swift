import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry for the Bob Refs reading-room panel. The calculations use
/// Foundation types so the layout contract remains testable on Linux.
public enum RefsPanelGeometry {
    public static let maxWidth: CGFloat = 1440
    public static let maxHeight: CGFloat = 1000
    public static let horizontalMargin: CGFloat = 48
    public static let verticalMargin: CGFloat = 36
    public static let outerPadding: CGFloat = 8
    public static let listFraction: CGFloat = 0.52
    public static let maxListWidth: CGFloat = 560
    public static let inspectorThreshold: CGFloat = 760
    public static let dividerWidth: CGFloat = 0.5
    public static let wideColumnThreshold: CGFloat = 568
    public static let compactPadding: CGFloat = 18
    public static let widePadding: CGFloat = 24
    public static let readableWidth: CGFloat = 720

    public static func panelSize(visible: CGRect) -> CGSize {
        let availableWidth = finiteNonNegative(visible.size.width - 2 * horizontalMargin)
        let availableHeight = finiteNonNegative(visible.size.height - 2 * verticalMargin)
        return CGSize(
            width: floorToPoint(min(maxWidth, availableWidth)),
            height: floorToPoint(min(maxHeight, availableHeight))
        )
    }

    public static func panelFrame(visible: CGRect) -> CGRect {
        let size = panelSize(visible: visible)
        let x = visible.origin.x + ((visible.size.width - size.width) / 2).rounded()
        let y = visible.origin.y + ((visible.size.height - size.height) / 2).rounded()
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    public static func showsInspector(panelWidth: CGFloat) -> Bool {
        panelWidth >= inspectorThreshold
    }

    public static func listWidth(panelWidth: CGFloat) -> CGFloat {
        let width = finiteNonNegative(panelWidth)
        return min((width * listFraction).rounded(), maxListWidth)
    }

    public static func inspectorColumnWidth(panelWidth: CGFloat) -> CGFloat {
        max(
            0,
            finiteNonNegative(panelWidth)
                - 2 * outerPadding
                - listWidth(panelWidth: panelWidth)
                - dividerWidth
        )
    }

    public static func inspectorLayout(panelWidth: CGFloat) -> RefsInspectorLayout {
        let columnWidth = inspectorColumnWidth(panelWidth: panelWidth)
        let mode: RefsInspectorLayout.Mode = columnWidth >= wideColumnThreshold ? .wide : .compact
        let padding = mode == .wide ? widePadding : compactPadding
        let contentWidth: CGFloat
        if mode == .wide {
            contentWidth = min(max(0, columnWidth - 2 * padding), readableWidth)
        } else {
            contentWidth = max(0, columnWidth - 2 * padding)
        }
        return RefsInspectorLayout(
            mode: mode,
            columnWidth: columnWidth,
            padding: padding,
            contentWidth: contentWidth
        )
    }

    private static func finiteNonNegative(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 0
        }
        return max(0, value)
    }

    private static func floorToPoint(_ value: CGFloat) -> CGFloat {
        finiteNonNegative(value).rounded(.down)
    }
}

/// The inspector's pure width mode and image sizing limits.
public struct RefsInspectorLayout: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case compact
        case wide
    }

    public let mode: Mode
    public let columnWidth: CGFloat
    public let padding: CGFloat
    public let contentWidth: CGFloat

    public var imageMaxHeight: CGFloat {
        mode == .wide ? 420 : 260
    }

    public init(
        mode: Mode,
        columnWidth: CGFloat,
        padding: CGFloat,
        contentWidth: CGFloat
    ) {
        self.mode = mode
        self.columnWidth = columnWidth
        self.padding = padding
        self.contentWidth = contentWidth
    }
}
