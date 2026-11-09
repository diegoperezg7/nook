import SwiftUI

@main
struct PerchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // La interfaz vive en el panel del notch y en la ventana de ajustes propia
        // (AppDelegate). Esta escena solo existe porque App exige una.
        Settings { EmptyView() }
    }
}
