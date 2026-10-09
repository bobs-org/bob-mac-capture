/// Registers the global Bob Refs hotkey (Control-Shift-Command-R) when
/// its setting is on, and unregisters it when off. Registering replaces
/// only the Refs key: a failure leaves every other registration intact
/// and is reported, never thrown.
enum RefsHotkeyRegistration {
    /// Syncs the `.refs` registration with the setting. Returns true when
    /// the hotkey ends up registered.
    @discardableResult
    static func sync(
        registry: HotKeyRegistry,
        enabled: Bool,
        onError: (String) -> Void
    ) -> Bool {
        guard enabled else {
            registry.unregister(.refs)
            return false
        }
        do {
            try registry.register(.refs, configuration: .refs)
            return true
        } catch {
            onError("Refs hotkey conflict: \(error)")
            return false
        }
    }
}
