import AppKit
import Foundation

/// What the panel knows about the key event's context: whether the
/// query is empty, whether the scope is All, whether the Highlights
/// Tabs filter is on, whether Newest is on, whether the field editor
/// holds marked (IME-composing) text, whether the selection is an open
/// tab, and whether Option-↑/↓ may jump sections. A banner in flight
/// needs no router flag: the model's Esc ladder dismisses it first.
/// Printable keys always fall through to the search field.
public struct RefsKeyContext: Equatable, Sendable {
  public var queryIsEmpty: Bool
  public var scopeIsAll: Bool
  public var tabsFilterOn: Bool
  public var newestOn: Bool
  public var markedTextPresent: Bool
  public var selectionIsOpenTab: Bool
  /// True in browse mode, and in Newest even while a query is typed.
  public var sectionJumps: Bool

  public init(
    queryIsEmpty: Bool = true,
    scopeIsAll: Bool = true,
    tabsFilterOn: Bool = false,
    newestOn: Bool = false,
    markedTextPresent: Bool = false,
    selectionIsOpenTab: Bool = false,
    sectionJumps: Bool = true
  ) {
    self.queryIsEmpty = queryIsEmpty
    self.scopeIsAll = scopeIsAll
    self.tabsFilterOn = tabsFilterOn
    self.newestOn = newestOn
    self.markedTextPresent = markedTextPresent
    self.selectionIsOpenTab = selectionIsOpenTab
    self.sectionJumps = sectionJumps
  }
}

/// The docs/keyboard.md table as a pure function over a key code and
/// modifiers, so the router tests never build an `NSEvent`. The panel
/// controller adapts live events into this form and funnels the result
/// through `RefsPanelModel.perform`. A nil result passes the key
/// through to the search field.
public enum RefsKeyRouter {
  private enum KeyCode {
    static let one: UInt16 = 18
    static let two: UInt16 = 19
    static let three: UInt16 = 20
    static let four: UInt16 = 21
    static let five: UInt16 = 23
    static let zero: UInt16 = 29
    static let r: UInt16 = 15
    static let t: UInt16 = 17
    static let y: UInt16 = 16
    static let s: UInt16 = 1
    static let d: UInt16 = 2
    static let x: UInt16 = 7
    static let u: UInt16 = 32
    static let j: UInt16 = 38
    static let k: UInt16 = 40
    static let n: UInt16 = 45
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

  /// Maps one key press to a panel command, or nil to pass it through.
  /// Control-X closes a selected Tabs row; Control-D always scrolls;
  /// Shift-Command-T reopens the newest closed tab. Option-N toggles
  /// NEW except while IME-composing.
  public static func command(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags,
    context: RefsKeyContext
  ) -> RefsCommand? {
    let flags = modifiers.intersection(.deviceIndependentFlagsMask)
    switch keyCode {
    case KeyCode.return, KeyCode.keypadEnter:
      // Return while IME-composing passes through to the text system.
      if context.markedTextPresent {
        return nil
      }
      if flags == .command {
        return .open(.note)
      }
      if flags == .option {
        return .open(.reveal)
      }
      if flags.isEmpty {
        return .open(.highlights)
      }
      return nil
    case KeyCode.tab:
      // Plain Tab opens, like Return; Shift-Tab is consumed.
      if flags.isEmpty {
        return context.markedTextPresent ? nil : .open(.highlights)
      }
      if flags == .shift {
        return .consume
      }
      return nil
    case KeyCode.arrowDown:
      if flags.isEmpty {
        return .move(.next)
      }
      if flags == .command {
        return .move(.last)
      }
      if flags == .option, context.sectionJumps {
        return .move(.nextSection)
      }
      return nil
    case KeyCode.arrowUp:
      if flags.isEmpty {
        return .move(.previous)
      }
      if flags == .command {
        return .move(.first)
      }
      if flags == .option, context.sectionJumps {
        return .move(.previousSection)
      }
      return nil
    case KeyCode.pageDown:
      return flags.isEmpty ? .move(.pageDown) : nil
    case KeyCode.pageUp:
      return flags.isEmpty ? .move(.pageUp) : nil
    case KeyCode.home:
      return flags.isEmpty ? .move(.first) : nil
    case KeyCode.end:
      return flags.isEmpty ? .move(.last) : nil
    case KeyCode.p:
      return flags == .control ? .move(.previous) : nil
    case KeyCode.n:
      if flags == .control { return .move(.next) }
      if flags.subtracting(.capsLock) == .command, !context.markedTextPresent {
        return .showTodayLinkCard
      }
      if flags.subtracting(.capsLock) == .option {
        return context.markedTextPresent ? nil : .toggleNew
      }
      return nil
    case KeyCode.k:
      if flags == .control {
        return .move(.previous)
      }
      if flags == .command {
        return .showActions
      }
      return nil
    case KeyCode.y:
      if flags.subtracting(.capsLock) == .command {
        return context.markedTextPresent ? nil : .showCopyCard
      }
      return nil
    case KeyCode.j:
      return flags == .control ? .move(.next) : nil
    case KeyCode.d:
      if flags == .control {
        return context.markedTextPresent ? nil : .scrollInspector(.down)
      }
      return nil
    case KeyCode.x:
      // Control-X closes only a closable Tabs row; elsewhere it
      // passes through to the search field. Plain X typing and
      // Command-X text editing never reach this branch.
      if flags == .control {
        if context.markedTextPresent {
          return nil
        }
        return context.selectionIsOpenTab ? .closeSelectedTab : nil
      }
      return nil
    case KeyCode.u:
      if flags == .control {
        return context.markedTextPresent ? nil : .scrollInspector(.up)
      }
      return nil
    case KeyCode.one:
      return flags == .command ? .setScope(.all) : nil
    case KeyCode.two:
      return flags == .command ? .setScope(.chats) : nil
    case KeyCode.three:
      return flags == .command ? .setScope(.papers) : nil
    case KeyCode.four:
      return flags == .command ? .setScope(.articles) : nil
    case KeyCode.five:
      return flags == .command ? .setScope(.docs) : nil
    case KeyCode.zero:
      // ⌘0 toggles Newest. Caps Lock never blocks it; Shift-⌘0
      // and the keypad 0 are unbound. While IME-composing it
      // belongs to the text system.
      if context.markedTextPresent {
        return nil
      }
      let commandFlags = flags.subtracting(.capsLock)
      return commandFlags == .command ? .toggleNewest : nil
    case KeyCode.r:
      if flags == [.command, .shift] {
        return .showRenameCard
      }
      return flags == .command ? .refresh : nil
    case KeyCode.s:
      return flags == .command ? .scan : nil
    case KeyCode.t:
      // Shift-⌘T reopens a closed tab; plain ⌘T toggles the Tabs
      // filter. While IME-composing either key belongs to the text
      // system. Caps Lock never blocks the shortcuts.
      if context.markedTextPresent {
        return nil
      }
      let commandFlags = flags.subtracting(.capsLock)
      if commandFlags == [.command, .shift] {
        return .reopenClosedTab
      }
      return commandFlags == .command ? .toggleTabs : nil
    case KeyCode.delete:
      // Only unmodified Backspace on an empty query removes a
      // token: the Tabs or Newest token first (even under scope
      // All), then the scope. `perform` re-checks, so a token
      // must be on for a non-nil result here too.
      if flags.isEmpty, context.queryIsEmpty,
        context.tabsFilterOn || context.newestOn || !context.scopeIsAll
      {
        return .deleteBackwardOnEmpty
      }
      return nil
    case KeyCode.escape:
      return flags.isEmpty ? .escape : nil
    case KeyCode.leftBracket:
      return flags == .control ? .escape : nil
    default:
      return nil
    }
  }
}
