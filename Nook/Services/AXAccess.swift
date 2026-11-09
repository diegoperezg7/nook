import AppKit
import ApplicationServices

/// Permiso de Accesibilidad: lo necesitan pegar en otra app, ajustar ventanas, el
/// texto seleccionado y los controles de reunion (pulsar atajos en la app de la llamada).
enum AXAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Pide el permiso (macOS muestra su aviso con el boton a Ajustes). Solo lo
    /// llama una accion del usuario, nunca el arranque.
    @discardableResult
    static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Pulsa un atajo en la app que tenga el foco (⌘V, ⌘⇧A...).
    static func press(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    static func paste() {
        press(9, .maskCommand) // kVK_ANSI_V
    }
}
