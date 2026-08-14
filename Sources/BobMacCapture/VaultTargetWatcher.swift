import CoreServices
import Foundation

final class VaultTargetWatcher {
    private let path: String
    private let latency: TimeInterval
    private let onChange: () -> Void
    private let onFailure: (String) -> Void
    private let queue = DispatchQueue(label: "org.bobs.bob-mac-capture.vault-watcher")
    private var stream: FSEventStreamRef?
    private var pendingRefresh: DispatchWorkItem?

    init(
        path: String,
        latency: TimeInterval = 0.3,
        onChange: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        self.path = path
        self.latency = latency
        self.onChange = onChange
        self.onFailure = onFailure
    }

    deinit {
        invalidate()
    }

    func start() {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            onFailure("Vault path is not available: \(path)")
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
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else {
                return
            }
            let watcher = Unmanaged<VaultTargetWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleRefresh()
        }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            onFailure("Unable to create a vault watcher for \(path)")
            return
        }

        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            onFailure("Unable to start a vault watcher for \(path)")
            return
        }

        stream = created
    }

    func invalidate() {
        pendingRefresh?.cancel()
        pendingRefresh = nil

        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pendingRefresh = item
        queue.asyncAfter(deadline: .now() + latency, execute: item)
    }
}
