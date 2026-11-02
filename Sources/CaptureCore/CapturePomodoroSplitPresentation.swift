import Foundation

/// Presentation of Bob's resolved `pomodoro_split` object. Swift does not
/// resolve selectors or infer which links move; it only words Bob's result.
public struct CapturePomodoroSplitPresentation: Equatable, Sendable {
    public struct CreatedRow: Equatable, Sendable {
        public let type: CapturePomodoroThemeRef
        public let line: Int
        public let name: String
        public let movedLinks: Int
    }

    public let isDryRun: Bool
    public let before: String
    public let after: String
    public let base: CapturePomodoroThemeRef
    public let createdRows: [CreatedRow]
    public let stayedLinks: Int
    public let destinationText: String?
    public let primaryActionTitle: String
    public let statusText: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let split = capture.pomodoroSplit else {
            return nil
        }
        isDryRun = capture.dryRun
        before = split.before
        after = split.after
        base = split.base
        createdRows = split.created.map {
            CreatedRow(type: $0.typeRef, line: $0.line, name: $0.name, movedLinks: $0.movedLinks)
        }
        stayedLinks = split.stayedLinks
        let path = split.path.isEmpty ? capture.relativeTarget : split.path
        destinationText = split.entryLine > 0 ? "\(path) · line \(split.entryLine)" : nil
        primaryActionTitle = "Split"

        let verb = capture.dryRun ? "Would split" : "Split"
        statusText = "\(verb) \(before) → \(after)"
        notificationTitle = "\(capture.dryRun ? "Would split" : "Split") \(before)"
        var body = ["\(before) → \(after)"]
        if let destinationText {
            body.append(destinationText)
        }
        body.append(
            contentsOf: createdRows.map { row in
                let count: String
                if row.movedLinks == 0 {
                    count = "no links"
                } else {
                    count = "\(row.movedLinks) link\(row.movedLinks == 1 ? "" : "s")"
                }
                return "\(row.type.name) · \(count)"
            })
        if stayedLinks > 0 {
            body.append("\(stayedLinks) link\(stayedLinks == 1 ? " stays" : "s stay")")
        }
        notificationBody = body.joined(separator: "\n")
        previewAccessibilitySummary = body.joined(separator: ", ")
    }
}
