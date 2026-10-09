import Carbon
import Foundation

struct HotKeyConfiguration: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let development = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(cmdKey | controlKey | shiftKey),
        displayName: "Control-Shift-Command-R"
    )

    static let production = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_I),
        modifiers: UInt32(cmdKey | controlKey | shiftKey),
        displayName: "Control-Shift-Command-I"
    )

    static let refs = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: UInt32(cmdKey | controlKey | shiftKey),
        displayName: "Control-Shift-Command-O"
    )

    static let highlightsCommandO = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: UInt32(cmdKey),
        displayName: "Command-O"
    )

    static let highlightsControlO = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: UInt32(controlKey),
        displayName: "Control-O"
    )
}

protocol HotKeyRegistering {
    func register(
        configuration: HotKeyConfiguration,
        identifier: EventHotKeyID,
        reference: UnsafeMutablePointer<EventHotKeyRef?>?
    ) -> OSStatus

    func unregister(reference: EventHotKeyRef)
}

struct CarbonHotKeyRegistrar: HotKeyRegistering {
    func register(
        configuration: HotKeyConfiguration,
        identifier: EventHotKeyID,
        reference: UnsafeMutablePointer<EventHotKeyRef?>?
    ) -> OSStatus {
        RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            reference
        )
    }

    func unregister(reference: EventHotKeyRef) {
        UnregisterEventHotKey(reference)
    }
}

enum HotKeyRegistrationError: Error, Equatable, CustomStringConvertible {
    case registrationFailed(OSStatus)

    var description: String {
        switch self {
        case .registrationFailed(let status):
            return "Carbon RegisterEventHotKey failed with status \(status)"
        }
    }
}

enum HotKeyAction: UInt32, CaseIterable {
    case capture = 1
    case refs = 2
    case refsHighlightsOpen = 3
}

/// One Carbon event handler routing every Bob hotkey by `EventHotKeyID`.
///
/// Each action owns an independent registration under the shared `'BOBC'`
/// signature, so registering or unregistering one action never disturbs the
/// others. The C callback reads the pressed key's id from the event and
/// forwards it to `handle(hotKeyID:)`, which is the seam tests drive
/// directly.
final class HotKeyRegistry {
    static let signature = OSType(0x424F4243)

    private let registrar: HotKeyRegistering
    private let onPressed: (HotKeyAction) -> Void
    private var references: [HotKeyAction: EventHotKeyRef] = [:]
    private var eventHandlerReference: EventHandlerRef?

    init(
        registrar: HotKeyRegistering = CarbonHotKeyRegistrar(),
        onPressed: @escaping (HotKeyAction) -> Void
    ) {
        self.registrar = registrar
        self.onPressed = onPressed
        installEventHandler()
    }

    deinit {
        invalidate()
    }

    static func identifier(for action: HotKeyAction) -> EventHotKeyID {
        EventHotKeyID(signature: signature, id: action.rawValue)
    }

    func register(
        _ action: HotKeyAction,
        configuration: HotKeyConfiguration
    ) throws {
        unregister(action)

        var reference: EventHotKeyRef?
        let status = registrar.register(
            configuration: configuration,
            identifier: Self.identifier(for: action),
            reference: &reference
        )

        guard status == noErr, let reference else {
            throw HotKeyRegistrationError.registrationFailed(status)
        }

        references[action] = reference
    }

    func unregister(_ action: HotKeyAction) {
        if let reference = references.removeValue(forKey: action) {
            registrar.unregister(reference: reference)
        }
    }

    func isRegistered(_ action: HotKeyAction) -> Bool {
        references[action] != nil
    }

    func invalidate() {
        for reference in references.values {
            registrar.unregister(reference: reference)
        }
        references.removeAll()

        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    @discardableResult
    func handle(hotKeyID: EventHotKeyID) -> OSStatus {
        guard hotKeyID.signature == Self.signature,
            let action = HotKeyAction(rawValue: hotKeyID.id)
        else {
            return OSStatus(eventNotHandledErr)
        }
        onPressed(action)
        return noErr
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else {
                    return noErr
                }
                let registry = Unmanaged<HotKeyRegistry>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var hotKeyID = EventHotKeyID(signature: 0, id: 0)
                let status = withUnsafeMutablePointer(to: &hotKeyID) {
                    pointer in
                    GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        UnsafeMutableRawPointer(pointer)
                    )
                }
                guard status == noErr else {
                    return OSStatus(eventNotHandledErr)
                }
                return registry.handle(hotKeyID: hotKeyID)
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerReference
        )
    }
}
