import Foundation

/// Mirrors bob-cli `docs/plan.md` and bob-ledger-tools `workBadgeTone`.
/// A ladder change must land in both implementations.
public enum WorkBadgeTone: String, CaseIterable, Equatable, Sendable {
    case grey
    case blue
    case green
    case yellow
    case orange
    case magenta
    case red

    public init?(count: Int, cap: Int) {
        guard count >= 0, cap >= 1 else {
            return nil
        }
        if count == 0 {
            self = .grey
        } else if count > cap {
            self = .red
        } else if count == cap {
            self = .magenta
        } else if 5 * count >= 4 * cap {
            self = .orange
        } else if 5 * count >= 3 * cap {
            self = .yellow
        } else if 5 * count >= 2 * cap {
            self = .green
        } else {
            self = .blue
        }
    }

    public var lightHex: String {
        switch self {
        case .grey: "#5c5c5c"
        case .blue: "#086ddd"
        case .green: "#08b94e"
        case .yellow: "#e0ac00"
        case .orange: "#ec7500"
        case .magenta: "#923675"
        case .red: "#e93147"
        }
    }

    public var darkHex: String {
        switch self {
        case .grey: "#b3b3b3"
        case .blue: "#027aff"
        case .green: "#44cf6e"
        case .yellow: "#e0de71"
        case .orange: "#e9973f"
        case .magenta: "#e5a9d8"
        case .red: "#fb464c"
        }
    }

    public var spokenName: String {
        rawValue
    }
}

public struct TodayBadgePresentation: Equatable, Sendable {
    public let text: String
    public let tone: WorkBadgeTone?
    public let spokenText: String
    public let helpText: String

    public init(count: Int, cap: Int) {
        let tone = WorkBadgeTone(count: count, cap: cap)
        self.tone = tone

        guard tone != nil else {
            text = "TODAY –"
            spokenText = "TODAY unavailable"
            helpText = "Today's Task Link budget is unavailable"
            return
        }

        text = "TODAY \(count)/\(cap)"
        switch tone {
        case .magenta:
            spokenText = "TODAY \(count) of \(cap) links, at cap"
        case .red:
            spokenText = "TODAY \(count) of \(cap) links, over cap"
        default:
            spokenText = "TODAY \(count) of \(cap) links"
        }
        helpText = "\(count) of \(cap) Task Links in today's open Pomodoros"
    }
}
