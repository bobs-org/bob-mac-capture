import CaptureCore
import Foundation

/// The narrow key rule used to notice a user's Highlights save without
/// taking or changing the event.
public enum HighlightsSaveKey {
    /// Returns true for a non-repeating Command-S with no other primary
    /// modifier. Caps Lock, Fn, and keypad flags are intentionally omitted.
    public static func matches(
        charactersIgnoringModifiers: String?,
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool,
        isARepeat: Bool
    ) -> Bool {
        guard let charactersIgnoringModifiers,
            charactersIgnoringModifiers.lowercased() == "s",
            command,
            !shift,
            !option,
            !control,
            !isARepeat
        else {
            return false
        }
        return true
    }
}

/// Decides whether a frontmost Highlights document belongs to the
/// reference library. A nil or empty path means Accessibility could not
/// identify the current document and returns nil.
public enum HighlightsSaveScanScope {
    public static func isLibraryDocument(path: String?, vaultRoot: String) -> Bool? {
        guard let path, !path.isEmpty else {
            return nil
        }
        let document = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            .standardizedFileURL.path
        let configuredRoot = URL(fileURLWithPath: vaultRoot).standardizedFileURL.path
        let resolvedRoot = URL(fileURLWithPath: vaultRoot).resolvingSymlinksInPath()
            .standardizedFileURL.path

        for root in Set([configuredRoot, resolvedRoot]) {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            guard document.hasPrefix(prefix) else {
                continue
            }
            let relative = document.dropFirst(prefix.count)
            let components = relative.split(separator: "/")
            guard !components.contains(where: { $0.hasPrefix(".") }),
                let first = components.first
            else {
                return false
            }
            return first == "lib" || first == "xlib"
        }
        return false
    }
}

/// A value-only trigger for a scan following a user's save in Highlights.
/// The caller owns its timer and supplies every event time explicitly.
public struct HighlightsSaveScanTrigger: Equatable, Sendable {
    public static let quietInterval: TimeInterval = 1.0
    public static let fallbackInterval: TimeInterval = 2.5
    public static let maximumInterval: TimeInterval = 10.0

    private let vaultRoot: String
    private var firstKeyAt: Date?
    private var latestKeyAt: Date?
    private var lastLibraryChangeAt: Date?

    public init(vaultRoot: String) {
        self.vaultRoot = vaultRoot
    }

    public var isArmed: Bool {
        firstKeyAt != nil
    }

    /// The next time at which a poll may fire the one scan for this cycle.
    public var nextDeadline: Date? {
        guard let firstKeyAt else {
            return nil
        }
        let cap = firstKeyAt.addingTimeInterval(Self.maximumInterval)
        let settle = lastLibraryChangeAt.map {
            $0.addingTimeInterval(Self.quietInterval)
        } ?? latestKeyAt?.addingTimeInterval(Self.fallbackInterval)
        guard let settle else {
            return cap
        }
        return min(settle, cap)
    }

    /// Arms a cycle or coalesces another save into the existing cycle.
    /// Repeated saves extend only the no-change fallback, never the cap.
    public mutating func keyPressed(at date: Date) {
        if firstKeyAt == nil {
            firstKeyAt = date
        }
        latestKeyAt = date
    }

    /// Records a visible library edit while a save cycle is armed.
    public mutating func libraryChanged(_ batch: VaultChangeBatch, at date: Date) {
        guard isArmed,
            RefsWatcherRelevance.isLibraryRelevant(batch, vaultRoot: vaultRoot)
        else {
            return
        }
        lastLibraryChangeAt = date
    }

    /// Clears the cycle without firing it.
    public mutating func disarm() {
        firstKeyAt = nil
        latestKeyAt = nil
        lastLibraryChangeAt = nil
    }

    /// Fires once when the quiet period, fallback, or hard cap is reached.
    public mutating func poll(at date: Date) -> Bool {
        guard let deadline = nextDeadline, date >= deadline else {
            return false
        }
        disarm()
        return true
    }

}
