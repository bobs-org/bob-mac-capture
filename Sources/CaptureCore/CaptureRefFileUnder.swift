import Foundation

/// Pure File-under picker logic for a bare-URL reference draft (`mode == "ref"`).
///
/// Bob remains the only implementation of capture grammar, preview, and vault
/// mutation: the panel opens this picker only when `bob capture-parse` reports
/// `ref_parent.source == "default"` for a single-item draft whose dry-run
/// library verdict will queue the link, inserts the chosen canonical route as
/// ` @<route>` through the existing draft/analysis pattern, and renders the
/// destination Bob's dry run reports. Nothing here parses grammar, computes a
/// preview, or writes the vault.
public enum CaptureRefFileUnder {
    /// The picker's header, rendered above the route rows.
    public static let headerTitle = "File under"

    /// Library verdicts whose dry run queues a new ref job (and therefore
    /// need a parent choice). Library hits never open the picker.
    public static let queueableVerdicts: Set<String> = ["not_found", "legacy", "unknown"]

    /// Whether the File-under list opens on its own for this analysis.
    ///
    /// - `parseMode`: `capture-parse` top-level `mode` (`"ref"` for a bare URL).
    /// - `refParentSource`: `capture-parse` `ref_parent.source`
    ///   (`"explicit"`|`"global"`|`"default"`, nil for older Bob).
    /// - `itemCount`: number of capture items Bob reports (1 for a single
    ///   bare URL; batches never auto-open, including blank-line-free
    ///   multi-URL pastes, which Bob splits one item per line).
    /// - `verdict`: the dry-run `ref.library.verdict` (nil while the dry run
    ///   is still in flight, which never auto-opens).
    /// - `urlChangedSinceDismissal`: false after Esc dismissed the list for
    ///   this exact URL (the list does not reopen until the URL changes).
    public static func shouldAutoOpen(
        parseMode: String,
        refParentSource: String?,
        itemCount: Int,
        verdict: String?,
        urlChangedSinceDismissal: Bool
    ) -> Bool {
        guard parseMode == "ref" else {
            return false
        }
        guard refParentSource == "default" else {
            return false
        }
        guard itemCount == 1 else {
            return false
        }
        guard let verdict, queueableVerdicts.contains(verdict) else {
            return false
        }
        return urlChangedSinceDismissal
    }

    /// Whether one query string matches a target, aliases included.
    /// Case-insensitive; `-` and `_` stay distinct characters.
    public static func matches(target: CaptureTarget, query: String) -> Bool {
        let folded = query.lowercased()
        guard !folded.isEmpty else {
            return true
        }
        if target.route.lowercased().contains(folded) {
            return true
        }
        if target.label.lowercased().contains(folded) {
            return true
        }
        if target.name.lowercased().contains(folded) {
            return true
        }
        return target.projectNameAliases.contains { $0.lowercased().contains(folded) }
    }

    /// Display name for a File-under row: `"bob · aka bob-cli"` when the
    /// note claims aliases, else the plain route.
    public static func displayName(for target: CaptureTarget) -> String {
        let aliases = target.projectNameAliases.filter { !$0.isEmpty }
        guard !aliases.isEmpty else {
            return target.route
        }
        return "\(target.route) · aka \(aliases.joined(separator: ", "))"
    }

    /// The draft splice accepting a row performs: ` @<route>` appended at
    /// the end of the draft (the canonical route, never the alias).
    public static func insertionText(route: String) -> String {
        " @\(route)"
    }

    /// Order the cached inbox, area, and project targets for the picker:
    /// the last-used parent first, then `mac_inbox`, then the cache order.
    /// Missing entries are skipped, never duplicated.
    public static func orderedTargets(
        _ targets: [CaptureTarget],
        lastUsedParent: String?
    ) -> [CaptureTarget] {
        var ordered: [CaptureTarget] = []
        var seen = Set<String>()
        func append(_ route: String) {
            guard !route.isEmpty, seen.insert(route).inserted,
                  let target = targets.first(where: { $0.route == route })
            else {
                return
            }
            ordered.append(target)
        }
        if let lastUsedParent, !lastUsedParent.isEmpty {
            append(lastUsedParent)
        }
        append("mac_inbox")
        for target in targets where seen.insert(target.route).inserted {
            ordered.append(target)
        }
        return ordered
    }

    /// Rank filtered targets for a typed query, preserving the input
    /// order inside each bucket: canonical prefix matches (route, label,
    /// or name) first, then alias-prefix matches, then every other
    /// substring match (aliases included). An empty query keeps the input
    /// order. Callers that reorder (File under's last-used-first list)
    /// sort with `orderedTargets` before calling.
    public static func rankedTargets(
        _ targets: [CaptureTarget],
        query: String
    ) -> [CaptureTarget] {
        let folded = query.lowercased()
        guard !folded.isEmpty else {
            return targets
        }
        let filtered = targets.filter { matches(target: $0, query: query) }
        let prefix = filtered.filter { target in
            target.route.lowercased().hasPrefix(folded)
                || target.label.lowercased().hasPrefix(folded)
                || target.name.lowercased().hasPrefix(folded)
        }
        let alias = filtered.filter { target in
            !prefix.contains(target)
                && target.projectNameAliases.contains { $0.lowercased().hasPrefix(folded) }
        }
        let rest = filtered.filter { !prefix.contains($0) && !alias.contains($0) }
        return prefix + alias + rest
    }

    /// Whether a typed query names an alias of exactly one target (used to
    /// hint the canonical route before accept).
    public static func aliasOwner(
        _ targets: [CaptureTarget],
        query: String
    ) -> CaptureTarget? {
        let folded = query.lowercased()
        guard !folded.isEmpty else {
            return nil
        }
        let owners = targets.filter { target in
            target.projectNameAliases.contains { $0.lowercased() == folded }
        }
        return owners.count == 1 ? owners[0] : nil
    }
}
