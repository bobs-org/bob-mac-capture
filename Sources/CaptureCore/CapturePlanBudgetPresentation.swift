import Foundation

/// Pure presentation model for a Bob `plan_budget` in a capture preview
/// or saved idle agenda, built once so the SwiftUI layer never branches
/// on budget JSON fields or recomputes meter math. A capture preview's
/// only source of truth is Bob's resolved `plan_budget` object — which comes from
/// `bob capture --dry-run [--no-clip] --format json` for live preview
/// (`--no-clip` is omitted only for a `%c` draft) and the same command
/// resolving the clipboard for submission — so
/// there is no Swift-side ledger logic here, only wording.
///
/// Wording mirrors `print_plan_budget` and `format_pomodoro_task_destination`
/// in `src/native/capture/output.rs` (`plan L/Lc links`, `→ new Pomodoro BOB`,
/// `→ into running GOALS (…)`, `→ under GOALS (named)`) so the panel and the
/// CLI describe the same budget the same way. The daily plan caps Task Links
/// only: there is no type meter, `+N` type delta, or type-cap warning, even
/// when an older Bob still sends `themes` / `added_themes` / a
/// `plan_theme_cap_exceeded` warning (all ignored). The Mac destination row
/// shortens the CLI's arrow to the row form (`→ GOALS · next up`,
/// `→ running GOALS 0945–1015`, `→ new Pomodoro BOB`); the TODAY badge and
/// warning captions carry the same numbers.
public struct CapturePlanBudgetPresentation: Equatable, Sendable {
    /// `"→ GOALS · next up"`, `"→ running GOALS 0945–1015"`,
    /// `"→ new Pomodoro BOB"`, or nil when Bob reported no link
    /// destination. The time range uses an en dash; Bob's wire
    /// `time_range` uses a hyphen.
    public let destinationRowText: String?
    /// The shared TODAY badge, including its spoken and tooltip descriptions.
    public let today: TodayBadgePresentation
    /// Link-cap warning messages in Bob's order, rendered as orange captions.
    public let warningTexts: [String]
    public let accessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let budget = capture.planBudget else {
            return nil
        }
        self.init(
            budget: budget,
            destination: capture.pomodoroLinkDestination
        )
    }

    public init(
        budget: CapturePlanBudget,
        destination: PomodoroLinkEndpoint?,
        includeProposalDetails: Bool = true
    ) {
        destinationRowText = Self.destinationRowText(for: destination)
        today = TodayBadgePresentation(count: budget.links.count, cap: budget.links.cap)
        warningTexts = includeProposalDetails
            ? budget.warnings
                .filter { $0.code != Self.retiredTypeCapWarningCode }
                .map(\.message)
            : []

        var parts: [String] = []
        if let destinationRowText {
            parts.append(destinationRowText)
        }
        parts.append(today.spokenText)
        parts.append(contentsOf: warningTexts)
        accessibilitySummary = parts.joined(separator: ", ")
    }

    /// The destination row for one link endpoint, or nil when there is no
    /// endpoint. Unknown or missing roles fall back to the bare name (or
    /// the range, or the line) so a newer Bob never breaks the row.
    public static func destinationRowText(
        for destination: PomodoroLinkEndpoint?
    ) -> String? {
        guard let destination else {
            return nil
        }
        let name = destination.name?.isEmpty == false ? destination.name! : nil
        switch destination.role {
        case "created":
            return "→ new Pomodoro \(name ?? endpointFallbackLabel(for: destination))"
        case "current":
            let target = name ?? endpointFallbackLabel(for: destination)
            if let range = destination.timeRange, !range.isEmpty {
                return "→ running \(target) \(displayRange(range))"
            }
            return "→ running \(target)"
        case "named":
            return "→ \(name ?? endpointFallbackLabel(for: destination)) · named"
        case "next_up":
            return "→ \(name ?? endpointFallbackLabel(for: destination)) · next up"
        default:
            if let name {
                return "→ \(name)"
            }
            if let range = destination.timeRange, !range.isEmpty {
                return "→ \(displayRange(range))"
            }
            return "→ line \(destination.line)"
        }
    }

    private static func endpointFallbackLabel(
        for destination: PomodoroLinkEndpoint
    ) -> String {
        if let range = destination.timeRange, !range.isEmpty {
            return displayRange(range)
        }
        return "line \(destination.line)"
    }

    /// Bob's wire `time_range` uses a hyphen (`0945-1015`); the Mac row
    /// uses an en dash (`0945–1015`).
    static func displayRange(_ timeRange: String) -> String {
        timeRange.replacingOccurrences(of: "-", with: "–")
    }

    /// The retired daily type cap's warning code. An older Bob still sends
    /// it; the Mac drops it so no type-cap copy reaches the panel.
    private static let retiredTypeCapWarningCode = "plan_theme_cap_exceeded"

    /// Swatches for a preview destination name, resolved against the
    /// budget's `added_theme_refs`. Created destinations tint; existing
    /// names resolve to unknown swatches and render neutral pills until
    /// Bob ships destination refs. Empty when there is no budget.
    public static func destinationThemeSwatches(
        destination: PomodoroLinkEndpoint?,
        budget: CapturePlanBudget?
    ) -> [CaptureThemeSwatch] {
        swatches(forName: destination?.name, budget: budget)
    }

    /// Swatches for any preview Pomodoro name against a capture's
    /// budget refs. Shared by destination rows, start/toggle/project-note
    /// previews, and the Refs Today pill.
    public static func swatches(
        forName name: String?,
        budget: CapturePlanBudget?
    ) -> [CaptureThemeSwatch] {
        guard let budget else {
            return []
        }
        return PomodoroThemeSwatches.swatches(
            forName: name,
            refs: budget.addedThemeRefs
        )
    }
}
