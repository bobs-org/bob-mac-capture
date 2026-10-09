import CaptureCore
import CoreServices
import Foundation

extension VaultChangeFlags {
    /// Maps one `FSEventStreamEventFlags` word onto the vault-neutral
    /// batch flags the agenda relevance filter reads.
    init(fsEvents: FSEventStreamEventFlags) {
        var mapped = VaultChangeFlags()
        if fsEvents & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
            mapped.insert(.mustScanSubDirs)
        }
        if fsEvents & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            mapped.insert(.rootChanged)
        }
        if fsEvents & FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped) != 0 {
            mapped.insert(.kernelDropped)
        }
        if fsEvents & FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped) != 0 {
            mapped.insert(.userDropped)
        }
        if fsEvents & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
            mapped.insert(.itemRenamed)
        }
        if fsEvents & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
            mapped.insert(.itemRemoved)
        }
        if fsEvents & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 {
            mapped.insert(.itemIsDir)
        }
        self = mapped
    }
}

final class VaultTargetWatcher {
    private let paths: [String]
    private let latency: TimeInterval
    private let onChange: () -> Void
    private let onBatch: (VaultChangeBatch) -> Void
    private let onFailure: (String) -> Void
    private let queue = DispatchQueue(label: "org.bobs.bob-mac-capture.vault-watcher")
    private var stream: FSEventStreamRef?
    private var pendingRefresh: DispatchWorkItem?
    private var pendingPaths = Set<String>()
    private var pendingFlags = VaultChangeFlags()

    init(
        paths: [String],
        latency: TimeInterval = 0.3,
        onChange: @escaping () -> Void,
        onBatch: @escaping (VaultChangeBatch) -> Void = { _ in },
        onFailure: @escaping (String) -> Void
    ) {
        self.paths = paths
        self.latency = latency
        self.onChange = onChange
        self.onBatch = onBatch
        self.onFailure = onFailure
    }

    convenience init(
        path: String,
        latency: TimeInterval = 0.3,
        onChange: @escaping () -> Void,
        onBatch: @escaping (VaultChangeBatch) -> Void = { _ in },
        onFailure: @escaping (String) -> Void
    ) {
        self.init(
            paths: [path],
            latency: latency,
            onChange: onChange,
            onBatch: onBatch,
            onFailure: onFailure
        )
    }

    deinit {
        invalidate()
    }

    func start() {
        let watched = paths.filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        guard !watched.isEmpty else {
            onFailure("Vault path is not available: \(paths.joined(separator: ", "))")
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        let callback: FSEventStreamCallback = {
            _, info, eventCount, eventPaths, eventFlags, _ in
            guard let info else {
                return
            }
            let watcher = Unmanaged<VaultTargetWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleRefresh(
                paths: VaultTargetWatcher.eventPaths(eventPaths, count: eventCount),
                flags: VaultTargetWatcher.eventFlags(eventFlags, count: eventCount)
            )
        }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            watched as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            onFailure("Unable to create a vault watcher for \(watched.joined(separator: ", "))")
            return
        }

        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            onFailure("Unable to start a vault watcher for \(watched.joined(separator: ", "))")
            return
        }

        stream = created
    }

    func invalidate() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        pendingPaths.removeAll()
        pendingFlags = VaultChangeFlags()

        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Reads one callback's paths out of the `UseCFTypes` array. The
    /// array is only valid for the callback's duration, so this takes it
    /// unretained and copies the strings out before returning.
    private static func eventPaths(
        _ raw: UnsafeMutableRawPointer?,
        count: Int
    ) -> [String] {
        guard count > 0, let raw else {
            return []
        }
        let bridged = Unmanaged<NSArray>.fromOpaque(raw)
            .takeUnretainedValue() as? [String] ?? []
        return Array(bridged.prefix(count))
    }

    /// ORs one callback's per-event flags into the batch flags.
    private static func eventFlags(
        _ raw: UnsafePointer<FSEventStreamEventFlags>?,
        count: Int
    ) -> VaultChangeFlags {
        guard count > 0, let raw else {
            return VaultChangeFlags()
        }
        var mapped = VaultChangeFlags()
        for index in 0..<count {
            mapped.formUnion(VaultChangeFlags(fsEvents: raw[index]))
        }
        return mapped
    }

    private func scheduleRefresh(paths: [String], flags: VaultChangeFlags) {
        pendingPaths.formUnion(paths)
        pendingFlags.formUnion(flags)
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.deliverBatch()
        }
        pendingRefresh = item
        queue.asyncAfter(deadline: .now() + latency, execute: item)
    }

    /// Delivers one batch per debounce window: the union of paths and the
    /// OR of flags. The targets cache refreshes on every batch exactly as
    /// before; the batch also feeds the agenda relevance filter.
    private func deliverBatch() {
        let batch = VaultChangeBatch(
            paths: pendingPaths.sorted(),
            flags: pendingFlags
        )
        pendingPaths.removeAll()
        pendingFlags = VaultChangeFlags()
        onChange()
        onBatch(batch)
    }
}
