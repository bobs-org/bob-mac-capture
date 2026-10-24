import AppKit
import CaptureCore

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
    case focusSimilarRow(Int)
    case similarNextRow
    case similarPreviousRow
    case similarNextAction
    case similarPreviousAction
    case similarApplyDefault
    case similarApply(CaptureRelatedAction)
    case similarUnfocus
    case discardAndClose
    case stashDraftAndClose
    case toggleStashPicker
    case dismissStashPicker
    case clearCanceledDraftStash
    case nextStashEntry
    case previousStashEntry
    case restoreSelectedStashEntry
    case restoreStashEntry(Int)
    case toggleTemplateShelf
    case dismissTemplateShelf
    case nextTemplateEntry
    case previousTemplateEntry
    case useSelectedTemplate
    case useTemplate(Int)
    case armOrConfirmTemplateDelete
    case switchTemplateShelfToStash
    case saveTemplate
    case consumeKey
    case acceptCompletion
    case toggleCompletionThemeVisibility
    case acceptCompletionThenSubmitAndOpen
    case nextCompletion
    case previousCompletion
    case tabEditorAssist
    case decreaseBulletIndentation
    case submitTaskIDPrompt
    case cancelTaskIDPrompt
    case submitPomodoroNamePrompt
    case cancelPomodoroNamePrompt
    case openRelationLabelPrompt
    case submitRelationLabelPrompt
    case cancelRelationLabelPrompt
    case cycleRelationLabelSuggestionForward
    case cycleRelationLabelSuggestionBackward
    case acceptRelationLabelSuggestion
    case confirmPullInChoice
    case confirmPullInChoiceAndOpen
    case chooseNoPullInOffers
    case cancelPullInChoice
    case nextPullInOffer
    case previousPullInOffer
    case togglePullInOffer
    case markAllPullInOffers
    case acceptPickerRow
    case acceptPickerRowAndStart
    case acceptPickerRowAndContinue
    case acceptPickerRowAndSubmit
    case acceptPickerRowAndSubmitAndOpen
    case nextPickerRow
    case previousPickerRow
    case pagePickerRowsDown
    case pagePickerRowsUp
    case firstPickerRow
    case lastPickerRow
    case escapePicker
    case removePickerTrigger
    case openPickerFromChip
    case cycleTaskLinkSuggestionForward
    case cycleTaskLinkSuggestionBackward
    case continuePickerOperator(String)
    case insertCloseTaskNumber(String)
    case openTodayPomodoro
    case switchPanel
}

struct CaptureKeyRoutingContext: Equatable {
    var similarRowsVisible = false
    var similarRowFocused = false
    var completionVisible = false
    var completionHasSelectedHistoryTheme = false
    var completionThemeVisibilityWriteInFlight = false
    var stashPickerVisible = false
    var stashEntryCount = 0
    var templateShelfVisible = false
    var templateEntryCount = 0
    var taskIDPromptVisible = false
    var taskIDPromptIsTaskLink = false
    var taskIDPromptIsDependency = false
    var taskIDPromptIsTaskComplete = false
    var pomodoroNamePromptVisible = false
    var relationLabelPromptVisible = false
    var pickerSourceIsRelation = false
    var pullInChoiceVisible = false
    var pullInFilterFocused = false
    var pullInFilterIsEmpty = true
    var keyIsRepeat = false
    var pickerVisible = false
    var pickerSourceIsTaskLink = false
    var pickerSourceIsTaskComplete = false
    var pickerSourceIsTaskGoto = false
    var pickerDispatchInFlight = false
    var pickerFilterIsEmpty = true
    var pickerChipVisible = false
    var pickerOperatorContinuationKeys: [String] = []
    var taskIDPromptCyclesSuggestions = false
    var closeTaskCommaArmed = false
    var editorHasMarkedText = false
}

struct CaptureKeyCommandRouter {
    private static let ignoredReturnModifiers: NSEvent.ModifierFlags = [
        .capsLock, .numericPad, .function, .help,
    ]

    private static func strippedReturnModifiers(
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        modifiers.subtracting(ignoredReturnModifiers)
    }

    private enum KeyCode {
        static let `return`: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
        static let tab: UInt16 = 48
        static let delete: UInt16 = 51
        static let digit1: UInt16 = 18
        static let digit2: UInt16 = 19
        static let digit3: UInt16 = 20
        static let digit4: UInt16 = 21
        static let digit5: UInt16 = 23
        static let arrowDown: UInt16 = 125
        static let arrowUp: UInt16 = 126
        static let arrowLeft: UInt16 = 123
        static let arrowRight: UInt16 = 124
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
        static let home: UInt16 = 115
        static let end: UInt16 = 119
        static let a: UInt16 = 0
        static let space: UInt16 = 49
        static let j: UInt16 = 38
        static let k: UInt16 = 40
        static let s: UInt16 = 1
        static let t: UInt16 = 17
        static let c: UInt16 = 8
        static let d: UInt16 = 2
        static let e: UInt16 = 14
        static let n: UInt16 = 45
        static let o: UInt16 = 31
        static let p: UInt16 = 35
        static let u: UInt16 = 32
        static let leftBracket: UInt16 = 33
        static let backslash: UInt16 = 42
    }

    func command(
        for event: NSEvent,
        context: CaptureKeyRoutingContext = CaptureKeyRoutingContext()
    ) -> CaptureKeyCommand? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Ctrl+Tab / Ctrl+Shift+Tab switches panels. Matched before any
        // modal branch so the gesture always works while open surfaces
        // close through the existing hide paths. Caps Lock is ignored;
        // any other added modifier stays AppKit's.
        if event.keyCode == KeyCode.tab {
            let switchModifiers = modifiers.subtracting(.capsLock)
            if switchModifiers == .control || switchModifiers == [.control, .shift] {
                if context.editorHasMarkedText {
                    return nil
                }
                if context.keyIsRepeat || event.isARepeat || context.pickerDispatchInFlight {
                    return .consumeKey
                }
                return .switchPanel
            }
        }

        if context.templateShelfVisible {
            return templateShelfCommand(for: event, modifiers: modifiers, context: context)
        }

        if context.stashPickerVisible {
            return stashPickerCommand(for: event, modifiers: modifiers, context: context)
        }

        if context.taskIDPromptVisible {
            return taskIDPromptCommand(for: event, modifiers: modifiers, context: context)
        }

        if context.pomodoroNamePromptVisible {
            return pomodoroNamePromptCommand(for: event, modifiers: modifiers)
        }

        if context.relationLabelPromptVisible {
            return relationLabelPromptCommand(for: event, modifiers: modifiers)
        }

        if context.pullInChoiceVisible {
            return pullInChoiceCommand(
                for: event,
                modifiers: modifiers,
                isRepeat: context.keyIsRepeat || event.isARepeat,
                filterFocused: context.pullInFilterFocused,
                filterIsEmpty: context.pullInFilterIsEmpty
            )
        }

        if context.pickerVisible {
            if context.pickerDispatchInFlight {
                return .consumeKey
            }
            return pickerCommand(for: event, modifiers: modifiers, context: context)
        }

        if event.keyCode == KeyCode.d,
           modifiers == .control,
           context.completionHasSelectedHistoryTheme
        {
            return context.completionThemeVisibilityWriteInFlight
                ? .consumeKey
                : .toggleCompletionThemeVisibility
        }

        // Similar-tasks focus owns its keys in the main editor. Modal branches
        // above keep precedence, so a picker or prompt naturally shadows these.
        if context.similarRowFocused {
            if let number = Self.similarDigitNumber(for: event, modifiers: modifiers) {
                return .focusSimilarRow(number)
            }
            if let focused = similarFocusedCommand(for: event, modifiers: modifiers) {
                return focused
            }
            // Any other key unfocuses and passes through. The controller
            // unfocuses on the nil return, then returns the event to AppKit.
            return nil
        }

        if context.similarRowsVisible {
            if let number = Self.similarDigitNumber(for: event, modifiers: modifiers) {
                return .focusSimilarRow(number)
            }
        }

        if event.keyCode == KeyCode.s, modifiers == .control {
            return .toggleStashPicker
        }

        if event.keyCode == KeyCode.t, modifiers == .control {
            return .toggleTemplateShelf
        }

        if event.keyCode == KeyCode.backslash, modifiers == .control {
            return .openTodayPomodoro
        }

        if event.keyCode == KeyCode.s, modifiers == .command {
            return .saveTemplate
        }

        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            let keys = Self.strippedReturnModifiers(modifiers)
            if keys.contains(.command) {
                return context.completionVisible ? .acceptCompletionThenSubmitAndOpen : .submitAndOpen
            }
            if keys == .control {
                return context.completionVisible ? .acceptCompletionThenSubmitAndOpen : .submitAndOpen
            }
            if keys.contains(.shift) || keys.contains(.option) {
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
                return context.pickerChipVisible ? .openPickerFromChip : .tabEditorAssist
            }
            return modifiers == .shift ? .decreaseBulletIndentation : nil
        case KeyCode.arrowDown:
            if context.completionVisible {
                return .nextCompletion
            }
            return context.pickerChipVisible && modifiers.isEmpty ? .openPickerFromChip : nil
        case KeyCode.arrowUp:
            return context.completionVisible ? .previousCompletion : nil
        case KeyCode.n:
            if context.completionVisible, modifiers.contains(.control) {
                return .nextCompletion
            }
            return context.pickerChipVisible && modifiers == .control ? .openPickerFromChip : nil
        case KeyCode.p:
            return context.completionVisible && modifiers.contains(.control) ? .previousCompletion : nil
        default:
            // Close-list auto-comma: a digit typed in the main editor
            // right after a close task number. Checks `characters`, not
            // key codes, so numeric-keypad and Shift-digit layouts count;
            // only Command/Control/Option veto. Stash, prompt, and picker
            // branches above already own their digits.
            if context.closeTaskCommaArmed,
               modifiers.intersection([.command, .control, .option]).isEmpty,
               let characters = event.characters,
               characters.unicodeScalars.count == 1,
               let scalar = characters.unicodeScalars.first,
               scalar.value >= 0x31,
               scalar.value <= 0x39
            {
                return .insertCloseTaskNumber(characters)
            }
            return nil
        }
    }

    private func pullInChoiceCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool,
        filterFocused: Bool,
        filterIsEmpty: Bool
    ) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            guard !isRepeat else { return .consumeKey }
            let keys = Self.strippedReturnModifiers(modifiers)
            if keys == .control {
                return .confirmPullInChoiceAndOpen
            }
            if keys.contains(.control) {
                return .consumeKey
            }
            if keys == .shift {
                return .chooseNoPullInOffers
            }
            return keys.isEmpty ? .confirmPullInChoice : .consumeKey
        case KeyCode.escape:
            return .cancelPullInChoice
        case KeyCode.leftBracket:
            return modifiers == .control ? .cancelPullInChoice : nil
        case KeyCode.arrowUp:
            return modifiers.isEmpty ? .previousPullInOffer : nil
        case KeyCode.arrowDown:
            return modifiers.isEmpty ? .nextPullInOffer : nil
        case KeyCode.n:
            return modifiers == .control ? .nextPullInOffer : nil
        case KeyCode.p:
            return modifiers == .control ? .previousPullInOffer : nil
        case KeyCode.space:
            guard modifiers.isEmpty else { return nil }
            if isRepeat {
                return .consumeKey
            }
            return (!filterFocused || filterIsEmpty) ? .togglePullInOffer : nil
        case KeyCode.a:
            return modifiers == .command ? .markAllPullInOffers : nil
        case KeyCode.t:
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.backslash:
            return modifiers == .control ? .consumeKey : nil
        default:
            return nil
        }
    }

    func command(for event: NSEvent, completionVisible: Bool) -> CaptureKeyCommand? {
        command(for: event, context: CaptureKeyRoutingContext(completionVisible: completionVisible))
    }

    /// ⌘1–⌘5 by key code or by `charactersIgnoringModifiers`, in the
    /// main-editor branch next to ⌘S. The app menu uses no ⌘-digit.
    private static func similarDigitNumber(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> Int? {
        guard modifiers == .command else { return nil }
        switch event.keyCode {
        case KeyCode.digit1: return 1
        case KeyCode.digit2: return 2
        case KeyCode.digit3: return 3
        case KeyCode.digit4: return 4
        case KeyCode.digit5: return 5
        default: break
        }
        guard let chars = event.charactersIgnoringModifiers,
              chars.count == 1,
              let digit = Int(chars),
              (1...5).contains(digit)
        else { return nil }
        return digit
    }

    private func similarFocusedCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            // Plain Return applies the chosen action. Any modified Return
            // unfocuses and passes through (⌘↩ included).
            return Self.strippedReturnModifiers(modifiers).isEmpty ? .similarApplyDefault : nil
        case KeyCode.escape:
            return modifiers.isEmpty ? .similarUnfocus : nil
        case KeyCode.leftBracket:
            return modifiers == .control ? .similarUnfocus : nil
        case KeyCode.arrowLeft:
            return modifiers.isEmpty ? .similarPreviousAction : nil
        case KeyCode.arrowRight:
            return modifiers.isEmpty ? .similarNextAction : nil
        case KeyCode.arrowUp:
            return modifiers.isEmpty ? .similarPreviousRow : nil
        case KeyCode.arrowDown:
            return modifiers.isEmpty ? .similarNextRow : nil
        case KeyCode.delete:
            guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty else {
                return nil
            }
            return .similarApply(.discard)
        default:
            break
        }
        // Sigil direct-apply: the strip keys are the grammar itself. Shift is
        // allowed (`~` and `+` need it); Command/Control/Option veto.
        if modifiers.intersection([.command, .control, .option]).isEmpty,
           let characters = event.characters,
           characters.count == 1
        {
            switch characters {
            case "~": return .similarApply(.relate)
            case "+": return .similarApply(.note)
            case "&": return .similarApply(.needs)
            case "*": return .similarApply(.blocks)
            case "/": return .similarApply(.open)
            default: break
            }
        }
        return nil
    }

    private func taskIDPromptCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        // Link-mode Add block ID prompt: Tab / Shift-Tab cycle suggestions.
        // The parent-task flow keeps Tab consumed.
        if context.taskIDPromptCyclesSuggestions
            || context.taskIDPromptIsTaskLink
            || context.taskIDPromptIsDependency
            || context.taskIDPromptIsTaskComplete,
           event.keyCode == KeyCode.tab
        {
            if modifiers.isEmpty {
                return .cycleTaskLinkSuggestionForward
            }
            if modifiers == .shift {
                return .cycleTaskLinkSuggestionBackward
            }
        }
        return isolatedPromptCommand(
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

    private func relationLabelPromptCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> CaptureKeyCommand? {
        if event.keyCode == KeyCode.tab {
            if modifiers.isEmpty {
                return .acceptRelationLabelSuggestion
            }
            if modifiers == .shift {
                return .consumeKey
            }
        }
        if event.keyCode == KeyCode.arrowDown && modifiers.isEmpty
            || event.keyCode == KeyCode.n && modifiers == .control
        {
            return .cycleRelationLabelSuggestionForward
        }
        if event.keyCode == KeyCode.arrowUp && modifiers.isEmpty
            || event.keyCode == KeyCode.p && modifiers == .control
        {
            return .cycleRelationLabelSuggestionBackward
        }
        return isolatedPromptCommand(
            for: event,
            modifiers: modifiers,
            submit: .submitRelationLabelPrompt,
            cancel: .cancelRelationLabelPrompt
        )
    }

    /// Keyboard while the capture picker is open. Every key the picker
    /// table leaves to native field editing (printables, Cmd-A/C/V/X/Z,
    /// Ctrl-A/E, Left/Right) returns nil here — notably Ctrl-A/E, which must
    /// not fall through to the editor line-edge commands.
    private func pickerCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            let keys = Self.strippedReturnModifiers(modifiers)
            if keys.contains(.command) {
                return .acceptPickerRowAndSubmit
            }
            if keys == .control {
                return context.pickerSourceIsTaskGoto ? .acceptPickerRow : .acceptPickerRowAndSubmitAndOpen
            }
            if keys.contains(.control) {
                return .consumeKey
            }
            if keys == .shift {
                if context.pickerSourceIsTaskLink {
                    return .acceptPickerRowAndStart
                }
                if context.pickerSourceIsTaskComplete {
                    return .acceptPickerRowAndContinue
                }
                if context.pickerSourceIsRelation {
                    return .openRelationLabelPrompt
                }
                return .consumeKey
            }
            if keys.contains(.option) {
                return .consumeKey
            }
            return keys.isEmpty ? .acceptPickerRow : nil
        case KeyCode.tab:
            if modifiers.isEmpty {
                return .acceptPickerRow
            }
            return modifiers == .shift ? .consumeKey : nil
        case KeyCode.arrowDown:
            if modifiers.isEmpty {
                return .nextPickerRow
            }
            return modifiers == .command ? .lastPickerRow : nil
        case KeyCode.arrowUp:
            if modifiers.isEmpty {
                return .previousPickerRow
            }
            return modifiers == .command ? .firstPickerRow : nil
        case KeyCode.pageDown:
            return modifiers.isEmpty ? .pagePickerRowsDown : nil
        case KeyCode.pageUp:
            return modifiers.isEmpty ? .pagePickerRowsUp : nil
        case KeyCode.home:
            return modifiers.isEmpty || modifiers == .command ? .firstPickerRow : nil
        case KeyCode.end:
            return modifiers.isEmpty || modifiers == .command ? .lastPickerRow : nil
        case KeyCode.escape:
            return .escapePicker
        case KeyCode.leftBracket:
            if modifiers == .control {
                return .escapePicker
            }
            // Plain "[" doubles as a Complete-picker continuation key when the
            // filter is empty. The explicit keyCode case must not swallow it.
            if context.pickerFilterIsEmpty,
               !context.pickerOperatorContinuationKeys.isEmpty,
               modifiers.intersection([.command, .option, .control]).isEmpty,
               let characters = event.characters,
               characters.count == 1,
               context.pickerOperatorContinuationKeys.contains(characters)
            {
                return .continuePickerOperator(characters)
            }
            return nil
        case KeyCode.delete:
            // Only an unmodified Backspace on an empty filter removes the
            // trigger; any other Backspace edits the filter natively.
            guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty else {
                return nil
            }
            return context.pickerFilterIsEmpty ? .removePickerTrigger : nil
        case KeyCode.n:
            return modifiers == .control ? .nextPickerRow : nil
        case KeyCode.p:
            return modifiers == .control ? .previousPickerRow : nil
        case KeyCode.j:
            return modifiers == .control ? .nextPickerRow : nil
        case KeyCode.k:
            return modifiers == .control ? .previousPickerRow : nil
        case KeyCode.s:
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.t:
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.backslash:
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.c:
            return modifiers == .control ? .stashDraftAndClose : nil
        default:
            if context.pickerFilterIsEmpty,
               !context.pickerOperatorContinuationKeys.isEmpty,
               modifiers.intersection([.command, .option, .control]).isEmpty,
               let characters = event.characters,
               characters.count == 1,
               context.pickerOperatorContinuationKeys.contains(characters)
            {
                return .continuePickerOperator(characters)
            }
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
        case KeyCode.t:
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.backslash:
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
        if event.keyCode == KeyCode.t, modifiers == .control {
            return .toggleTemplateShelf
        }
        if event.keyCode == KeyCode.backslash, modifiers == .control {
            return .consumeKey
        }

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
            if modifiers == .control {
                return .consumeKey
            }
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

    private func templateShelfCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        if event.keyCode == KeyCode.t, modifiers == .control {
            return .toggleTemplateShelf
        }
        if event.keyCode == KeyCode.s, modifiers == .control {
            return .switchTemplateShelfToStash
        }
        if event.keyCode == KeyCode.backslash, modifiers == .control {
            return .consumeKey
        }

        if modifiers.isEmpty,
           let index = CapturePickerHelpers.acceleratorIndex(
            for: event.characters ?? "",
            entryCount: context.templateEntryCount
           )
        {
            return .useTemplate(index)
        }

        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            if modifiers == .control {
                return .consumeKey
            }
            return modifiers.isEmpty ? .useSelectedTemplate : nil
        case KeyCode.escape:
            return .dismissTemplateShelf
        case KeyCode.leftBracket:
            return modifiers == .control ? .dismissTemplateShelf : printableModalCommand(for: event, modifiers: modifiers)
        case KeyCode.delete:
            return modifiers.intersection([.command, .option, .control, .shift]).isEmpty
                ? .armOrConfirmTemplateDelete
                : printableModalCommand(for: event, modifiers: modifiers)
        case KeyCode.arrowDown:
            return modifiers.isEmpty ? .nextTemplateEntry : nil
        case KeyCode.arrowUp:
            return modifiers.isEmpty ? .previousTemplateEntry : nil
        case KeyCode.n:
            return modifiers == .control ? .nextTemplateEntry : printableModalCommand(for: event, modifiers: modifiers)
        case KeyCode.p:
            return modifiers == .control ? .previousTemplateEntry : printableModalCommand(for: event, modifiers: modifiers)
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
