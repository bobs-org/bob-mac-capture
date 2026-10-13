import Foundation

/// Pure presentation model for a refused link (`link_guard` on kind
/// `"link_guard"`, or a `task_toggle` without `toggle_direction`), built
/// once from `CaptureCommandSuccess` so the SwiftUI layer never branches
/// on guard JSON itself. Bob's `detail` sentence is shown verbatim; the
/// Mac app never decides why the link was refused.
///
/// Footer enablement does not change: submitting still runs Bob's
/// consumption. The preview is the not-linked sentence instead of a
/// generic card.
public struct CaptureLinkGuardPresentation: Equatable, Sendable {
    public let isDryRun: Bool
    /// `"Would not link"` on a dry run, `"Not linked"` once committed.
    public let headline: String
    /// SF Symbol name for the lock glyph.
    public let glyphName: String
    /// Bob's `link_guard.detail` sentence, verbatim. Empty only when Bob
    /// omitted `detail`.
    public let detail: String
    /// Promoted prerequisite identities (`route#^block`) in Bob's order.
    public let promoted: [String]
    public let notificationTitle: String
    public let notificationBody: String
    public let previewAccessibilitySummary: String

    public init?(capture: CaptureCommandSuccess) {
        guard let guard = capture.linkGuard else {
            return nil
        }
        let kind = capture.kind
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let isLinkGuardKind = kind == "link_guard"
        let isGuardedToggle = kind == "task_toggle" && capture.toggleDirection == nil
        guard isLinkGuardKind || isGuardedToggle else {
            return nil
        }

        isDryRun = capture.dryRun
        headline = capture.dryRun ? "Would not link" : "Not linked"
        glyphName = "lock.fill"
        detail = guard.detail ?? ""
        promoted = guard.promoted
        notificationTitle = "Not linked"

        var bodyLines: [String] = []
        if !detail.isEmpty {
            bodyLines.append(detail)
        }
        bodyLines.append(contentsOf: promoted)
        notificationBody = bodyLines.joined(separator: "\n")

        var previewParts = [headline]
        if !detail.isEmpty {
            previewParts.append(detail)
        }
        previewParts.append(contentsOf: promoted)
        previewAccessibilitySummary = previewParts.joined(separator: ", ")
    }
}
