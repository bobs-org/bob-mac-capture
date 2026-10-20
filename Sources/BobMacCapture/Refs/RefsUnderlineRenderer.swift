import RefsCore
import SwiftUI

/// Marks a quote `Text` run as an underline piece so the renderer
/// can draw a gold bar under it.
struct RefsUnderlineMark: TextAttribute {
  let role: RefsQuotePieceRole
}

/// Draws pixel-crisp rounded gold bars under underlined quote runs,
/// then paints the glyphs on top so descenders sit on the stroke.
@available(macOS 26.0, *)
struct RefsUnderlineRenderer: TextRenderer {
  /// Stored rather than read from the environment so proofs can force
  /// Increase Contrast; `colorSchemeContrast` cannot be set through
  /// `.environment`.
  var increasedContrast: Bool

  var displayPadding: EdgeInsets {
    EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0)
  }

  func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    let scale = Double(ctx.environment.displayScale)
    for line in layout {
      let bounds = line.typographicBounds
      let baseline = Double(bounds.rect.minY + bounds.ascent)
      let ascent = Double(bounds.ascent)
      let descent = Double(bounds.descent)
      var extents: [RefsQuoteLineRun] = []
      for run in line {
        let role = run[RefsUnderlineMark.self]?.role ?? .plain
        let rect = run.typographicBounds.rect
        extents.append(
          RefsQuoteLineRun(
            role: role,
            minX: Double(rect.minX),
            maxX: Double(rect.maxX)
          )
        )
      }
      for span in RefsQuoteUnderline.bars(in: extents) {
        guard
          let bar = RefsQuoteUnderline.bar(
            minX: span.minX,
            maxX: span.maxX,
            baseline: baseline,
            ascent: ascent,
            descent: descent,
            increasedContrast: increasedContrast,
            displayScale: scale
          )
        else {
          continue
        }
        let rect = CGRect(
          x: bar.x,
          y: bar.y,
          width: bar.width,
          height: bar.height
        )
        let path = RoundedRectangle(
          cornerRadius: bar.cornerRadius,
          style: .continuous
        ).path(in: rect)
        ctx.fill(path, with: .color(RefsVisualTokens.inspectorUnderlineInk))
      }
      ctx.draw(line)
    }
  }
}

@available(macOS 26.0, *)
extension View {
  func refsUnderlineInk() -> some View {
    modifier(RefsUnderlineInkModifier())
  }
}

@available(macOS 26.0, *)
private struct RefsUnderlineInkModifier: ViewModifier {
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    content.textRenderer(
      RefsUnderlineRenderer(increasedContrast: contrast == .increased)
    )
  }
}
