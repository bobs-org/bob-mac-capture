import AppKit
import XCTest

@testable import BobMacCapture

/// Router tests for the §12 keyboard table: every row plus IME
/// passthrough. The router is pure over a key code and modifiers, so
/// no test builds an `NSEvent`.
final class RefsKeyRouterTests: XCTestCase {
    private enum KeyCode {
        static let one: UInt16 = 18
        static let two: UInt16 = 19
        static let three: UInt16 = 20
        static let four: UInt16 = 21
        static let five: UInt16 = 23
        static let a: UInt16 = 0
        static let r: UInt16 = 15
        static let s: UInt16 = 1
        static let d: UInt16 = 2
        static let u: UInt16 = 32
        static let j: UInt16 = 38
        static let k: UInt16 = 40
        static let n: UInt16 = 45
        static let o: UInt16 = 31
        static let p: UInt16 = 35
        static let tab: UInt16 = 48
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let leftBracket: UInt16 = 33
        static let home: UInt16 = 115
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
        static let end: UInt16 = 119
        static let `return`: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let arrowUp: UInt16 = 126
        static let arrowDown: UInt16 = 125
    }

    private func route(
        _ keyCode: UInt16,
        _ modifiers: NSEvent.ModifierFlags = [],
        context: RefsKeyContext = RefsKeyContext()
    ) -> RefsCommand? {
        RefsKeyRouter.command(
            keyCode: keyCode,
            modifiers: modifiers,
            context: context
        )
    }

    func testReturnOpensInHighlights() {
        XCTAssertEqual(route(KeyCode.return), .open(.highlights))
        XCTAssertEqual(route(KeyCode.keypadEnter), .open(.highlights))
        XCTAssertEqual(route(KeyCode.return, .command), .open(.note))
        XCTAssertEqual(route(KeyCode.return, .option), .open(.reveal))
        XCTAssertNil(route(KeyCode.return, .shift))
    }

    func testReturnPassesThroughWhileComposing() {
        let composing = RefsKeyContext(markedTextPresent: true)
        XCTAssertNil(route(KeyCode.return, [], context: composing))
        XCTAssertNil(route(KeyCode.tab, [], context: composing))
    }

    func testTabOpensAndShiftTabIsConsumed() {
        XCTAssertEqual(route(KeyCode.tab), .open(.highlights))
        XCTAssertEqual(route(KeyCode.tab, .shift), .consume)
        XCTAssertNil(route(KeyCode.tab, .command))
        XCTAssertNil(route(KeyCode.tab, .option))
    }

    func testArrowsMoveAndWrapThroughModel() {
        XCTAssertEqual(route(KeyCode.arrowDown), .move(.next))
        XCTAssertEqual(route(KeyCode.arrowUp), .move(.previous))
        XCTAssertEqual(route(KeyCode.arrowDown, .command), .move(.last))
        XCTAssertEqual(route(KeyCode.arrowUp, .command), .move(.first))
        XCTAssertNil(route(KeyCode.arrowDown, .control))
    }

    func testControlMoves() {
        XCTAssertEqual(route(KeyCode.p, .control), .move(.previous))
        XCTAssertEqual(route(KeyCode.n, .control), .move(.next))
        XCTAssertEqual(route(KeyCode.k, .control), .move(.previous))
        XCTAssertEqual(route(KeyCode.j, .control), .move(.next))
        XCTAssertNil(route(KeyCode.p))
        XCTAssertNil(route(KeyCode.n))
        XCTAssertNil(route(KeyCode.j))
        XCTAssertNil(route(KeyCode.k))
    }

    func testCommandKMasksActionsMenu() {
        XCTAssertEqual(route(KeyCode.k, .command), .showActions)
    }

    func testPagingAndEnds() {
        XCTAssertEqual(route(KeyCode.pageDown), .move(.pageDown))
        XCTAssertEqual(route(KeyCode.pageUp), .move(.pageUp))
        XCTAssertEqual(route(KeyCode.home), .move(.first))
        XCTAssertEqual(route(KeyCode.end), .move(.last))
        XCTAssertNil(route(KeyCode.pageDown, .shift))
        XCTAssertNil(route(KeyCode.home, .command))
    }

    func testControlDAndUScrollInspectorInBrowseAndSearch() {
        let browse = RefsKeyContext(listModeIsBrowse: true)
        let search = RefsKeyContext(listModeIsBrowse: false)
        XCTAssertEqual(
            route(KeyCode.d, .control, context: browse),
            .scrollInspector(.down)
        )
        XCTAssertEqual(
            route(KeyCode.u, .control, context: browse),
            .scrollInspector(.up)
        )
        XCTAssertEqual(
            route(KeyCode.d, .control, context: search),
            .scrollInspector(.down)
        )
        XCTAssertEqual(
            route(KeyCode.u, .control, context: search),
            .scrollInspector(.up)
        )
    }

    func testControlDAndURequireExactControl() {
        XCTAssertNil(route(KeyCode.d))
        XCTAssertNil(route(KeyCode.u))
        XCTAssertNil(route(KeyCode.d, .command))
        XCTAssertNil(route(KeyCode.u, .option))
        XCTAssertNil(route(KeyCode.d, [.control, .shift]))
        XCTAssertNil(route(KeyCode.u, [.control, .command]))
        XCTAssertNil(route(KeyCode.d, [.control, .option]))
    }

    func testControlDAndUPassThroughWhileComposing() {
        let composing = RefsKeyContext(markedTextPresent: true)
        XCTAssertNil(route(KeyCode.d, .control, context: composing))
        XCTAssertNil(route(KeyCode.u, .control, context: composing))
    }

    func testOptionArrowsJumpSectionsInBrowseOnly() {
        let browse = RefsKeyContext(listModeIsBrowse: true)
        XCTAssertEqual(
            route(KeyCode.arrowDown, .option, context: browse),
            .move(.nextSection)
        )
        XCTAssertEqual(
            route(KeyCode.arrowUp, .option, context: browse),
            .move(.previousSection)
        )
        let search = RefsKeyContext(listModeIsBrowse: false)
        XCTAssertNil(route(KeyCode.arrowDown, .option, context: search))
        XCTAssertNil(route(KeyCode.arrowUp, .option, context: search))
    }

    func testScopes() {
        XCTAssertEqual(route(KeyCode.one, .command), .setScope(.all))
        XCTAssertEqual(route(KeyCode.two, .command), .setScope(.chats))
        XCTAssertEqual(route(KeyCode.three, .command), .setScope(.papers))
        XCTAssertEqual(route(KeyCode.four, .command), .setScope(.articles))
        XCTAssertEqual(route(KeyCode.five, .command), .setScope(.docs))
        XCTAssertNil(route(KeyCode.two))
    }

    func testRefresh() {
        XCTAssertEqual(route(KeyCode.r, .command), .refresh)
        XCTAssertNil(route(KeyCode.r))
    }

    func testCommandSMapsToScanAndOtherModifiersPassThrough() {
        XCTAssertEqual(route(KeyCode.s, .command), .scan)
        XCTAssertNil(route(KeyCode.s))
        XCTAssertNil(route(KeyCode.s, [.command, .shift]))
        XCTAssertNil(route(KeyCode.s, [.command, .option]))
        XCTAssertNil(route(KeyCode.s, .control))
    }

    func testDeleteBackwardOnEmptyRemovesScope() {
        let scoped = RefsKeyContext(queryIsEmpty: true, scopeIsAll: false)
        XCTAssertEqual(
            route(KeyCode.delete, [], context: scoped),
            .deleteBackwardOnEmpty
        )
        XCTAssertNil(route(KeyCode.delete))
        let unscoped = RefsKeyContext(queryIsEmpty: true, scopeIsAll: true)
        XCTAssertNil(route(KeyCode.delete, [], context: unscoped))
        XCTAssertNil(route(KeyCode.delete, .shift, context: scoped))
    }

    func testEscapeChain() {
        XCTAssertEqual(route(KeyCode.escape), .escape)
        XCTAssertEqual(route(KeyCode.leftBracket, .control), .escape)
        XCTAssertNil(route(KeyCode.escape, .shift))
        XCTAssertNil(route(KeyCode.leftBracket))
    }

    func testPrintableKeysFallThrough() {
        XCTAssertNil(route(KeyCode.a))
        XCTAssertNil(route(KeyCode.o, .command))
        XCTAssertNil(route(KeyCode.r, .option))
    }
}
