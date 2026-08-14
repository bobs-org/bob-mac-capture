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
        static let n: UInt16 = 45
        static let p: UInt16 = 35
    }

    func command(for event: NSEvent, completionVisible: Bool = false) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            if completionVisible {
                return .acceptCompletion
            }
            if event.modifierFlags.contains(.command) {
                return .submitAndOpen
            }
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
                return .insertNewline
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
        case KeyCode.n:
            return completionVisible && event.modifierFlags.contains(.control) ? .nextCompletion : nil
        case KeyCode.p:
            return completionVisible && event.modifierFlags.contains(.control) ? .previousCompletion : nil
        default:
            return nil
        }
    }
}
