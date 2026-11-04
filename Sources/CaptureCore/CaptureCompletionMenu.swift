import Foundation

/// Shared unselected-menu copy and selection rules for every completion
/// context. The `%`, bare-`#`, and `@note+id#` drawer menus all open through
/// this one no-selection mechanism.
public enum CaptureCompletionMenu: Sendable {
    /// Footer shown when Bob opened a menu with `initial_selection: none`
    /// and the user has not highlighted a row.
    public static let unselectedFooterHint =
        "⇥ take the first · type a letter · ⏎ capture as typed"

    public static let directiveTitle = "CAPTURE AS"

    /// Row 0 when Bob omitted `initial_selection`; `nil` when Bob sent
    /// `none`. A `pomodoro_name` empty-query suggestion still wins over
    /// first-row, and loses to `none`.
    public static func initialSelectedIndex(
        for completion: CaptureCompletionResponse,
        queryIsEmpty: Bool
    ) -> Int? {
        if completion.opensWithoutSelection {
            return nil
        }
        if completion.context == "pomodoro_name"
            || completion.context == "pomodoro_past_name",
            queryIsEmpty,
            let suggested = completion.candidates.firstIndex(where: \.suggested)
        {
            return suggested
        }
        return completion.candidates.isEmpty ? nil : 0
    }

    /// Disabled rows consume Tab/Return/click without editing or submitting.
    public static func isDisabled(_ candidate: CaptureCompletionCandidate) -> Bool {
        if let reason = candidate.disabledReason, !reason.isEmpty {
            return true
        }
        return candidate.refused != nil
    }
}
