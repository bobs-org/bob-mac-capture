import Foundation

/// Which key opens Bob Refs in Tabs while Highlights is frontmost.
enum RefsHighlightsTabsKey: String, CaseIterable, Sendable {
    case shiftCmdO = "shiftCmdO"
    case cmdE = "cmdE"
    case off = "off"

    var displayName: String {
        switch self {
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
        case .shiftCmdO:
            return .highlightsShiftCommandO
        case .cmdE:
            return .highlightsCommandE
        case .off:
            return nil
        }
    }
}
