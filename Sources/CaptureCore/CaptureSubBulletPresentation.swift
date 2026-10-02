import Foundation

/// Pure wording for a `sub_bullet` capture item whose parent task renders
/// as a batch-level card. Nil for every other kind, so the standard item
/// keeps its wire-word header and verbatim stack. The header says _what_
/// the item did; the card says _where_ it landed.
public struct CaptureSubBulletPresentation: Equatable, Sendable {
    /// `"^capture"` for a parent with a block ID, `"task"` without one,
    /// for the status and summary strings.
    public let parentLabel: String
    /// `"under ^capture"`, `"under ^capture › REQUIREMENTS"`, or
    /// `"under task"`, following the compact item header.
    public let headerDetail: String
    /// VoiceOver phrase for the compact header.
    public let accessibilityText: String

    /// Nil unless the capture is a sub-bullet capture.
    public init?(capture: CaptureCommandSuccess) {
        let kind =
            capture.kind
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        guard kind == "sub_bullet" else {
            return nil
        }
        if let blockID = capture.blockID, !blockID.isEmpty {
            parentLabel = "^\(blockID)"
        } else {
            parentLabel = "task"
        }
        if let section = capture.parentSection, !section.isEmpty {
            headerDetail = "under \(parentLabel) › \(section)"
            accessibilityText = "Sub-bullet under \(parentLabel), in \(section)"
        } else {
            headerDetail = "under \(parentLabel)"
            accessibilityText = "Sub-bullet under \(parentLabel)"
        }
    }
}
