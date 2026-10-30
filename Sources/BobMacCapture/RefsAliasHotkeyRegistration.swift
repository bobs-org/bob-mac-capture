/// Registers the global Bob Refs alias hotkey (Command-]) when its
/// setting is on, and unregisters it when off. Registering replaces
/// only the alias key: a failure leaves every other registration intact
/// and is reported, never thrown.
enum RefsAliasHotkeyRegistration {
    /// Syncs the `.refsAlias` registration with the setting. Returns
    /// true when the hotkey ends up registered.
    @discardableResult
    static func sync(
        registry: HotKeyRegistry,
        enabled: Bool,
        onError: (String) -> Void
    ) -> Bool {
        guard enabled else {
            registry.unregister(.refsAlias)
            return false
        }
        do {
            try registry.register(
                .refsAlias,
                configuration: .refsCommandRightBracket
            )
            return true
        } catch {
            let chord = HotKeyConfiguration.refsCommandRightBracket.displayName
            onError("Refs alias hotkey conflict: \(chord) (\(error))")
            return false
        }
    }
}
