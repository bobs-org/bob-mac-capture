import Foundation

/// Which key opens the Copy card while Highlights is frontmost.
/// Command-Y is the default; Off leaves the chord with Highlights.
enum RefsHighlightsCopyKey: String, CaseIterable, Sendable {
    case cmdY = "cmdY"
    case off = "off"

    var displayName: String {
        switch self {
        case .cmdY:
            return "Command-Y"
        case .off:
            return "Off"
        }
    }

    /// The takeover registration, or nil when the takeover is off.
    var configuration: HotKeyConfiguration? {
        switch self {
        case .cmdY:
            return .highlightsCommandY
        case .off:
            return nil
        }
    }
}
