import Foundation
import XCTest

@testable import CaptureCore

final class BobExecutableResolverTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testRejectsRelativeOverride() {
        let resolver = BobExecutableResolver(homeDirectory: tempDirectory, candidates: [])

        XCTAssertThrowsError(try resolver.resolve(configuredOverride: "bin/bob")) { error in
            XCTAssertEqual(
                error as? BobClientError,
                .executableOverrideNotAbsolute("bin/bob")
            )
        }
    }

    func testUsesExecutableOverrideBeforeCandidates() throws {
        let override = try makeExecutable(named: "override-bob")
        let candidate = try makeExecutable(named: "candidate-bob")
        let resolver = BobExecutableResolver(homeDirectory: tempDirectory, candidates: [candidate.path])

        XCTAssertEqual(try resolver.resolve(configuredOverride: override.path), override.path)
    }

    func testFallsBackThroughGuiSafeCandidates() throws {
        let candidate = try makeExecutable(named: "bob")
        let resolver = BobExecutableResolver(
            homeDirectory: tempDirectory,
            candidates: [tempDirectory.appendingPathComponent("missing").path, candidate.path]
        )

        XCTAssertEqual(try resolver.resolve(configuredOverride: nil), candidate.path)
    }

    private func makeExecutable(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
