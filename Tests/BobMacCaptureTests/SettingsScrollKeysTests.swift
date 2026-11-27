import AppKit
import XCTest

@testable import BobMacCapture

/// Pure routing for the Settings scroll keys: Control-D pages down and
/// Control-U pages up by half the viewport, from any field.
final class SettingsScrollKeysTests: XCTestCase {
    private enum KeyCode {
        static let d: UInt16 = 2
        static let u: UInt16 = 32
    }

    private func route(
        _ keyCode: UInt16,
        _ modifiers: NSEvent.ModifierFlags = [],
        markedTextPresent: Bool = false
    ) -> RefsInspectorScrollDirection? {
        SettingsScrollKeys.direction(
            keyCode: keyCode,
            modifiers: modifiers,
            markedTextPresent: markedTextPresent
        )
    }

    func testControlDRoutesDownAndControlURoutesUp() {
        XCTAssertEqual(route(KeyCode.d, .control), .down)
        XCTAssertEqual(route(KeyCode.u, .control), .up)
    }

    func testCapsLockDoesNotBlockTheChord() {
        XCTAssertEqual(route(KeyCode.d, [.control, .capsLock]), .down)
        XCTAssertEqual(route(KeyCode.u, [.control, .capsLock]), .up)
    }

    func testNumericPadAndFunctionDoNotBlockTheChord() {
        XCTAssertEqual(route(KeyCode.d, [.control, .numericPad]), .down)
        XCTAssertEqual(route(KeyCode.u, [.control, .function]), .up)
    }

    func testPlainKeysAndOtherModifiersPassThrough() {
        XCTAssertNil(route(KeyCode.d))
        XCTAssertNil(route(KeyCode.u))
        XCTAssertNil(route(KeyCode.d, .command))
        XCTAssertNil(route(KeyCode.u, .option))
        XCTAssertNil(route(KeyCode.d, [.control, .shift]))
        XCTAssertNil(route(KeyCode.u, [.control, .option]))
        XCTAssertNil(route(KeyCode.d, [.control, .command]))
        XCTAssertNil(route(KeyCode.u, [.control, .shift, .command]))
    }

    func testMarkedTextPassesThrough() {
        XCTAssertNil(route(KeyCode.d, .control, markedTextPresent: true))
        XCTAssertNil(route(KeyCode.u, .control, markedTextPresent: true))
    }

    func testRepeatsStillRoute() {
        XCTAssertEqual(route(KeyCode.d, .control), .down)
        XCTAssertEqual(route(KeyCode.d, .control), .down)
        XCTAssertEqual(route(KeyCode.u, .control), .up)
        XCTAssertEqual(route(KeyCode.u, .control), .up)
    }
}
