import AppKit

/// Añade archivos a la bandeja sin arrastrarlos: desde el boton "+" (panel de abrir)
/// o desde Finder (Servicios > Añadir a Nook).
@MainActor
enum FileImporter {
    static func chooseFiles(into store: ItemStore) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.message = String(localized: "Elige lo que quieres dejar en la bandeja")
        panel.prompt = String(localized: "Añadir")
        NSApp.activate()
        panel.begin { response in
            guard response == .OK else { return }
            MainActor.assumeIsolated { add(panel.urls, to: store) }
        }
    }

    /// Copia en segundo plano (un archivo grande no bloquea el panel).
    static func add(_ urls: [URL], to store: ItemStore) {
        let directory = store.itemsDirectory
        Task.detached(priority: .userInitiated) {
            for url in urls {
                guard let staged = try? ItemStore.stageFile(url, in: directory) else { continue }
                await MainActor.run { store.addShelfFile(staged) }
            }
        }
    }
}

/// Servicio de macOS "Añadir a Nook": aparece al hacer clic derecho en Finder.
final class ServiceProvider: NSObject {
    private let store: ItemStore

    init(store: ItemStore) {
        self.store = store
    }

    @objc func addToNook(
        _ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = String(localized: "No hay archivos que añadir") as NSString
            return
        }
        MainActor.assumeIsolated { FileImporter.add(urls, to: store) }
    }
}
