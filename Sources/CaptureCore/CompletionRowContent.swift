import Foundation

/// The semantic family a piece of capture-marker or wikilink syntax belongs to. Shared by
/// editor highlighting and completion-row presentation so both draw from one palette instead
/// of duplicating a kind-to-color mapping.
public enum CaptureSemanticCategory: Equatable, Sendable {
    case route
    case section
    case blockID
    case schedule
    case priority
    case clipboard
    case wikilinkDelimiter
    case wikilinkTarget
    case wikilinkHeading
    case wikilinkBlock
    case wikilinkAlias
    case interactivePlaceholder
    case explicitToggle
    case blockedTaskSigil
    case relationSigil
    case relationLabel
    case relationCancelLabel
    case relationCompleteLabel
    case pomodoroStart
    case pomodoroCloseInProgress
    case pomodoroClosePark
    case pomodoroCloseComplete
    case pomodoroCloseDrop
    case pomodoroCloseLog
    case pomodoroStartDrop
    case link
    case templateSlot(Int)
    case neutral
}

extension CaptureSemanticCategory {
    /// Only the reading-queue link underline uses this: `ref_url` renders as
    /// an underlined link, every other span kind renders without one.
    public var isUnderlined: Bool {
        self == .link
    }

    /// Relation labels render muted italic in the editor. Cancel and
    /// complete labels keep the italic and take the ⊘/✓ tint instead of
    /// the muted role.
    public var isItalic: Bool {
        self == .relationLabel || self == .relationCancelLabel || self == .relationCompleteLabel
    }
}

/// Maps a `capture-parse` span kind to its semantic category. Unrecognized kinds fall back to
/// `.neutral`, matching ordinary prose rather than signaling an error.
public func captureSemanticCategory(forSpanKind kind: String) -> CaptureSemanticCategory {
    switch kind {
    case "route", "task_block_id_route", "pomodoro_route", "sub_bullet_route",
         "global_route", "global_sub_bullet_route", "task_toggle_route", "template_header",
         "active_task_route":
        return .route
    case "section", "sub_bullet_section", "pomodoro_name", "task_toggle_pomodoro_name":
        return .section
    case "task_block_id", "pomodoro_block_id", "sub_bullet_block_id",
         "global_sub_bullet_block_id", "task_toggle_block_id", "active_task_block_id",
         "project_task_block_id", "dependency_block_id":
        return .blockID
    case "dependency_sigil", "dependency_note":
        // `&note:id` renders like `@route:id`: the sigil and note share
        // the route family, the ID the block family. Never claimed by a
        // Swift-side regex — only Bob's semantic spans highlight here.
        return .route
    case "blocked_task_sigil":
        return .blockedTaskSigil
    case "blocked_task_note":
        return .route
    case "blocked_task_block_id":
        return .blockID
    case "relation_sigil":
        return .relationSigil
    case "relation_note":
        return .route
    case "relation_block_id":
        return .blockID
    case "relation_label_separator":
        return .interactivePlaceholder
    case "relation_label":
        return .relationLabel
    case "task_complete_sigil":
        // The `!` sigil completes like `x!`: it shares the complete-green
        // with the close-list complete digits.
        return .pomodoroCloseComplete
    case "task_complete_note":
        // The note side of `!note:id` renders like `@route:id`'s route.
        return .route
    case "task_complete_block_id":
        // The ID side of `!note:id` renders like every other block ID.
        return .blockID
    case "schedule":
        return .schedule
    case "priority":
        return .priority
    case "clipboard":
        return .clipboard
    case "ref_listen":
        // Bob marks the listen directive semantically; use the existing
        // route accent so it stays distinct from clipboard syntax.
        return .route
    case "wikilink_delimiter":
        return .wikilinkDelimiter
    case "wikilink_task_delimiter":
        return .wikilinkDelimiter
    case "wikilink_target":
        return .wikilinkTarget
    case "wikilink_heading":
        return .wikilinkHeading
    case "wikilink_block_id":
        return .wikilinkBlock
    case "wikilink_alias":
        return .wikilinkAlias
    case "interactive_placeholder":
        return .interactivePlaceholder
    case "task_toggle_explicit_toggle", "task_toggle_force_next", "project_note_marker",
         "project_task_link_marker":
        return .explicitToggle
    case "pomodoro_start":
        return .pomodoroStart
    case "pomodoro_adjust":
        // The whole-item `+N`/`-N` token is Pomodoro-family syntax like the
        // `=<X>` suffix, so it shares the Pomodoro highlight rather than taking
        // a distinct palette category.
        return .pomodoroStart
    case "pomodoro_shift":
        // The whole-item `++N`/`--N` token shifts the running session, so it
        // shares the Pomodoro-session highlight with the start and adjust
        // spans.
        return .pomodoroStart
    case "pomodoro_close":
        // The whole-item `x` token and the `=x` link suffix close the running
        // session, so they share the Pomodoro-session highlight with the start
        // and adjust spans.
        return .pomodoroStart
    case "pomodoro_close_in_progress":
        // The `<N>` digits select the rows that stay in progress, so they
        // share the badge color of an in-progress outcome.
        return .pomodoroCloseInProgress
    case "pomodoro_close_park":
        // The `*<P>` digits select the rows that park (recorded but not
        // carried), so they share the teal parking accent.
        return .pomodoroClosePark
    case "pomodoro_close_complete":
        // The `!<M>` digits select the rows that complete, so they share the
        // badge color of a complete outcome.
        return .pomodoroCloseComplete
    case "pomodoro_close_drop":
        // The `~<K>` digits select the rows that drop from today, so they
        // get their own muted category distinct from neutral text.
        return .pomodoroCloseDrop
    case "pomodoro_close_log_index":
        // Each Work Log entry index chip shares the log tint with the typed
        // entry line it lands on in the close card.
        return .pomodoroCloseLog
    case "pomodoro_start_drop":
        // The `~<K>` digits on a whole-item start select the queued rows
        // that drop as the session starts: the same muted gray as the close
        // drop list.
        return .pomodoroStartDrop
    case "ref_url":
        // The whole reference URL token on a `ref` item renders as a link.
        return .link
    default:
        return .neutral
    }
}

/// Maps a typed span while retaining the template slot index carried by Bob.
/// Template spans without a field index remain neutral; every older span kind
/// follows the established kind-only mapping.
public func captureSemanticCategory(forSpan span: CaptureSpan) -> CaptureSemanticCategory {
    switch span.kind {
    case "template_header":
        return .route
    case "template_placeholder", "template_field":
        guard let field = span.field else {
            return .neutral
        }
        return .templateSlot(field)
    case "relation_label" where span.completesSource:
        return .relationCompleteLabel
    case "relation_label" where span.cancelsSource:
        return .relationCancelLabel
    default:
        return captureSemanticCategory(forSpanKind: span.kind)
    }
}

/// The completion contexts `capture-complete` can report, typed so row presentation cannot
/// silently mishandle an unrecognized string. `capture-complete --help` documents these exact
/// wire values.
public enum CaptureCompletionContext: Equatable, Sendable {
    case route
    case section
    case pomodoroBlockID
    case taskBlockID
    case projectTaskBlockID
    case pomodoroName
    case pomodoroStartName
    case task
    case taskSection
    case activeTask
    case taskLink
    case taskGoto
    case taskParent
    case taskDependency
    case blockedTask
    case relationTo
    case relationFrom
    case relationLabel
    case taskComplete
    case wikilinkNote
    case wikilinkHeading
    case wikilinkBlock
    case wikilinkTask

    public init?(rawContext: String?) {
        switch rawContext {
        case "route": self = .route
        case "section": self = .section
        case "pomodoro_block_id": self = .pomodoroBlockID
        case "task_block_id": self = .taskBlockID
        case "project_task_block_id": self = .projectTaskBlockID
        case "pomodoro_name": self = .pomodoroName
        case "pomodoro_start_name": self = .pomodoroStartName
        case "task": self = .task
        case "task_section": self = .taskSection
        case "active_task": self = .activeTask
        case "task_link": self = .taskLink
        case "task_goto": self = .taskGoto
        case "task_parent": self = .taskParent
        case "task_dependency": self = .taskDependency
        case "blocked_task": self = .blockedTask
        case "relation_to": self = .relationTo
        case "relation_from": self = .relationFrom
        case "relation_label": self = .relationLabel
        case "task_complete": self = .taskComplete
        case "wikilink_note": self = .wikilinkNote
        case "wikilink_heading": self = .wikilinkHeading
        case "wikilink_block": self = .wikilinkBlock
        case "wikilink_task": self = .wikilinkTask
        default: return nil
        }
    }
}

/// Everything a completion row needs to render its context icon, primary/secondary text,
/// badges, and accessibility description, computed once per candidate so `CompletionRow` in
/// the app target stays a thin SwiftUI layer instead of branching on raw candidate fields.
public struct CompletionRowContent: Equatable, Sendable {
    public let category: CaptureSemanticCategory
    public let symbolName: String
    public let contextLabel: String
    public let primaryText: String
    /// Character-offset range within `primaryText` that matches the in-progress query,
    /// case-insensitively, for restrained emphasis. `nil` when the query is empty or the
    /// matched field isn't the one shown as `primaryText`.
    public let primaryMatchRange: Range<Int>?
    public let secondaryText: String?
    public let badges: [String]
  /// Bob-reported hue swatches for Pomodoro-name rows, in component order.
  public let themeSwatches: [CaptureThemeSwatch]
  /// A hidden history row remains visible as an undo affordance until the
  /// next editor change refreshes Bob's completion result.
  public let isHiddenThemeGhost: Bool
    /// When Bob preselects this `pomodoro_name` row, the hue of the
    /// declaring note (`theme_suggestion.from.hue`) so the view can tint
    /// the `●` dot in the secondary text.
    public let suggestedFromHue: PomodoroHomeHue?
    public let accessibilityLabel: String
    public let accessibilityHint: String

    public init(
        category: CaptureSemanticCategory,
        symbolName: String,
        contextLabel: String,
        primaryText: String,
        primaryMatchRange: Range<Int>?,
        secondaryText: String?,
        badges: [String],
        themeSwatches: [CaptureThemeSwatch] = [],
        isHiddenThemeGhost: Bool = false,
        suggestedFromHue: PomodoroHomeHue? = nil,
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        self.category = category
        self.symbolName = symbolName
        self.contextLabel = contextLabel
        self.primaryText = primaryText
        self.primaryMatchRange = primaryMatchRange
        self.secondaryText = secondaryText
        self.badges = badges
        self.themeSwatches = themeSwatches
        self.isHiddenThemeGhost = isHiddenThemeGhost
        self.suggestedFromHue = suggestedFromHue
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }
}

/// One Bob-reported theme color, retaining the known/unknown distinction so
/// unknown typed names stay neutral while exempt themes can use a hollow mark.
public struct CaptureThemeSwatch: Equatable, Sendable {
    public let hue: PomodoroHomeHue?
    public let known: Bool
    /// `false` when Bob reports the name is outside the configured vocabulary.
    public let configured: Bool?

    public var isUnconfigured: Bool { configured == false }

    public init(hue: PomodoroHomeHue?, known: Bool, configured: Bool? = nil) {
        self.hue = hue
        self.known = known
        self.configured = configured
    }

    public init(_ ref: CapturePomodoroThemeRef) {
        self.init(hue: ref.hue, known: ref.known, configured: ref.configured)
    }
}

/// Resolves per-component swatches for a Pomodoro name from Bob-owned
/// theme refs, so agenda headers, preview rows, and the Refs Today pill
/// draw the same colors as the completion rows without re-implementing
/// the hue rule. Components without a matching ref resolve to an
/// unknown swatch and render neutral, never a guessed hue.
public enum PomodoroThemeSwatches {
    /// Swatches for each `+`-separated component of `name`, in order.
    /// Empty when the name is nil or blank.
    public static func swatches(
        forName name: String?,
        refs: [CapturePomodoroThemeRef]
    ) -> [CaptureThemeSwatch] {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }
        let byKey = refsByKey(refs)
        return name.split(separator: "+").map { part in
            let key = normalizeThemeKey(String(part))
            if let ref = byKey[key] {
                return CaptureThemeSwatch(ref)
            }
            return CaptureThemeSwatch(hue: nil, known: false)
        }
    }

    /// Spoken type colors for an accessibility label (`BOB, magenta`).
    /// Unknown components read as unknown; exempt types read as muted;
    /// unconfigured types read as muted and not in your types.
    public static func spokenThemeColors(
        forName name: String?,
        refs: [CapturePomodoroThemeRef]
    ) -> [String] {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }
        let byKey = refsByKey(refs)
        return name.split(separator: "+").compactMap { part -> String? in
            let display = String(part).trimmingCharacters(in: .whitespaces)
            guard !display.isEmpty else {
                return nil
            }
            guard let ref = byKey[normalizeThemeKey(String(part))] else {
                return "\(display), unknown type"
            }
            return CaptureUnconfiguredThemePresentation.spokenColor(
                name: display,
                hue: ref.hue,
                hueSource: ref.hueSource,
                known: ref.known,
                configured: ref.configured
            )
        }
    }

    /// First-wins map so a refs array with a repeated key (`FIX + fix`)
    /// cannot trap `Dictionary(uniqueKeysWithValues:)`.
    static func refsByKey(
        _ refs: [CapturePomodoroThemeRef]
    ) -> [String: CapturePomodoroThemeRef] {
        Dictionary(refs.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Matches Bob's `normalize_component`: whitespace collapsed,
    /// lowercased.
    public static func normalizeThemeKey(_ raw: String) -> String {
        raw.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .split(separator: "\t", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

/// Builds the presentation content for one completion candidate. `query` is the in-progress
/// text between the completion replacement's start and the cursor; pass an empty string when
/// there is none (an empty-query result list still renders, just without match emphasis).
/// `override` is Bob's top-level `override` object for a `=#` name field while a
/// session runs (nil when idle, or on an older Bob): under `=#` open rows read as a
/// ledger takeover and the running row teaches the restart instead of the close.
public func completionRowContent(
    for candidate: CaptureCompletionCandidate,
    context rawContext: String?,
    query: String,
    override: CaptureCompleteOverride? = nil,
    temporarilyHiddenThemeKey: String? = nil,
    themeSuggestion: CaptureThemeSuggestion? = nil
) -> CompletionRowContent {
    let context = CaptureCompletionContext(rawContext: rawContext)

    let category: CaptureSemanticCategory
    let symbolName: String
    let contextLabel: String
    let primaryText: String
    var secondaryText: String?
    var badges: [String] = []
    let accessibilityHint: String

    switch context {
    case .route:
        category = .route
        if candidate.kind == "template" {
            symbolName = "square.stack.3d.down.right"
            contextLabel = "Template"
            primaryText = "@@template:"
            secondaryText = candidate.label
            accessibilityHint = "Starts a bulk template: one capture per row"
        } else {
            symbolName = "signpost.right"
            contextLabel = "Destination"
            if let alias = candidate.alias, !alias.isEmpty,
               let route = candidate.route, !route.isEmpty
            {
                primaryText = "\(route) · aka \(alias)"
            } else {
                primaryText = candidate.route ?? candidate.label ?? candidate.replacement
            }
            if let label = candidate.label, label != primaryText {
                secondaryText = label
            }
            badges = [candidate.kind, candidate.status].compactMap { $0 }.filter { !$0.isEmpty }
            accessibilityHint = "Sets the capture destination."
        }

    case .section:
        category = .section
        symbolName = "list.bullet.indent"
        contextLabel = "Section"
        primaryText = candidate.title ?? candidate.replacement
        if let level = candidate.level {
            badges = ["H\(level)"]
        }
        accessibilityHint = "Inserts this section heading."

    case .taskSection:
        category = .section
        symbolName = "list.bullet.rectangle"
        contextLabel = "Task Section"
        primaryText = candidate.title ?? candidate.replacement
        secondaryText = candidate.text
        if let blockID = candidate.blockID {
            badges.append("^\(blockID)")
        }
        let childCount = candidate.childCount ?? 0
        badges.append(childCount == 0 ? "Empty" : "\(childCount) items")
        accessibilityHint = "Nests the capture under this task section."

    case .pomodoroBlockID, .taskBlockID, .projectTaskBlockID, .task, .taskParent:
        let needsBlockID = context == .task && candidate.requiresBlockID
        category = needsBlockID ? .priority : .blockID
        symbolName = needsBlockID ? "link.badge.plus" : "link"
        // `task_block_id` and `project_task_block_id` candidates are always
        // empty per the contract, so this branch is defensive; label them
        // honestly rather than as tasks.
        if context == .taskBlockID || context == .projectTaskBlockID {
            contextLabel = "Block ID"
        } else if context == .taskParent {
            contextLabel = "Parent Task"
        } else {
            contextLabel = context == .pomodoroBlockID ? "Pomodoro Task" : "Parent Task"
        }
        primaryText = candidate.text ?? candidate.replacement
        secondaryText = candidate.section
        if let symbol = candidate.statusSymbol, let name = candidate.statusName {
            badges.append("[\(symbol)] \(name)")
        } else if let name = candidate.statusName {
            badges.append(name)
        }
        if let blockID = candidate.blockID {
            badges.append("^\(blockID)")
        } else if needsBlockID {
            badges.append("Add ID")
        }
        accessibilityHint = needsBlockID
            ? "Adds a block ID, then selects this task."
            : "Nests the capture under this task."

    case .pomodoroName:
        if candidate.origin == "history", candidate.createsPomodoro {
            category = .pomodoroStart
            symbolName = "timer"
            contextLabel = ""
            primaryText = candidate.name ?? candidate.replacement
            secondaryText = themeHistorySummary(lastUsed: candidate.lastUsed, daysUsed: candidate.daysUsed)
            accessibilityHint = "Uses this recent Pomodoro type."
        } else if candidate.createsPomodoro {
            category = .priority
            symbolName = "timer.badge.plus"
            contextLabel = "Pomodoro"
            if let name = candidate.name, !name.isEmpty {
                primaryText = name
            } else {
                primaryText = candidate.replacement
            }
            secondaryText = "New future Pomodoro"
            badges = ["Create"]
            // A create row that would push the plan past its theme cap
            // carries a red `after/cap` badge (e.g. `4/3`). Older Bob
            // omits both fields and the row stays exactly today's.
            if let capBadge = planCapBadge(
                after: candidate.planThemesAfter,
                cap: candidate.planThemesCap
            ) {
                badges.append(capBadge)
            }
            if candidate.hidden {
                badges.append("Hidden")
            }
            accessibilityHint = "Creates this named future Pomodoro when the draft is captured."
        } else {
            let needsName = candidate.requiresName
            category = needsName ? .priority : .section
            symbolName = needsName ? "square.and.pencil" : "timer"
            contextLabel = "Pomodoro"
            if let name = candidate.name, !name.isEmpty {
                primaryText = name
            } else if let timeRange = candidate.timeRange, !timeRange.isEmpty {
                primaryText = timeRange
            } else {
                primaryText = "Unnamed Pomodoro"
            }
            if let name = candidate.name, !name.isEmpty,
               let timeRange = candidate.timeRange, !timeRange.isEmpty
            {
                secondaryText = timeRange
            } else if candidate.placeholder {
                secondaryText = "Planned"
            }
            if candidate.isCurrent {
                badges.append("Current")
            }
            if let matchCount = candidate.matchCount, matchCount > 1 {
                badges.append("\(matchCount) matches")
            }
            let childCount = candidate.childCount ?? 0
            badges.append(childCount == 0 ? "Empty" : "\(childCount) links")
            if needsName {
                badges.append("Name it")
            }
            accessibilityHint = needsName
                ? "Names this Pomodoro, then selects it."
                : "Inserts this Pomodoro name."
        }

    case .pomodoroStartName:
        // Rows for the name part of a whole-item `=<X>#name` named start.
        // Bob orders them start, new, again, name-it, running; the kind is
        // read off the existing candidate fields, exactly as the contract
        // table documents. `.pomodoroName` rows are untouched.
        contextLabel = "Start"
        if candidate.requiresName {
            category = .priority
            symbolName = "square.and.pencil"
            if let timeRange = candidate.timeRange, !timeRange.isEmpty {
                primaryText = timeRange
            } else {
                primaryText = "Unnamed Pomodoro"
            }
            secondaryText = candidate.nextUp ? "Next up" : "Planned"
            badges = [startNameLinkBadge(childCount: candidate.childCount), "Name it"]
            accessibilityHint = "Names this Pomodoro, then selects it."
        } else if candidate.origin == "history", candidate.createsPomodoro {
            category = .pomodoroStart
            symbolName = "timer.badge.plus"
            primaryText = startNameDisplayName(for: candidate)
            secondaryText = themeHistorySummary(lastUsed: candidate.lastUsed, daysUsed: candidate.daysUsed)
            badges = ["New"]
            if let capBadge = planCapBadge(
                after: candidate.planThemesAfter,
                cap: candidate.planThemesCap
            ) {
                badges.append(capBadge)
            }
            if candidate.hidden {
                badges.append("Hidden")
            }
            let name = candidate.name.flatMap { $0.isEmpty ? nil : $0 } ?? candidate.replacement
            accessibilityHint = "Starts a new \(name) session using this recent type."
        } else if candidate.createsPomodoro, candidate.state == "completed" {
            category = .pomodoroStart
            symbolName = "arrow.clockwise.circle"
            primaryText = startNameDisplayName(for: candidate)
            if let timeRange = candidate.timeRange, !timeRange.isEmpty {
                secondaryText = "Last ran \(enDashRange(timeRange))"
            } else {
                secondaryText = "Completed"
            }
            badges = ["Again"]
            if let capBadge = planCapBadge(
                after: candidate.planThemesAfter,
                cap: candidate.planThemesCap
            ) {
                badges.append(capBadge)
            }
            let name = candidate.name.flatMap { $0.isEmpty ? nil : $0 } ?? candidate.replacement
            accessibilityHint = "Starts a new \(name) session now."
        } else if candidate.createsPomodoro {
            category = .priority
            symbolName = "timer.badge.plus"
            primaryText = startNameDisplayName(for: candidate)
            secondaryText = "New session"
            badges = ["New"]
            if let capBadge = planCapBadge(
                after: candidate.planThemesAfter,
                cap: candidate.planThemesCap
            ) {
                badges.append(capBadge)
            }
            accessibilityHint = "Creates this Pomodoro and starts it now."
        } else if let timeRange = candidate.timeRange, !timeRange.isEmpty {
            category = .neutral
            symbolName = "timer"
            primaryText = startNameDisplayName(for: candidate)
            secondaryText = "Running \(enDashRange(timeRange))"
            badges = ["Running"]
            accessibilityHint = startNameRunningHint(override: override)
        } else {
            category = .pomodoroStart
            symbolName = "play.circle"
            primaryText = startNameDisplayName(for: candidate)
            secondaryText = startNameOpenSecondary(
                nextUp: candidate.nextUp,
                override: override
            )
            if candidate.nextUp {
                badges.append("Next")
            }
            badges.append(startNameLinkBadge(childCount: candidate.childCount))
            if let matchCount = candidate.matchCount, matchCount > 1 {
                badges.append("\(matchCount) matches")
            }
            accessibilityHint = "Starts this Pomodoro now."
        }

    case .activeTask:
        // In Progress tasks are already being worked; Next tasks are queued but
        // untouched. The glyph and the palette tint both say which, so the row
        // needs no extra status badge to stay calm and legible.
        if candidate.statusSymbol == "/" {
            category = .schedule
            symbolName = "play.circle"
        } else {
            category = .blockID
            symbolName = "bookmark"
        }
        contextLabel = "Active Task"
        primaryText = candidate.text ?? candidate.replacement
        if let route = candidate.route, let blockID = candidate.blockID {
            var secondary = "\(route):\(blockID)"
            if let section = candidate.section, !section.isEmpty {
                secondary += " · \(section)"
            }
            secondaryText = secondary
        } else {
            secondaryText = candidate.section
        }
        badges = [activeTaskPomodoroBadge(for: candidate.pomodoro)]
        accessibilityHint = "Inserts this task's route and block ID."

    case .taskLink:
        // The `:` picker owns the card; this is only the stray inline
        // rendering, which reads as a task rather than neutral text.
        category = .blockID
        symbolName = "link"
        contextLabel = "Task"
        primaryText = candidate.text ?? candidate.replacement
        if let route = candidate.route, let blockID = candidate.blockID {
            var secondary = "\(route):\(blockID)"
            if let section = candidate.section, !section.isEmpty {
                secondary += " · \(section)"
            }
            secondaryText = secondary
        } else {
            secondaryText = candidate.section
        }
        accessibilityHint = "Inserts this task's route and block ID."

    case .taskGoto:
        category = .blockID
        symbolName = "arrow.up.forward"
        contextLabel = "Task to open"
        primaryText = candidate.text ?? candidate.replacement
        if let notePath = candidate.notePath, let line = candidate.line {
            let anchor = candidate.blockID.map { "^\($0)" } ?? "line \(line)"
            secondaryText = "\(notePath):\(anchor)"
        } else {
            secondaryText = candidate.notePath ?? candidate.route
        }
        accessibilityHint = "Opens this task in Obsidian without changing the vault."

    case .taskDependency:
        // The `&` picker owns the card; this is only the stray inline
        // rendering, which reads as a prerequisite rather than neutral
        // text. The locator uses Bob's exact `note_path`, never a
        // lowercased route.
        category = .blockID
        symbolName = "link"
        contextLabel = "Prerequisite"
        primaryText = candidate.text ?? candidate.replacement
        let locator = candidate.locator ?? candidate.route
        if let locator, let blockID = candidate.blockID ?? candidate.blockIDSuggestions.first {
            var secondary = "\(locator):\(blockID)"
            if let section = candidate.section, !section.isEmpty {
                secondary += " · \(section)"
            }
            secondaryText = secondary
        } else {
            secondaryText = candidate.section
        }
        if candidate.alreadyDependency {
            badges = ["Already added"]
        } else if let reason = candidate.disabledReason, !reason.isEmpty {
            badges = [reason]
        } else if candidate.requiresBlockID {
            badges = ["Needs ID"]
        }
        accessibilityHint = "Inserts this prerequisite."

    case .blockedTask:
        category = .blockID
        symbolName = "link"
        contextLabel = "Task to block"
        primaryText = candidate.text ?? candidate.replacement
        let locator = candidate.locator ?? candidate.route
        if let locator, let blockID = candidate.blockID ?? candidate.blockIDSuggestions.first {
            var secondary = "\(locator):\(blockID)"
            if let section = candidate.section, !section.isEmpty {
                secondary += " · \(section)"
            }
            secondaryText = secondary
        } else {
            secondaryText = candidate.section
        }
        if candidate.alreadyBlocked {
            badges = ["Already blocked"]
        } else if let reason = candidate.disabledReason, !reason.isEmpty {
            badges = [reason]
        } else if candidate.requiresBlockID {
            badges = ["Needs ID"]
        }
        accessibilityHint = "Blocks this task until the current task is done."

    case .relationTo, .relationFrom:
        category = .relationSigil
        symbolName = "arrow.left.arrow.right"
        contextLabel = context == .relationFrom ? "Linked from" : "Links to"
        primaryText = candidate.text ?? candidate.replacement
        let locator = candidate.locator ?? candidate.route
        if let locator, let blockID = candidate.blockID ?? candidate.blockIDSuggestions.first {
            var secondary = "\(locator):\(blockID)"
            if let section = candidate.section, !section.isEmpty {
                secondary += " · \(section)"
            }
            secondaryText = secondary
        } else {
            secondaryText = candidate.section
        }
        if candidate.alreadyLinked {
            if let label = candidate.existingLabel, !label.isEmpty {
                badges = ["Already linked · \(label)"]
            } else {
                badges = ["Already linked"]
            }
        } else if candidate.alsoPrerequisite {
            badges = ["Prerequisite too"]
        } else if let reason = candidate.disabledReason, !reason.isEmpty {
            badges = [reason]
        } else if candidate.requiresBlockID {
            badges = ["Needs ID"]
        }
        accessibilityHint = context == .relationFrom
            ? "Inserts a relation from this task to the owner."
            : "Inserts a relation from the owner to this task."

    case .relationLabel:
        if candidate.completesSource {
            category = .relationCompleteLabel
            symbolName = "checkmark.circle"
        } else if candidate.cancelsSource {
            category = .relationCancelLabel
            symbolName = "circle.slash"
        } else {
            category = .relationLabel
            symbolName = "textformat"
        }
        contextLabel = "Relation label"
        primaryText = candidate.label ?? candidate.replacement
        let labelCount = candidate.count ?? candidate.matchCount
        if let labelCount, labelCount > 0 {
            secondaryText = "\(labelCount)"
        } else {
            secondaryText = nil
        }
        var labelBadges: [String] = []
        if candidate.completesSource {
            labelBadges.append("completes")
        } else if candidate.cancelsSource {
            labelBadges.append("cancels")
        }
        if candidate.typed {
            labelBadges.append("Typed")
        } else if let reason = candidate.disabledReason, !reason.isEmpty {
            labelBadges.append(reason)
        }
        badges = labelBadges
        if candidate.completesSource {
            accessibilityHint = "Inserts this complete relation label."
        } else if candidate.cancelsSource {
            accessibilityHint = "Inserts this cancel relation label."
        } else {
            accessibilityHint = "Inserts this relation label."
        }

    case .taskComplete:
        // The `!` picker owns the card; this is only the stray inline
        // rendering, which reads as a completable task. The locator uses
        // Bob's exact `note_path`, never a lowercased route.
        category = .blockID
        symbolName = "checkmark.circle"
        contextLabel = "Complete"
        primaryText = candidate.text ?? candidate.replacement
        let completeLocator = candidate.locator ?? candidate.route
        if let completeLocator, let blockID = candidate.blockID ?? candidate.blockIDSuggestions.first {
            var secondary = "\(completeLocator):\(blockID)"
            if let section = candidate.section, !section.isEmpty {
                secondary += " · \(section)"
            }
            secondaryText = secondary
        } else {
            secondaryText = candidate.section
        }
        if let reason = candidate.disabledReason, !reason.isEmpty {
            badges = [reason]
        } else if candidate.requiresBlockID {
            badges = ["Needs ID"]
        }
        accessibilityHint = "Inserts this task to complete."

    case .wikilinkNote:
        category = .wikilinkTarget
        symbolName = "doc.text"
        contextLabel = "Note"
        primaryText = candidate.alias ?? candidate.name ?? candidate.replacement
        secondaryText = candidate.path
        if candidate.alias != nil {
            badges = ["Alias"]
        }
        accessibilityHint = "Inserts a link to this note."

    case .wikilinkHeading:
        category = .wikilinkHeading
        symbolName = "number"
        contextLabel = "Heading"
        primaryText = candidate.heading ?? candidate.replacement
        secondaryText = candidate.path
        if let level = candidate.level {
            badges = ["H\(level)"]
        }
        accessibilityHint = "Inserts a link to this heading."

    case .wikilinkBlock:
        category = .wikilinkBlock
        symbolName = "paragraphsign"
        contextLabel = "Block"
        primaryText = candidate.blockID.map { "^\($0)" } ?? candidate.replacement
        secondaryText = candidate.path
        if let preview = candidate.preview, !preview.isEmpty {
            badges = [preview]
        }
        accessibilityHint = "Inserts a link to this block."

    case .wikilinkTask:
        // The `((` picker owns the card; this is only the stray inline
        // rendering, which reads as a linkable task. The locator uses
        // Bob's exact `link_target` when present, never a lowercased route.
        category = .wikilinkTarget
        symbolName = "link"
        contextLabel = "Task link"
        primaryText = candidate.text ?? candidate.replacement
        let wikilinkLocator = candidate.linkTarget ?? candidate.locator ?? candidate.route
        if let wikilinkLocator, let blockID = candidate.blockID ?? candidate.blockIDSuggestions.first {
            var secondary = "\(wikilinkLocator)#^\(blockID)"
            if let section = candidate.section, !section.isEmpty {
                secondary += " · \(section)"
            }
            secondaryText = secondary
        } else {
            secondaryText = candidate.section
        }
        if let reason = candidate.disabledReason, !reason.isEmpty {
            badges = [reason]
        } else if candidate.requiresBlockID {
            badges = ["Needs ID"]
        }
        accessibilityHint = "Inserts a link to this task."

    case nil:
        category = .neutral
        symbolName = "text.cursor"
        contextLabel = ""
        primaryText = candidate.label ?? candidate.text ?? candidate.title ?? candidate.replacement
        accessibilityHint = "Inserts this completion."
    }

    let themeContext = context == .pomodoroName || context == .pomodoroStartName
    let themeSwatches = themeContext
        ? candidate.themes.map { CaptureThemeSwatch($0) }
        : []
    if themeContext {
        if candidate.hidden, !badges.contains("Hidden") {
            badges.append("Hidden")
        }
        for theme in candidate.themes {
            if theme.hueSource == "pin", !badges.contains("Pinned") {
                badges.append("Pinned")
            }
            if theme.hueSource == "exempt", !badges.contains("Exempt") {
                badges.append("Exempt")
            }
        }
        let isCreateRow = candidate.createsPomodoro && candidate.origin != "history"
        if isCreateRow,
           candidate.themes.contains(where: { $0.configured == false }),
           !badges.contains(CaptureUnconfiguredThemePresentation.createBadge)
        {
            badges.append(CaptureUnconfiguredThemePresentation.createBadge)
        }
    }
    let isHistoryTheme = themeContext && candidate.origin == "history"
    let isHiddenThemeGhost = isHistoryTheme
        && candidate.themes.contains(where: { $0.key == temporarilyHiddenThemeKey })
    if isHiddenThemeGhost {
        secondaryText = "Hidden · ⌃D undo"
        badges = []
    }

    // Task-theme suggestion: in `pomodoro_name` with an empty query, the
    // row Bob preselected carries `suggested` and renders the reason in
    // the secondary slot. With a non-empty query PT7 ranking wins and the
    // row keeps the reason but never moves.
    var suggestedFromHue: PomodoroHomeHue? = nil
    var suggestedRowLabel: String? = nil
    if context == .pomodoroName, candidate.suggested, !isHiddenThemeGhost {
        if let label = candidate.suggestionLabel, !label.isEmpty {
            suggestedRowLabel = label
            secondaryText = CaptureTaskThemePresentation.suggestedSecondaryText(
                label: label, themeName: candidate.name ?? themeSuggestion?.theme.name)
        } else if let fallback = themeSuggestion, !fallback.label.isEmpty {
            suggestedRowLabel = fallback.label
            secondaryText = CaptureTaskThemePresentation.suggestedSecondaryText(
                label: fallback.label, themeName: candidate.name ?? fallback.theme.name)
        }
        // The dot hue comes from the top-level suggestion's declaring note.
        suggestedFromHue = themeSuggestion?.from?.hue
        if !badges.contains("Suggested") {
            badges.append("Suggested")
        }
    }

    // Reading tasks (`#task #ref`) draw the book symbol in the task
    // pickers (`^`, `:`, `+`, `&`, `!`). Bob already strips `#ref` from
    // the display text, so only the symbol changes.
    let resolvedSymbolName = bookSymbolName(for: candidate, context: context) ?? symbolName
    let matchRange = completionMatchRange(in: primaryText, query: query)
    let baseAccessibilityLabel = completionAccessibilityLabel(
        contextLabel: contextLabel,
        primaryText: primaryText,
        secondaryText: secondaryText,
        badges: badges
    )
    let themeAccessibilityDetails = themeContext
        ? candidate.themes.map { CaptureUnconfiguredThemePresentation.spokenColor(for: $0) }
        : []
    var accessibilityParts = ([baseAccessibilityLabel] + themeAccessibilityDetails)
        .filter { !$0.isEmpty }
    if context == .pomodoroName, candidate.suggested, !isHiddenThemeGhost {
        let themeName = candidate.name ?? themeSuggestion?.theme.name ?? primaryText
        let reason = suggestedRowLabel ?? candidate.suggestionLabel ?? themeSuggestion?.label ?? ""
        let suggestedLabel = CaptureTaskThemePresentation.suggestedAccessibilityLabel(
            themeName: themeName, label: reason)
        if !suggestedLabel.isEmpty, !accessibilityParts.contains(suggestedLabel) {
            accessibilityParts.append(suggestedLabel)
        }
    }
    let accessibilityLabel = accessibilityParts.joined(separator: ", ")

    return CompletionRowContent(
        category: category,
        symbolName: resolvedSymbolName,
        contextLabel: contextLabel,
        primaryText: primaryText,
        primaryMatchRange: matchRange,
        secondaryText: secondaryText,
        badges: badges,
        themeSwatches: themeSwatches,
        isHiddenThemeGhost: isHiddenThemeGhost,
        suggestedFromHue: suggestedFromHue,
        accessibilityLabel: accessibilityLabel,
        accessibilityHint: isHiddenThemeGhost
            ? "Type hidden from Recent. Press Control+D to undo."
            : accessibilityHint
    )
}

private func themeHistorySummary(lastUsed: String?, daysUsed: Int?) -> String? {
    var parts: [String] = []
    if let lastUsed {
        let fields = lastUsed.split(separator: "-")
        if fields.count == 3,
           let month = Int(fields[1]),
           let day = Int(fields[2]),
           (1...12).contains(month)
        {
            let formatter = DateFormatter()
            let availableMonths: [String]? = formatter.shortMonthSymbols
            if let months = availableMonths, month <= months.count {
                let monthName = months[month - 1]
                parts.append("\(monthName) \(day)")
            }
        } else if !lastUsed.isEmpty {
            parts.append(lastUsed)
        }
    }
    if let daysUsed, daysUsed > 0 {
        parts.append("\(daysUsed) \(daysUsed == 1 ? "day" : "days")")
    }
    return parts.isEmpty ? "your type · never used" : parts.joined(separator: " · ")
}

/// The `book` override for reading-task rows in the task pickers, or
/// nil when the row renders as before. Only `task_kind == "ref"` rows in
/// the `^` (active_task), `:` (task_link), `/` (task_goto), `+` (task_parent and scoped
/// task), `&` (task_dependency), `!` (task_complete), and `((` (wikilink_task)
/// contexts change; an older `bob` omits `task_kind` and every other context
/// is untouched.
private func bookSymbolName(
    for candidate: CaptureCompletionCandidate,
    context: CaptureCompletionContext?
) -> String? {
    guard candidate.taskKind == "ref" else {
        return nil
    }
    switch context {
    case .activeTask, .taskLink, .taskGoto, .task, .taskParent, .taskDependency, .blockedTask, .taskComplete, .wikilinkTask:
        return "book"
    default:
        return nil
    }
}

/// The red `after/cap` badge for a create row that would push the plan
/// past its theme cap (e.g. `4/3`). Shared by the `pomodoro_name` create
/// row and the `pomodoro_start_name` new and again rows. `nil` when the
/// fields are missing or the plan stays within cap.
private func planCapBadge(after: Int?, cap: Int?) -> String? {
    guard let after, let cap, after > cap else {
        return nil
    }
    return "\(after)/\(cap)"
}

/// The queued-link badge for a `pomodoro_start_name` start or name-it row.
/// Unlike the `pomodoro_name` context, the singular "1 link" is used here.
private func startNameLinkBadge(childCount: Int?) -> String {
    let count = childCount ?? 0
    if count == 0 {
        return "Empty"
    }
    return count == 1 ? "1 link" : "\(count) links"
}

/// The secondary text for a `pomodoro_start_name` open row: under a
/// ledger-keeping `=#` while a session runs, the row reads as a takeover
/// of the running ledger (`Takes over 0920–0945`); otherwise it keeps the
/// `Next up` / `Planned` discovery text. A keeps-ledger response with no
/// running session (idle) has no ledger to take over, so it also keeps the
/// discovery text.
private func startNameOpenSecondary(
    nextUp: Bool,
    override: CaptureCompleteOverride?
) -> String {
    if override?.keepsLedger == true,
       let range = override?.running?.timeRange, !range.isEmpty
    {
        return "Takes over \(enDashRange(range))"
    }
    return nextUp ? "Next up" : "Planned"
}

/// The accessibility hint for a `pomodoro_start_name` running row: under
/// `=#` while a session runs the row teaches the swap (`=` restarts the
/// running session, any other pick swaps in), under `=<X>#` it restarts,
/// and when Bob reports no override object it teaches `=` before the close
/// spellings.
private func startNameRunningHint(override: CaptureCompleteOverride?) -> String {
    if override?.running != nil {
        if override?.keepsLedger == true {
            return "Already running \u{2014} = restarts it; pick another Pomodoro to swap in"
        }
        return "Restarts it now"
    }
    return "Already running. Restart it with =, or close it first with x."
}

/// The display name for a `pomodoro_start_name` start, new, again, or running
/// row: Bob's canonical name, falling back to the typed slug.
private func startNameDisplayName(for candidate: CaptureCompletionCandidate) -> String {
    if let name = candidate.name, !name.isEmpty {
        return name
    }
    return candidate.replacement
}

/// Renders a `HHMM-HHMM` range with an en dash, matching the app's session
/// typography for the "Last ran", "Running", and "New session" lines. Shared
/// with the start card, which renders the created-session body the same way.
func enDashRange(_ timeRange: String) -> String {
    timeRange.replacingOccurrences(of: "-", with: "\u{2013}")
}

/// The single Pomodoro badge for an active-task row: the current entry shows when
/// it runs, a queued entry shows its name, an unnamed placeholder shows that the
/// task is planned but not yet named, and an unqueued task says so outright.
private func activeTaskPomodoroBadge(for pomodoro: ActiveTaskPomodoro?) -> String {
    guard let pomodoro else {
        return "Not queued"
    }
    if pomodoro.isCurrent {
        let name = pomodoro.name.flatMap { $0.isEmpty ? nil : $0 } ?? "current"
        guard let timeRange = pomodoro.timeRange, !timeRange.isEmpty else {
            return "Now · \(name)"
        }
        return "Now · \(name) \(timeRange)"
    }
    if let name = pomodoro.name, !name.isEmpty {
        return name
    }
    return "Planned"
}

private func completionAccessibilityLabel(
    contextLabel: String,
    primaryText: String,
    secondaryText: String?,
    badges: [String]
) -> String {
    var parts: [String] = []
    if !contextLabel.isEmpty {
        parts.append(contextLabel)
    }
    parts.append(primaryText)
    if let secondaryText, !secondaryText.isEmpty {
        parts.append(secondaryText)
    }
    parts.append(contentsOf: badges)
    return parts.joined(separator: ", ")
}

/// Case-insensitive first-occurrence match of `query` within `text`, expressed as a
/// `Character`-offset range so callers don't need to reason about `String.Index` validity
/// across differently-sourced strings.
public func completionMatchRange(in text: String, query: String) -> Range<Int>? {
    guard !query.isEmpty else {
        return nil
    }
    guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
        return nil
    }

    let lowerOffset = text.distance(from: text.startIndex, to: range.lowerBound)
    let upperOffset = text.distance(from: text.startIndex, to: range.upperBound)
    return lowerOffset..<upperOffset
}

/// Truncates `path` to at most `maxLength` characters, preserving the final path component
/// (the basename) intact and collapsing the middle of the leading directory portion with an
/// ellipsis. Falls back to plain middle truncation when there is no `/` or the basename alone
/// exceeds the budget.
public func middleTruncatedPath(_ path: String, maxLength: Int) -> String {
    guard maxLength > 0, path.count > maxLength else {
        return path
    }

    let ellipsis = "\u{2026}"
    guard let lastSlash = path.lastIndex(of: "/") else {
        return middleTruncated(path, maxLength: maxLength, ellipsis: ellipsis)
    }

    let basename = String(path[path.index(after: lastSlash)...])
    let suffix = "/\(basename)"
    if suffix.count >= maxLength {
        return middleTruncated(basename, maxLength: maxLength, ellipsis: ellipsis)
    }

    let directoryBudget = maxLength - suffix.count - ellipsis.count
    guard directoryBudget > 0 else {
        return "\(ellipsis)\(suffix)"
    }

    let directory = String(path[path.startIndex..<lastSlash])
    let headCount = (directoryBudget + 1) / 2
    let tailCount = directoryBudget - headCount
    let head = directory.prefix(headCount)
    let tail = directory.suffix(tailCount)
    return "\(head)\(ellipsis)\(tail)\(suffix)"
}

private func middleTruncated(_ text: String, maxLength: Int, ellipsis: String) -> String {
    guard text.count > maxLength else {
        return text
    }
    guard maxLength > ellipsis.count else {
        return String(ellipsis.prefix(maxLength))
    }

    let budget = maxLength - ellipsis.count
    let headCount = (budget + 1) / 2
    let tailCount = budget - headCount
    let head = text.prefix(headCount)
    let tail = text.suffix(tailCount)
    return "\(head)\(ellipsis)\(tail)"
}
