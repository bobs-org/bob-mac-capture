import XCTest

@testable import CaptureCore

final class BobEnvironmentTests: XCTestCase {
    func testBuildsMinimalGuiSafeEnvironment() {
        let environment = BobEnvironmentBuilder(
            homeDirectory: "/Users/bryan",
            bobDirectory: "/Users/bryan/bob",
            currentEnvironment: [
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8",
                "BOB_LOG": "debug",
                "SHELL": "/bin/zsh",
            ]
        ).build()

        XCTAssertEqual(environment["HOME"], "/Users/bryan")
        XCTAssertEqual(environment["BOB_DIR"], "/Users/bryan/bob")
        XCTAssertEqual(environment["BOB_LOG"], "debug")
        XCTAssertNil(environment["SHELL"])
        XCTAssertFalse(environment["PATH", default: ""].contains("/bin/zsh"))
    }
}
