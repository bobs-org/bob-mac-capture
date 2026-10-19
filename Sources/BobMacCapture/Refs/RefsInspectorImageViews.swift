import AppKit
import RefsCore
import SwiftUI

/// One annotation image at a reserved `displaySize`. The placeholder
/// holds that frame until the bitmap arrives, then the bitmap
/// cross-fades in. Preview mode and Reduce Motion skip the fade.
/// Images are not interactive; VoiceOver reads them through the entry.
struct RefsInspectorImageView: View {
  let path: String
  let metrics: RefsImageMetrics
  let displaySize: CGSize
  var store: RefsInspectorImageStore? = nil
  var previewMode = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var loaded: NSImage?
  @State private var appeared: Bool

  init(
    path: String,
    metrics: RefsImageMetrics,
    displaySize: CGSize,
    store: RefsInspectorImageStore? = nil,
    previewMode: Bool = false
  ) {
    self.path = path
    self.metrics = metrics
    self.displaySize = displaySize
    self.store = store
    self.previewMode = previewMode
    let cached = store?.cachedImage(path: path, maxPixel: Self.maxPixel(for: displaySize))
    _loaded = State(initialValue: cached)
    _appeared = State(initialValue: previewMode || cached != nil)
  }

  var body: some View {
    let bitmap = loaded ?? store?.cachedImage(path: path, maxPixel: maxPixel)
    ZStack {
      if metrics.hasAlpha {
        RoundedRectangle(
          cornerRadius: RefsVisualTokens.thumbnailRadius,
          style: .continuous
        )
        .fill(Color.white)
      }
      if let bitmap, appeared || previewMode || reduceMotion {
        Image(nsImage: bitmap)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
      } else if let bitmap {
        Image(nsImage: bitmap)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .opacity(appeared ? 1 : 0)
      } else {
        placeholder
      }
    }
    .frame(width: displaySize.width, height: displaySize.height)
    .clipShape(
      RoundedRectangle(
        cornerRadius: RefsVisualTokens.thumbnailRadius,
        style: .continuous
      )
    )
    .overlay(
      RoundedRectangle(
        cornerRadius: RefsVisualTokens.thumbnailRadius,
        style: .continuous
      )
      .stroke(.primary.opacity(0.08), lineWidth: 0.5)
    )
    .help(fileName)
    .accessibilityHidden(true)
    .task(id: taskID) {
      guard !previewMode, let store else {
        return
      }
      let image = await store.loadImage(path: path, maxPixel: maxPixel)
      loaded = image
      if reduceMotion {
        appeared = true
      } else {
        withAnimation(
          .easeOut(duration: RefsVisualTokens.inspectorImageFadeDuration)
        ) {
          appeared = true
        }
      }
    }
  }

  private var placeholder: some View {
    ZStack {
      RoundedRectangle(
        cornerRadius: RefsVisualTokens.thumbnailRadius,
        style: .continuous
      )
      .fill(.secondary.opacity(0.08))
      Image(systemName: "photo")
        .font(.title2)
        .foregroundStyle(.tertiary)
    }
  }

  private var fileName: String {
    URL(fileURLWithPath: path).lastPathComponent
  }

  private var maxPixel: Int {
    Self.maxPixel(for: displaySize)
  }

  private var taskID: String {
    "\(path)|\(maxPixel)"
  }

  static func maxPixel(for displaySize: CGSize) -> Int {
    Int(ceil(max(max(displaySize.width, displaySize.height), 1) * 2))
  }
}

/// One-line tertiary caption for an image that did not resolve or
/// could not be read. Absence stays honest and takes one line, not a
/// box.
struct RefsInspectorImageUnavailableRow: View {
  let fileName: String

  private static let symbolName: String = {
    if NSImage(
      systemSymbolName: "photo.badge.exclamationmark",
      accessibilityDescription: nil
    ) != nil {
      return "photo.badge.exclamationmark"
    }
    return "exclamationmark.triangle"
  }()

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: Self.symbolName)
        .imageScale(.small)
      Text("Image unavailable")
      Text(fileName)
        .font(.caption.monospaced())
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .font(.caption)
    .foregroundStyle(.tertiary)
    .accessibilityHidden(true)
  }
}
