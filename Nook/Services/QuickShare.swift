import AppKit

/// Acciones rapidas: AirDrop y correo con los servicios de compartir de macOS.
@MainActor
enum QuickShare {
    static func send(_ items: [Any], via name: NSSharingService.Name) {
        guard !items.isEmpty, let service = NSSharingService(named: name), service.canPerform(withItems: items) else {
            NSSound.beep()
            return
        }
        // La ventana de AirDrop o el correo nuevo tienen que quedar delante.
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items)
    }
}
