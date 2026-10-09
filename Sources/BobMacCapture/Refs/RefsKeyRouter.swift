import AppKit
import Foundation

/// What the panel knows about the key event's context: whether a banner
/// is up, whether the query is empty, whether the scope is All, whether
/// the field editor holds marked (IME-composing) text, and whether the
/// listing is in browse mode. Printable keys always fall through to the
/// search field.
public struct RefsKeyContext: Equatable, Sendable {
    public var bannerVisible: Bool
    public var queryIsEmpty: Bool
    public var scopeIsAll: Bool
    public var markedTextPresent: Bool
    public var listModeIsBrowse: Bool

    public init(
        bannerVisible: Bool = false,
        queryIsEmpty: Bool = true,
        scopeIsAll: Bool = true,
        markedTextPresent: Bool = false,
        listModeIsBrowse: Bool = true
    ) {
        self.bannerVisible = bannerVisible
        self.queryIsEmpty = queryIsEmpty
        self.scopeIsAll = scopeIsAll
        self.markedTextPresent = markedTextPresent
        self.listModeIsBrowse = listModeIsBrowse
    }
}

/// The §12 keyboard table as a pure function over a key code and
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
        static let r: UInt16 = 15
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
            if flags == .option, context.listModeIsBrowse {
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
            if flags == .option, context.listModeIsBrowse {
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
            return flags == .control ? .move(.next) : nil
        case KeyCode.k:
            if flags == .control {
                return .move(.previous)
            }
            if flags == .command {
                return .showActions
            }
            return nil
        case KeyCode.j:
            return flags == .control ? .move(.next) : nil
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
        case KeyCode.r:
            return flags == .command ? .refresh : nil
        case KeyCode.delete:
            // Only unmodified Backspace on an empty query removes the
            // scope token; `perform` re-checks the scope, so a non-All
            // scope is required for a non-nil result here too.
            if flags.isEmpty, context.queryIsEmpty, !context.scopeIsAll {
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
