import Foundation

/// Capture-language revision the Mac requires before it will submit.
/// Grammar 2 added `%` directives; grammar 3 added glued `#drawer` capture
/// and retired attached `#type` on `+id`/`^id`. `schema_version` stays 1.
public enum CaptureGrammarGate: Sendable {
    public static let minimumRevision = 3

    /// Exact copy shown when `capture-parse` grammar is missing or too low.
    public static let blockedMessage = "Update bob to use drawers and % directives"

    /// True when Bob reported a revision this client can capture with.
    /// A missing value is incompatible: the gate cannot tell an older Bob
    /// from a failed parse.
    public static func isCompatible(_ grammar: Int?) -> Bool {
        guard let grammar else {
            return false
        }
        return grammar >= minimumRevision
    }
}
