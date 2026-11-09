import Carbon.HIToolbox
import Foundation

/// Atajo global con la API de Carbon: funciona en sandbox y no pide Accesibilidad
/// (al contrario que un monitor global de teclado).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void
    private let id: UInt32

    /// Por defecto ⌃⌘V. Cada atajo lleva su `id`: el manejador recibe las
    /// pulsaciones de todos y solo responde a la suya.
    init(
        keyCode: UInt32 = UInt32(kVK_ANSI_V),
        modifiers: UInt32 = UInt32(controlKey | cmdKey),
        id: UInt32 = 1,
        onPress: @escaping () -> Void
    ) {
        self.onPress = onPress
        self.id = id
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { hotKey.onPress() }
            return noErr
        }, 1, &spec, selfPointer, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E42_494E), id: id) // "NBIN"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
