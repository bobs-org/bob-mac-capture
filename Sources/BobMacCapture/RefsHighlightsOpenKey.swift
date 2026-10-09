import Foundation

/// Which key opens Bob Refs while Highlights is frontmost. The default is
/// the `highlights_open_key` epic decision (`cmdO`): Command-O opens Bob
/// Refs, and Highlights' File > Open… menu item keeps its own dialog.
/// `off` leaves every key with its owning app, so only the global hotkey
/// opens Bob Refs. The Settings picker can change the key at any time.
enum RefsHighlightsOpenKey: String, CaseIterable, Sendable {
    case cmdO = "cmdO"
    case ctrlO = "ctrlO"
    case off = "off"

    var displayName: String {
        switch self {
        case .cmdO:
            return "Command-O"
        case .ctrlO:
            return "Control-O"
        case .off:
            return "Off"
        }
    }

    /// The takeover registration, or nil when the takeover is off.
    var configuration: HotKeyConfiguration? {
        switch self {
        case .cmdO:
            return .highlightsCommandO
        case .ctrlO:
            return .highlightsControlO
        case .off:
            return nil
        }
    }
}
