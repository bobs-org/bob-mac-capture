import AppKit

enum CaptureKeyCommand: Equatable {
    case submit
    case submitAndOpen
    case insertNewline
    case escape
}

struct CaptureKeyCommandRouter {
    private enum KeyCode {
        static let `return`: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
    }

    func command(for event: NSEvent) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            if event.modifierFlags.contains(.command) {
                return .submitAndOpen
            }
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
                return .insertNewline
            }
            return .submit
        case KeyCode.escape:
            return .escape
        default:
            return nil
        }
    }
}
