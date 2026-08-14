import Carbon
import Foundation

struct HotKeyConfiguration: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let development = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: UInt32(cmdKey | controlKey | shiftKey),
        displayName: "Control-Shift-Command-O"
    )

    static let production = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_I),
        modifiers: UInt32(cmdKey | controlKey | shiftKey),
        displayName: "Control-Shift-Command-I"
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

final class HotKeyManager {
    private let registrar: HotKeyRegistering
    private let onPressed: () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(
        registrar: HotKeyRegistering = CarbonHotKeyRegistrar(),
        onPressed: @escaping () -> Void
    ) {
        self.registrar = registrar
        self.onPressed = onPressed
        installEventHandler()
    }

    deinit {
        invalidate()
    }

    func register(configuration: HotKeyConfiguration) throws {
        unregisterHotKey()

        let identifier = EventHotKeyID(signature: OSType(0x424F4243), id: 1)
        var reference: EventHotKeyRef?
        let status = registrar.register(
            configuration: configuration,
            identifier: identifier,
            reference: &reference
        )

        guard status == noErr, let reference else {
            throw HotKeyRegistrationError.registrationFailed(status)
        }

        hotKeyReference = reference
    }

    func unregister() {
        unregisterHotKey()
    }

    func invalidate() {
        unregisterHotKey()

        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private func unregisterHotKey() {
        if let hotKeyReference {
            registrar.unregister(reference: hotKeyReference)
            self.hotKeyReference = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }
                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                manager.onPressed()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerReference
        )
    }
}
