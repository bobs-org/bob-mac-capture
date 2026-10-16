import CaptureCore
import Combine
import Foundation

enum SavedTemplateShelfRefreshReason: String, Equatable, Sendable {
    case launch
    case show
    case submit
    case mutation
    case recheck
}

enum SavedTemplateShelfAvailability: Equatable, Sendable {
    case unknown
    case available
    case unsupported
    case failed(String)
}

/// In-memory cache of bob's template shelf. One refresh is in flight at a
/// time; a trigger during a refresh schedules exactly one follow-up. The
/// last good list is kept on failure. Vault events are not a trigger.
@MainActor
final class SavedTemplateShelf: ObservableObject {
    @Published private(set) var templates: [CaptureSavedTemplate] = []
    @Published private(set) var capacity: Int = 0
    @Published private(set) var saving = false
    @Published private(set) var file = ""
    @Published private(set) var availability: SavedTemplateShelfAvailability = .unknown
    @Published private(set) var lastRefreshedAt: Date?

    var processClient: BobProcessClient? {
        didSet {
            guard processClient !== oldValue else {
                return
            }
            generation &+= 1
            isRefreshing = false
            followUpQueued = false
        }
    }

    private var generation: UInt64 = 0
    private var isRefreshing = false
    private var followUpQueued = false
    private let now: () -> Date

    init(
        processClient: BobProcessClient? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.processClient = processClient
        self.now = now
    }

    var isEmpty: Bool {
        templates.isEmpty
    }

    var count: Int {
        templates.count
    }

    var isUnsupported: Bool {
        if case .unsupported = availability {
            return true
        }
        return false
    }

    func template(at index: Int) -> CaptureSavedTemplate? {
        guard templates.indices.contains(index) else {
            return nil
        }
        return templates[index]
    }

    func template(id: String) -> CaptureSavedTemplate? {
        templates.first { $0.id == id }
    }

    func refresh(reason: SavedTemplateShelfRefreshReason) {
        _ = reason
        guard let client = processClient else {
            return
        }
        if isRefreshing {
            followUpQueued = true
            return
        }
        generation &+= 1
        isRefreshing = true
        let generation = self.generation
        Task { [weak self] in
            do {
                let response = try await client.savedTemplates()
                await MainActor.run {
                    self?.finishList(response, generation: generation)
                }
            } catch let clientError as BobClientError {
                await MainActor.run {
                    self?.finishClientError(clientError, generation: generation)
                }
            } catch {
                await MainActor.run {
                    self?.finishFailure(String(describing: error), generation: generation)
                }
            }
        }
    }

    /// Clears bob's saved templates and refreshes the shared cache after the
    /// mutation. `nil` means the app does not currently have a resolved bob.
    func clearSavedTemplates() async throws -> CaptureTemplateClearResponse? {
        guard let processClient else {
            return nil
        }
        let response = try await processClient.clearSavedTemplates()
        refresh(reason: .mutation)
        return response
    }

    /// Optimistic local removal used by two-press delete. The caller then
    /// asks bob to delete and refreshes; a failed delete restores from the
    /// snapshot the caller kept.
    @discardableResult
    func removeLocally(id: String) -> [CaptureSavedTemplate] {
        templates.removeAll { $0.id == id }
        return templates
    }

    func restoreLocally(_ templates: [CaptureSavedTemplate]) {
        self.templates = templates
    }

    func replaceCacheForTests(
        templates: [CaptureSavedTemplate],
        capacity: Int = 36,
        saving: Bool = true,
        file: String = "/tmp/templates.json",
        availability: SavedTemplateShelfAvailability = .available
    ) {
        self.templates = templates
        self.capacity = capacity
        self.saving = saving
        self.file = file
        self.availability = availability
        lastRefreshedAt = now()
    }

    private func finishList(_ response: CaptureSavedTemplatesResponse, generation: UInt64) {
        guard generation == self.generation else {
            return
        }
        templates = response.templates
        capacity = response.capacity
        saving = response.saving
        file = response.file
        availability = .available
        lastRefreshedAt = now()
        endRefresh(generation: generation)
    }

    private func finishClientError(_ error: BobClientError, generation: UInt64) {
        guard generation == self.generation else {
            return
        }
        if case .unsupportedCommand = error {
            templates = []
            capacity = 0
            saving = false
            file = ""
            availability = .unsupported
            lastRefreshedAt = now()
            isRefreshing = false
            followUpQueued = false
            return
        }
        finishFailure(error.description, generation: generation)
    }

    private func finishFailure(_ message: String, generation: UInt64) {
        guard generation == self.generation else {
            return
        }
        if templates.isEmpty {
            availability = .failed(message)
        }
        endRefresh(generation: generation)
    }

    private func endRefresh(generation: UInt64) {
        guard generation == self.generation else {
            return
        }
        let followUp = followUpQueued
        isRefreshing = false
        followUpQueued = false
        if followUp {
            refresh(reason: .show)
        }
    }
}
