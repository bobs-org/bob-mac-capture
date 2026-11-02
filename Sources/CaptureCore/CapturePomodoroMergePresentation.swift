import Foundation

/// Presentation of Bob's resolved `pomodoro_merge` object. Swift does not
/// resolve selectors or infer which child lines move; it only words the result.
public struct CapturePomodoroMergePresentation: Equatable, Sendable {
    public struct AbsorbedRow: Equatable, Sendable {
        public let name: String
        public let fromLine: Int
        public let movedLines: Int
        public let droppedDuplicates: Int
    }

    public let isDryRun: Bool
    public let before: String
    public let after: String
    public let absorbedRows: [AbsorbedRow]
    public let destinationText: String?
    public let primaryActionTitle: String
    public let statusText: String
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let merge = capture.pomodoroMerge else {
            return nil
        }
        isDryRun = capture.dryRun
        before = merge.before
        after = merge.after
        absorbedRows = merge.absorbed.map {
            AbsorbedRow(
                name: $0.name,
                fromLine: $0.fromLine,
                movedLines: $0.movedLines,
                droppedDuplicates: $0.droppedDuplicates
            )
        }
        let path = merge.path.isEmpty ? capture.relativeTarget : merge.path
        destinationText = merge.entryLine > 0 ? "\(path) · line \(merge.entryLine)" : nil
        primaryActionTitle = "Merge"

        let names = absorbedRows.map(\.name).joined(separator: ", ")
        let verb = capture.dryRun ? "Would merge" : "Merged"
        statusText = "\(verb) \(names) into \(after)"
        notificationTitle = "\(capture.dryRun ? "Would merge" : "Merged") \(names)"
        var body = ["\(before) → \(after)"]
        if let destinationText {
            body.append(destinationText)
        }
        body.append(
            contentsOf: absorbedRows.map { row in
                let movedLineNoun = row.movedLines == 1 ? "line" : "lines"
                var detail = "\(row.name) · \(row.movedLines) \(movedLineNoun) moved"
                if row.droppedDuplicates > 0 {
                    let duplicate = row.droppedDuplicates == 1 ? "duplicate" : "duplicates"
                    detail += " · \(row.droppedDuplicates) \(duplicate) dropped"
                }
                return detail
            })
        notificationBody = body.joined(separator: "\n")
        previewAccessibilitySummary = body.joined(separator: ", ")
    }
}
