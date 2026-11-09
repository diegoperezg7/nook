import AppKit
import Sparkle

/// Actualizaciones automaticas con Sparkle: mira el appcast una vez al dia y, si hay
/// version nueva firmada con nuestra clave, la ofrece. En Debug no se arranca (la build
/// de desarrollo no debe sustituirse por la publicada).
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController

    init() {
        #if DEBUG
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        #else
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }

    /// "Buscar actualizaciones…": Nook no tiene Dock, asi que se activa para que la
    /// ventana de Sparkle salga delante.
    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
