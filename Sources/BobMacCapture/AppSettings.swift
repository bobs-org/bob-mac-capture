import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var bobExecutableOverride: String {
        didSet { defaults.set(bobExecutableOverride, forKey: Keys.bobExecutableOverride) }
    }

    @Published var bobDirectory: String {
        didSet { defaults.set(bobDirectory, forKey: Keys.bobDirectory) }
    }

    @Published var useProductionHotkey: Bool {
        didSet { defaults.set(useProductionHotkey, forKey: Keys.useProductionHotkey) }
    }

    @Published var canceledDraftStashCapacity: Int {
        didSet {
            let clamped = Self.clampedCanceledDraftStashCapacity(canceledDraftStashCapacity)
            if canceledDraftStashCapacity != clamped {
                canceledDraftStashCapacity = clamped
            }
            defaults.set(canceledDraftStashCapacity, forKey: Keys.canceledDraftStashCapacity)
        }
    }

    // `didSet` (not a setter method) so every existing call site that assigns
    // `diagnosticStatus` directly gets recorded without further wiring.
    @Published var diagnosticStatus: String = "Starting" {
        didSet {
            guard diagnosticStatus != oldValue else {
                return
            }
            recordDiagnostic(diagnosticStatus)
        }
    }
    @Published var resolvedBobPath: String = "Not resolved"
    @Published var signingDiagnostic: String = "Not checked"
    // Metadata-only (status strings never contain captured text), bounded so Settings
    // can show recent activity without an unbounded in-memory log.
    @Published private(set) var diagnosticHistory: [String] = []

    private static let diagnosticHistoryLimit = 20
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bobExecutableOverride = defaults.string(forKey: Keys.bobExecutableOverride) ?? ""
        bobDirectory = defaults.string(forKey: Keys.bobDirectory) ?? ""
        useProductionHotkey = defaults.object(forKey: Keys.useProductionHotkey) == nil
            ? true
            : defaults.bool(forKey: Keys.useProductionHotkey)
        canceledDraftStashCapacity = Self.loadCanceledDraftStashCapacity(from: defaults)
    }

    var hotKeyConfiguration: HotKeyConfiguration {
        useProductionHotkey ? .production : .development
    }

    static func clampedCanceledDraftStashCapacity(_ capacity: Int) -> Int {
        CanceledDraftStash.clampedCapacity(capacity)
    }

    private static func loadCanceledDraftStashCapacity(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: Keys.canceledDraftStashCapacity) else {
            return CanceledDraftStash.defaultCapacity
        }

        if let capacity = value as? Int {
            return clampedCanceledDraftStashCapacity(capacity)
        }
        if let number = value as? NSNumber {
            return clampedCanceledDraftStashCapacity(number.intValue)
        }
        return CanceledDraftStash.defaultCapacity
    }

    private func recordDiagnostic(_ message: String) {
        let timestamp = Self.timestampFormatter.string(from: Date())
        diagnosticHistory.append("\(timestamp)  \(message)")
        if diagnosticHistory.count > Self.diagnosticHistoryLimit {
            diagnosticHistory.removeFirst(diagnosticHistory.count - Self.diagnosticHistoryLimit)
        }
    }
}

private enum Keys {
    static let bobExecutableOverride = "bobExecutableOverride"
    static let bobDirectory = "bobDirectory"
    static let useProductionHotkey = "useProductionHotkey"
    static let canceledDraftStashCapacity = "canceledDraftStashCapacity"
}
