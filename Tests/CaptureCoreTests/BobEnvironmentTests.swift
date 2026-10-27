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

    func testPreservesTheBobConfigAndTemplateShelfOverridesBobReads() {
        XCTAssertTrue(BobEnvironmentBuilder.preservedOverrideKeys.contains("BOB_CONFIG_FILE"))
        XCTAssertTrue(
            BobEnvironmentBuilder.preservedOverrideKeys.contains("BOB_CAPTURE_TEMPLATES_FILE"))
        XCTAssertTrue(BobEnvironmentBuilder.preservedOverrideKeys.contains("XDG_STATE_HOME"))
        XCTAssertFalse(BobEnvironmentBuilder.preservedOverrideKeys.contains("BOB_CONFIG"))

        let environment = BobEnvironmentBuilder(
            homeDirectory: "/Users/bryan",
            currentEnvironment: [
                "BOB_CONFIG_FILE": "/tmp/bob.yml",
                "BOB_CAPTURE_TEMPLATES_FILE": "/tmp/templates.json",
                "XDG_STATE_HOME": "/tmp/state",
            ]
        ).build()
        XCTAssertEqual(environment["BOB_CONFIG_FILE"], "/tmp/bob.yml")
        XCTAssertEqual(environment["BOB_CAPTURE_TEMPLATES_FILE"], "/tmp/templates.json")
        XCTAssertEqual(environment["XDG_STATE_HOME"], "/tmp/state")
        XCTAssertNil(environment["BOB_CONFIG"])
    }

    func testPathSeesLocalBinBeforeCargoBin() {
        let environment = BobEnvironmentBuilder(
            homeDirectory: "/Users/bryan",
            currentEnvironment: [:]
        ).build()

        let path = environment["PATH", default: ""]
        let components = path.split(separator: ":").map(String.init)
        guard let localBin = components.firstIndex(of: "/Users/bryan/.local/bin"),
            let cargoBin = components.firstIndex(of: "/Users/bryan/.cargo/bin"),
            let homeBin = components.firstIndex(of: "/Users/bryan/bin")
        else {
            return XCTFail("expected .local/bin, .cargo/bin, and bin on PATH: \(path)")
        }
        XCTAssertLessThan(localBin, cargoBin)
        XCTAssertLessThan(cargoBin, homeBin)
    }
}
