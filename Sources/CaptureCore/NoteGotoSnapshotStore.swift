import Foundation

/// One trusted `note_goto` snapshot: Bob's read-only note rows plus the
/// catalog metadata that produced them. The store only ever holds a
/// snapshot whose response context was `note_goto`; callers enforce that
/// by storing only validated responses.
public struct NoteGotoSnapshot: Equatable, Sendable {
    public let candidates: [CaptureCompletionCandidate]
    public let noteGoto: CaptureCompletionNoteGoto
    public let bobIdentity: String
    public let fetchedAt: Date

    public init(
        candidates: [CaptureCompletionCandidate],
        noteGoto: CaptureCompletionNoteGoto,
        bobIdentity: String,
        fetchedAt: Date = Date()
    ) {
        self.candidates = candidates
        self.noteGoto = noteGoto
        self.bobIdentity = bobIdentity
        self.fetchedAt = fetchedAt
    }
}

/// App-memory cache for the last good `note_goto` rows. It is never
/// persisted and never logged: on continuation (`/` → `//`) the store's
/// rows render immediately while the real `//` analysis revalidates, and
/// the `/` session's task rows are retained separately for the peel back.
/// A snapshot is trusted only for the bob identity that produced it and
/// only while fresh; a stale snapshot still renders (stale-while-revalidate)
/// but always triggers a background refetch.
public struct NoteGotoSnapshotStore: Equatable, Sendable {
    private var snapshot: NoteGotoSnapshot?
    /// Freshness horizon for silent use. A snapshot older than this still
    /// renders, but every render path refetches while it is showing.
    public var stalenessInterval: TimeInterval

    public init(stalenessInterval: TimeInterval = 300) {
        self.stalenessInterval = stalenessInterval
    }

    public var isEmpty: Bool {
        snapshot == nil
    }

    /// Records a validated `note_goto` response. Call only after the
    /// response context, scope token, and marker range checks pass.
    public mutating func store(
        candidates: [CaptureCompletionCandidate],
        noteGoto: CaptureCompletionNoteGoto,
        bobIdentity: String,
        now: Date = Date()
    ) {
        guard !noteGoto.archived else {
            return
        }
        snapshot = NoteGotoSnapshot(
            candidates: candidates,
            noteGoto: noteGoto,
            bobIdentity: bobIdentity,
            fetchedAt: now
        )
    }

    public mutating func invalidate() {
        snapshot = nil
    }

    /// The snapshot for immediate rendering, or nil when there is nothing
    /// to show (empty, or produced by a different bob identity).
    public func rows(
        bobIdentity: String,
        now: Date = Date()
    ) -> NoteGotoSnapshot? {
        guard let snapshot, snapshot.bobIdentity == bobIdentity else {
            return nil
        }
        return snapshot
    }

    /// True when the stored snapshot should be refetched in the background:
    /// empty, from another bob identity, or older than the horizon.
    public func needsRefresh(bobIdentity: String, now: Date = Date()) -> Bool {
        guard let snapshot else {
            return true
        }
        guard snapshot.bobIdentity == bobIdentity else {
            return true
        }
        return now.timeIntervalSince(snapshot.fetchedAt) >= stalenessInterval
    }

    /// True when the structured content differs, so a revalidation must
    /// replace the rendered rows. Order matters: Bob's canonical order is
    /// part of the contract.
    public static func contentDiffers(
        _ left: NoteGotoSnapshot,
        candidates: [CaptureCompletionCandidate],
        noteGoto: CaptureCompletionNoteGoto
    ) -> Bool {
        left.candidates != candidates || left.noteGoto != noteGoto
    }
}

extension NoteGotoSnapshotStore {
    /// Vault batches that can change the living-notes catalog: a stream
    /// rescan, root change, or dropped events; or any visible `.md` note
    /// write (no path component starts with `.`, so `.git/`, `.trash/`,
    /// and `.obsidian/workspace` churn stays ignored). Dot-directories and
    /// non-note files never invalidate the warm snapshot.
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
        let prefix = vaultRoot.hasSuffix("/") ? vaultRoot : vaultRoot + "/"
        for path in batch.paths {
            let relative =
                path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
            let components = relative.split(separator: "/")
            guard !components.isEmpty,
                  !components.contains(where: { $0.hasPrefix(".") })
            else {
                continue
            }
            guard let last = components.last else {
                continue
            }
            if last.hasSuffix(".md") || last.hasSuffix(".base") {
                return true
            }
        }
        return false
    }
}
