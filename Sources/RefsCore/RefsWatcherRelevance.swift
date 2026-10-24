import CaptureCore
import Foundation

/// Refs refreshes depend on visible vault notes and reference PDFs, but
/// not on churn inside hidden vault directories such as `.git/`.
public enum RefsWatcherRelevance {
    /// Whether a watcher batch could contain an edit to a reference
    /// library document. Incomplete batches are conservatively relevant;
    /// ordinary paths must be visible and live under `lib/` or `xlib/`.
    public static func isLibraryRelevant(
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

        let roots = canonicalRoots(vaultRoot)
        for path in batch.paths {
            let eventPath = standardizedPath(path)
            guard let relativePath = relativePath(of: eventPath, under: roots) else {
                continue
            }
            let components = relativePath.split(separator: "/")
            guard !components.contains(where: { $0.hasPrefix(".") }),
                let first = components.first,
                first == "lib" || first == "xlib"
            else {
                continue
            }
            return true
        }
        return false
    }

    /// Conservatively accepts incomplete/rescan batches, paths outside the
    /// watched root, and any visible path under the vault. Hidden path
    /// components are ignored regardless of extension.
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
        guard !batch.paths.isEmpty else {
            return true
        }

        let roots = canonicalRoots(vaultRoot)

        for path in batch.paths {
            let eventPath = standardizedPath(path)
            guard let relativePath = relativePath(of: eventPath, under: roots) else {
                return true
            }
            let components = relativePath.split(separator: "/")
            if !components.contains(where: { $0.hasPrefix(".") }) {
                return true
            }
        }
        return false
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func canonicalRoots(_ vaultRoot: String) -> Set<String> {
        let configuredRoot = standardizedPath(vaultRoot)
        let resolvedRoot = standardizedPath(
            URL(fileURLWithPath: vaultRoot).resolvingSymlinksInPath().path
        )
        return Set([configuredRoot, resolvedRoot])
    }

    private static func relativePath(of path: String, under roots: Set<String>) -> String? {
        for root in roots {
            if path == root {
                return ""
            }
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if path.hasPrefix(prefix) {
                return String(path.dropFirst(prefix.count))
            }
            if root == "/", path.hasPrefix("/") {
                return String(path.dropFirst())
            }
        }
        return nil
    }
}
