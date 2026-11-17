import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Poster loading stays behind `VideoPosterLoading` so tests can inject a
/// stub and the production loader can fail closed on a missing source.
@MainActor
final class VideoPosterLoaderTests: XCTestCase {
    override func tearDown() {
        VideoPosterMemoryCache.shared.reset()
        super.tearDown()
    }

    func testProductionLoaderReturnsNilForMissingAndNonVideoSources() async throws {
        let loader = AVFoundationVideoPosterLoader()
        let missing = await loader.load(
            source: FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-\(UUID().uuidString).mp4").path)
        XCTAssertNil(missing)

        let png = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))
        let unreadableVideo = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: unreadableVideo)
        let nonVideo = await loader.load(source: unreadableVideo.path)
        XCTAssertNil(nonVideo)
    }

    func testCacheKeysBySourceAndModificationDate() {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        let frame = VideoPosterFrame(image: image, duration: 6)
        let first = Date(timeIntervalSince1970: 1)
        let second = Date(timeIntervalSince1970: 2)
        let path = "/tmp/clip.mp4"
        VideoPosterMemoryCache.shared.store(
            frame, for: VideoPosterCacheKey(source: path, modificationDate: first))
        XCTAssertEqual(
            VideoPosterMemoryCache.shared.frame(
                for: VideoPosterCacheKey(source: path, modificationDate: first)
            )?.duration,
            6)
        XCTAssertNil(
            VideoPosterMemoryCache.shared.frame(
                for: VideoPosterCacheKey(source: path, modificationDate: second)))
    }

    func testStubLoaderSatisfiesThePosterProtocol() async {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let loader = StubVideoPosterLoader(
            frame: VideoPosterFrame(image: image, duration: 6.2))
        let loaded = await loader.load(source: "/tmp/clip.mp4")
        XCTAssertEqual(loaded?.duration, 6.2)
        XCTAssertEqual(
            CaptureClipPresentation.AttachmentRow.videoDurationBadge(
                seconds: loaded?.duration ?? 0),
            "0:06")
    }

    private struct StubVideoPosterLoader: VideoPosterLoading {
        let frame: VideoPosterFrame?
        func load(source: String) async -> VideoPosterFrame? {
            frame
        }
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQ"
        + "AAAABJRU5ErkJggg=="
}
