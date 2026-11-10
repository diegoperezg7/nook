import AppKit
import Observation

/// Capturas de pantalla de la carpeta donde las guarda macOS (normalmente el
/// Escritorio). Nook no las copia: las enseña donde estan, las vigila para que las
/// nuevas aparezcan al momento y, al borrarlas, las manda a la Papelera.
///
/// La app esta en sandbox: el usuario elige la carpeta una vez y se guarda un
/// marcador con permiso de lectura y escritura.
@Observable
@MainActor
final class ScreenshotLibrary {
    struct Shot: Identifiable, Hashable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    private(set) var folder: URL?
    private(set) var shots: [Shot] = []
    var selection: Set<URL> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pendingReload: DispatchWorkItem?
    @ObservationIgnored private var scopedFolder: URL?

    static let bookmarkKey = "screenshotsFolderBookmark"
    nonisolated private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "pdf"]
    /// Respaldo si el archivo no trae la marca de captura: prefijos que usa macOS.
    nonisolated private static let namePrefixes = ["Captura de pantalla", "Screenshot", "Bildschirmfoto", "Capture d’écran", "Schermata"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    var selectedShots: [Shot] { shots.filter { selection.contains($0.url) } }

    // MARK: - Carpeta

    /// Pide la carpeta de capturas. Sugiere el Escritorio, que es donde van por defecto.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Self.realHome.appendingPathComponent("Desktop", isDirectory: true)
        panel.message = String(localized: "Elige la carpeta donde se guardan tus capturas de pantalla (normalmente el Escritorio).")
        panel.prompt = String(localized: "Usar esta carpeta")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmark, forKey: Self.bookmarkKey)
        }
        use(url)
    }

    /// Donde guarda macOS las capturas (Captura de pantalla > Opciones); por defecto, el Escritorio.
    static var systemFolder: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return realHome.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Usa la carpeta de macOS sin dialogo (Nook no esta en sandbox).
    func useSystemFolder() {
        let url = Self.systemFolder
        if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmark, forKey: Self.bookmarkKey)
        }
        use(url)
    }

    /// La miniatura flotante de macOS retiene cada captura unos 5 s antes de guardarla:
    /// sin ella, la captura llega al momento a la carpeta y a Nook.
    static var instantCaptures: Bool {
        UserDefaults(suiteName: "com.apple.screencapture")?.object(forKey: "show-thumbnail") as? Bool == false
    }

    static func setInstantCaptures(_ on: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.screencapture", "show-thumbnail", "-bool", on ? "false" : "true"]
        try? process.run()
        process.waitUntilExit()
    }

    func showFolderInFinder() {
        guard let folder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        // Un marcador creado dentro del sandbox puede no abrirse con permisos fuera de
        // el: entonces se resuelve como uno normal (sin sandbox no hacen falta).
        guard let url = (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)) else { return }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        use(url)
    }

    private func use(_ url: URL) {
        scopedFolder?.stopAccessingSecurityScopedResource()
        scopedFolder = url.startAccessingSecurityScopedResource() ? url : nil
        folder = url
        selection = []
        watch(url)
        reload()
    }

    // MARK: - Vigilar

    private func watch(_ url: URL) {
        watcher?.cancel()
        watcher = nil
        // Fuera del hilo principal: si macOS pide permiso para la carpeta, open()
        // espera la respuesta y congelaría el arranque.
        Task {
            let descriptor = await Task.detached(priority: .utility) { open(url.path, O_EVTONLY) }.value
            guard descriptor >= 0 else { return }
            guard folder == url else { close(descriptor); return }
            attach(descriptor)
        }
    }

    private func attach(_ descriptor: Int32) {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// macOS escribe la captura como archivo oculto y luego la renombra: se espera
    /// un poco para leer la carpeta una sola vez.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Se lee fuera del hilo principal: si macOS pide permiso para la carpeta
    /// (Escritorio, Documentos), la lectura espera a la respuesta y no debe congelar
    /// el arranque ni el notch.
    func reload() {
        guard let folder else { shots = []; return }
        Task {
            let found = await Task.detached(priority: .utility) { Self.screenshots(in: folder) }.value
            guard self.folder == folder else { return }
            shots = found
            selection.formIntersection(found.map(\.url))
        }
    }

    nonisolated static func screenshots(in folder: URL) -> [Shot] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url -> Shot? in
            guard isScreenshot(url),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { return nil }
            return Shot(url: url, date: values.creationDate ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    /// Una captura lleva la marca `kMDItemIsScreenCapture`; si no (copiada de otro
    /// sitio, otro idioma), se mira el nombre que pone macOS.
    nonisolated static func isScreenshot(_ url: URL) -> Bool {
        guard imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
        let marked = getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
        return marked || namePrefixes.contains { url.lastPathComponent.hasPrefix($0) }
    }

    // MARK: - Acciones

    func toggle(_ shot: Shot) {
        if selection.contains(shot.url) {
            selection.remove(shot.url)
        } else {
            selection.insert(shot.url)
        }
    }

    func selectAll() { selection = Set(shots.map(\.url)) }
    func clearSelection() { selection = [] }

    /// Manda las capturas a la Papelera (se pueden recuperar desde alli).
    func trash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // Se quitan ya de la lista: la Papelera tarda un instante.
        shots.removeAll { urls.contains($0.url) }
        selection.subtract(urls)
    }

    /// Carpeta personal real: dentro del sandbox `homeDirectory` apunta al contenedor.
    private static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
