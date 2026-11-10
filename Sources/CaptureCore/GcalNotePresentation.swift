import Foundation

/// Highlight roles for private event-note spans. Unknown kinds stay
/// neutral: the painter must not invent a semantic color for them.
public enum GcalNoteHighlightRole: Equatable, Sendable {
    case route
    case root
    case clock
    case buffer
    case reasonSign
    case reason
    case prose
    case unknown
}

/// Display strings and live-preview selection for Event note mode. Bob
/// remains the authority for parsing, validation, and task fields; this
/// type only chooses which returned objects to show.
public enum GcalNotePresentation {
    public struct LivePreview: Equatable, Sendable {
        public let preview: GcalNotePreview?
        public let effective: GcalNoteEffective?
        public let spans: [GcalNoteSpan]
        public let errors: [GcalNoteIssue]
        public let warnings: [String]
        public let isCurrent: Bool
        public let isPending: Bool
        public let isInvalid: Bool
        public let statusLabel: String?
        public let errorMessage: String?

        public init(
            preview: GcalNotePreview?,
            effective: GcalNoteEffective?,
            spans: [GcalNoteSpan],
            errors: [GcalNoteIssue],
            warnings: [String],
            isCurrent: Bool,
            isPending: Bool,
            isInvalid: Bool,
            statusLabel: String?,
            errorMessage: String?
        ) {
            self.preview = preview
            self.effective = effective
            self.spans = spans
            self.errors = errors
            self.warnings = warnings
            self.isCurrent = isCurrent
            self.isPending = isPending
            self.isInvalid = isInvalid
            self.statusLabel = statusLabel
            self.errorMessage = errorMessage
        }
    }

    public static func highlightRole(forKind kind: String) -> GcalNoteHighlightRole {
        switch kind {
        case "route": .route
        case "root": .root
        case "clock": .clock
        case "buffer": .buffer
        case "reason_sign": .reasonSign
        case "reason": .reason
        case "prose": .prose
        default: .unknown
        }
    }

    public static func matchingWrite(
        _ response: GcalNoteWriteResponse?,
        text: String
    ) -> GcalNoteWriteResponse? {
        guard let response, response.input?.text == text else {
            return nil
        }
        return response
    }

    public static func livePreview(
        editorText: String,
        isDirty: Bool,
        phase: GcalNoteSession.Phase,
        show: GcalNoteShowResponse?,
        preview: GcalNoteWriteResponse?,
        lastValid: GcalNoteWriteResponse?,
        previewError: String?
    ) -> LivePreview {
        let matching = matchingWrite(preview, text: editorText)
        let matchingValid = matching.flatMap { $0.ok ? $0 : nil }
        let retained = matchingWrite(lastValid, text: editorText) ?? lastValid
        let pending = phase == .previewPending
        if let matchingValid {
            return LivePreview(
                preview: matchingValid.preview,
                effective: matchingValid.effective,
                spans: matchingValid.spans,
                errors: matchingValid.errors,
                warnings: matchingValid.warnings,
                isCurrent: true,
                isPending: pending,
                isInvalid: false,
                statusLabel: pending ? "Updating preview…" : nil,
                errorMessage: nil
            )
        }
        if let matching, !matching.ok {
            return LivePreview(
                preview: retained?.preview ?? show?.preview,
                effective: retained?.effective ?? show?.effective,
                spans: matching.spans,
                errors: matching.errors,
                warnings: matching.warnings,
                isCurrent: false,
                isPending: pending,
                isInvalid: true,
                statusLabel: "This note is invalid",
                errorMessage: matching.error?.message
                    ?? matching.errors.first?.message
                    ?? previewError
            )
        }
        if !isDirty, let show {
            return LivePreview(
                preview: show.preview,
                effective: show.effective,
                spans: [],
                errors: [],
                warnings: show.warnings,
                isCurrent: true,
                isPending: pending,
                isInvalid: false,
                statusLabel: pending ? "Updating preview…" : nil,
                errorMessage: nil
            )
        }
        let retainedPreview = retained?.ok == true ? retained : nil
        let status: String?
        if pending {
            status = "Updating preview…"
        } else if previewError != nil {
            status = "Showing the last valid preview"
        } else {
            status = retainedPreview == nil ? nil : "Showing the last valid preview"
        }
        return LivePreview(
            preview: retainedPreview?.preview ?? show?.preview,
            effective: retainedPreview?.effective ?? show?.effective,
            spans: [],
            errors: [],
            warnings: matching?.warnings ?? preview?.warnings ?? show?.warnings ?? [],
            isCurrent: false,
            isPending: pending,
            isInvalid: previewError != nil,
            statusLabel: status,
            errorMessage: previewError
        )
    }

    public static func answerLabel(_ answer: String?) -> String? {
        switch answer?.lowercased() {
        case "yes", "accepted": "Yes"
        case "maybe", "tentative": "Maybe"
        case "no_reply", "needs_action", "awaiting_reply": "Awaiting reply"
        case "no", "declined": "No"
        default: nil
        }
    }

    public static func organizerLabel(for event: GcalNoteEvent) -> String {
        if let name = nonBlank(event.organizer?.name) {
            return name
        }
        if let calendar = nonBlank(event.calendarName) {
            return calendar
        }
        return "Calendar"
    }

    public static func identitySubtitle(for event: GcalNoteEvent) -> String {
        [event.day, event.time].compactMap { nonBlank($0) }.joined(separator: " · ")
    }

    public static func scopeLabel(_ scope: GcalNoteScope) -> String {
        switch scope {
        case .series: "All events"
        default: "This event"
        }
    }

    public static func footerOwnership(scope: GcalNoteScope) -> String {
        "Only in Bob · \(scopeLabel(scope))"
    }

    public static func footerKeys(recurring: Bool, canUndo: Bool) -> String {
        var parts = ["⏎ Save", "⇧⏎ New line", "⌘⌫ Clear", "⎋ Back"]
        if recurring {
            parts.append("⌃⌥S Scope")
        }
        if canUndo {
            parts.append("⌘Z Undo last save")
        }
        return parts.joined(separator: " · ")
    }

    public static func statusBannerText(
        _ status: GcalNoteStatus?,
        action: String? = nil
    ) -> String? {
        guard let status else { return nil }
        let actionLabel: String?
        switch action?.lowercased() {
        case "saved": actionLabel = "Saved"
        case "cleared": actionLabel = "Cleared"
        case "unchanged": actionLabel = "Unchanged"
        default: actionLabel = nil
        }
        if let detail = nonBlank(status.detail) {
            if let actionLabel,
                detail.lowercased().hasPrefix(actionLabel.lowercased()),
                detail.dropFirst(actionLabel.count).first.map({
                    !$0.isLetter && !$0.isNumber
                }) ?? true
            {
                return capitalizeFirst(detail)
            }
            if let actionLabel {
                return "\(actionLabel) · \(detail)"
            }
            return detail
        }
        return actionLabel ?? status.state
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Lands-as copy. A null preview row is a waiting/status explanation,
    /// never a fabricated Event Task.
    public static func landsExplanation(
        event: GcalNoteEvent,
        preview: GcalNotePreview?
    ) -> String {
        if let row = nonBlank(preview?.row) {
            return row
        }
        switch (event.lands ?? event.answer)?.lowercased() {
        case "waiting_reply", "no_reply", "needs_action", "awaiting_reply":
            return "Waiting for a reply — this invitation has no Event Task yet."
        case "waiting_maybe", "maybe", "tentative":
            return "Waiting — a Maybe RSVP has no Event Task yet."
        default:
            return "No Event Task row yet."
        }
    }

    public static func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
