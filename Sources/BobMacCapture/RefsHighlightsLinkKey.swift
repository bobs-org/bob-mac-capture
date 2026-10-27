import Foundation

/// Which key opens the Copy card with its link picker selected while
/// Highlights is frontmost. Command-L is the default; Off leaves the
/// chord with Highlights.
enum RefsHighlightsLinkKey: String, CaseIterable, Sendable {
    case cmdL = "cmdL"
    case off = "off"

    var displayName: String {
        switch self {
        case .cmdL: "Command-L"
        case .off: "Off"
        }
    }

    var configuration: HotKeyConfiguration? {
        switch self {
        case .cmdL: .highlightsCommandL
        case .off: nil
        }
    }
}
