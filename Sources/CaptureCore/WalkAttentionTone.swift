import Foundation

/// Tier hues for the walk attention marks. Mirrors the Obsidian
/// `data-attention-tier` CSS on the default palette (nav's bracket-mode
/// indicator), so the idle agenda's `s`/`w`/`b` dots match the selector.
/// Vault CSS-snippet overrides are not mirrored: bob reports the tier and
/// the app paints the stock hue. Unknown tiers return nil and the view
/// falls back to the accent color.
public enum WalkAttentionTone {
    /// Light-mode hex for a walks tier, or nil for an unknown tier.
    public static func lightHex(for tier: String) -> String? {
        switch tier {
        case "pre": return "#00bfbc"
        case "new": return WorkBadgeTone.red.lightHex
        case "projects": return "#7852ee"
        case "pending": return WorkBadgeTone.yellow.lightHex
        case "next": return WorkBadgeTone.green.lightHex
        case "recurring": return "#d53984"
        case "tickler": return WorkBadgeTone.blue.lightHex
        case "over": return WorkBadgeTone.red.lightHex
        case "waiting": return WorkBadgeTone.orange.lightHex
        default: return nil
        }
    }

    /// Dark-mode hex for a walks tier, or nil for an unknown tier.
    public static func darkHex(for tier: String) -> String? {
        switch tier {
        case "pre": return "#53dfdd"
        case "new": return WorkBadgeTone.red.darkHex
        case "projects": return "#a882ff"
        case "pending": return WorkBadgeTone.yellow.darkHex
        case "next": return WorkBadgeTone.green.darkHex
        case "recurring": return "#fa99cd"
        case "tickler": return WorkBadgeTone.blue.darkHex
        case "over": return WorkBadgeTone.red.darkHex
        case "waiting": return WorkBadgeTone.orange.darkHex
        default: return nil
        }
    }
}
