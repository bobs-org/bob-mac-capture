import AppKit
import Foundation
import ImageIO
import RefsCore

/// Loads annotation-image metrics and downsampled bitmaps so tests can
/// inject stubs. Failures return nil and are never cached.
public protocol RefsAnnotationImageProviding: Sendable {
  func metrics(for url: URL) async -> RefsImageMetrics?
  func image(for url: URL, maxPixel: Int) async -> NSImage?
}

/// ImageIO-backed loader: raster headers from
/// `CGImageSourceCopyPropertiesAtIndex` (no decode), bitmaps from
/// `CGImageSourceCreateThumbnailAtIndex`, GIF frame 0, SVG through
/// `NSImage` on the main actor. Metrics cache by (path, size, mtime);
/// bitmaps live in an `NSCache` of about 128 MB keyed by
/// (path, mtime, maxPixel). Decoding runs off the main actor.
public actor RefsAnnotationImageLoader: RefsAnnotationImageProviding {
  /// Byte-cost cap for decoded bitmaps.
  public static let bitmapCacheByteLimit = 128 * 1024 * 1024

  private struct MetricsKey: Hashable, Sendable {
    var path: String
    var fileSize: UInt64
    var mtime: TimeInterval
  }

  private let cache = NSCache<NSString, NSImage>()
  private var metricsCache: [MetricsKey: RefsImageMetrics] = [:]

  public init() {
    cache.totalCostLimit = Self.bitmapCacheByteLimit
  }

  public func metrics(for url: URL) async -> RefsImageMetrics? {
    if Self.isSVG(url) {
      return await svgMetrics(for: url)
    }
    let key = metricsKey(for: url)
    if let cached = metricsCache[key] {
      return cached
    }
    guard let loaded = Self.rasterMetrics(for: url) else {
      return nil
    }
    metricsCache[key] = loaded
    return loaded
  }

  public func image(for url: URL, maxPixel: Int) async -> NSImage? {
    let pixel = max(maxPixel, 1)
    if Self.isSVG(url) {
      return await MainActor.run { NSImage(contentsOf: url) }
    }
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    let mtime = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let cacheKey = "\(url.path)|\(mtime)|\(pixel)" as NSString
    if let cached = cache.object(forKey: cacheKey) {
      return cached
    }
    guard let loaded = await Self.rasterImage(for: url, maxPixel: pixel) else {
      return nil
    }
    cache.setObject(loaded, forKey: cacheKey, cost: Self.cost(for: loaded))
    return loaded
  }

  private func metricsKey(for url: URL) -> MetricsKey {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return MetricsKey(
      path: url.path,
      fileSize: (attributes?[.size] as? NSNumber)?.uint64Value ?? 0,
      mtime: (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    )
  }

  private func svgMetrics(for url: URL) async -> RefsImageMetrics? {
    let image = await MainActor.run { NSImage(contentsOf: url) }
    guard let image else {
      return nil
    }
    let width = max(1, Int(image.size.width.rounded()))
    let height = max(1, Int(image.size.height.rounded()))
    return RefsImageMetrics(
      pixelWidth: width,
      pixelHeight: height,
      hasAlpha: true
    )
  }

  private static func isSVG(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == "svg"
  }

  private static func rasterMetrics(for url: URL) -> RefsImageMetrics? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any]
    else {
      return nil
    }
    let pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    guard pixelWidth > 0, pixelHeight > 0 else {
      return nil
    }
    let dpiWidth = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
    let dpiHeight = (props[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue
    let dpi: Double?
    if let dpiWidth, dpiWidth.isFinite, dpiWidth > 0 {
      dpi = dpiWidth
    } else if let dpiHeight, dpiHeight.isFinite, dpiHeight > 0 {
      dpi = dpiHeight
    } else {
      dpi = nil
    }
    let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let hasAlpha = (props[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false
    return RefsImageMetrics(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      dpi: dpi,
      orientation: orientation,
      hasAlpha: hasAlpha
    )
  }

  private static func rasterImage(for url: URL, maxPixel: Int) async -> NSImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let cgImage = CGImageSourceCreateThumbnailAtIndex(
        source, 0, options as CFDictionary
      )
    else {
      return nil
    }
    let size = NSSize(width: cgImage.width, height: cgImage.height)
    return await MainActor.run {
      NSImage(cgImage: cgImage, size: size)
    }
  }

  private static func cost(for image: NSImage) -> Int {
    let width =
      image.representations.map(\.pixelsWide).max()
      ?? max(1, Int(image.size.width.rounded()))
    let height =
      image.representations.map(\.pixelsHigh).max()
      ?? max(1, Int(image.size.height.rounded()))
    return max(1, width * height * 4)
  }
}

/// Main-actor cache of decoded annotation images. Preview-installed
/// images are returned for any `maxPixel`. Vault-relative paths resolve
/// through `RefsVaultAssetPath` against `library.vaultRootURL`.
@MainActor
public final class RefsInspectorImageStore {
  private let library: RefsLibrary
  private let provider: RefsAnnotationImageProviding
  private var loaded: [String: NSImage] = [:]
  private var previewImages: [String: NSImage] = [:]

  public init(library: RefsLibrary, provider: RefsAnnotationImageProviding) {
    self.library = library
    self.provider = provider
  }

  /// Synchronous hit: a preview-installed image or one already loaded.
  public func cachedImage(path: String, maxPixel: Int) -> NSImage? {
    if let preview = previewImages[path] {
      return preview
    }
    return loaded[cacheKey(path: path, maxPixel: maxPixel)]
  }

  public func loadImage(path: String, maxPixel: Int) async -> NSImage? {
    if let cached = cachedImage(path: path, maxPixel: maxPixel) {
      return cached
    }
    guard let url = RefsVaultAssetPath.resolve(path, root: library.vaultRootURL)
    else {
      return nil
    }
    let pixel = max(maxPixel, 1)
    guard let image = await provider.image(for: url, maxPixel: pixel) else {
      return nil
    }
    loaded[cacheKey(path: path, maxPixel: pixel)] = image
    return image
  }

  public func installImagesForPreviews(_ images: [String: NSImage]) {
    previewImages = images
  }

  public func reset() {
    loaded = [:]
    previewImages = [:]
  }

  /// Pixel size, DPI, and alpha from a preview `NSImage`, so design
  /// fixtures reserve the same frames the live loader would.
  public static func metrics(from image: NSImage) -> RefsImageMetrics {
    var pixelWidth = max(1, Int(image.size.width.rounded()))
    var pixelHeight = max(1, Int(image.size.height.rounded()))
    var dpi: Double?
    var hasAlpha = false
    if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
      if bitmap.pixelsWide > 0 {
        pixelWidth = bitmap.pixelsWide
      }
      if bitmap.pixelsHigh > 0 {
        pixelHeight = bitmap.pixelsHigh
      }
      hasAlpha = bitmap.hasAlpha
      if bitmap.size.width > 0 {
        let computed =
          Double(bitmap.pixelsWide) / Double(bitmap.size.width) * 72
        if computed.isFinite, computed > 0 {
          dpi = computed
        }
      }
    } else if let rep = image.representations.first {
      if rep.pixelsWide > 0 {
        pixelWidth = rep.pixelsWide
      }
      if rep.pixelsHigh > 0 {
        pixelHeight = rep.pixelsHigh
      }
    }
    return RefsImageMetrics(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      dpi: dpi,
      hasAlpha: hasAlpha
    )
  }

  private func cacheKey(path: String, maxPixel: Int) -> String {
    "\(path)|\(maxPixel)"
  }
}
