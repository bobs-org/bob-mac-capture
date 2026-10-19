import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest

@testable import RefsCore

final class RefsImageMetricsTests: XCTestCase {
    func testIntrinsicPointSizeUsesDPIThresholdAndOrientation() {
        XCTAssertEqual(
            RefsImageMetrics(pixelWidth: 1200, pixelHeight: 800, dpi: 72).pointSize,
            CGSize(width: 1200, height: 800)
        )
        XCTAssertEqual(
            RefsImageMetrics(pixelWidth: 1200, pixelHeight: 800, dpi: 144).pointSize,
            CGSize(width: 600, height: 400)
        )
        XCTAssertEqual(
            RefsImageMetrics(pixelWidth: 1200, pixelHeight: 800).pointSize,
            CGSize(width: 1200, height: 800)
        )
        XCTAssertEqual(
            RefsImageMetrics(
                pixelWidth: 1200,
                pixelHeight: 800,
                dpi: 144,
                orientation: 6
            ).pointSize,
            CGSize(width: 400, height: 600)
        )
        XCTAssertEqual(
            RefsImageMetrics(pixelWidth: 0, pixelHeight: 800).pointSize,
            .zero
        )
    }

    func testDisplaySizeFitsWithoutUpscalingAndRoundsDown() {
        XCTAssertEqual(
            RefsImageFit.displaySize(
                pointSize: CGSize(width: 200, height: 100),
                maxWidth: 400,
                maxHeight: 300
            ),
            CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(
            RefsImageFit.displaySize(
                pointSize: CGSize(width: 800, height: 400),
                maxWidth: 300,
                maxHeight: 300
            ),
            CGSize(width: 300, height: 150)
        )
        XCTAssertEqual(
            RefsImageFit.displaySize(
                pointSize: CGSize(width: 800, height: 1600),
                maxWidth: 600,
                maxHeight: 500
            ),
            CGSize(width: 250, height: 500)
        )
        XCTAssertEqual(
            RefsImageFit.displaySize(
                pointSize: CGSize(width: 100.9, height: 50.6),
                maxWidth: 100.1,
                maxHeight: 100
            ),
            CGSize(width: 100, height: 50)
        )
        XCTAssertEqual(
            RefsImageFit.displaySize(
                pointSize: CGSize(width: 100, height: 100),
                maxWidth: 0,
                maxHeight: 100
            ),
            .zero
        )
        XCTAssertEqual(
            RefsImageFit.displaySize(
                pointSize: CGSize(width: -1, height: 100),
                maxWidth: 100,
                maxHeight: 100
            ),
            .zero
        )
    }

    func testVaultAssetPathResolvesOnlyLexicallyContainedRelativePaths() {
        let root = URL(fileURLWithPath: "/tmp/vault")

        XCTAssertEqual(
            RefsVaultAssetPath.resolve("ref/images/figure.png", root: root)?.path,
            "/tmp/vault/ref/images/figure.png"
        )
        XCTAssertEqual(
            RefsVaultAssetPath.resolve("./ref/images/figure.png", root: root)?.path,
            "/tmp/vault/ref/images/figure.png"
        )
        XCTAssertNil(RefsVaultAssetPath.resolve("", root: root))
        XCTAssertNil(RefsVaultAssetPath.resolve("  ", root: root))
        XCTAssertNil(RefsVaultAssetPath.resolve("/etc/passwd", root: root))
        XCTAssertNil(RefsVaultAssetPath.resolve("~/secret.png", root: root))
        XCTAssertNil(RefsVaultAssetPath.resolve("ref/../outside.png", root: root))
        XCTAssertNil(RefsVaultAssetPath.resolve("../vault2/outside.png", root: root))
    }
}
