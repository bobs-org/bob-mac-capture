import AppKit

enum CaptureKeyCommand: Equatable {
    case submit
    case submitAndOpen
    case insertNewline
    case insertBulletNewline
    case deleteBackward
    case escape
    case discardAndClose
    case stashDraftAndClose
    case toggleStashPicker
    case dismissStashPicker
    case nextStashEntry
    case previousStashEntry
    case restoreSelectedStashEntry
    case restoreStashEntry(Int)
    case consumeKey
    case acceptCompletion
    case nextCompletion
    case previousCompletion
    case increaseBulletIndentation
    case decreaseBulletIndentation
}

struct CaptureKeyRoutingContext: Equatable {
    var completionVisible = false
    var stashPickerVisible = false
    var stashEntryCount = 0
}

struct CaptureKeyCommandRouter {
    private enum KeyCode {
        static let `return`: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
        static let tab: UInt16 = 48
        static let delete: UInt16 = 51
        static let arrowDown: UInt16 = 125
        static let arrowUp: UInt16 = 126
        static let j: UInt16 = 38
        static let s: UInt16 = 1
        static let c: UInt16 = 8
        static let n: UInt16 = 45
        static let p: UInt16 = 35
        static let leftBracket: UInt16 = 33
    }

    func command(
        for event: NSEvent,
        context: CaptureKeyRoutingContext = CaptureKeyRoutingContext()
    ) -> CaptureKeyCommand? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if context.stashPickerVisible {
            return stashPickerCommand(for: event, modifiers: modifiers, context: context)
        }

        if event.keyCode == KeyCode.s, modifiers == .control {
            return .toggleStashPicker
        }

        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            if modifiers.contains(.command) {
                return context.completionVisible ? .acceptCompletion : .submitAndOpen
            }
            if modifiers.contains(.shift) || modifiers.contains(.option) {
                return .insertNewline
            }
            if context.completionVisible {
                return .acceptCompletion
            }
            return .submit
        case KeyCode.j:
            return modifiers == .control ? .insertBulletNewline : nil
        case KeyCode.delete:
            // Only unmodified Backspace may claim the empty-bullet deletion; every
            // modified variant (including Shift-Backspace) stays AppKit's.
            return modifiers.intersection([.command, .option, .control, .shift]).isEmpty
                ? .deleteBackward
                : nil
        case KeyCode.escape:
            return .escape
        case KeyCode.leftBracket:
            return modifiers == .control ? .escape : nil
        case KeyCode.c:
            return modifiers == .control ? .stashDraftAndClose : nil
        case KeyCode.tab:
            // Plain Tab keeps the existing completion-acceptance contract and otherwise
            // indents; Shift-Tab always outdents, deliberately replacing the accidental
            // completion acceptance it used to trigger. Every other modifier combination
            // (Command, Option, Control, or Shift plus another modifier) stays AppKit's.
            if modifiers.isEmpty {
                return context.completionVisible ? .acceptCompletion : .increaseBulletIndentation
            }
            return modifiers == .shift ? .decreaseBulletIndentation : nil
        case KeyCode.arrowDown:
            return context.completionVisible ? .nextCompletion : nil
        case KeyCode.arrowUp:
            return context.completionVisible ? .previousCompletion : nil
        case KeyCode.n:
            return context.completionVisible && modifiers.contains(.control) ? .nextCompletion : nil
        case KeyCode.p:
            return context.completionVisible && modifiers.contains(.control) ? .previousCompletion : nil
        default:
            return nil
        }
    }

    func command(for event: NSEvent, completionVisible: Bool) -> CaptureKeyCommand? {
        command(for: event, context: CaptureKeyRoutingContext(completionVisible: completionVisible))
    }

    private func stashPickerCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        if modifiers.isEmpty,
           let index = CanceledDraftStash.acceleratorIndex(
            for: event.characters ?? "",
            entryCount: context.stashEntryCount
           )
        {
            return .restoreStashEntry(index)
        }

        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            return modifiers.isEmpty ? .restoreSelectedStashEntry : nil
        case KeyCode.escape:
            return .dismissStashPicker
        case KeyCode.leftBracket:
            return modifiers == .control ? .dismissStashPicker : printableModalCommand(for: event, modifiers: modifiers)
        case KeyCode.s:
            return modifiers == .control ? .toggleStashPicker : printableModalCommand(for: event, modifiers: modifiers)
        case KeyCode.arrowDown:
            return modifiers.isEmpty ? .nextStashEntry : nil
        case KeyCode.arrowUp:
            return modifiers.isEmpty ? .previousStashEntry : nil
        case KeyCode.n:
            return modifiers == .control ? .nextStashEntry : printableModalCommand(for: event, modifiers: modifiers)
        case KeyCode.p:
            return modifiers == .control ? .previousStashEntry : printableModalCommand(for: event, modifiers: modifiers)
        default:
            return printableModalCommand(for: event, modifiers: modifiers)
        }
    }

    private func printableModalCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> CaptureKeyCommand? {
        if modifiers.contains(.command) {
            return nil
        }
        guard let characters = event.characters, characters.count == 1 else {
            return nil
        }
        guard characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return .consumeKey
    }
}
