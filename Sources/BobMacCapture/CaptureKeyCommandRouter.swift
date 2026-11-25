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
    case moveByWord(CaptureWordMotion.Direction, CaptureWordMotion.Unit)
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
    case recordTab
    case recordShiftTab
    case recordReturn(openAfterCapture: Bool)
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
    case toggleRelationLabelVisibility
    case toggleRelationLabelHiddenSection
    case openRelationLabelRename
    case relationLabelPromptBackspace
    case confirmMoveChoice
    case confirmMoveChoiceAndOpen
    case chooseNoMoves
    case cancelMoveChoice
    case confirmMailClose
    case cancelMailClose
    case hintMailClose
    case openMailCloseGmail
    case nextMoveChoice
    case previousMoveChoice
    case toggleMoveChoice
    case selectAllMoveChoices
    case setMoveChoice(CaptureMoveChoiceAnswer)
    case editMoveChoiceFilter(String)
    case deleteMoveChoiceFilter
    case confirmPullInChoice
    case confirmPullInChoiceAndOpen
    case chooseNoPullInOffers
    case cancelPullInChoice
    case nextPullInOffer
    case previousPullInOffer
    case togglePullInOffer
    case togglePullInJump
    case togglePullInOfferAndAdvance(keepFilterFocus: Bool)
    case previousPullInOfferFromTab(keepFilterFocus: Bool)
    case markAllPullInOffers
    case stagePullInDone
    case beginPullInCancel
    case stageRequirementCarry
    case confirmPullInReason
    case restorePullInReason
    case recallNextPullInReason
    case recallPreviousPullInReason
    case movePullInLinkNext
    case movePullInLinkPrevious
    case acceptPullInLink
    case acceptPullInLinkFromTab
    case closePullInLinkBand
    /// NAME stage of the tasks band: write the ID and insert the link.
    case commitPullInLinkName
    /// NAME stage: back to the task list with the filter intact.
    case cancelPullInLinkName
    case cyclePullInLinkNameForward
    case cyclePullInLinkNameBackward
    case togglePullInOfferAt(String)
    case confirmInboxRouteChoice
    case confirmInboxRouteChoiceAndOpen
    case keepInboxRouteCandidate
    case cancelInboxRouteChoice
    case nextInboxRouteDestination
    case previousInboxRouteDestination
    case acceptPickerRow
    case acceptPickerRowAndStart
    case acceptPickerRowAndContinue
    case acceptPickerRowAndSubmit
    case acceptPickerRowAndSubmitAndOpen
    case toggleGotoClosedTasks
    case toggleGotoArchivedNotes
    case showNoteGotoUpgradeHint
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
    case flipRelationDirection
    case flipRelationLabelDirection
    case insertCloseTaskNumber(String)
    case openTodayPomodoro
    case openGotoFromBackslash
    case typeLiteralBackslash
    case typeKeyBeforeHashAliasReply
    case typeLiteralForHashAlias
    case typeKeyBeforeEqualsReply
    case undoEqualsGestureAndTypeLiteral
    case restoreRelationEqualsOpener(String)
    case joinCalendarEvent
    case openGcalNote(String?)
    case gcalNoteEscape
    case gcalNoteMoveNext
    case gcalNoteMovePrevious
    case gcalNoteOpenSelected
    case gcalNoteSave
    case gcalNoteClear
    case gcalNoteToggleScope
    case gcalNoteUndo
    case gcalNotePassThrough
    case openMeetingNotes(String?)
    case meetingNotesEscape
    case meetingNotesMoveNext
    case meetingNotesMovePrevious
    case meetingNotesOpenSelected
    case meetingNotesFile
    case meetingNotesRetry
    case meetingNotesPassThrough
    case switchPanel
    case armEditorLeader
    case cancelEditorLeader
    case toggleLineCase
    case rejectEditorLeaderKey
}

enum MeetingNotesKeySurface: Equatable {
    case inactive
    case choosingMeeting
    case choosingParent
    case confirmingReplace
    case preview
    case writing
    case other
}

struct CaptureKeyRoutingContext: Equatable {
    var similarRowsVisible = false
    var similarRowFocused = false
    var completionVisible = false
    var recordCardActive = false
    var recordAssistAvailable = false
    var recordCompletionListVisible = false
    var recordEditorListVisible = false
    var recordShowsGenericCompletionFallback = false
    /// Defaults true so omitted flags keep selected-row Return/Tab behavior.
    var completionHasSelection = true
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
    var taskIDPromptIsWikilinkTask = false
    var pomodoroNamePromptVisible = false
    var relationLabelPromptVisible = false
    var relationLabelPromptFieldIsEmpty = true
    var relationLabelPromptOneOff = false
    var relationLabelRenameActive = false
    var relationLabelFieldHasMarkedText = false
    var pickerSourceIsRelation = false
    var moveChoiceVisible = false
    var moveChoiceFilterFocused = false
    var moveChoiceFilterIsEmpty = true
    var mailCloseVisible = false
    var pullInChoiceVisible = false
    var pullInFilterFocused = false
    var pullInFilterIsEmpty = true
    var pullInReasonFocused = false
    /// The LINK band is visible in the recall slot: its keys win.
    var pullInLinkOpen = false
    /// The LINK band has a selected row to insert.
    var pullInLinkCanAccept = false
    /// The tasks band's NAME stage owns the keys: its block ID field holds
    /// first responder while the reason draft stays untouched.
    var pullInLinkNaming = false
    var inboxRouteChoiceVisible = false
    var keyIsRepeat = false
    /// Defaults true so omitted flags keep selected-row picker Return/Tab.
    var pickerHasSelection = true
    var pickerVisible = false
    var pickerSourceIsTaskLink = false
    var pickerSourceIsTaskComplete = false
    var pickerSourceIsTaskGoto = false
    var pickerSourceIsNoteGoto = false
    var pickerSourceIsParentTask = false
    var pickerParentContinuationAvailable = false
    var pickerSourceIsProjectTaskMove = false
    var pickerDispatchInFlight = false
    var pickerFilterIsEmpty = true
    var pickerChipVisible = false
    var pickerOperatorContinuationKeys: [String] = []
    var pickerOperatorContinuationAliases: [String: String] = [:]
    var taskIDPromptCyclesSuggestions = false
    var closeTaskCommaArmed = false
    var draftIsBlank = false
    var draftIsBareGotoSigil = false
    var backslashLiteralArmed = false
    var hashAliasLiteralKey: String? = nil
    var hashAliasReplyPendingKey: String? = nil
    var relationEqualsOpenerArmed = false
    var modifierAliasOpenerOwnPickerIsEmpty = false
    var equalsGestureFastSecond = false
    var equalsGestureFastSecondKey = "="
    var equalsProbeFirstKey: String? = nil
    var equalsProbeReplyPendingKey: String? = nil
    var editorHasMarkedText = false
    var editorLeaderPending = false
    var gcalNoteModeVisible = false
    var gcalNoteEditing = false
    var gcalNoteCanUndoMutation = false
    var calendarNoteActionIsFocused = false
    var focusedCalendarNoteURL: String? = nil
    var meetingNotesModeVisible = false
    var meetingNotesIsWriting = false
    var meetingNotesCanFile = false
    var meetingNotesFilterFocused = false
    var meetingNotesActionIsFocused = false
    var focusedMeetingRef: String? = nil
    var captureSubmitInFlight = false
    var meetingNotesKnownUnsupported = false
    var meetingNotesSurface: MeetingNotesKeySurface = .inactive
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

    /// Typed `\` by characters, not key code, so layouts needing Option or
    /// Shift still match. Command and Control veto; marked text is checked
    /// by the caller through `editorHasMarkedText`.
    static func isTypedBackslash(
        event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard event.characters == "\\" else {
            return false
        }
        return !modifiers.contains(.command)
            && !modifiers.contains(.control)
    }

    /// Typed `/` by characters, not key code, so layouts needing Shift or
    /// Option for `/` still match. Command and Control veto; marked text is
    /// checked by the caller through `editorHasMarkedText`.
    static func isTypedSlash(
        event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard event.characters == "/" else {
            return false
        }
        return !modifiers.contains(.command)
            && !modifiers.contains(.control)
    }

    /// The typed hash-alias key (`\` or `/`) by characters, or nil for any
    /// other key. Command and Control veto; marked text is checked by the
    /// caller through `editorHasMarkedText`.
    static func typedHashAliasKey(
        event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> String? {
        if isTypedBackslash(event: event, modifiers: modifiers) {
            return "\\"
        }
        if isTypedSlash(event: event, modifiers: modifiers) {
            return "/"
        }
        return nil
    }

    /// The typed probe key by characters, or nil for another key. Shift is
    /// allowed (for `~`); Command, Option, and Control veto. Dot and
    /// semicolon count only after the same pending first key.
    static func typedEqualsProbeKey(
        event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        pendingFirstKey: String? = nil
    ) -> String? {
        guard event.characters == "=" || event.characters == "~"
                || event.characters == "." || event.characters == ";",
              modifiers.intersection([.command, .option, .control]).isEmpty
        else {
            return nil
        }
        if event.characters == "." || event.characters == ";" {
            guard pendingFirstKey == event.characters else {
                return nil
            }
        }
        return event.characters
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
        static let x: UInt16 = 7
        static let d: UInt16 = 2
        static let g: UInt16 = 5
        static let h: UInt16 = 4
        static let l: UInt16 = 37
        static let r: UInt16 = 15
        static let e: UInt16 = 14
        static let z: UInt16 = 6
        static let m: UInt16 = 46
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

        if context.gcalNoteModeVisible {
            if context.editorHasMarkedText {
                return .gcalNotePassThrough
            }
            if event.keyCode == KeyCode.escape,
               modifiers.subtracting(.capsLock).isEmpty
            {
                return .gcalNoteEscape
            }
            if event.keyCode == KeyCode.z, modifiers.subtracting(.capsLock) == .command {
                if context.gcalNoteCanUndoMutation {
                    return .gcalNoteUndo
                }
                if context.gcalNoteEditing {
                    return .gcalNotePassThrough
                }
                return .consumeKey
            }
            if event.keyCode == KeyCode.e, modifiers.subtracting(.capsLock) == .command {
                return .consumeKey
            }
            if event.keyCode == KeyCode.s,
               modifiers.subtracting(.capsLock) == [.control, .option]
            {
                return context.gcalNoteEditing ? .gcalNoteToggleScope : .consumeKey
            }
            if event.keyCode == KeyCode.delete,
               modifiers.subtracting(.capsLock) == .command
            {
                return context.gcalNoteEditing ? .gcalNoteClear : .consumeKey
            }
            if context.gcalNoteEditing {
                if event.keyCode == KeyCode.return || event.keyCode == KeyCode.keypadEnter {
                    if context.keyIsRepeat || event.isARepeat {
                        return .consumeKey
                    }
                    if Self.strippedReturnModifiers(modifiers).isEmpty {
                        return .gcalNoteSave
                    }
                    if Self.strippedReturnModifiers(modifiers) == .shift {
                        return .gcalNotePassThrough
                    }
                }
                // Caret motion, typing, and the editor's own undo stay in the
                // event-note NSTextView. Picker selection keys do not apply.
                return .gcalNotePassThrough
            }
            if event.keyCode == KeyCode.arrowDown,
               modifiers.intersection([.command, .control, .option, .shift]).isEmpty
            {
                return .gcalNoteMoveNext
            }
            if event.keyCode == KeyCode.arrowUp,
               modifiers.intersection([.command, .control, .option, .shift]).isEmpty
            {
                return .gcalNoteMovePrevious
            }
            if event.keyCode == KeyCode.n, modifiers == .control {
                return .gcalNoteMoveNext
            }
            if event.keyCode == KeyCode.p, modifiers == .control {
                return .gcalNoteMovePrevious
            }
            if event.keyCode == KeyCode.return || event.keyCode == KeyCode.keypadEnter {
                if Self.strippedReturnModifiers(modifiers).isEmpty {
                    return .gcalNoteOpenSelected
                }
            }
            // Keep native filter typing, but prevent capture commands from acting on
            // the covered editor.
            return .gcalNotePassThrough
        }

        if context.meetingNotesModeVisible {
            if context.editorHasMarkedText {
                return .meetingNotesPassThrough
            }
            if event.keyCode == KeyCode.escape,
                modifiers.subtracting(.capsLock).isEmpty
            {
                return context.keyIsRepeat || event.isARepeat
                    ? .consumeKey : .meetingNotesEscape
            }
            if event.keyCode == KeyCode.leftBracket, modifiers == .control {
                return context.keyIsRepeat || event.isARepeat
                    ? .consumeKey : .meetingNotesEscape
            }
            if !context.meetingNotesFilterFocused,
                modifiers.subtracting(.capsLock).isEmpty,
                event.characters == "q" || event.characters == "Q"
            {
                return context.keyIsRepeat || event.isARepeat
                    ? .consumeKey : .meetingNotesEscape
            }
            if event.keyCode == KeyCode.m,
                modifiers.subtracting(.capsLock) == .command
            {
                return .consumeKey
            }
            if event.keyCode == KeyCode.e,
                modifiers.subtracting(.capsLock) == .command
            {
                return .consumeKey
            }
            if context.meetingNotesIsWriting || context.meetingNotesSurface == .writing {
                return .consumeKey
            }
            let choiceSurface =
                context.meetingNotesSurface == .choosingMeeting
                || context.meetingNotesSurface == .choosingParent
                || context.meetingNotesSurface == .confirmingReplace
            if event.keyCode == KeyCode.arrowDown,
                modifiers.intersection([.command, .control, .option, .shift]).isEmpty
            {
                return choiceSurface ? .meetingNotesMoveNext : .consumeKey
            }
            if event.keyCode == KeyCode.arrowUp,
                modifiers.intersection([.command, .control, .option, .shift]).isEmpty
            {
                return choiceSurface ? .meetingNotesMovePrevious : .consumeKey
            }
            if event.keyCode == KeyCode.n, modifiers == .control {
                return choiceSurface ? .meetingNotesMoveNext : .consumeKey
            }
            if event.keyCode == KeyCode.p, modifiers == .control {
                return choiceSurface ? .meetingNotesMovePrevious : .consumeKey
            }
            if event.keyCode == KeyCode.return || event.keyCode == KeyCode.keypadEnter {
                if context.keyIsRepeat || event.isARepeat {
                    return .consumeKey
                }
                if Self.strippedReturnModifiers(modifiers).isEmpty {
                    switch context.meetingNotesSurface {
                    case .choosingMeeting, .choosingParent, .confirmingReplace:
                        return .meetingNotesOpenSelected
                    case .preview:
                        return context.meetingNotesCanFile
                            ? .meetingNotesFile : .consumeKey
                    default:
                        return .consumeKey
                    }
                }
            }
            // Filter typing stays native. Every other key is consumed so
            // it cannot mutate the covered capture editor. Ctrl+[ already
            // escaped above and never types.
            if context.meetingNotesFilterFocused {
                return .meetingNotesPassThrough
            }
            return .consumeKey
        }

        if event.keyCode == KeyCode.e,
           modifiers.subtracting(.capsLock) == .command
        {
            if context.editorHasMarkedText {
                return nil
            }
            if context.keyIsRepeat || event.isARepeat || context.captureSubmitInFlight {
                return .consumeKey
            }
            return .openGcalNote(
                context.calendarNoteActionIsFocused ? context.focusedCalendarNoteURL : nil
            )
        }

        if event.keyCode == KeyCode.m,
           modifiers.subtracting(.capsLock) == .command
        {
            if context.editorHasMarkedText {
                return nil
            }
            if context.keyIsRepeat || event.isARepeat || context.captureSubmitInFlight
                || context.meetingNotesKnownUnsupported
            {
                return .consumeKey
            }
            return .openMeetingNotes(
                context.meetingNotesActionIsFocused ? context.focusedMeetingRef : nil
            )
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
            return relationLabelPromptCommand(
                for: event,
                modifiers: modifiers,
                fieldIsEmpty: context.relationLabelPromptFieldIsEmpty,
                oneOff: context.relationLabelPromptOneOff,
                renameActive: context.relationLabelRenameActive,
                fieldHasMarkedText: context.relationLabelFieldHasMarkedText,
                keyIsRepeat: context.keyIsRepeat
            )
        }

        if context.mailCloseVisible {
            return mailCloseCommand(for: event, modifiers: modifiers, context: context)
        }
        if context.moveChoiceVisible {
            return moveChoiceCommand(for: event, modifiers: modifiers, context: context)
        }
        if context.pullInChoiceVisible {
            return pullInChoiceCommand(
                for: event,
                modifiers: modifiers,
                isRepeat: context.keyIsRepeat || event.isARepeat,
                filterFocused: context.pullInFilterFocused,
                filterIsEmpty: context.pullInFilterIsEmpty,
                reasonFocused: context.pullInReasonFocused,
                linkOpen: context.pullInLinkOpen,
                linkCanAccept: context.pullInLinkCanAccept,
                linkNaming: context.pullInLinkNaming
            )
        }

        if context.inboxRouteChoiceVisible {
            return inboxRouteChoiceCommand(
                for: event,
                modifiers: modifiers,
                isRepeat: context.keyIsRepeat || event.isARepeat
            )
        }

        if context.pickerVisible {
            if context.pickerDispatchInFlight {
                return .consumeKey
            }
            return pickerCommand(for: event, modifiers: modifiers, context: context)
        }

        // A fast second key undoes whatever the first key did and types
        // one literal (`=` or `.`). Checked before the opener restores and
        // every other editor path.
        if context.equalsGestureFastSecond,
           event.characters == context.equalsGestureFastSecondKey,
           modifiers.intersection([.command, .option, .control]).isEmpty,
           !context.editorHasMarkedText,
           !context.keyIsRepeat,
           !event.isARepeat
        {
            return .undoEqualsGestureAndTypeLiteral
        }

        if let command = relationEqualsOpenerRestoreCommand(
            for: event,
            modifiers: modifiers,
            context: context
        ) {
            return command
        }

        if context.editorLeaderPending {
            return editorLeaderCommand(
                for: event,
                modifiers: modifiers,
                isRepeat: context.keyIsRepeat || event.isARepeat
            )
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
            if let motion = Self.wordMotionCommand(
                for: event,
                modifiers: modifiers,
                context: context
            ) {
                return motion
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

        if event.keyCode == KeyCode.g, modifiers == .control {
            return context.editorHasMarkedText ? nil : .armEditorLeader
        }

        if event.keyCode == KeyCode.backslash, modifiers == .command {
            return .openTodayPomodoro
        }

        if let hashAliasKey = Self.typedHashAliasKey(event: event, modifiers: modifiers),
           !context.editorHasMarkedText
        {
            let isRepeat = context.keyIsRepeat || event.isARepeat
            if hashAliasKey == "\\",
               context.draftIsBlank || context.draftIsBareGotoSigil
            {
                if isRepeat {
                    return .consumeKey
                }
                if context.draftIsBlank {
                    return .openGotoFromBackslash
                }
                if context.backslashLiteralArmed {
                    return .typeLiteralBackslash
                }
                if context.pickerChipVisible {
                    return .openPickerFromChip
                }
                return .consumeKey
            }
            if context.hashAliasLiteralKey == hashAliasKey {
                if isRepeat {
                    return .consumeKey
                }
                return .typeLiteralForHashAlias
            }
            if context.hashAliasReplyPendingKey == hashAliasKey {
                if isRepeat {
                    return nil
                }
                return .typeKeyBeforeHashAliasReply
            }
        }

        if let probeKey = Self.typedEqualsProbeKey(
            event: event,
            modifiers: modifiers,
            pendingFirstKey: context.equalsProbeFirstKey
        ),
           !context.editorHasMarkedText,
           context.equalsProbeReplyPendingKey == probeKey
        {
            if context.keyIsRepeat || event.isARepeat {
                return nil
            }
            return .typeKeyBeforeEqualsReply
        }

        if event.keyCode == KeyCode.s, modifiers == .command {
            return .saveTemplate
        }

        if let motion = Self.wordMotionCommand(
            for: event,
            modifiers: modifiers,
            context: context
        ) {
            return motion
        }

        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            let keys = Self.strippedReturnModifiers(modifiers)
            if context.recordCardActive,
               !keys.contains(.shift), !keys.contains(.option)
            {
                if context.completionHasSelection,
                   context.recordCompletionListVisible
                       || context.recordShowsGenericCompletionFallback
                {
                    return .acceptCompletion
                }
                if keys.contains(.command) || keys == .control {
                    return .recordReturn(openAfterCapture: true)
                }
                if keys.isEmpty {
                    return .recordReturn(openAfterCapture: false)
                }
            }
            if keys.contains(.command) {
                if context.completionVisible, context.completionHasSelection {
                    return .acceptCompletionThenSubmitAndOpen
                }
                return .submitAndOpen
            }
            if keys == .control {
                if context.completionVisible, context.completionHasSelection {
                    return .acceptCompletionThenSubmitAndOpen
                }
                return .submitAndOpen
            }
            if keys.contains(.shift) || keys.contains(.option) {
                return .insertNewline
            }
            if context.completionVisible, context.completionHasSelection {
                return .acceptCompletion
            }
            return .submit
        case KeyCode.o:
            return modifiers == [.control, .shift] ? .insertLineAbove : nil
        case KeyCode.j:
            // Command-J is free: in an empty draft it joins the focus
            // calendar event. Any other draft leaves the key to AppKit.
            if modifiers == .command {
                return context.draftIsBlank ? .joinCalendarEvent : nil
            }
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
                if context.recordCardActive, context.recordAssistAvailable {
                    if context.recordCompletionListVisible || context.recordEditorListVisible {
                        return .acceptCompletion
                    }
                    if context.pickerChipVisible {
                        return .openPickerFromChip
                    }
                    return .recordTab
                }
                if context.completionVisible {
                    return .acceptCompletion
                }
                return context.pickerChipVisible ? .openPickerFromChip : .tabEditorAssist
            }
            if modifiers == .shift, context.recordCardActive, context.recordAssistAvailable {
                return .recordShiftTab
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

    private func moveChoiceCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        let repeated = context.keyIsRepeat || event.isARepeat
        if modifiers.subtracting(.shift).isEmpty,
            let text = event.characters, text == "^" || text == ":"
        {
            return repeated ? .consumeKey : .setMoveChoice(text == "^" ? .move : .moveAndLink)
        }
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            guard !repeated else { return .consumeKey }
            let keys = Self.strippedReturnModifiers(modifiers)
            if keys == .control { return .confirmMoveChoiceAndOpen }
            if keys == .shift { return .chooseNoMoves }
            return keys.isEmpty ? .confirmMoveChoice : .consumeKey
        case KeyCode.escape: return .cancelMoveChoice
        case KeyCode.leftBracket:
            if modifiers == .control { return .cancelMoveChoice }
        case KeyCode.arrowUp:
            return modifiers.isEmpty ? .previousMoveChoice : nil
        case KeyCode.arrowDown:
            return modifiers.isEmpty ? .nextMoveChoice : nil
        case KeyCode.n:
            if modifiers == .control { return .nextMoveChoice }
        case KeyCode.p:
            if modifiers == .control { return .previousMoveChoice }
        case KeyCode.a:
            if modifiers == .command { return repeated ? .consumeKey : .selectAllMoveChoices }
        case KeyCode.space:
            if modifiers.isEmpty, context.moveChoiceFilterIsEmpty {
                return repeated ? .consumeKey : .toggleMoveChoice
            }
        case KeyCode.delete:
            if modifiers.isEmpty, !context.moveChoiceFilterFocused {
                return .deleteMoveChoiceFilter
            }
        default: break
        }
        if !context.moveChoiceFilterFocused, modifiers.subtracting(.shift).isEmpty,
            let text = event.characters, !text.isEmpty,
            text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        {
            return .editMoveChoiceFilter(text)
        }
        return nil
    }

    private func mailCloseCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        let repeated = context.keyIsRepeat || event.isARepeat
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            guard !repeated else { return .consumeKey }
            let keys = Self.strippedReturnModifiers(modifiers)
            if keys == .command { return .openMailCloseGmail }
            if keys.isEmpty { return .hintMailClose }
            return .consumeKey
        case KeyCode.escape:
            return repeated ? .consumeKey : .cancelMailClose
        case KeyCode.leftBracket:
            if modifiers == .control { return repeated ? .consumeKey : .cancelMailClose }
            return .consumeKey
        default: break
        }
        if modifiers.subtracting(.shift).isEmpty, let text = event.characters {
            if text == "y" || text == "Y" {
                return repeated ? .consumeKey : .confirmMailClose
            }
            if text == "q" || text == "Q" {
                return repeated ? .consumeKey : .cancelMailClose
            }
        }
        return .consumeKey
    }

    private func pullInChoiceCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool,
        filterFocused: Bool,
        filterIsEmpty: Bool,
        reasonFocused: Bool = false,
        linkOpen: Bool = false,
        linkCanAccept: Bool = false,
        linkNaming: Bool = false
    ) -> CaptureKeyCommand? {
        // The NAME stage's field holds first responder, so neither the
        // reason keys nor the offer-list keys may see its events: Return
        // would otherwise confirm the Pull-In.
        if linkNaming {
            return pullInLinkNameCommand(
                for: event, modifiers: modifiers, isRepeat: isRepeat)
        }
        if reasonFocused {
            if linkOpen {
                return pullInLinkCommand(
                    for: event, modifiers: modifiers, isRepeat: isRepeat,
                    canAccept: linkCanAccept)
            }
            switch event.keyCode {
            case KeyCode.return, KeyCode.keypadEnter:
                guard !isRepeat else { return .consumeKey }
                let keys = Self.strippedReturnModifiers(modifiers)
                return keys.isEmpty ? .confirmPullInReason : nil
            case KeyCode.j:
                // Ctrl+J never pins while a Cancel reason is being edited.
                return modifiers == .control ? .consumeKey : nil
            case KeyCode.escape:
                guard !isRepeat else { return .consumeKey }
                return .restorePullInReason
            case KeyCode.leftBracket:
                return modifiers == .control && !isRepeat ? .restorePullInReason : nil
            case KeyCode.arrowUp:
                return modifiers.isEmpty ? .recallPreviousPullInReason : nil
            case KeyCode.arrowDown:
                return modifiers.isEmpty ? .recallNextPullInReason : nil
            case KeyCode.n:
                return modifiers == .control ? .recallNextPullInReason : nil
            case KeyCode.p:
                return modifiers == .control ? .recallPreviousPullInReason : nil
            default:
                return nil
            }
        }
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
            return isRepeat ? .consumeKey : .cancelPullInChoice
        case KeyCode.leftBracket:
            if modifiers == .control {
                return isRepeat ? .consumeKey : .cancelPullInChoice
            }
            return nil
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
        case KeyCode.tab:
            if modifiers.isEmpty {
                return isRepeat
                    ? .consumeKey
                    : .togglePullInOfferAndAdvance(keepFilterFocus: filterFocused)
            }
            if modifiers == .shift {
                return .previousPullInOfferFromTab(keepFilterFocus: filterFocused)
            }
            return nil
        case KeyCode.a:
            return modifiers == .command ? .markAllPullInOffers : nil
        case KeyCode.x:
            if modifiers == .command {
                return nil
            }
            if modifiers == .control {
                return isRepeat ? .consumeKey : .stagePullInDone
            }
            if modifiers == [.control, .shift] {
                return isRepeat ? .consumeKey : .beginPullInCancel
            }
            return nil
        case KeyCode.j:
            // Ctrl+J pins the jump successor. Shift, Command, and Option
            // stay native; a repeat only consumes.
            if modifiers == .control {
                return isRepeat ? .consumeKey : .togglePullInJump
            }
            return nil
        case KeyCode.t:
            // Ctrl+Shift+T carries a requirement branch; plain Ctrl+T keeps
            // its existing consumption guard and never acts on ordinary rows.
            if modifiers == [.control, .shift] {
                return isRepeat ? .consumeKey : .stageRequirementCarry
            }
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.backslash:
            return modifiers == .command ? .consumeKey : nil
        default:
            return nil
        }
    }

    /// Keys for the Pull-In reason `LINK` band, while it replaces the
    /// recall band in its slot. Return and Tab insert bob's replacement at
    /// bob's byte range; zero rows (or no selection) make Return close the
    /// band without confirming, while Tab passes through to the host. Esc
    /// and Ctrl+[ close the band only.
    private func pullInLinkCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool,
        canAccept: Bool
    ) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            guard !isRepeat else { return .consumeKey }
            let keys = Self.strippedReturnModifiers(modifiers)
            return keys.isEmpty ? .acceptPullInLink : nil
        case KeyCode.tab:
            guard !isRepeat else { return .consumeKey }
            if modifiers == .shift {
                return nil
            }
            return modifiers.isEmpty && canAccept ? .acceptPullInLinkFromTab : nil
        case KeyCode.j:
            // Ctrl+J never pins while a Cancel reason is being edited.
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.escape:
            guard !isRepeat else { return .consumeKey }
            return .closePullInLinkBand
        case KeyCode.leftBracket:
            return modifiers == .control && !isRepeat ? .closePullInLinkBand : nil
        case KeyCode.arrowUp:
            return modifiers.isEmpty ? .movePullInLinkPrevious : nil
        case KeyCode.arrowDown:
            return modifiers.isEmpty ? .movePullInLinkNext : nil
        case KeyCode.n:
            return modifiers == .control ? .movePullInLinkNext : nil
        case KeyCode.p:
            return modifiers == .control ? .movePullInLinkPrevious : nil
        default:
            return nil
        }
    }

    /// Keys for the tasks band's NAME stage. Return (with or without
    /// Control, Command, or Option) writes the ID and inserts the link on a
    /// fresh key-down only; Esc and Ctrl+[ go back to the list; Tab, Down,
    /// and Ctrl+N cycle bob's suggestions forward, Shift+Tab, Up, and Ctrl+P
    /// back. Text keys stay with the field. Nothing here ever confirms the
    /// Pull-In or reaches the offer list.
    private func pullInLinkNameCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            guard !isRepeat else { return .consumeKey }
            let keys = Self.strippedReturnModifiers(modifiers)
            if keys.isEmpty || !keys.intersection([.control, .command, .option]).isEmpty {
                return .commitPullInLinkName
            }
            return .consumeKey
        case KeyCode.escape:
            return isRepeat ? .consumeKey : .cancelPullInLinkName
        case KeyCode.leftBracket:
            guard modifiers == .control else { return nil }
            return isRepeat ? .consumeKey : .cancelPullInLinkName
        case KeyCode.tab:
            if modifiers.isEmpty { return .cyclePullInLinkNameForward }
            if modifiers == .shift { return .cyclePullInLinkNameBackward }
            return nil
        case KeyCode.arrowDown:
            return modifiers.isEmpty ? .cyclePullInLinkNameForward : nil
        case KeyCode.arrowUp:
            return modifiers.isEmpty ? .cyclePullInLinkNameBackward : nil
        case KeyCode.n:
            return modifiers == .control ? .cyclePullInLinkNameForward : nil
        case KeyCode.p:
            return modifiers == .control ? .cyclePullInLinkNameBackward : nil
        case KeyCode.j:
            // Ctrl+J never pins while a Cancel reason is being edited.
            return modifiers == .control ? .consumeKey : nil
        default:
            return nil
        }
    }

    private func inboxRouteChoiceCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> CaptureKeyCommand? {
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter:
            guard !isRepeat else { return .consumeKey }
            let keys = Self.strippedReturnModifiers(modifiers)
            if keys == .control {
                return .confirmInboxRouteChoiceAndOpen
            }
            if keys == .shift {
                return .keepInboxRouteCandidate
            }
            if keys.isEmpty {
                return .confirmInboxRouteChoice
            }
            return .consumeKey
        case KeyCode.escape:
            return .cancelInboxRouteChoice
        case KeyCode.leftBracket:
            return modifiers == .control ? .cancelInboxRouteChoice : nil
        case KeyCode.arrowUp:
            return modifiers.isEmpty ? .previousInboxRouteDestination : nil
        case KeyCode.arrowDown:
            return modifiers.isEmpty ? .nextInboxRouteDestination : nil
        case KeyCode.n:
            return modifiers == .control ? .nextInboxRouteDestination : nil
        case KeyCode.p:
            return modifiers == .control ? .previousInboxRouteDestination : nil
        case KeyCode.t:
            return modifiers == .control ? .consumeKey : nil
        case KeyCode.backslash:
            return modifiers == .command ? .consumeKey : nil
        default:
            return nil
        }
    }

    func command(for event: NSEvent, completionVisible: Bool) -> CaptureKeyCommand? {
        command(for: event, context: CaptureKeyRoutingContext(completionVisible: completionVisible))
    }

    private static let editorLeaderBindings: [String: CaptureKeyCommand] = [
        "u": .toggleLineCase,
    ]

    private func editorLeaderCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> CaptureKeyCommand {
        if event.keyCode == KeyCode.g, modifiers == .control {
            return isRepeat ? .armEditorLeader : .cancelEditorLeader
        }
        if event.keyCode == KeyCode.escape {
            return .cancelEditorLeader
        }
        if event.keyCode == KeyCode.leftBracket, modifiers == .control {
            return .cancelEditorLeader
        }
        if modifiers.intersection([.command, .control, .option]).isEmpty,
            let characters = event.characters,
            characters.unicodeScalars.count == 1,
            let command = Self.editorLeaderBindings[characters.lowercased()]
        {
            return command
        }
        return .rejectEditorLeaderKey
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

    private static func wordMotionCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        guard event.keyCode == KeyCode.h || event.keyCode == KeyCode.l else {
            return nil
        }
        let keys = modifiers.subtracting(.capsLock)
        let unit: CaptureWordMotion.Unit
        if keys == .control {
            unit = .bigWord
        } else if keys == [.control, .shift] {
            unit = .word
        } else {
            return nil
        }
        guard !context.editorHasMarkedText else {
            return nil
        }
        let direction: CaptureWordMotion.Direction =
            event.keyCode == KeyCode.l ? .forward : .backward
        return .moveByWord(direction, unit)
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
            || context.taskIDPromptIsTaskComplete
            || context.taskIDPromptIsWikilinkTask,
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
        modifiers: NSEvent.ModifierFlags,
        fieldIsEmpty: Bool,
        oneOff: Bool,
        renameActive: Bool,
        fieldHasMarkedText: Bool,
        keyIsRepeat: Bool
    ) -> CaptureKeyCommand? {
        // Ctrl+R renames the selected row (or the typed existing label)
        // everywhere. In rename mode it is a no-op; Escape leaves first.
        if event.keyCode == KeyCode.r, modifiers == .control {
            return renameActive ? .consumeKey : .openRelationLabelRename
        }
        if renameActive {
            // The rename field owns printable keys through the AppKit
            // field; Tab, arrows, and Ctrl+N/P stay inside the card
            // instead of touching choose rows. `~` / `=` stay text (A10).
            return isolatedPromptCommand(
                for: event,
                modifiers: modifiers,
                submit: .submitRelationLabelPrompt,
                cancel: .cancelRelationLabelPrompt
            )
        }
        // Choose-mode `~` / `=` flip direction before isolated prompt
        // keys. Shift is allowed so `~` still matches; Command, Option,
        // and Control leave the key to the field. Marked text (IME) and
        // auto-repeat never flip.
        if event.characters == "~" || event.characters == "=",
           modifiers.intersection([.command, .option, .control]).isEmpty,
           !fieldHasMarkedText
        {
            if keyIsRepeat || event.isARepeat {
                return .consumeKey
            }
            return .flipRelationLabelDirection
        }
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
        // Ctrl+D hides what Return would insert (or unhides a hidden row);
        // with no selection it toggles one-off. Claimed only inside this
        // one-line card. Key auto-repeat is ignored.
        if event.keyCode == KeyCode.d, modifiers == .control {
            if event.isARepeat {
                return .consumeKey
            }
            return .toggleRelationLabelVisibility
        }
        // Ctrl+H shows or hides the Hidden section, mirroring
        // `bob relations -H`. Claimed only inside this one-line card.
        if event.keyCode == KeyCode.h, modifiers == .control {
            return .toggleRelationLabelHiddenSection
        }
        // Backspace on an empty field turns one-off off; otherwise the
        // field edits normally.
        if event.keyCode == KeyCode.delete, modifiers.isEmpty, fieldIsEmpty, oneOff {
            return .relationLabelPromptBackspace
        }
        return isolatedPromptCommand(
            for: event,
            modifiers: modifiers,
            submit: .submitRelationLabelPrompt,
            cancel: .cancelRelationLabelPrompt
        )
    }

    /// Keyboard while the capture picker is open. Every key the picker
    /// table leaves to native field editing (printables, Cmd-A/C/V/X/Z except
    /// Command-X in Go To,
    /// Ctrl-A/E, Left/Right) returns nil here — notably Ctrl-A/E, which must
    /// not fall through to the editor line-edge commands.
    private func pickerCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        // A fast second key undoes the first key (opener or flip) and types
        // one literal (`=` or `.`). Checked before the opener restores and
        // the ordinary flip routing.
        if context.equalsGestureFastSecond,
           event.characters == context.equalsGestureFastSecondKey,
           modifiers.intersection([.command, .option, .control]).isEmpty,
           !context.editorHasMarkedText,
           !context.keyIsRepeat,
           !event.isARepeat
        {
            return .undoEqualsGestureAndTypeLiteral
        }
        if let command = relationEqualsOpenerRestoreCommand(
            for: event,
            modifiers: modifiers,
            context: context
        ) {
            return command
        }
        // Bare `/` Go To keeps `\` out of the draft and filter: a second
        // `\` right after the alias types a literal, otherwise consume.
        // Before the keyCode switch, whose explicit backslash case would
        // otherwise swallow non-Command keys.
        if Self.isTypedBackslash(event: event, modifiers: modifiers),
           context.pickerSourceIsNoteGoto,
           context.pickerFilterIsEmpty
        {
            return .consumeKey
        }
        if Self.isTypedBackslash(event: event, modifiers: modifiers),
           !context.editorHasMarkedText,
           context.pickerSourceIsTaskGoto,
           context.pickerFilterIsEmpty,
           context.draftIsBareGotoSigil
        {
            if context.keyIsRepeat || event.isARepeat {
                return .consumeKey
            }
            return context.backslashLiteralArmed ? .typeLiteralBackslash : .consumeKey
        }
        if context.pickerFilterIsEmpty,
           modifiers.intersection([.command, .option, .control]).isEmpty,
           event.characters == "/"
        {
            if context.pickerSourceIsNoteGoto {
                return .consumeKey
            }
            if context.pickerSourceIsTaskGoto {
                if context.keyIsRepeat || event.isARepeat || context.editorHasMarkedText {
                    return .consumeKey
                }
                return context.pickerOperatorContinuationKeys.contains("/")
                    ? .continuePickerOperator("/")
                    : .showNoteGotoUpgradeHint
            }
        }
        switch event.keyCode {
        case KeyCode.x:
            if modifiers == .command, context.pickerSourceIsNoteGoto {
                return context.keyIsRepeat || event.isARepeat
                    ? .consumeKey : .toggleGotoArchivedNotes
            }
            guard modifiers == .command, context.pickerSourceIsTaskGoto else {
                return nil
            }
            return context.keyIsRepeat || event.isARepeat ? .consumeKey : .toggleGotoClosedTasks
        case KeyCode.return, KeyCode.keypadEnter:
            let keys = Self.strippedReturnModifiers(modifiers)
            if keys.contains(.command) {
                if context.pickerSourceIsNoteGoto {
                    return context.pickerHasSelection ? .acceptPickerRow : .consumeKey
                }
                return context.pickerHasSelection ? .acceptPickerRowAndSubmit : .submitAndOpen
            }
            if keys == .control {
                if context.pickerSourceIsRelation {
                    return .openRelationLabelPrompt
                }
                if !context.pickerHasSelection {
                    if context.pickerSourceIsNoteGoto {
                        return .consumeKey
                    }
                    return .submitAndOpen
                }
                return context.pickerSourceIsTaskGoto || context.pickerSourceIsNoteGoto
                    ? .acceptPickerRow : .acceptPickerRowAndSubmitAndOpen
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
                if context.pickerSourceIsProjectTaskMove {
                    return .acceptPickerRowAndContinue
                }
                if context.pickerSourceIsParentTask,
                    context.pickerParentContinuationAvailable
                {
                    return .acceptPickerRowAndContinue
                }
                return .consumeKey
            }
            if keys.contains(.option) {
                return .consumeKey
            }
            if keys.isEmpty {
                if context.pickerSourceIsNoteGoto, !context.pickerHasSelection {
                    return .consumeKey
                }
                return context.pickerHasSelection ? .acceptPickerRow : .submit
            }
            return nil
        case KeyCode.tab:
            if modifiers.isEmpty {
                if context.pickerSourceIsNoteGoto, !context.pickerHasSelection {
                    return .consumeKey
                }
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
               characters.count == 1
            {
                if context.pickerOperatorContinuationKeys.contains(characters) {
                    return .continuePickerOperator(characters)
                }
                if let mapped = context.pickerOperatorContinuationAliases[characters],
                   context.pickerOperatorContinuationKeys.contains(mapped)
                {
                    return .continuePickerOperator(mapped)
                }
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
            return modifiers == .command ? .consumeKey : nil
        case KeyCode.c:
            return modifiers == .control ? .stashDraftAndClose : nil
        default:
            if context.pickerSourceIsRelation,
               event.characters == "~" || event.characters == "=",
               modifiers.intersection([.command, .option, .control]).isEmpty,
               !context.editorHasMarkedText
            {
                if context.keyIsRepeat || event.isARepeat {
                    return .consumeKey
                }
                return .flipRelationDirection
            }
            if context.pickerFilterIsEmpty,
               !context.pickerOperatorContinuationKeys.isEmpty,
               modifiers.intersection([.command, .option, .control]).isEmpty,
               let characters = event.characters,
               characters.count == 1
            {
                if context.pickerOperatorContinuationKeys.contains(characters) {
                    return .continuePickerOperator(characters)
                }
                if let mapped = context.pickerOperatorContinuationAliases[characters],
                   context.pickerOperatorContinuationKeys.contains(mapped)
                {
                    return .continuePickerOperator(mapped)
                }
            }
            if !context.pickerFilterIsEmpty,
                context.pickerHasSelection,
                context.pickerSourceIsParentTask,
                context.pickerParentContinuationAvailable,
                modifiers.isEmpty,
                event.characters == ",",
                !context.keyIsRepeat,
                !event.isARepeat
            {
                return .acceptPickerRowAndContinue
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
            return modifiers == .command ? .consumeKey : nil
        default:
            return nil
        }
    }

    private func relationEqualsOpenerRestoreCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        guard context.relationEqualsOpenerArmed,
              modifiers.intersection([.command, .control, .option]).isEmpty,
              !context.editorHasMarkedText
        else {
            return nil
        }
        // The arm restores while its own picker has an empty filter. Before
        // the picker appears (race window), the arm alone is enough.
        if context.pickerVisible && !context.modifierAliasOpenerOwnPickerIsEmpty {
            return nil
        }
        let key: String?
        if event.keyCode == KeyCode.escape {
            key = ""
        } else if event.characters == " " {
            key = " "
        } else {
            key = nil
        }
        guard let key else {
            return nil
        }
        if context.keyIsRepeat || event.isARepeat {
            return .consumeKey
        }
        return .restoreRelationEqualsOpener(key)
    }

    private func stashPickerCommand(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        context: CaptureKeyRoutingContext
    ) -> CaptureKeyCommand? {
        if event.keyCode == KeyCode.t, modifiers == .control {
            return .toggleTemplateShelf
        }
        if event.keyCode == KeyCode.backslash, modifiers == .command {
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
        if event.keyCode == KeyCode.backslash, modifiers == .command {
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
