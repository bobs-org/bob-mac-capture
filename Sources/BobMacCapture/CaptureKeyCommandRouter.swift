import AppKit

enum CaptureKeyCommand: Equatable {
    case submit
    case submitAndOpen
    case insertNewline
    case escape
    case acceptCompletion
    case nextCompletion
    case previousCompletion
}

struct CaptureKeyCommandRouter {
    private enum KeyCode {
        static let `return`: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
        static let tab: UInt16 = 48
        static let arrowDown: UInt16 = 125
        static let arrowUp: UInt16 = 126
        static let j: UInt16 = 38
        static let n: UInt16 = 45
        static let p: UInt16 = 35
    }

    func command(for event: NSEvent, completionVisible: Bool = false) -> CaptureKeyCommand? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            if modifiers.contains(.command) {
                return completionVisible ? .acceptCompletion : .submitAndOpen
            }
            if modifiers.contains(.shift) || modifiers.contains(.option) {
                return .insertNewline
            }
            if completionVisible {
                return .acceptCompletion
            }
            return .submit
        case KeyCode.escape:
            return .escape
        case KeyCode.tab:
            return completionVisible ? .acceptCompletion : nil
        case KeyCode.arrowDown:
            return completionVisible ? .nextCompletion : nil
        case KeyCode.arrowUp:
            return completionVisible ? .previousCompletion : nil
        case KeyCode.j:
            return modifiers == .control ? .insertNewline : nil
        case KeyCode.n:
            return completionVisible && modifiers.contains(.control) ? .nextCompletion : nil
        case KeyCode.p:
            return completionVisible && modifiers.contains(.control) ? .previousCompletion : nil
        default:
            return nil
        }
    }
}
