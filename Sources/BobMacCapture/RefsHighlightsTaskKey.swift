import Foundation

/// Which key opens the focused PDF's reading task while Highlights is
/// frontmost. Control-Return is the default; Off leaves the chord with
/// Highlights.
enum RefsHighlightsTaskKey: String, CaseIterable, Sendable {
    case ctrlReturn = "ctrlReturn"
    case off = "off"

    var displayName: String {
        switch self {
        case .ctrlReturn: "Control-Return"
        case .off: "Off"
        }
    }

    var configuration: HotKeyConfiguration? {
        switch self {
        case .ctrlReturn: .highlightsControlReturn
        case .off: nil
        }
    }
}
