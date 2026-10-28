import Foundation

/// The one-off warning slot's cancel-label contents. Bob authors `text`;
/// Swift only chooses the ⊘ tint versus muted from the verdict or hint.
public struct CaptureRelationCancelSlot: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        /// Verdict `cancels`: ⊘ tint, never strikethrough.
        case cancels
        /// A refused cancel row, `already_closed`, or an inverse hint: muted.
        case muted
    }

    public let text: String
    public let style: Style

    public init(text: String, style: Style) {
        self.text = text
        self.style = style
    }
}

/// One preview warning that is not a duplicate of a `relation_cancels[]`
/// row. Hide warnings stay amber; leftover cancel warnings use the ⊘ tint.
public struct CapturePreviewWarningRow: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case amber
        case cancelled
    }

    public let text: String
    public let style: Style
    public let accessibilityLabel: String

    public init(text: String, style: Style, accessibilityLabel: String? = nil) {
        self.text = text
        self.style = style
        self.accessibilityLabel = accessibilityLabel ?? text
    }
}

/// Thin-client helpers for Bob's cancel-label flags and strings. Swift
/// never computes a verdict: it only decides whether to show Bob's
/// `cancels_source` capsule, dim the source, and pick the slot style.
public enum CaptureRelationCancelPresentation {
    /// True when this row's key is a configured cancel label.
    public static func cancelsSource(_ candidate: CaptureCompletionCandidate) -> Bool {
        candidate.cancelsSource
    }

    /// Dim the live-sentence source only when the selected or typed label
    /// cancels and Bob's verdict is `cancels`.
    public static func dimsSource(
        candidate: CaptureCompletionCandidate?,
        cancel: CaptureCompletionRelationCancel?
    ) -> Bool {
        guard let candidate, candidate.cancelsSource, let cancel else {
            return false
        }
        return cancel.verdict == "cancels"
    }

    /// Bob's `relation_cancel.message` when the active cancel label would
    /// cancel or is refused, else the muted inverse `hint`.
    public static func slot(
        candidate: CaptureCompletionCandidate?,
        cancel: CaptureCompletionRelationCancel?
    ) -> CaptureRelationCancelSlot? {
        guard let cancel else {
            return nil
        }
        if let candidate, candidate.cancelsSource {
            switch cancel.verdict {
            case "cancels":
                return CaptureRelationCancelSlot(text: cancel.message, style: .cancels)
            case "already_closed":
                return CaptureRelationCancelSlot(text: cancel.message, style: .muted)
            case "recurring", "new_task":
                return CaptureRelationCancelSlot(text: cancel.message, style: .muted)
            default:
                return nil
            }
        }
        if let hint = cancel.hint, !hint.isEmpty {
            return CaptureRelationCancelSlot(text: hint, style: .muted)
        }
        return nil
    }

    /// VoiceOver for a dimmed source: "Cancels Sell stocks!".
    public static func sourceAccessibilityLabel(
        sourceText: String,
        dimsSource: Bool
    ) -> String {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dimsSource, !trimmed.isEmpty else {
            return trimmed
        }
        return "Cancels \(trimmed)"
    }

    /// Hide and leftover cancel warnings for the preview stack. Skip
    /// `relation_cancelled_source` when `relation_cancels[]` already shows
    /// Bob's message, so the ⊘ row is never an orange duplicate.
    public static func previewWarningRows(
        for capture: CaptureCommandSuccess
    ) -> [CapturePreviewWarningRow] {
        let skipCancelledSource = !capture.relationCancels.isEmpty
        return capture.warnings.compactMap { warning in
            if warning.isThemeNotConfigured {
                return nil
            }
            if warning.isRelationCancelledSource {
                if skipCancelledSource {
                    return nil
                }
                return CapturePreviewWarningRow(
                    text: warning.message,
                    style: .cancelled,
                    accessibilityLabel: warning.message
                )
            }
            if warning.isRelationHideWarning {
                return CapturePreviewWarningRow(
                    text: warning.message,
                    style: .amber,
                    accessibilityLabel: "Warning: \(warning.message)"
                )
            }
            return nil
        }
    }

    /// Start-card warnings: every non-theme warning, with cancel-source
    /// skipped when cancel rows already show Bob's message, restyled by
    /// code otherwise.
    public static func startCardWarningRows(
        for capture: CaptureCommandSuccess
    ) -> [CapturePreviewWarningRow] {
        let skipCancelledSource = !capture.relationCancels.isEmpty
        return capture.warnings.compactMap { warning in
            if warning.isThemeNotConfigured {
                return nil
            }
            if warning.isRelationCancelledSource {
                if skipCancelledSource {
                    return nil
                }
                return CapturePreviewWarningRow(
                    text: warning.message,
                    style: .cancelled,
                    accessibilityLabel: warning.message
                )
            }
            if warning.isRelationHideWarning {
                return CapturePreviewWarningRow(
                    text: warning.message,
                    style: .amber,
                    accessibilityLabel: "Warning: \(warning.message)"
                )
            }
            return CapturePreviewWarningRow(
                text: warning.message,
                style: .amber,
                accessibilityLabel: "Warning: \(warning.message)"
            )
        }
    }

    public static func cancelCount(in captures: [CaptureCommandSuccess]) -> Int {
        captures.flatMap(\.normalizedCaptures).reduce(0) { $0 + $1.relationCancels.count }
    }

    public static func submitHint(cancelCount: Int) -> String? {
        guard cancelCount > 0 else {
            return nil
        }
        let noun = cancelCount == 1 ? "task" : "tasks"
        return "Capture & cancel \(cancelCount) \(noun)"
    }
}
