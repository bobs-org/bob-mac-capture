import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Image metadata needed to reserve a stable inspector frame before its
/// pixels are decoded.
public struct RefsImageMetrics: Equatable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let dpi: Double?
    public let orientation: Int
    public let hasAlpha: Bool

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        dpi: Double? = nil,
        orientation: Int = 1,
        hasAlpha: Bool = false
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.dpi = dpi
        self.orientation = orientation
        self.hasAlpha = hasAlpha
    }

    /// Intrinsic point dimensions. Bob's 90 DPI threshold distinguishes
    /// physical-size metadata from ordinary pixel dimensions.
    public var pointSize: CGSize {
        guard pixelWidth > 0, pixelHeight > 0 else {
            return .zero
        }
        let scale: CGFloat
        if let dpi, dpi.isFinite, dpi >= 90 {
            scale = 72 / CGFloat(dpi)
        } else {
            scale = 1
        }
        var width = CGFloat(pixelWidth) * scale
        var height = CGFloat(pixelHeight) * scale
        if (5...8).contains(orientation) {
            swap(&width, &height)
        }
        return CGSize(width: width, height: height)
    }
}

/// Pure sizing helpers shared by the loader and the inspector views.
public enum RefsImageFit {
    /// Fits an image into its slot without enlarging it. Returned values
    /// are whole points and stay within both positive caps.
    public static func displaySize(
        pointSize: CGSize,
        maxWidth: CGFloat,
        maxHeight: CGFloat
    ) -> CGSize {
        let width = pointSize.width
        let height = pointSize.height
        guard width.isFinite, height.isFinite,
              maxWidth.isFinite, maxHeight.isFinite,
              width > 0, height > 0, maxWidth > 0, maxHeight > 0,
              maxWidth >= 1, maxHeight >= 1
        else {
            return .zero
        }

        let scale = min(1, maxWidth / width, maxHeight / height)
        guard scale.isFinite, scale > 0 else {
            return .zero
        }
        return CGSize(
            width: max(1, (width * scale).rounded(.down)),
            height: max(1, (height * scale).rounded(.down))
        )
    }
}

/// Resolves bob's vault-relative image paths without allowing a lexical
/// escape from the vault root. Symlinks are deliberately not resolved.
public enum RefsVaultAssetPath {
    public static func resolve(_ relative: String, root: URL) -> URL? {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~")
        else {
            return nil
        }

        var path = trimmed
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        guard !path.isEmpty else {
            return nil
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0 == ".." }) else {
            return nil
        }

        let standardizedRoot = root.standardizedFileURL
        let target = standardizedRoot
            .appendingPathComponent(path)
            .standardizedFileURL
        let rootPath = standardizedRoot.path
        let targetPath = target.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(rootPrefix), targetPath != rootPath else {
            return nil
        }
        return target
    }
}
