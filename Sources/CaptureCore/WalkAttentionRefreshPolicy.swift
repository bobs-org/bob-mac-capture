import Foundation

/// Pure refresh policy for the walks attention lane. The walks scan is
/// whole-vault, so debouncing keeps active Obsidian typing from spawning
/// back-to-back scans, while show-time revalidation and the 60 s age bound
/// catch config edits outside the vault.
///
/// Concurrency reuses `CaptureAgendaRefreshState`'s single-flight machine
/// (one refresh in flight with at most one follow-up): it is snapshot
/// agnostic except for its agenda date guard, and the walks date guard
/// below covers `WalkAttentionSnapshot`. The store holds one agenda state
/// and one walks state side by side.
public enum WalkAttentionRefreshPolicy {
    /// A shown panel with a last success this old (or older) refreshes
    /// instead of painting the cache.
    public static let showStaleAfter: TimeInterval = 60
    /// Trailing debounce after a relevant vault event while visible.
    public static let visibleDebounce: TimeInterval = 2
    /// Trailing debounce after a relevant vault event while hidden.
    public static let hiddenDebounce: TimeInterval = 10

    /// True when showing the panel must spawn a refresh: the cache is
    /// dirty, nothing has ever succeeded, or the last success is older
    /// than `showStaleAfter`. Otherwise the panel paints the cached marks
    /// and spawns nothing.
    public static func shouldRefreshOnShow(
        dirty: Bool,
        lastSuccess: Date?,
        now: Date
    ) -> Bool {
        if dirty {
            return true
        }
        guard let lastSuccess else {
            return true
        }
        return now.timeIntervalSince(lastSuccess) >= showStaleAfter
    }

    /// Trailing debounce for a relevant vault event. Uses the same
    /// relevance filter as the agenda (`CaptureAgendaRefreshFilter`).
    public static func debounceInterval(visible: Bool) -> TimeInterval {
        visible ? visibleDebounce : hiddenDebounce
    }
}

extension CaptureAgendaRefreshState {
    /// The walks date guard: a snapshot whose `date` is not today is never
    /// shown. A missing date never counts as today.
    public func isCurrent(_ snapshot: WalkAttentionSnapshot) -> Bool {
        guard let date = snapshot.date else {
            return false
        }
        return date == today()
    }
}
