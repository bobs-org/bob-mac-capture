import AppKit
import CaptureCore
import Foundation
import RefsCore
import SwiftUI

/// Every size constant from the panel spec (§6–§9) as named statics, plus
/// the pure panel-geometry math the controller and the geometry tests
/// share. Colors are adaptive system colors only, so dark mode and
/// increased contrast carry through without bespoke handling.
enum RefsVisualTokens {
    // MARK: - Window

    /// Fixed panel width in points, clamped to the screen.
    static let panelWidth: CGFloat = 880
    /// Fixed panel height in points, clamped to the screen.
    static let panelHeight: CGFloat = 560
    /// Margin kept around the panel on every side.
    static let screenMargin: CGFloat = 80
    /// Fraction of the visible height left above the panel's top edge.
    static let topFraction: CGFloat = 0.16
    /// Glass corner radius.
    static let glassRadius: CGFloat = 20
    /// Outer padding between the glass and the content well.
    static let outerPadding: CGFloat = 8
    /// Content-well radius, concentric with the glass.
    static let wellRadius: CGFloat = 12

    /// Width at and above which the inspector column shows.
    static let inspectorThreshold: CGFloat = 760
    /// Fraction of the panel width the list column takes.
    static let listFraction: CGFloat = 0.52

    // MARK: - Pieces

    static let searchBarHeight: CGFloat = 52
    static let sectionHeaderHeight: CGFloat = 26
    static let rowHeight: CGFloat = 44
    static let footerHeight: CGFloat = 30
    static let listVerticalPadding: CGFloat = 6
    static let inspectorPadding: CGFloat = 18
    static let inspectorSpacing: CGFloat = 14
    static let heroTileSize: CGFloat = 44
    static let heroTileRadius: CGFloat = 11
    static let thumbnailWidth: CGFloat = 112
    static let thumbnailHeight: CGFloat = 145
    static let thumbnailRadius: CGFloat = 6
    static let kindTileSize: CGFloat = 28
    static let kindTileRadius: CGFloat = 7
    static let factLabelWidth: CGFloat = 84

    // MARK: - Geometry

    /// The clamped panel size for a visible frame.
    static func panelSize(for visibleFrame: NSRect) -> NSSize {
        NSSize(
            width: min(panelWidth, visibleFrame.width - screenMargin),
            height: min(panelHeight, visibleFrame.height - screenMargin)
        )
    }

    /// Whether the inspector column shows at a panel width.
    static func showsInspector(width: CGFloat) -> Bool {
        width >= inspectorThreshold
    }

    /// The list column width for a panel width.
    static func listWidth(panelWidth: CGFloat) -> CGFloat {
        round(panelWidth * listFraction)
    }

    /// The panel frame for a visible frame: centered horizontally, the
    /// top edge below the top of the screen by `topFraction` of its
    /// height, then clamped inside the visible frame. Recomputed on
    /// every show.
    static func panelFrame(for visibleFrame: NSRect) -> NSRect {
        let size = panelSize(for: visibleFrame)
        let x = visibleFrame.minX + (visibleFrame.width - size.width) / 2
        var y = visibleFrame.maxY - round(visibleFrame.height * topFraction)
        y -= size.height
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    // MARK: - Kind and state

    /// The kind tint: purple chat, teal paper, brown article, indigo
    /// doc, secondary for everything else. Status hues never encode
    /// kind; pink means Today only; the accent means selection,
    /// matches, and the unopened dot.
    static func tint(for kind: RefKind) -> Color {
        switch kind {
        case .chat:
            return .purple
        case .paper:
            return .teal
        case .article:
            return .brown
        case .doc:
            return .indigo
        case .book, .slides, .other:
            return .secondary
        }
    }

    /// The palette status for an item: `isBlocked` overrides the
    /// displayed glyph and label but not the lane.
    static func paletteStatus(for item: RefItem) -> CapturePickerTaskStatus {
        if item.isBlocked {
            return .blocked
        }
        switch item.state {
        case .reading:
            return .inProgress
        case .next:
            return .next
        case .ready:
            return .todo
        case .read:
            return .done
        case .dropped:
            return .canceled
        case .unknown:
            return .other("unknown")
        }
    }

    /// The scope a scope token stands for, for its glyph and tint.
    static func kind(for scope: RefScope) -> RefKind {
        switch scope {
        case .all:
            return .other(raw: nil)
        case .chats:
            return .chat
        case .papers:
            return .paper
        case .articles:
            return .article
        case .docs:
            return .doc
        }
    }
}
