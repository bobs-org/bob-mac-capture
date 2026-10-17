import Foundation

/// Portable copy for the footer Control-Return chip and hold-to-reveal
/// destinations capsule. Built from the latest live-preview open plan so
/// SwiftUI never decides labels, line details, or overflow itself.
public struct CaptureOpenHintPresentation: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let symbolName: String
        public let label: String
        public let detail: String?

        public init(symbolName: String, label: String, detail: String?) {
            self.symbolName = symbolName
            self.label = label
            self.detail = detail
        }
    }

    public static let maxVisibleRows = 4

    /// Whether the footer chip should appear for this plan. A missing plan
    /// (no preview yet) is available; an explicit empty plan is not.
    public let isAvailable: Bool
    public let accessibilityLabel: String
    public let helpText: String
    public let rows: [Row]
    public let overflowText: String?

    public init(plan: CaptureOpenPlan?) {
        guard let plan else {
            isAvailable = true
            accessibilityLabel = Self.genericAccessibilityLabel
            helpText = Self.genericHelpText
            rows = []
            overflowText = nil
            return
        }
        if plan.isEmpty {
            isAvailable = false
            accessibilityLabel = Self.genericAccessibilityLabel
            helpText = Self.genericHelpText
            rows = []
            overflowText = nil
            return
        }

        isAvailable = true
        let visible = Array(plan.notes.prefix(Self.maxVisibleRows))
        rows = visible.map(Self.row(for:))
        let extra = plan.notes.count - visible.count
        overflowText = extra > 0 ? "+\(extra) more" : nil
        let phrases = plan.notes.map(Self.destinationPhrase(for:))
        let joined = Self.join(phrases)
        accessibilityLabel = "Control-Return: capture and open \(joined) in Obsidian"
        helpText = joined
    }

    private static let genericAccessibilityLabel =
        "Control-Return: capture and open in Obsidian"
    private static let genericHelpText = "Capture and open in Obsidian"

    private static func row(for note: CaptureOpenNote) -> Row {
        Row(
            symbolName: note.role == .day ? "calendar" : "doc.text",
            label: displayLabel(for: note),
            detail: note.line.map { "line \($0)" }
        )
    }

    private static func displayLabel(for note: CaptureOpenNote) -> String {
        if !note.label.isEmpty {
            return note.label
        }
        if note.role == .day {
            return "Today"
        }
        return note.relativePath
    }

    private static func destinationPhrase(for note: CaptureOpenNote) -> String {
        let name: String
        switch note.role {
        case .day:
            name = "Today"
        default:
            name = displayLabel(for: note)
        }
        if let line = note.line {
            return "\(name) at line \(line)"
        }
        return name
    }

    private static func join(_ phrases: [String]) -> String {
        switch phrases.count {
        case 0:
            return ""
        case 1:
            return phrases[0]
        case 2:
            return "\(phrases[0]) and \(phrases[1])"
        default:
            let head = phrases.dropLast().joined(separator: ", ")
            return "\(head), and \(phrases[phrases.count - 1])"
        }
    }
}
