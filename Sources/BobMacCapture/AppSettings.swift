import Combine
import Foundation
import RefsCore

@MainActor
final class AppSettings: ObservableObject {
    /// Defaults key for the Highlights override path, shared with the
    /// Sendable locator read in AppDelegate.
    static let refsHighlightsAppPathKey = "refsHighlightsAppPath"

    @Published var bobExecutableOverride: String {
        didSet { defaults.set(bobExecutableOverride, forKey: Keys.bobExecutableOverride) }
    }

    @Published var bobDirectory: String {
        didSet { defaults.set(bobDirectory, forKey: Keys.bobDirectory) }
    }

    @Published var useProductionHotkey: Bool {
        didSet { defaults.set(useProductionHotkey, forKey: Keys.useProductionHotkey) }
    }

    @Published var refsHotkeyEnabled: Bool {
        didSet { defaults.set(refsHotkeyEnabled, forKey: Keys.refsHotkeyEnabled) }
    }

    @Published var refsHighlightsOpenKey: RefsHighlightsOpenKey {
        didSet { defaults.set(refsHighlightsOpenKey.rawValue, forKey: Keys.refsHighlightsOpenKey) }
    }

    @Published var refsHighlightsTabsKey: RefsHighlightsTabsKey {
        didSet { defaults.set(refsHighlightsTabsKey.rawValue, forKey: Keys.refsHighlightsTabsKey) }
    }

    @Published var refsHighlightsCopyKey: RefsHighlightsCopyKey {
        didSet { defaults.set(refsHighlightsCopyKey.rawValue, forKey: Keys.refsHighlightsCopyKey) }
    }

    @Published var refsHighlightsCodeKey: RefsHighlightsCodeKey {
        didSet { defaults.set(refsHighlightsCodeKey.rawValue, forKey: Keys.refsHighlightsCodeKey) }
    }

    @Published var refsHighlightsLinkKey: RefsHighlightsLinkKey {
        didSet { defaults.set(refsHighlightsLinkKey.rawValue, forKey: Keys.refsHighlightsLinkKey) }
    }

    @Published var refsHighlightsAppPath: String {
        didSet { defaults.set(refsHighlightsAppPath, forKey: Keys.refsHighlightsAppPath) }
    }

    @Published var agendaEnabled: Bool {
        didSet { defaults.set(agendaEnabled, forKey: Keys.agendaEnabled) }
    }

    @Published var similarTasksEnabled: Bool {
        didSet { defaults.set(similarTasksEnabled, forKey: Keys.similarTasksEnabled) }
    }

    @Published var refsNotifyOpenPDFUpdates: Bool {
        didSet { defaults.set(refsNotifyOpenPDFUpdates, forKey: Keys.refsNotifyOpenPDFUpdates) }
    }

    @Published var refsScanOnHighlightsSave: Bool {
        didSet { defaults.set(refsScanOnHighlightsSave, forKey: Keys.refsScanOnHighlightsSave) }
    }

    /// Live agenda diagnostic from the store ("Last refreshed 14:32",
    /// "Couldn't refresh: …", or the old-bob hint). Transient: never
    /// persisted. AppDelegate keeps it in sync with the store.
    @Published var agendaDiagnostic = ""

    @Published var canceledDraftStashCapacity: Int {
        didSet {
            let clamped = Self.clampedCanceledDraftStashCapacity(canceledDraftStashCapacity)
            if canceledDraftStashCapacity != clamped {
                canceledDraftStashCapacity = clamped
            }
            defaults.set(canceledDraftStashCapacity, forKey: Keys.canceledDraftStashCapacity)
        }
    }

    @Published var refsInspectorNotesPageSize: Int {
        didSet {
            let clamped = Self.clampedRefsInspectorNotesPageSize(
                refsInspectorNotesPageSize
            )
            if refsInspectorNotesPageSize != clamped {
                refsInspectorNotesPageSize = clamped
            }
            defaults.set(
                refsInspectorNotesPageSize,
                forKey: Keys.refsInspectorNotesPageSize
            )
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
        refsHotkeyEnabled = defaults.object(forKey: Keys.refsHotkeyEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.refsHotkeyEnabled)
        if let raw = defaults.string(forKey: Keys.refsHighlightsOpenKey),
            let key = RefsHighlightsOpenKey(rawValue: raw)
        {
            refsHighlightsOpenKey = key
        } else {
            // The `highlights_open_key` epic decision defaults the
            // Highlights-frontmost takeover to Command-O.
            refsHighlightsOpenKey = .cmdO
        }
        if let raw = defaults.string(forKey: Keys.refsHighlightsTabsKey),
            let key = RefsHighlightsTabsKey(rawValue: raw)
        {
            refsHighlightsTabsKey = key
        } else {
            // The Highlights Tabs key defaults to Command-T.
            refsHighlightsTabsKey = .cmdT
        }
        if let raw = defaults.string(forKey: Keys.refsHighlightsCopyKey),
            let key = RefsHighlightsCopyKey(rawValue: raw)
        {
            refsHighlightsCopyKey = key
        } else {
            // The Highlights Copy key defaults to Command-Y.
            refsHighlightsCopyKey = .cmdY
        }
        if let raw = defaults.string(forKey: Keys.refsHighlightsCodeKey),
            let key = RefsHighlightsCodeKey(rawValue: raw)
        {
            refsHighlightsCodeKey = key
        } else {
            refsHighlightsCodeKey = .cmdB
        }
        if let raw = defaults.string(forKey: Keys.refsHighlightsLinkKey),
            let key = RefsHighlightsLinkKey(rawValue: raw)
        {
            refsHighlightsLinkKey = key
        } else {
            refsHighlightsLinkKey = .cmdL
        }
        refsHighlightsAppPath = defaults.string(forKey: Keys.refsHighlightsAppPath) ?? ""
        agendaEnabled = defaults.object(forKey: Keys.agendaEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.agendaEnabled)
        similarTasksEnabled = defaults.object(forKey: Keys.similarTasksEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.similarTasksEnabled)
        refsNotifyOpenPDFUpdates =
            defaults.object(forKey: Keys.refsNotifyOpenPDFUpdates) == nil
            ? true
            : defaults.bool(forKey: Keys.refsNotifyOpenPDFUpdates)
        refsScanOnHighlightsSave =
            defaults.object(forKey: Keys.refsScanOnHighlightsSave) == nil
            ? true
            : defaults.bool(forKey: Keys.refsScanOnHighlightsSave)
        canceledDraftStashCapacity = Self.loadCanceledDraftStashCapacity(from: defaults)
        refsInspectorNotesPageSize = Self.loadRefsInspectorNotesPageSize(from: defaults)
    }

    var hotKeyConfiguration: HotKeyConfiguration {
        useProductionHotkey ? .production : .development
    }

    static func clampedCanceledDraftStashCapacity(_ capacity: Int) -> Int {
        CanceledDraftStash.clampedCapacity(capacity)
    }

    static func clampedRefsInspectorNotesPageSize(_ size: Int) -> Int {
        RefsNotesPage.clampedSize(size)
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

    private static func loadRefsInspectorNotesPageSize(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: Keys.refsInspectorNotesPageSize) else {
            return RefsNotesPage.defaultSize
        }

        if let size = value as? Int {
            return clampedRefsInspectorNotesPageSize(size)
        }
        if let number = value as? NSNumber {
            return clampedRefsInspectorNotesPageSize(number.intValue)
        }
        return RefsNotesPage.defaultSize
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
    static let refsHotkeyEnabled = "refsHotkeyEnabled"
    static let refsHighlightsOpenKey = "refsHighlightsOpenKey"
    static let refsHighlightsTabsKey = "refsHighlightsTabsKey"
    static let refsHighlightsCopyKey = "refsHighlightsCopyKey"
    static let refsHighlightsCodeKey = "refsHighlightsCodeKey"
    static let refsHighlightsLinkKey = "refsHighlightsLinkKey"
    static let refsHighlightsAppPath = AppSettings.refsHighlightsAppPathKey
    static let canceledDraftStashCapacity = "canceledDraftStashCapacity"
    static let refsInspectorNotesPageSize = "refsInspectorNotesPageSize"
    static let agendaEnabled = "agendaEnabled"
    static let similarTasksEnabled = "similarTasksEnabled"
    static let refsNotifyOpenPDFUpdates = "refsNotifyOpenPDFUpdates"
    static let refsScanOnHighlightsSave = "refsScanOnHighlightsSave"
}
