import Foundation

/// Pure presentation model for the plan-budget portion of a
/// `bob capture --format json` success (`plan_budget` present), built once
/// from `CaptureCommandSuccess` so the SwiftUI layer never branches on
/// budget JSON fields or recomputes meter math. The preview's only source
/// of truth is Bob's resolved `plan_budget` object — which comes from
/// `bob capture --dry-run --no-clip --format json` for live preview and
/// the same command without `--dry-run`/`--no-clip` for submission — so
/// there is no Swift-side ledger logic here, only wording.
///
/// Wording mirrors `print_plan_budget` and `format_pomodoro_task_destination`
/// in `src/native/capture/output.rs` (`plan T/Tc themes · L/Lc links`,
/// `(+N theme: NAME)`, `→ new Pomodoro BOB`, `→ into running GOALS (…)`,
/// `→ under GOALS (named)`) so the panel and the CLI describe the same
/// budget the same way. The Mac destination row shortens the CLI's arrow
/// to the row form (`→ GOALS · next up`, `→ running GOALS 0945–1015`,
/// `→ new Pomodoro BOB`); the meter capsules, delta chip, and warning
/// captions carry the same numbers and names.
public struct CapturePlanBudgetPresentation: Equatable, Sendable {
    /// `"→ GOALS · next up"`, `"→ running GOALS 0945–1015"`,
    /// `"→ new Pomodoro BOB"`, or nil when Bob reported no link
    /// destination. The time range uses an en dash; Bob's wire
    /// `time_range` uses a hyphen.
    public let destinationRowText: String?
    /// `"Themes 3/3"` — always present when the budget is present.
    public let themesCapsuleText: String
    public let themesOverCap: Bool
    /// `"Links 8/10"` — always present when the budget is present.
    public let linksCapsuleText: String
    public let linksOverCap: Bool
    /// `"+1 BOB"` when the themes meter grew past its previous count,
    /// else nil. Names the first added theme when Bob reported one.
    public let deltaChipText: String?
    /// Budget warning messages in Bob's order, rendered as orange captions.
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

    public init(budget: CapturePlanBudget, destination: PomodoroLinkEndpoint?) {
        destinationRowText = Self.destinationRowText(for: destination)
        themesCapsuleText = "Themes \(budget.themes.count)/\(budget.themes.cap)"
        themesOverCap = budget.themes.over
        linksCapsuleText = "Links \(budget.links.count)/\(budget.links.cap)"
        linksOverCap = budget.links.over
        deltaChipText = Self.deltaChipText(for: budget)
        warningTexts = budget.warnings.map(\.message)

        var parts: [String] = []
        if let destinationRowText {
            parts.append(destinationRowText)
        }
        parts.append("\(themesCapsuleText), \(linksCapsuleText)")
        if let deltaChipText {
            parts.append(deltaChipText)
        }
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

    private static func deltaChipText(for budget: CapturePlanBudget) -> String? {
        let before = budget.themes.before ?? budget.themes.count
        guard budget.themes.count > before else {
            return nil
        }
        let delta = budget.themes.count - before
        if let first = budget.addedThemes.first, !first.isEmpty {
            return "+\(delta) \(first)"
        }
        return "+\(delta)"
    }
}
