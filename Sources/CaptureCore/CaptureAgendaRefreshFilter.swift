import Foundation

/// Aggregated FSEvents flags for one vault change batch, in vault-neutral
/// terms so the relevance filter stays pure and testable on Linux. The
/// watcher maps each `FSEventStreamEventFlags` value onto this set and
/// ORs them across its trailing debounce window.
public struct VaultChangeFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// `kFSEventStreamEventFlagMustScanSubDirs`: rescan everything.
    public static let mustScanSubDirs = Self(rawValue: 1 << 0)
    /// `kFSEventStreamEventFlagRootChanged`: the watched root moved.
    public static let rootChanged = Self(rawValue: 1 << 1)
    /// `kFSEventStreamEventFlagKernelDropped`: the kernel dropped events.
    public static let kernelDropped = Self(rawValue: 1 << 2)
    /// `kFSEventStreamEventFlagUserDropped`: the user space dropped events.
    public static let userDropped = Self(rawValue: 1 << 3)
    /// `kFSEventStreamEventFlagItemRenamed`: a path was renamed.
    public static let itemRenamed = Self(rawValue: 1 << 4)
    /// `kFSEventStreamEventFlagItemRemoved`: a path was removed.
    public static let itemRemoved = Self(rawValue: 1 << 5)
    /// `kFSEventStreamEventFlagItemIsDir`: the event targets a directory.
    public static let itemIsDir = Self(rawValue: 1 << 6)
}

/// One debounced vault change batch: the union of changed paths plus the
/// OR of their flags. The targets cache refreshes on every batch; the
/// agenda store refreshes only when the relevance filter accepts it.
public struct VaultChangeBatch: Equatable, Sendable {
    public var paths: [String]
    public var flags: VaultChangeFlags

    public init(
        paths: [String] = [],
        flags: VaultChangeFlags = []
    ) {
        self.paths = paths
        self.flags = flags
    }
}

/// Pure relevance filter for agenda refreshes: most vault writes (git
/// internals, workspace state, attachments) never touch the ledger, so
/// they must not spawn `bob capture-pomodoros --tasks`.
public enum CaptureAgendaRefreshFilter {
    /// Vault-relative path of the Tasks plugin global filter: the one
    /// dotfile whose changes can renumber or hide agenda tasks.
    public static let tasksFilterRelativePath =
        ".obsidian/plugins/obsidian-tasks-plugin/data.json"

    /// True when the batch can change what the agenda shows:
    /// - the stream says rescan, root-changed, or dropped events;
    /// - a directory under the vault was renamed or removed (folder
    ///   moves change basename resolution);
    /// - a visible `.md` note changed (no path component starts with
    ///   `.`, so `.git/`, `.trash/`, and `.obsidian/workspace*.json`
    ///   stay ignored);
    /// - the Tasks plugin global filter changed.
    public static func isRelevant(
        _ batch: VaultChangeBatch,
        vaultRoot: String
    ) -> Bool {
        let flags = batch.flags
        if flags.contains(.mustScanSubDirs)
            || flags.contains(.rootChanged)
            || flags.contains(.kernelDropped)
            || flags.contains(.userDropped)
        {
            return true
        }
        if flags.contains(.itemIsDir)
            && (flags.contains(.itemRenamed)
                || flags.contains(.itemRemoved))
        {
            return true
        }
        let prefix =
            vaultRoot.hasSuffix("/") ? vaultRoot : vaultRoot + "/"
        for path in batch.paths {
            guard path.hasPrefix(prefix) else {
                continue
            }
            let relative = String(path.dropFirst(prefix.count))
            if relative == tasksFilterRelativePath {
                return true
            }
            guard relative.hasSuffix(".md") else {
                continue
            }
            let hidden = relative.split(separator: "/").contains {
                $0.hasPrefix(".")
            }
            if hidden {
                continue
            }
            return true
        }
        return false
    }
}
