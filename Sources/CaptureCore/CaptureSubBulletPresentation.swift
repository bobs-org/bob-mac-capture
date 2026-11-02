import Foundation

/// Pure wording for a `sub_bullet` capture item whose parent task renders
/// as a batch-level card. Nil for every other kind, so the standard item
/// keeps its wire-word header and verbatim stack. The header says _what_
/// the item did; the card says _where_ it landed.
public struct CaptureSubBulletPresentation: Equatable, Sendable {
    public struct DrawerCapsule: Equatable, Sendable, Identifiable {
        public let title: String
        public let creates: Bool

        public var id: String { title }
    }

    /// Capsule text for a drawer the commit creates.
    public static let newDrawerBadge = "new drawer"

    /// `"^capture"` for a parent with a block ID, `"task"` without one,
    /// for the status and summary strings.
    public let parentLabel: String
    /// `"under ^capture"`, `"under ^capture › REQUIREMENTS"`, or
    /// `"under task"`, following the compact item header.
    public let headerDetail: String
    /// The drawer the bullet lands in, from Bob's per-item `drawer` object.
    public let drawerTitle: String?
    /// True when Bob says the commit creates the drawer; the header then shows a
    /// `new drawer` capsule after `headerDetail`.
    public let createsDrawer: Bool
    /// VoiceOver phrase for the compact header.
    public let accessibilityText: String
    /// Number of notes when Bob returned the additive multi-note summary.
    /// Nil keeps the legacy one-note header unchanged.
    public let noteCount: Int?
    /// Drawers a multi-note item touched, in Bob's first-touch order.
    public let drawerCapsules: [DrawerCapsule]
    public var isMultiNote: Bool { noteCount != nil }

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
        if let notes = capture.notes {
            let count = notes.count
            let drawers = (capture.drawers ?? []).map {
                DrawerCapsule(title: $0.title, creates: $0.created)
            }
            noteCount = count
            drawerCapsules = drawers
            drawerTitle = nil
            createsDrawer = false
            headerDetail = "\(count) note\(count == 1 ? "" : "s") under \(parentLabel)"
            let locations = drawers.map { drawer in
                drawer.creates ? "new drawer \(drawer.title)" : drawer.title
            }
            let suffix = locations.isEmpty ? "" : ", in \(Self.join(locations))"
            accessibilityText =
                "\(count) note\(count == 1 ? "" : "s") under \(parentLabel)\(suffix)"
            return
        }
        noteCount = nil
        drawerCapsules = []
        if let drawer = capture.drawer?.title, !drawer.isEmpty {
            let created = capture.drawer?.created ?? false
            drawerTitle = drawer
            createsDrawer = created
            headerDetail = "under \(parentLabel) › \(drawer)"
            accessibilityText =
                created
                ? "Sub-bullet under \(parentLabel), in new drawer \(drawer)"
                : "Sub-bullet under \(parentLabel), in \(drawer)"
        } else {
            drawerTitle = nil
            createsDrawer = false
            headerDetail = "under \(parentLabel)"
            accessibilityText = "Sub-bullet under \(parentLabel)"
        }
    }

    private static func join(_ values: [String]) -> String {
        switch values.count {
        case 0: return ""
        case 1: return values[0]
        case 2: return "\(values[0]) and \(values[1])"
        default:
            return "\(values.dropLast().joined(separator: ", ")), and \(values[values.count - 1])"
        }
    }
}
