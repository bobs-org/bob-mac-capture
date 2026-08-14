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

    @Published var diagnosticStatus: String = "Starting"
    @Published var resolvedBobPath: String = "Not resolved"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bobExecutableOverride = defaults.string(forKey: Keys.bobExecutableOverride) ?? ""
        bobDirectory = defaults.string(forKey: Keys.bobDirectory) ?? ""
        useProductionHotkey = defaults.bool(forKey: Keys.useProductionHotkey)
    }

    var hotKeyConfiguration: HotKeyConfiguration {
        useProductionHotkey ? .production : .development
    }
}

private enum Keys {
    static let bobExecutableOverride = "bobExecutableOverride"
    static let bobDirectory = "bobDirectory"
    static let useProductionHotkey = "useProductionHotkey"
}
