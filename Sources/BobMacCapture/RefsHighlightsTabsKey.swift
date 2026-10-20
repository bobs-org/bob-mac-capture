import Foundation

/// Which key opens Bob Refs in Tabs while Highlights is frontmost.
/// Command-T is the default; Shift-Command-O, Command-E, and Off are selectable.
enum RefsHighlightsTabsKey: String, CaseIterable, Sendable {
    case cmdT = "cmdT"
    case shiftCmdO = "shiftCmdO"
    case cmdE = "cmdE"
    case off = "off"

    var displayName: String {
        switch self {
        case .cmdT:
            return "Command-T"
        case .shiftCmdO:
            return "Shift-Command-O"
        case .cmdE:
            return "Command-E"
        case .off:
            return "Off"
        }
    }

    /// The takeover registration, or nil when the takeover is off.
    var configuration: HotKeyConfiguration? {
        switch self {
        case .cmdT:
            return .highlightsCommandT
        case .shiftCmdO:
            return .highlightsShiftCommandO
        case .cmdE:
            return .highlightsCommandE
        case .off:
            return nil
        }
    }

    /// Command-T also toggles Tabs inside Bob Refs, so its takeover steps
    /// aside while the panel is visible.
    var yieldsToVisiblePanel: Bool {
        self == .cmdT
    }
}
