/// Registers the global Capture alias hotkey (Command-\) when its
/// setting is on, and unregisters it when off. Registering replaces
/// only the alias key: a failure leaves every other registration intact
/// and is reported, never thrown.
enum CaptureAliasHotkeyRegistration {
    /// Syncs the `.captureAlias` registration with the setting. Returns
    /// true when the hotkey ends up registered.
    @discardableResult
    static func sync(
        registry: HotKeyRegistry,
        enabled: Bool,
        onError: (String) -> Void
    ) -> Bool {
        guard enabled else {
            registry.unregister(.captureAlias)
            return false
        }
        do {
            try registry.register(
                .captureAlias,
                configuration: .captureCommandBackslash
            )
            return true
        } catch {
            let chord = HotKeyConfiguration.captureCommandBackslash.displayName
            onError("Capture alias hotkey conflict: \(chord) (\(error))")
            return false
        }
    }
}
