import XCTest

@testable import BobMacCapture

final class BundleSigningInspectorTests: XCTestCase {
    func testUnsignedOutputIsDetected() {
        let state = BundleSigningInspector.state(
            fromCodesignOutput: "Bob Mac Capture.app: code object is not signed at all\n"
        )

        XCTAssertEqual(state, .unsigned)
    }

    func testAdHocOutputIsDetected() {
        let output = """
            Executable=/Applications/Bob Mac Capture.app/Contents/MacOS/BobMacCapture
            Identifier=org.bobs.bob-mac-capture
            Format=app bundle with Mach-O thin (arm64)
            CodeDirectory v=20500 size=... flags=0x2(adhoc) hashes=...
            Signature=adhoc
            """
        let state = BundleSigningInspector.state(fromCodesignOutput: output)

        XCTAssertEqual(state, .adHoc)
    }

    func testSignedOutputExtractsAuthority() {
        let output = """
            Executable=/Applications/Bob Mac Capture.app/Contents/MacOS/BobMacCapture
            Identifier=org.bobs.bob-mac-capture
            Authority=Apple Development: Name (TEAMID)
            Authority=Apple Worldwide Developer Relations Certification Authority
            Authority=Apple Root CA
            """
        let state = BundleSigningInspector.state(fromCodesignOutput: output)

        XCTAssertEqual(state, .signed(identity: "Apple Development: Name (TEAMID)"))
    }

    func testUnknownOutputFallsBackWithoutCrashing() {
        let state = BundleSigningInspector.state(fromCodesignOutput: "")

        if case .unknown = state {
            // expected
        } else {
            XCTFail("Expected .unknown for empty codesign output")
        }
    }
}
