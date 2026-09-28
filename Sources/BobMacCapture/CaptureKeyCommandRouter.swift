import AppKit

enum CaptureKeyCommand: Equatable {
    case submit
    case submitAndOpen
    case insertNewline
    case insertBulletNewline
    case insertLineAbove
    case deleteToBeginningOfLineOrPreviousLine
    case moveToBeginningOfLineOrPreviousLine
    case moveToEndOfLineOrNextLine
    case moveToNextLineKeepingColumn
    case moveToPreviousLineKeepingColumn
    case deleteBackward
    case escape
    case discardAndClose
    case stashDraftAndClose
    case toggleStashPicker
    case dismissStashPicker
    case clearCanceledDraftStash
    case nextStashEntry
    case previousStashEntry
    case restoreSelectedStashEntry
    case restoreStashEntry(Int)
    case consumeKey
    case acceptCompletion
    case nextCompletion
    case previousCompletion
    case tabEditorAssist
    case decreaseBulletIndentation
    case submitTaskIDPrompt
    case cancelTaskIDPrompt
    case submitPomodoroNamePrompt
    case cancelPomodoroNamePrompt
    case acceptActiveTask
    case acceptActiveTaskAndSubmit
    case nextActiveTask
    case previousActiveTask
    case pageActiveTasksDown
    case pageActiveTasksUp
    case firstActiveTask
    case lastActiveTask
    case escapeActiveTaskPicker
    case removeActiveTaskTrigger
    case openActiveTaskPicker
}

struct CaptureKeyRoutingContext: Equatable {
    var completionVisible = false
    var stashPickerVisible = false
    var stashEntryCount = 0
    var taskIDPromptVisible = false
    var pomodoroNamePromptVisible = false
    var activeTaskPickerVisible = false
    var activeTaskFilterIsEmpty = true
    var activeTaskChipVisible = false
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
        static let arrowLeft: UInt16 = 123
        static let arrowRight: UInt16 = 124
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
        static let home: UInt16 = 115
        static let end: UInt16 = 119
        static let a: UInt16 = 0
        static let j: UInt16 = 38
        static let k: UInt16 = 40
        static let s: UInt16 = 1
        static let c: UInt16 = 8
        static let e: UInt16 = 14
        static let n: UInt16 = 45
        static let o: UInt16 = 31
        static let p: UInt16 = 35
        static let u: UInt16 = 32
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

        if context.taskIDPromptVisible {
            return taskIDPromptCommand(for: event, modifiers: modifiers)
        }

        if context.pomodoroNamePromptVisible {
            return pomodoroNamePromptCommand(for: event, modifiers: modifiers)
        }

        if context.activeTaskPickerVisible {
            return activeTaskPickerCommand(for: event, modifiers: modifiers, context: context)
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
        case KeyCode.o:
            return modifiers == [.control, .shift] ? .insertLineAbove : nil
        case KeyCode.j:
            if modifiers == .control {
                return .insertBulletNewline
            }
            return modifiers == [.control, .shift] ? .moveToNextLineKeepingColumn : nil
        case KeyCode.k:
            return modifiers == [.control, .shift] ? .moveToPreviousLineKeepingColumn : nil
        case KeyCode.u:
            return modifiers == .control ? .deleteToBeginningOfLineOrPreviousLine : nil
        case KeyCode.a:
            return modifiers == .control ? .moveToBeginningOfLineOrPreviousLine : nil
        case KeyCode.e:
            return modifiers == .control ? .moveToEndOfLineOrNextLine : nil
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
            // runs the ordered editor-assist chain (snippet expansion, then bullet
            // indentation); Shift-Tab always outdents, deliberately replacing the
            // accidental completion acceptance it used to trigger. Every other modifier
            // combination (Command, Option, Control, or Shift plus another modifier)
            // stays AppKit's. While the reopen chip is visible, plain Tab reopens
            // the picker instead.
            if modifiers.isEmpty {
                if context.completionVisible {
                    return .acceptCompletion
                }
                return context.activeTaskChipVisible ? .openActiveTaskPicker : .tabEditorAssist
            }
            return modifiers == .shift ? .decreaseBulletIndentation : nil
        case KeyCode.arrowDown:
            if context.completionVisible {
                return .nextCompletion
            }
            return context.activeTaskChipVisible && modifiers.isEmpty ? .openActiveTaskPicker : nil
        case KeyCode.arrowUp:
            return context.completionVisible ? .previousCompletion : nil
        case KeyCode.n:
            if context.completionVisible, modifiers.contains(.control) {
                return .nextCompletion
            }
            return context.activeTaskChipVisible && modifiers == .control ? .openActiveTaskPicker : nil
        case KeyCode.p:
            return context.completionVisible && modifiers.contains(.control) ? .previousCompletion : nil
        default:
            return nil
        }
    }

    func command(for event: NSEvent, completionVisible: Bool) -> CaptureKeyCommand? {
        command(for: event, context: CaptureKeyRoutingContext(completionVisible: completionVisible))
    }

    private func taskIDPromptCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> CaptureKeyCommand? {
        isolatedPromptCommand(
            for: event,
            modifiers: modifiers,
            submit: .submitTaskIDPrompt,
            cancel: .cancelTaskIDPrompt
        )
    }

    private func pomodoroNamePromptCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> CaptureKeyCommand? {
        isolatedPromptCommand(
            for: event,
            modifiers: modifiers,
            submit: .submitPomodoroNamePrompt,
            cancel: .cancelPomodoroNamePrompt
        )
    }

    /// Keyboard while the Active Task Picker is open. Every key the picker
    /// table leaves to native field editing (printables, Cmd-A/C/V/X/Z,
    /// Ctrl-A/E, Left/Right) returns nil here — notably Ctrl-A/E, which must
    /// not fall through to the editor line-edge commands.
    private func activeTaskPickerCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            if modifiers.contains(.command) {
                return .acceptActiveTaskAndSubmit
            }
            if modifiers.contains(.shift) || modifiers.contains(.option) {
                return .consumeKey
            }
            return modifiers.isEmpty ? .acceptActiveTask : nil
        case KeyCode.tab:
            if modifiers.isEmpty {
                return .acceptActiveTask
            }
            return modifiers == .shift ? .consumeKey : nil
        case KeyCode.arrowDown:
            if modifiers.isEmpty {
                return .nextActiveTask
            }
            return modifiers == .command ? .lastActiveTask : nil
        case KeyCode.arrowUp:
            if modifiers.isEmpty {
                return .previousActiveTask
            }
            return modifiers == .command ? .firstActiveTask : nil
        case KeyCode.pageDown:
            return modifiers.isEmpty ? .pageActiveTasksDown : nil
        case KeyCode.pageUp:
            return modifiers.isEmpty ? .pageActiveTasksUp : nil
        case KeyCode.home:
            return modifiers.isEmpty || modifiers == .command ? .firstActiveTask : nil
        case KeyCode.end:
            return modifiers.isEmpty || modifiers == .command ? .lastActiveTask : nil
        case KeyCode.escape:
            return .escapeActiveTaskPicker
        case KeyCode.leftBracket:
            return modifiers == .control ? .escapeActiveTaskPicker : nil
        case KeyCode.delete:
            // Only an unmodified Backspace on an empty filter removes the
            // trigger; any other Backspace edits the filter natively.
            guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty else {
                return nil
            }
            return context.activeTaskFilterIsEmpty ? .removeActiveTaskTrigger : nil
        case KeyCode.n:
            return modifiers == .control ? .nextActiveTask : nil
        case KeyCode.p:
            return modifiers == .control ? .previousActiveTask : nil
        case KeyCode.j:
            return modifiers == .control ? .nextActiveTask : nil
        case KeyCode.k:
            return modifiers == .control ? .previousActiveTask : nil
        case KeyCode.s:
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.c:
            return modifiers == .control ? .stashDraftAndClose : nil
        default:
            return nil
        }
    }

    private func isolatedPromptCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        submit: CaptureKeyCommand,
        cancel: CaptureKeyCommand
    ) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            if modifiers.contains(.command) {
                return .consumeKey
            }
            return submit
        case KeyCode.escape:
            return cancel
        case KeyCode.leftBracket:
            return modifiers == .control ? cancel : nil
        case KeyCode.c:
            return modifiers == .control ? .stashDraftAndClose : nil
        case KeyCode.tab, KeyCode.arrowDown, KeyCode.arrowUp:
            return modifiers.contains(.command) ? nil : .consumeKey
        case KeyCode.n, KeyCode.p:
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.s:
            return modifiers == .control ? .consumeKey : nil
        default:
            return nil
        }
    }

    private func stashPickerCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        if isClearStashShortcut(for: event, modifiers: modifiers) {
            return .clearCanceledDraftStash
        }

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

    private func isClearStashShortcut(for event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard event.characters == "D" else {
            return false
        }
        return modifiers.subtracting([.shift, .capsLock]).isEmpty
    }
}
