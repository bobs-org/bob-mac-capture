import Foundation

/// Which note a Block ID picker session edits: an ordinary `@route`/`@route^`
/// marker position (`.note`), or a trailing ` :id` / ` ^id` project-task token
/// inside a project-note item (`.projectTask`, from Bob's
/// `project_task_block_id` context). A project-task session names IDs inside
/// the new project note rather than addressing a routed note, so it shows no
/// `@route` anywhere.
public enum CaptureBlockIDScope: Equatable, Sendable {
    case note
    case projectTask
}

/// Which Block ID position a picker session edits: the decoded `block_id`
/// field (nil for older Bob binaries that send `pomodoro_block_id` without
/// it), the route, the marker (`:` or `^`), the intent, and Bob's ID rules
/// (nil when Bob's grammar is missing or unreadable, which disables
/// type-through and New ID rows).
public struct BlockIDPickerContext: Equatable, Sendable {
    public let field: CaptureBlockIDField?
    public let route: String
    public let marker: String
    public let intent: CaptureBlockIDIntent
    public let rules: BlockIDRules?
    public let scope: CaptureBlockIDScope

    public init(
        field: CaptureBlockIDField?,
        route: String,
        marker: String,
        intent: CaptureBlockIDIntent,
        rules: BlockIDRules?,
        scope: CaptureBlockIDScope = .note
    ) {
        self.field = field
        self.route = route
        self.marker = marker
        self.intent = intent
        self.rules = rules
        self.scope = scope
    }

    /// Link intent, or no field (older Bob): browse the note's tasks.
    /// Anything else is the New ID composer.
    public var isNewIDMode: Bool {
        intent == .new || intent == .projectNote
    }

    /// Note file the picker browses (`sase.md`), from Bob's
    /// `relative_target` when present.
    public var noteTarget: String {
        if let relativeTarget = field?.relativeTarget, !relativeTarget.isEmpty {
            return relativeTarget
        }
        return "\(route).md"
    }

    /// Marker token naming the position (`@sase:` / `@sase^`, or the bare
    /// ` :` / ` ^` project-task sigil with no `@route`).
    public var scopeToken: String {
        if scope == .projectTask {
            return " \(marker)"
        }
        return "@\(route)\(marker)"
    }
}

/// Which picker source a session belongs to. `^`, `:`, `&`, and the Block
/// ID picker are sources feeding one state machine, routing, focus repair,
/// filter field, sizing, and card.
public enum CapturePickerSource: Equatable, Sendable {
    case activeTask
    case taskLink
    case dependency
    case taskComplete
    case blockID(BlockIDPickerContext)
    case parentTask(ParentTaskPickerContext)

    /// The block-ID scope, so the fuzzy index shapes rows (no `@route`)
    /// for a project-task session. `.note` for the `^` source.
    public var blockIDScope: CaptureBlockIDScope {
        if case .blockID(let context) = self {
            return context.scope
        }
        return .note
    }

    /// Server-authored parent-task context when this source is `.parentTask`.
    public var parentTaskContext: ParentTaskPickerContext? {
        if case .parentTask(let context) = self {
            return context
        }
        return nil
    }

    /// Draft byte the picker opened on (`^` for active tasks, `:` or `&`
    /// for the pickers, `:` or `^` for block IDs, `+` for parent tasks).
    /// Backspace on an empty filter removes this byte together with any
    /// fragment it opened on, except parent-task which uses Bob's
    /// `trigger_removal_range` instead of hunting for the marker.
    public var triggerByte: UInt8 {
        switch self {
        case .activeTask:
            return 94 // `^`
        case .taskLink:
            return 58 // `:`
        case .dependency:
            return 38 // `&`
        case .taskComplete:
            return 33 // `!`
        case .blockID(let context):
            return context.marker == "^" ? 94 : 58 // `^` or `:`
        case .parentTask:
            return 43 // `+`
        }
    }

    /// Filter-field placeholder while this source is open.
    public var filterPlaceholder: String {
        switch self {
        case .activeTask:
            return "Filter by task, note, ^id, or Pomodoro"
        case .taskLink:
            return "Search tasks by text, note, or ^id"
        case .dependency:
            return "Search tasks by text, note, or ^id"
        case .taskComplete:
            return "Search open tasks to complete"
        case .blockID(let context):
            if context.isNewIDMode {
                return "Type a new ID for \(context.noteTarget)"
            }
            let suffix = context.field == nil ? "" : ", or type a new ID"
            return "Filter \(context.noteTarget) tasks\(suffix)"
        case .parentTask(let context):
            if context.isVault {
                return "Search tasks by text, note, or +id"
            }
            return "Filter \(context.noteFileName) tasks"
        }
    }

    /// Filter-field accessibility label while this source is open.
    public var filterAccessibilityLabel: String {
        switch self {
        case .activeTask:
            return "Filter active tasks"
        case .taskLink:
            return "Search open tasks"
        case .dependency:
            return "Search tasks to depend on"
        case .taskComplete:
            return "Search open tasks to complete"
        case .blockID(let context):
            if context.isNewIDMode {
                return "Type a new block ID for \(context.noteTarget)"
            }
            return "Filter \(context.noteTarget) tasks"
        case .parentTask(let context):
            if context.isVault {
                return "Search open tasks across capture notes"
            }
            return "Filter \(context.noteFileName) tasks"
        }
    }

    /// Scope-token symbol text (`^`, `@sase:`) shown in the filter bar capsule.
    public var scopeSymbolText: String {
        switch self {
        case .activeTask:
            return "^"
        case .taskLink:
            return ":"
        case .dependency:
            return "&"
        case .taskComplete:
            return "!"
        case .blockID(let context):
            return context.scopeToken
        case .parentTask(let context):
            return context.scopeToken
        }
    }

    /// Scope-token caption (`Active Tasks`, `Tasks`, `New ID`) shown in the
    /// filter bar capsule.
    public var scopeCaption: String {
        switch self {
        case .activeTask:
            return "Active Tasks"
        case .taskLink:
            return "Open Tasks"
        case .dependency:
            return "Depends On"
        case .taskComplete:
            return "Complete"
        case .blockID(let context):
            if context.intent == .projectNote {
                return "Project note"
            }
            if context.scope == .projectTask {
                return context.marker == ":" ? "Linked task" : "Task ID"
            }
            return context.isNewIDMode ? "New ID" : "Tasks"
        case .parentTask(let context):
            return context.isVault ? "All capture notes" : context.noteFileName
        }
    }

    /// Reopen-chip label shown instead of the picker.
    public var chipLabel: String {
        switch self {
        case .activeTask:
            return "Browse active tasks"
        case .taskLink:
            return "Browse open tasks"
        case .dependency:
            return "Choose dependency"
        case .taskComplete:
            return "Pick a task to complete"
        case .blockID(let context):
            if context.isNewIDMode {
                return "Suggest an ID for \(context.noteTarget)"
            }
            return "Browse \(context.noteTarget) tasks"
        case .parentTask(let context):
            return context.isVault ? "Select a parent task" : "Append to a task"
        }
    }

    /// Reopen-chip SF Symbol name.
    public var chipIcon: String {
        switch self {
        case .activeTask:
            return "list.bullet.rectangle.portrait"
        case .taskLink:
            return "magnifyingglass"
        case .dependency:
            return "link"
        case .taskComplete:
            return "checkmark.circle"
        case .blockID(let context):
            return context.isNewIDMode ? "sparkles" : "list.bullet.rectangle.portrait"
        case .parentTask:
            return "plus"
        }
    }

    /// Reopen-chip help text.
    public var chipHelp: String {
        switch self {
        case .activeTask:
            return "Reopen the Active Task Picker for the ^ item (Tab)."
        case .taskLink:
            return "Reopen the Task Link Picker for the : item (Tab)."
        case .dependency:
            return "Reopen the dependency picker for the & item (Tab)."
        case .taskComplete:
            return "Reopen the Complete picker for the ! item (Tab)."
        case .blockID(let context):
            return "Reopen the Block ID picker for \(context.scopeToken) (Tab)."
        case .parentTask(let context):
            return "Reopen the parent-task picker for the \(context.scopeToken) item (Tab)."
        }
    }

    /// Reopen-chip accessibility label.
    public var chipAccessibilityLabel: String {
        switch self {
        case .activeTask:
            return "Browse active tasks"
        case .taskLink:
            return "Browse open tasks"
        case .dependency:
            return "Choose dependency"
        case .taskComplete:
            return "Pick a task to complete"
        case .blockID:
            return chipLabel
        case .parentTask:
            return chipLabel
        }
    }

    /// Reopen-chip accessibility hint.
    public var chipAccessibilityHint: String {
        switch self {
        case .activeTask:
            return "Opens the Active Task Picker for the current item."
        case .taskLink:
            return "Opens the Task Link Picker for the current item."
        case .dependency:
            return "Opens the dependency picker for the current item."
        case .taskComplete:
            return "Opens the Complete picker for the current item."
        case .blockID(let context):
            return "Opens the Block ID picker for \(context.scopeToken)."
        case .parentTask(let context):
            return "Opens the parent-task picker for \(context.scopeToken)."
        }
    }

    /// Card accessibility label.
    public var cardAccessibilityLabel: String {
        switch self {
        case .activeTask:
            return "Active task picker"
        case .taskLink:
            return "Task link picker"
        case .dependency:
            return "Dependency picker"
        case .taskComplete:
            return "Complete picker"
        case .blockID(let context):
            if context.isNewIDMode {
                return "New block ID for \(context.noteTarget)"
            }
            return "Task picker for \(context.noteTarget)"
        case .parentTask(let context):
            if context.isVault {
                return "Parent task picker"
            }
            return "Parent task picker for \(context.noteFileName)"
        }
    }

    /// Card accessibility hint.
    public var cardAccessibilityHint: String {
        switch self {
        case .activeTask:
            return "Arrow keys move, Return inserts the task, Escape cancels."
        case .taskLink:
            return "Arrow keys move, Return inserts the task link, Shift-Return inserts it and starts its session, Escape cancels."
        case .dependency:
            return "Arrow keys move, Return inserts the prerequisite, Command Return inserts and captures, Escape cancels."
        case .taskComplete:
            return "Arrow keys move, Return inserts the task, Shift Return inserts it and starts the next, Command Return inserts and captures, Escape cancels."
        case .blockID(let context):
            if context.isNewIDMode {
                return "Arrow keys move, Return inserts the ID, Escape cancels."
            }
            return "Arrow keys move, Return inserts the task, Escape cancels."
        case .parentTask:
            return "Arrow keys move, Return inserts the parent task, Escape cancels."
        }
    }

    /// Announcement prefix when the card appears (`"Active tasks, 72 tasks"`).
    public var appearedAnnouncementPrefix: String {
        switch self {
        case .activeTask:
            return "Active tasks"
        case .taskLink:
            return "Open tasks"
        case .dependency:
            return "Prerequisites"
        case .taskComplete:
            return "Tasks to complete"
        case .blockID(let context):
            if context.isNewIDMode {
                return "New ID for \(context.noteTarget)"
            }
            return "\(context.noteTarget) tasks"
        case .parentTask(let context):
            return context.isVault ? "All capture notes" : "\(context.noteFileName) tasks"
        }
    }

    /// Footer key hints in display order.
    public func keyHintItems() -> [(keys: String, action: String)] {
        switch self {
        case .activeTask:
            return [
                ("↑↓", "Move"),
                ("↩", "Insert"),
                ("⌘↩", "Insert & Capture"),
                ("esc", "Clear / Cancel"),
            ]
        case .taskLink:
            return [
                ("↑↓", "Move"),
                ("↩", "Link"),
                ("⇧↩", "Link & Start"),
                ("⌘↩", "Link & Capture"),
                ("esc", "Clear / Cancel"),
            ]
        case .dependency:
            // Shift-Return has no start-session behavior on this source:
            // dependencies never smuggle a Pomodoro start into the capture.
            return [
                ("↑↓", "Move"),
                ("↩", "Use task"),
                ("⌘↩", "Capture"),
                ("esc", "Clear / Cancel"),
            ]
        case .taskComplete:
            return [
                ("↑↓", "Move"),
                ("↩", "Insert"),
                ("⇧↩", "Insert & next"),
                ("⌘↩", "Complete"),
                ("esc", "Clear / Cancel"),
            ]
        case .blockID(let context):
            if context.isNewIDMode {
                return [
                    ("↑↓", "Move"),
                    ("↩", "Insert"),
                    ("⌘↩", "Insert & Capture"),
                    ("␣", "Insert & keep typing"),
                    ("esc", "Clear / Cancel"),
                ]
            }
            return [
                ("↑↓", "Move"),
                ("↩", "Insert"),
                ("⌘↩", "Insert & Capture"),
                ("esc", "Clear / Cancel"),
            ]
        case .parentTask:
            // Shift-Return never starts a plus-selected task; it is consumed
            // like the other non-link sources.
            return [
                ("↑↓", "Move"),
                ("↩", "Select Task"),
                ("⌘↩", "Select & Capture"),
                ("esc", "Clear / Cancel"),
            ]
        }
    }

    /// Footer key-hints accessibility label.
    public var keyHintsAccessibilityLabel: String {
        switch self {
        case .activeTask:
            return "Picker keys: up and down to move, Return to insert, Command Return to insert and capture, Escape to clear or cancel."
        case .taskLink:
            return "Picker keys: up and down to move, Return to link, Shift Return to link and start, Command Return to link and capture, Escape to clear or cancel."
        case .dependency:
            return "Picker keys: up and down to move, Return to use the task, Command Return to use it and capture, Escape to clear or cancel."
        case .taskComplete:
            return "Picker keys: up and down to move, Return to insert, Shift Return to insert and start the next, Command Return to insert and capture, Escape to clear or cancel."
        case .blockID(let context):
            if context.isNewIDMode {
                return "Picker keys: up and down to move, Return to insert, Command Return to insert and capture, Space to insert and keep typing, Escape to clear or cancel."
            }
            return "Picker keys: up and down to move, Return to insert, Command Return to insert and capture, Escape to clear or cancel."
        case .parentTask:
            return "Picker keys: up and down to move, Return to select the task, Command Return to select and capture, Escape to clear or cancel."
        }
    }

    /// UserDefaults key recording that an insert happened, so the detail
    /// strip can teach follow-up keystrokes after the first use.
    public var pickerUsedDefaultsKey: String {
        switch self {
        case .activeTask:
            return "org.bobs.bob-mac-capture.active-task-picker-used"
        case .taskLink:
            return "org.bobs.bob-mac-capture.task-link-picker-used"
        case .dependency:
            return "org.bobs.bob-mac-capture.dependency-picker-used"
        case .taskComplete:
            return "org.bobs.bob-mac-capture.task-complete-picker-used"
        case .blockID:
            return "org.bobs.bob-mac-capture.block-id-picker-used"
        case .parentTask:
            return "org.bobs.bob-mac-capture.parent-task-picker-used"
        }
    }

    /// Quiet dual-use hint for the exact whole-item `+`. Nil everywhere else.
    public var operatorContinuationHint: String? {
        guard case .parentTask(let context) = self, context.isLonePlusOperator else {
            return nil
        }
        return "Type a number or + to adjust; Esc to extend +5m"
    }

    /// Locator separator between route and block ID (`:` for `:`/`^`/`&`,
    /// `+` for parent-task, the session marker for block IDs).
    public var locatorMarker: String {
        switch self {
        case .parentTask:
            return "+"
        case .blockID(let context):
            return context.marker
        case .activeTask, .taskLink, .dependency, .taskComplete:
            return ":"
        }
    }
}

/// Which incomplete picker need a parse reports. Each need carries the calm
/// status line shown instead of the doomed live dry run. Precedence is
/// `activeTask`, then `taskLink`, then `taskParent`, then `dependency`, then
/// `pomodoroID`, then `blockID`, then `pomodoroStart`.
public enum CapturePickerNeed: Equatable, Sendable {
    case activeTask
    case taskLink
    case taskParent
    case dependency
    case taskComplete
    case pomodoroID
    case blockID
    case pomodoroStart

    public var statusText: String {
        switch self {
        case .activeTask:
            return "Pick an active task — press Tab to browse"
        case .taskLink:
            return "Pick any open task — press Tab to browse"
        case .taskParent:
            return "Choose a task to append to — press Tab to browse"
        case .dependency:
            return "Pick a prerequisite — press Tab to browse"
        case .taskComplete:
            return "Pick a task to complete — press Tab to browse"
        case .pomodoroID:
            return "Pick a task or type a new ID — press Tab to browse"
        case .blockID:
            return "Type a new block ID — press Tab for suggestions"
        case .pomodoroStart:
            return "Pick a Pomodoro to start, or type a new name"
        }
    }
}

/// Task status derived from the candidate's status symbol: `/` is In
/// Progress, `*` is Next, space is Todo, `?` is Blocked, `x`/`X` is Done,
/// `-` is Canceled, and anything else keeps its status name (or symbol) for
/// display.
public enum CapturePickerTaskStatus: Equatable, Sendable {
    case inProgress
    case next
    case todo
    case blocked
    case done
    case canceled
    case other(String)

    public init(symbol: String?, name: String?) {
        switch symbol {
        case "/":
            self = .inProgress
        case "*":
            self = .next
        case " ":
            self = .todo
        case "?":
            self = .blocked
        case "x", "X":
            self = .done
        case "-":
            self = .canceled
        default:
            let label = name.flatMap { $0.isEmpty ? nil : $0 }
                ?? symbol.flatMap { $0.isEmpty ? nil : $0 }
                ?? "Other"
            self = .other(label)
        }
    }

    /// Canonical display name, used when the candidate carries no status
    /// name of its own.
    public var displayName: String {
        switch self {
        case .inProgress:
            return "In Progress"
        case .next:
            return "Next"
        case .todo:
            return "Todo"
        case .blocked:
            return "Blocked"
        case .done:
            return "Done"
        case .canceled:
            return "Canceled"
        case .other(let name):
            return name
        }
    }
}

/// Leading glyph of a picker row. Only `.task` is used by the `^` source;
/// the other cases are for the Block ID source.
public enum CapturePickerGlyph: Equatable, Sendable {
    case task(CapturePickerTaskStatus)
    case anchor
    case newID(CapturePickerAvailability)
    case alternativeID
    case suggestion
}

/// Availability of a candidate block ID. Unused by the `^` source.
public enum CapturePickerAvailability: Equatable, Sendable {
    case available
    case unchecked
    case taken(line: Int?, text: String)
    case invalid(String)
}

/// Which bucket of the picker a section belongs to. The `^` source uses the
/// Pomodoro, unqueued, other, and matches buckets; the Block ID source adds
/// note headings, suggestions, and used IDs; the `:` source reuses the
/// Pomodoro and unqueued buckets and adds per-note sections. The
/// filtered view uses a single header-less `.matches` section.
public enum CapturePickerSectionKind: Equatable, Sendable {
    case pomodoro
    case unqueuedInProgress
    case unqueuedNext
    case other
    case matches
    case noteHeading
    case suggestions
    case usedIDs
    case note
}

/// One picker section: a queued Pomodoro entry, an unqueued status bucket, or
/// the flat filtered match list.
public struct CapturePickerSection: Equatable, Sendable {
    public let id: String
    public let kind: CapturePickerSectionKind
    public let title: String
    /// Extra caption under the title. Unused by the `^` source.
    public let subtitle: String?
    /// `0900-0930` rendered as `09:00–09:30`; anything else shown raw.
    public let timeRangeText: String?
    /// 1-based position among the Pomodoro sections; 0 for other sections.
    public let ordinal: Int
    public let isCurrent: Bool
    /// Overrides the `"N task(s)"` header count when set. Unset for `^`.
    public let countText: String?
    public let rows: [CapturePickerRow]

    public init(
        id: String,
        kind: CapturePickerSectionKind,
        title: String,
        subtitle: String? = nil,
        timeRangeText: String? = nil,
        ordinal: Int = 0,
        isCurrent: Bool = false,
        countText: String? = nil,
        rows: [CapturePickerRow] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.timeRangeText = timeRangeText
        self.ordinal = ordinal
        self.isCurrent = isCurrent
        self.countText = countText
        self.rows = rows
    }
}

/// How the row's locator reads: `route:block-id` for `^`, `^block-id` for
/// block IDs.
public enum CapturePickerLocatorStyle: Equatable, Sendable {
    case routeBlock
    case blockOnly
}

/// Detail-strip content for one row: the outcome line of accepting it.
public struct CapturePickerRowDetail: Equatable, Sendable {
    /// Status wording (`In Progress`, `Queued in SASE (#1)`, ...).
    public let statusText: String
    public let route: String?
    public let section: String?
    /// Pomodoro wording (`Queued in SASE (#1)`, `Not in a Pomodoro`, ...).
    public let summary: String
    public let childCount: Int
    /// Literal prefix of the insertion before the locator (`^` for `^`).
    public let insertionPrefix: String

    public init(
        statusText: String,
        route: String? = nil,
        section: String? = nil,
        summary: String,
        childCount: Int = 0,
        insertionPrefix: String
    ) {
        self.statusText = statusText
        self.route = route
        self.section = section
        self.summary = summary
        self.childCount = childCount
        self.insertionPrefix = insertionPrefix
    }
}

/// An ID-less `:` row's pending block-ID assignment: the routed note, the
/// stale-safe task ref for `bob capture-task-id`, and Bob's ID suggestions
/// (possibly empty). Nil on every other row.
public struct CapturePickerPendingBlockID: Equatable, Sendable {
    public let route: String
    public let taskRef: String
    public let suggestions: [String]

    public init(route: String, taskRef: String, suggestions: [String]) {
        self.route = route
        self.taskRef = taskRef
        self.suggestions = suggestions
    }
}

/// One pickable row. `id` is Bob's `replacement`, so accepting a row inserts
/// exactly what Bob offered — except on the `:` source, where rows are keyed
/// by `"route|ref"` because ID-less rows share Bob's empty replacement.
/// Match ranges are `Character` offsets into `displayText`, `route`, and
/// `blockID`.
public struct CapturePickerRow: Equatable, Sendable {
    public let id: String
    public let bobIndex: Int
    public let glyph: CapturePickerGlyph
    public let displayText: String
    public let textSegments: [TaskDisplaySegment]
    public let textMatchRanges: [Range<Int>]
    public let route: String?
    public let blockID: String?
    public let routeMatchRanges: [Range<Int>]
    public let blockIDMatchRanges: [Range<Int>]
    public let locatorStyle: CapturePickerLocatorStyle
    /// Small Pomodoro chip for filtered rows; nil in grouped mode (the header
    /// already says it) and for unqueued tasks.
    public let chipText: String?
    /// Trailing badge capsule. Currently always nil; kept so row layout
    /// stays stable if a future source needs one.
    public let badgeText: String?
    /// Nesting depth; the row indents 14pt per depth (max 2). Always 0 for
    /// `^`, and nonzero only in grouped `:` note sections.
    public let depth: Int
    /// False for informational rows navigation must skip. Always true for
    /// `^` and `:`.
    public let isSelectable: Bool
    /// The exact string an accept places into Bob's replacement range; nil
    /// for ID-less `:` rows (the Add block ID prompt names them first) and
    /// when not selectable.
    public let insertion: String?
    /// Pending block-ID assignment for ID-less `:` rows. Nil everywhere
    /// else, so other sources behave byte-identically.
    public let pendingBlockID: CapturePickerPendingBlockID?
    /// Formatted schedule capsule (`Oct 3`, with the year appended outside
    /// the current year). Nil when Bob sent no schedule, so other sources
    /// behave byte-identically.
    public let scheduledText: String?
    /// Whether linking pulls a future schedule forward. Only set on `:`
    /// rows with a schedule; false everywhere else.
    public let pullsForward: Bool
    public let detail: CapturePickerRowDetail
    public let accessibilityLabel: String

    public init(
        id: String,
        bobIndex: Int,
        glyph: CapturePickerGlyph,
        displayText: String,
        textSegments: [TaskDisplaySegment] = [],
        textMatchRanges: [Range<Int>] = [],
        route: String? = nil,
        blockID: String? = nil,
        routeMatchRanges: [Range<Int>] = [],
        blockIDMatchRanges: [Range<Int>] = [],
        locatorStyle: CapturePickerLocatorStyle = .routeBlock,
        chipText: String? = nil,
        badgeText: String? = nil,
        depth: Int = 0,
        isSelectable: Bool = true,
        insertion: String?,
        pendingBlockID: CapturePickerPendingBlockID? = nil,
        scheduledText: String? = nil,
        pullsForward: Bool = false,
        detail: CapturePickerRowDetail,
        accessibilityLabel: String
    ) {
        self.id = id
        self.bobIndex = bobIndex
        self.glyph = glyph
        self.displayText = displayText
        self.textSegments = textSegments
        self.textMatchRanges = textMatchRanges
        self.route = route
        self.blockID = blockID
        self.routeMatchRanges = routeMatchRanges
        self.blockIDMatchRanges = blockIDMatchRanges
        self.locatorStyle = locatorStyle
        self.chipText = chipText
        self.badgeText = badgeText
        self.depth = depth
        self.isSelectable = isSelectable
        self.insertion = insertion
        self.pendingBlockID = pendingBlockID
        self.scheduledText = scheduledText
        self.pullsForward = pullsForward
        self.detail = detail
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Grouped (empty filter) or filtered (non-empty filter) presentation.
public enum CapturePickerMode: Equatable, Sendable {
    case grouped
    case filtered
}

/// What the list shows when there is nothing to pick.
public struct CapturePickerEmptyState: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    public static var noActiveTasks: Self {
        Self(
            title: "No active tasks",
            message: "No In Progress or Next tasks — a task needs `[/]` or `[*]` with a `^block-id` to appear here."
        )
    }

    public static var noOpenTasks: Self {
        Self(
            title: "No open tasks",
            message: "No open tasks in your area or project notes."
        )
    }

    public static var noCaptureNoteTasks: Self {
        Self(
            title: "No open tasks",
            message: "No open tasks in your capture notes."
        )
    }

    public static func noTasksInNote(_ note: String) -> Self {
        Self(
            title: "No tasks in \(note)",
            message: "No open tasks in \(note)."
        )
    }

    public static func noMatches(query: String, noun: String = "active tasks") -> Self {
        Self(
            title: "No matches",
            message: "No \(noun) match “\(query)” — Esc clears the filter."
        )
    }
}

/// The picker's view of one fetched snapshot for one filter string.
public struct CapturePickerPresentation: Equatable, Sendable {
    public let mode: CapturePickerMode
    public let sections: [CapturePickerSection]
    /// Selectable row IDs in display order (section order grouped, ranked
    /// flat filtered).
    public let orderedRowIDs: [String]
    public let rowsByID: [String: CapturePickerRow]
    /// Deduped snapshot size.
    public let totalCount: Int
    public let matchCount: Int
    /// `"72 tasks"`, `"1 task"`, or `"5 of 72"`.
    public let countText: String
    public let emptyState: CapturePickerEmptyState?
    /// Rows plus headers of the grouped view, clamped to 4...11 (4 when
    /// empty). The panel fixes its height from this once at open; filtering
    /// never resizes it.
    public let visibleRowBudget: Int
    /// Block-ID badge/detail-strip status for the current filter. Nil for
    /// the `^` source and older Bob responses without a `block_id` object.
    public let blockIDStatus: CapturePickerBlockIDStatus?

    public init(
        mode: CapturePickerMode,
        sections: [CapturePickerSection],
        orderedRowIDs: [String],
        rowsByID: [String: CapturePickerRow],
        totalCount: Int,
        matchCount: Int,
        countText: String,
        emptyState: CapturePickerEmptyState?,
        visibleRowBudget: Int,
        blockIDStatus: CapturePickerBlockIDStatus? = nil
    ) {
        self.mode = mode
        self.sections = sections
        self.orderedRowIDs = orderedRowIDs
        self.rowsByID = rowsByID
        self.totalCount = totalCount
        self.matchCount = matchCount
        self.countText = countText
        self.emptyState = emptyState
        self.visibleRowBudget = visibleRowBudget
        self.blockIDStatus = blockIDStatus
    }

    public func row(id: String) -> CapturePickerRow? {
        rowsByID[id]
    }
}

/// Pure navigation helpers over `orderedRowIDs`.
public enum CapturePickerNavigation: Sendable {
    /// The next row, wrapping around. Nil for an empty list or unknown ID.
    public static func next(after id: String, in orderedRowIDs: [String]) -> String? {
        guard let index = orderedRowIDs.firstIndex(of: id) else {
            return nil
        }
        return orderedRowIDs[(index + 1) % orderedRowIDs.count]
    }

    /// The previous row, wrapping around. Nil for an empty list or unknown ID.
    public static func previous(before id: String, in orderedRowIDs: [String]) -> String? {
        guard let index = orderedRowIDs.firstIndex(of: id) else {
            return nil
        }
        return orderedRowIDs[(index + orderedRowIDs.count - 1) % orderedRowIDs.count]
    }

    /// Moves `offset` rows from `id`, clamped to the ends. Nil for an empty
    /// list or unknown ID.
    public static func page(from id: String, by offset: Int, in orderedRowIDs: [String]) -> String? {
        guard let index = orderedRowIDs.firstIndex(of: id) else {
            return nil
        }
        let clamped = min(max(index + offset, 0), orderedRowIDs.count - 1)
        return orderedRowIDs[clamped]
    }

    public static func first(in orderedRowIDs: [String]) -> String? {
        orderedRowIDs.first
    }

    public static func last(in orderedRowIDs: [String]) -> String? {
        orderedRowIDs.last
    }

    /// Keeps the preferred row when still visible, else the first row, else
    /// nil.
    public static func resolvedSelection(
        preferred: String?,
        in orderedRowIDs: [String]
    ) -> String? {
        if let preferred, orderedRowIDs.contains(preferred) {
            return preferred
        }
        return orderedRowIDs.first
    }
}
