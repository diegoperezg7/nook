import Carbon.HIToolbox
import Foundation

/// Atajo global con la API de Carbon: funciona en sandbox y no pide Accesibilidad
/// (al contrario que un monitor global de teclado).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    /// Por defecto ⌃⌘V.
    init(
        keyCode: UInt32 = UInt32(kVK_ANSI_V),
        modifiers: UInt32 = UInt32(controlKey | cmdKey),
        onPress: @escaping () -> Void
    ) {
        self.onPress = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.onPress() }
            return noErr
        }, 1, &spec, selfPointer, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x4E42_494E), id: 1) // "NBIN"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
