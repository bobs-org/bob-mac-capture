import Foundation

/// When the idle agenda may paint: the setting is on, the draft is
/// blank, nothing else owns the auxiliary region, no live preview is
/// showing, and a snapshot or a state line is ready to show. While the
/// agenda is off the store keeps refreshing for the close-comma count,
/// but nothing is measured, planned, or shown.
public enum CaptureAgendaVisibility {
    public static func isVisible(
        settingOn: Bool,
        draftBlank: Bool,
        regionFree: Bool,
        previewIdle: Bool,
        hasPlan: Bool
    ) -> Bool {
        settingOn && draftBlank && regionFree && previewIdle && hasPlan
    }
}
