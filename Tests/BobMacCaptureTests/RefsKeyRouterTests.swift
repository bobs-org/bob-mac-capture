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
    static let t: UInt16 = 17
    static let y: UInt16 = 16
    static let b: UInt16 = 11
    static let s: UInt16 = 1
    static let d: UInt16 = 2
    static let x: UInt16 = 7
    static let z: UInt16 = 6
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
    static let keypadZero: UInt16 = 82
    static let zero: UInt16 = 29
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

  func testCommandNOpensTodayCardAndPassesThroughDuringComposition() {
    XCTAssertEqual(route(KeyCode.n, .command), .showTodayLinkCard)
    XCTAssertEqual(route(KeyCode.n, [.command, .capsLock]), .showTodayLinkCard)
    XCTAssertNil(
      route(
        KeyCode.n,
        .command,
        context: RefsKeyContext(markedTextPresent: true)
      ))
  }

  func testOptionNTogglesNewUnlessComposing() {
    XCTAssertEqual(route(KeyCode.n, .option), .toggleNew)
    XCTAssertEqual(route(KeyCode.n, [.option, .capsLock]), .toggleNew)
    XCTAssertNil(route(KeyCode.n, [.option, .shift]))
    XCTAssertNil(route(KeyCode.n, [.option, .command]))
    XCTAssertNil(
      route(
        KeyCode.n,
        .option,
        context: RefsKeyContext(markedTextPresent: true)
      ))
  }

  func testCommandKMasksActionsMenu() {
    XCTAssertEqual(route(KeyCode.k, .command), .showActions)
  }

  func testCommandYOpensCopyCardAndPassesThroughWhileComposing() {
    XCTAssertEqual(route(KeyCode.y, .command), .showCopyCard)
    XCTAssertEqual(route(KeyCode.y, [.command, .capsLock]), .showCopyCard)
    XCTAssertNil(route(KeyCode.y))
    XCTAssertNil(route(KeyCode.y, .control))
    XCTAssertNil(route(KeyCode.y, [.command, .shift]))
    XCTAssertNil(route(KeyCode.y, [.command, .option]))
    XCTAssertNil(
      route(
        KeyCode.y,
        .command,
        context: RefsKeyContext(markedTextPresent: true)
      ))
  }

  func testPagingAndEnds() {
    XCTAssertEqual(route(KeyCode.pageDown), .move(.pageDown))
    XCTAssertEqual(route(KeyCode.pageUp), .move(.pageUp))
    XCTAssertEqual(route(KeyCode.home), .move(.first))
    XCTAssertEqual(route(KeyCode.end), .move(.last))
    XCTAssertNil(route(KeyCode.pageDown, .shift))
    XCTAssertNil(route(KeyCode.home, .command))
  }

  func testControlDAndUScrollAndControlZResets() {
    let browse = RefsKeyContext(sectionJumps: true)
    let search = RefsKeyContext(sectionJumps: false)
    XCTAssertEqual(
      route(KeyCode.d, .control, context: browse),
      .scrollInspector(.down)
    )
    XCTAssertEqual(
      route(KeyCode.u, .control, context: browse),
      .scrollInspector(.up)
    )
    XCTAssertEqual(
      route(KeyCode.z, .control, context: browse),
      .resetView
    )
    XCTAssertNil(route(KeyCode.u, [.control, .shift], context: browse))
    XCTAssertEqual(
      route(KeyCode.d, .control, context: search),
      .scrollInspector(.down)
    )
    XCTAssertEqual(
      route(KeyCode.u, .control, context: search),
      .scrollInspector(.up)
    )
    XCTAssertEqual(
      route(KeyCode.z, .control, context: search),
      .resetView
    )
    XCTAssertNil(route(KeyCode.u, [.control, .shift], context: search))
    // Ctrl-D scrolls even with a closable Tabs row selected.
    let tabsRow = RefsKeyContext(selectionIsOpenTab: true)
    XCTAssertEqual(
      route(KeyCode.d, .control, context: tabsRow),
      .scrollInspector(.down)
    )
    XCTAssertEqual(
      route(KeyCode.z, .control, context: tabsRow),
      .resetView
    )
  }

  func testControlScrollAndResetRequireExactModifiers() {
    XCTAssertNil(route(KeyCode.d))
    XCTAssertNil(route(KeyCode.u))
    XCTAssertNil(route(KeyCode.x))
    XCTAssertNil(route(KeyCode.d, .command))
    XCTAssertNil(route(KeyCode.u, .option))
    XCTAssertNil(route(KeyCode.x, .command))
    XCTAssertNil(route(KeyCode.d, [.control, .shift]))
    XCTAssertNil(route(KeyCode.u, [.control, .command]))
    XCTAssertEqual(route(KeyCode.u, .control), .scrollInspector(.up))
    XCTAssertNil(route(KeyCode.u, [.control, .shift]))
    XCTAssertNil(route(KeyCode.u, [.control, .shift, .command]))
    XCTAssertNil(route(KeyCode.z))
    XCTAssertNil(route(KeyCode.z, .command))
    XCTAssertNil(route(KeyCode.z, [.command, .shift]))
    XCTAssertNil(route(KeyCode.z, [.control, .shift]))
    XCTAssertNil(route(KeyCode.z, [.control, .option]))
    XCTAssertNil(route(KeyCode.z, [.control, .command]))
    XCTAssertNil(route(KeyCode.z, [.control, .capsLock]))
    XCTAssertEqual(route(KeyCode.z, .control), .resetView)
    XCTAssertNil(route(KeyCode.b, .control))
    XCTAssertNil(route(KeyCode.d, [.control, .option]))
    XCTAssertNil(route(KeyCode.x, [.control, .shift]))
    XCTAssertNil(route(KeyCode.x, [.control, .command]))
    XCTAssertNil(route(KeyCode.x, [.control, .option]))
    // Plain X typing and Command-X editing never close.
    XCTAssertNil(route(KeyCode.x))
    XCTAssertNil(route(KeyCode.x, .command))
  }

  func testControlDUZPassThroughWhileComposing() {
    let composing = RefsKeyContext(markedTextPresent: true)
    XCTAssertNil(route(KeyCode.d, .control, context: composing))
    XCTAssertNil(route(KeyCode.u, .control, context: composing))
    XCTAssertNil(route(KeyCode.z, .control, context: composing))
    XCTAssertNil(route(KeyCode.u, [.control, .shift], context: composing))
    XCTAssertNil(route(KeyCode.x, .control, context: composing))
  }

  func testControlXClosesOnlyWhenAnOpenTabRowIsSelected() {
    let tabsRow = RefsKeyContext(selectionIsOpenTab: true)
    let otherRow = RefsKeyContext(tabsFilterOn: true)
    let libraryRow = RefsKeyContext()
    XCTAssertEqual(route(KeyCode.x, .control, context: tabsRow), .closeSelectedTab)
    XCTAssertNil(route(KeyCode.x, .control, context: otherRow))
    XCTAssertNil(route(KeyCode.x, .control, context: libraryRow))
    XCTAssertNil(
      route(
        KeyCode.x,
        .control,
        context: RefsKeyContext(markedTextPresent: true, selectionIsOpenTab: true)
      ))
  }

  func testOptionArrowsJumpSectionsInBrowseAndNewest() {
    let browse = RefsKeyContext(sectionJumps: true)
    XCTAssertEqual(
      route(KeyCode.arrowDown, .option, context: browse),
      .move(.nextSection)
    )
    XCTAssertEqual(
      route(KeyCode.arrowUp, .option, context: browse),
      .move(.previousSection)
    )
    let search = RefsKeyContext(sectionJumps: false)
    XCTAssertNil(route(KeyCode.arrowDown, .option, context: search))
    XCTAssertNil(route(KeyCode.arrowUp, .option, context: search))
    let newestSearch = RefsKeyContext(
      queryIsEmpty: false,
      newestOn: true,
      sectionJumps: true
    )
    XCTAssertEqual(
      route(KeyCode.arrowDown, .option, context: newestSearch),
      .move(.nextSection)
    )
    XCTAssertEqual(
      route(KeyCode.arrowUp, .option, context: newestSearch),
      .move(.previousSection)
    )
  }

  func testCommandZeroTogglesNewestUnlessComposing() {
    XCTAssertEqual(route(KeyCode.zero, .command), .toggleNewest)
    XCTAssertEqual(
      route(KeyCode.zero, [.command, .capsLock]),
      .toggleNewest
    )
    XCTAssertNil(route(KeyCode.zero))
    XCTAssertNil(route(KeyCode.zero, [.command, .shift]))
    XCTAssertNil(route(KeyCode.zero, [.command, .option]))
    XCTAssertNil(route(KeyCode.keypadZero, .command))
    XCTAssertNil(
      route(
        KeyCode.zero,
        .command,
        context: RefsKeyContext(markedTextPresent: true)
      ))
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
    XCTAssertEqual(route(KeyCode.r, [.command, .shift]), .showRenameCard)
    XCTAssertNil(route(KeyCode.r))
    XCTAssertNil(route(KeyCode.r, [.command, .option]))
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

  func testCommandTTogglesTabsUnlessComposing() {
    XCTAssertEqual(route(KeyCode.t, .command), .toggleTabs)
    XCTAssertEqual(
      route(KeyCode.t, [.command, .capsLock]),
      .toggleTabs
    )
    XCTAssertNil(route(KeyCode.t))
    XCTAssertNil(route(KeyCode.t, .control))
    XCTAssertNil(route(KeyCode.t, [.command, .option]))
    XCTAssertNil(
      route(
        KeyCode.t,
        .command,
        context: RefsKeyContext(markedTextPresent: true)
      ))
  }

  func testShiftCommandTReopensAndCommandTRemainsTabsToggle() {
    XCTAssertEqual(route(KeyCode.t, [.command, .shift]), .reopenClosedTab)
    XCTAssertEqual(
      route(KeyCode.t, [.command, .shift, .capsLock]),
      .reopenClosedTab
    )
    XCTAssertEqual(route(KeyCode.t, .command), .toggleTabs)
    XCTAssertNil(route(KeyCode.t, [.command, .shift, .option]))
    XCTAssertNil(
      route(
        KeyCode.t,
        [.command, .shift],
        context: RefsKeyContext(markedTextPresent: true)
      ))
  }

  func testDeleteBackwardOnEmptyRemovesTabsBeforeScope() {
    // Tabs on under scope All still removes the Tabs filter first,
    // matching A2's "removes it first".
    let tabsOn = RefsKeyContext(
      queryIsEmpty: true,
      scopeIsAll: true,
      tabsFilterOn: true
    )
    XCTAssertEqual(
      route(KeyCode.delete, [], context: tabsOn),
      .deleteBackwardOnEmpty
    )
    // A non-empty query keeps Backspace with the field editor.
    let typing = RefsKeyContext(
      queryIsEmpty: false,
      scopeIsAll: true,
      tabsFilterOn: true
    )
    XCTAssertNil(route(KeyCode.delete, [], context: typing))
  }

  func testDeleteBackwardOnEmptyRemovesNewestBeforeScope() {
    let newestOn = RefsKeyContext(
      queryIsEmpty: true,
      scopeIsAll: true,
      newestOn: true
    )
    XCTAssertEqual(
      route(KeyCode.delete, [], context: newestOn),
      .deleteBackwardOnEmpty
    )
    let typing = RefsKeyContext(
      queryIsEmpty: false,
      scopeIsAll: true,
      newestOn: true
    )
    XCTAssertNil(route(KeyCode.delete, [], context: typing))
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

  func testPanelSwitchMatchesCtrlTabVariants() {
    XCTAssertTrue(RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.tab, modifiers: .control))
    XCTAssertTrue(RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.tab, modifiers: [.control, .shift]))
    XCTAssertTrue(RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.tab, modifiers: [.control, .capsLock]))
    XCTAssertTrue(
      RefsKeyRouter.isPanelSwitch(
        keyCode: KeyCode.tab,
        modifiers: [.control, .shift, .capsLock]
      )
    )
  }

  func testPanelSwitchRejectsOtherModifiers() {
    XCTAssertFalse(RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.tab, modifiers: []))
    XCTAssertFalse(RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.tab, modifiers: .shift))
    XCTAssertFalse(RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.tab, modifiers: .command))
    XCTAssertFalse(RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.tab, modifiers: .option))
    XCTAssertFalse(
      RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.tab, modifiers: [.control, .command])
    )
    XCTAssertFalse(
      RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.tab, modifiers: [.control, .option])
    )
    XCTAssertFalse(RefsKeyRouter.isPanelSwitch(keyCode: KeyCode.return, modifiers: .control))
  }
}
