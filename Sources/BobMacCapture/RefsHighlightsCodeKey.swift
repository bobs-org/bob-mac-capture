import Foundation

/// Which key opens the Copy card with its code picker selected while
/// Highlights is frontmost. Command-B is the default; Off leaves the
/// chord with Highlights.
enum RefsHighlightsCodeKey: String, CaseIterable, Sendable {
    case cmdB = "cmdB"
    case off = "off"

    var displayName: String {
        switch self {
        case .cmdB: "Command-B"
        case .off: "Off"
        }
    }

    var configuration: HotKeyConfiguration? {
        switch self {
        case .cmdB: .highlightsCommandB
        case .off: nil
        }
    }
}
