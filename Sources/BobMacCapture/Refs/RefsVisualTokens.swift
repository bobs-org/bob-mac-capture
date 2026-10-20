import AppKit
import CaptureCore
import Foundation
import RefsCore
import SwiftUI

/// Every size constant from the panel spec (§6–§9) as named statics, plus
/// the pure panel-geometry math the controller and the geometry tests
/// share. Colors are adaptive system colors only, so dark mode and
/// increased contrast carry through without bespoke handling; yellow
/// (rule, card, and chip) and orange (note glyph) mean your highlights
/// and notes in the inspector.
enum RefsVisualTokens {
  // MARK: - Window

  /// Compact reference size in points. The live panel no longer uses
  /// a fixed size (see `panelSize(for:)`); 880 keeps its meaning as
  /// the compact reference the fixtures and list-only math use.
  static let panelWidth: CGFloat = 880
  /// Compact reference height, like `panelWidth`.
  static let panelHeight: CGFloat = 560
  /// Glass corner radius.
  static let glassRadius: CGFloat = 20
  /// Outer padding between the glass and the content well.
  static let outerPadding: CGFloat = 8
  /// Content-well radius, concentric with the glass.
  static let wellRadius: CGFloat = 12

  // MARK: - Pieces

  static let searchBarHeight: CGFloat = 52
  static let sectionHeaderHeight: CGFloat = RefsListGeometry.sectionHeaderHeight
  static let rowHeight: CGFloat = RefsListGeometry.rowHeight
  static let footerHeight: CGFloat = 30
  static let listVerticalPadding: CGFloat = RefsListGeometry.verticalPadding
  static let inspectorPadding: CGFloat = 18
  static let inspectorSpacing: CGFloat = 14
  static let heroTileSize: CGFloat = 44
  static let heroTileRadius: CGFloat = 11
  static let thumbnailWidth: CGFloat = 112
  static let thumbnailHeight: CGFloat = 145
  static let thumbnailRadius: CGFloat = 6
  /// Wide-layout thumbnail in points (US-letter ratio, like the
  /// compact size); the loader renders one 300 x 388 px image and
  /// both layouts draw from it.
  static let wideThumbnailWidth: CGFloat = 150
  static let wideThumbnailHeight: CGFloat = 194
  /// Wide-layout section spacing.
  static let wideInspectorSpacing: CGFloat = 18
  /// Wide-layout spacing between HIGHLIGHTS entries.
  static let wideInspectorEntrySpacing: CGFloat = 12
  /// Wide-layout title line limit.
  static let wideInspectorTitleLineLimit = 3
  /// Wide-layout quote line limit.
  static let wideInspectorQuoteLineLimit = 6
  /// Wide-layout quote line spacing.
  static let wideInspectorQuoteLineSpacing: CGFloat = 3
  static let kindTileSize: CGFloat = 28
  static let kindTileRadius: CGFloat = 7
  static let factLabelWidth: CGFloat = 84
  /// Context kept above a newly revealed notes page, so the last line
  /// of the previous page stays visible.
  static let inspectorRevealContext: CGFloat = 24
  static let inspectorQuoteRuleWidth: CGFloat = 2
  static let inspectorQuoteInset: CGFloat = 10
  static let inspectorHighlightLineLimit = 4
  static let inspectorPageRunGap: CGFloat = 4
  /// Vertical spacing between HIGHLIGHTS entries.
  static let inspectorEntrySpacing: CGFloat = 8
  /// Sticky-note glyph on the note card and the header chip.
  static let inspectorNoteSymbol = "note.text"
  /// Orange glyph tint: the darker sibling of the yellow card.
  static let inspectorNoteTint: Color = .orange
  static let inspectorNoteFillOpacity = 0.14
  static let inspectorNoteStrokeOpacity = 0.30
  static let inspectorNoteStrokeOpacityIncreased = 0.60
  static let inspectorNoteRadius: CGFloat = 8
  static let inspectorNoteVerticalPadding: CGFloat = 6
  /// Gap between a quote and its note card.
  static let inspectorNoteGap: CGFloat = 6
  /// Vertical gap between stacked attached images inside a note card.
  static let inspectorImageStackSpacing: CGFloat = 8
  /// Cross-fade from the image placeholder to the decoded bitmap.
  static let inspectorImageFadeDuration = 0.15

  // MARK: - Copy card

  static let copyCardHeaderHeight: CGFloat = 44
  static let copyCardRowHeight: CGFloat = 24
  static let copyCardPickerRowHeight: CGFloat = 36
  static let copyCardSeparatorHeight: CGFloat = 9
  static let copyCardNotesHeaderHeight: CGFloat = 22
  static let copyCardMessageLineHeight: CGFloat = 20
  static let copyCardVerticalPadding: CGFloat = 36
  static let copyCardKeycapSize: CGFloat = 18
  static let copyCardKeycapCornerRadius: CGFloat = 4.5
  static let copyCardLabelWidth: CGFloat = 92
  static let copyCardRowCornerRadius: CGFloat = 8
  static let copyHUDMaxValueWidth: CGFloat = 380

  /// Metrics the Copy card feeds `RefsCopyCardLayout`.
  static var copyCardMetrics: RefsCopyCardMetrics {
    RefsCopyCardMetrics(
      headerHeight: Double(copyCardHeaderHeight),
      rowHeight: Double(copyCardRowHeight),
      separatorHeight: Double(copyCardSeparatorHeight),
      notesHeaderHeight: Double(copyCardNotesHeaderHeight),
      messageLineHeight: Double(copyCardMessageLineHeight),
      verticalPadding: Double(copyCardVerticalPadding)
    )
  }

  // MARK: - Geometry

  /// The reading-room panel size for a visible frame. Delegates to
  /// `RefsPanelGeometry` so the controller, the views, and the pure
  /// geometry tests share one contract.
  static func panelSize(for visibleFrame: NSRect) -> NSSize {
    let size = RefsPanelGeometry.panelSize(visible: visibleFrame)
    return NSSize(width: size.width, height: size.height)
  }

  /// Whether the inspector column shows at a panel width.
  static func showsInspector(width: CGFloat) -> Bool {
    RefsPanelGeometry.showsInspector(panelWidth: width)
  }

  /// The list column width for a panel width.
  static func listWidth(panelWidth: CGFloat) -> CGFloat {
    RefsPanelGeometry.listWidth(panelWidth: panelWidth)
  }

  /// The panel frame for a visible frame: the reading-room size,
  /// centered on both axes. Recomputed on every show.
  static func panelFrame(for visibleFrame: NSRect) -> NSRect {
    RefsPanelGeometry.panelFrame(visible: visibleFrame)
  }

  // MARK: - Kind and state

  /// The kind tint: purple chat, teal paper, brown article, indigo
  /// doc, secondary for everything else. Status hues never encode
  /// kind; pink means the Now lane only; the accent means selection,
  /// matches, and the New dot.
  static let newDotSize: CGFloat = 6
  static let newDotGutterWidth: CGFloat = 8
  static let newDotHiddenScale: CGFloat = 0.3
  static let newDotAppearResponse: Double = 0.3
  static let newDotAppearDamping: Double = 0.6
  static let newDotDisappearDuration: Double = 0.16
  static let newDotReduceMotionDuration: Double = 0.12
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
