import Foundation

/// Donde viven los datos de Nook (bandeja, historial y sus archivos).
///
/// Desde la 0.11 viven en el App Group, no en el contenedor del sandbox: es el unico
/// sitio que podra leer una version futura sin sandbox (el contenedor le da EPERM).
/// Al arrancar se copian una vez del contenedor al App Group. Nada se borra: el
/// contenedor se queda como respaldo. Si la copia falla, se sigue con el contenedor.
enum DataHome {
    /// App Group de esta build (Release y Debug tienen el suyo, para no mezclar datos).
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "NookAppGroup") as? String }

    /// Carpeta "Nook" dentro del contenedor del sandbox (donde estaba todo hasta la 0.10).
    static var legacyDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nook", isDirectory: true)
    }

    static var groupDirectory: URL? {
        guard let groupID, let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        return base.appendingPathComponent("Library/Application Support/Nook", isDirectory: true)
    }

    /// Se decide una vez por arranque, antes de abrir el almacen.
    private(set) static var directory: URL = legacyDirectory

    private static let marker = ".copiado-del-contenedor"

    /// Copia (si hace falta) y fija `directory`. Devuelve lo que paso, para el log.
    @discardableResult
    static func prepare(fileManager: FileManager = .default) -> String {
        guard let group = groupDirectory else {
            directory = legacyDirectory
            return "sin App Group: se usa el contenedor"
        }
        let result = migrate(from: legacyDirectory, to: group, fileManager: fileManager)
        directory = result.useGroup ? group : legacyDirectory
        return result.message
    }

    /// Logica de la copia, separada para probarla con carpetas temporales.
    static func migrate(from legacy: URL, to group: URL, fileManager: FileManager = .default) -> (useGroup: Bool, message: String) {
        let groupStore = group.appendingPathComponent("Nook.store")
        // Ya migrado (o instalacion nueva que ya escribio en el grupo).
        if fileManager.fileExists(atPath: groupStore.path) { return (true, "datos en el App Group") }

        let legacyStore = legacy.appendingPathComponent("Nook.store")
        guard fileManager.fileExists(atPath: legacyStore.path) else {
            // Nada que copiar: instalacion nueva.
            try? fileManager.createDirectory(at: group, withIntermediateDirectories: true)
            return (true, "instalacion nueva en el App Group")
        }

        // Se copia a una carpeta temporal junto al destino y se renombra al final,
        // para que una copia a medias nunca parezca completa.
        let staging = group.deletingLastPathComponent().appendingPathComponent("Nook-copiando-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: group.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacy, to: staging)
            guard fileCount(staging, fileManager) == fileCount(legacy, fileManager) else {
                try? fileManager.removeItem(at: staging)
                return (false, "copia incompleta: se sigue con el contenedor")
            }
            try Data().write(to: staging.appendingPathComponent(marker))
            if fileManager.fileExists(atPath: group.path) {
                // Carpeta vacia de un arranque anterior sin almacen: se aparta, no se borra.
                try fileManager.moveItem(at: group, to: group.deletingLastPathComponent()
                    .appendingPathComponent("Nook-anterior-\(UUID().uuidString)", isDirectory: true))
            }
            try fileManager.moveItem(at: staging, to: group)
            return (true, "copiados \(fileCount(legacy, fileManager)) archivos al App Group")
        } catch {
            try? fileManager.removeItem(at: staging)
            return (false, "error al copiar (\(error.localizedDescription)): se sigue con el contenedor")
        }
    }

    private static func fileCount(_ url: URL, _ fileManager: FileManager) -> Int {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return -1 }
        return enumerator.reduce(0) { count, item in
            guard let url = item as? URL, url.lastPathComponent != marker,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return count }
            return count + 1
        }
    }

    /// Copia de los ajustes en el App Group, para que la version sin sandbox los
    /// recupere (sus defaults ya no son los del contenedor). Se rehace en cada arranque.
    static func exportDefaults() {
        guard let group = groupDirectory, let bundleID = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: bundleID) else { return }
        let file = group.appendingPathComponent("ajustes.plist")
        if let data = try? PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
