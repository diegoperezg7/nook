import Foundation
import SwiftData

/// Trae la bandeja y el historial guardados con los nombres anteriores de la app
/// (Perch, Notchbin). Cada app con sandbox tiene su propio contenedor, asi que al
/// cambiar el bundle id los datos se quedaban atras. Se hace una sola vez y sin tocar
/// los originales: se leen a traves de una copia temporal.
enum LegacyImport {
    static let doneKey = "legacyImportDone"

    private static let sources = [
        (bundle: "com.diegoperez.perch", name: "Perch"),
        (bundle: "com.diegoperez.notchbin", name: "Notchbin"),
    ]

    @MainActor
    static func run(into store: ItemStore, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        // Dentro del sandbox NSHomeDirectory() es el contenedor: se usa la carpeta real.
        guard let home = getpwuid(getuid())?.pointee.pw_dir.map({ String(cString: $0) }) else { return }
        for source in sources {
            let folder = URL(fileURLWithPath: home)
                .appendingPathComponent("Library/Containers/\(source.bundle)/Data/Library/Application Support/\(source.name)")
            let storeURL = folder.appendingPathComponent("\(source.name).store")
            guard FileManager.default.fileExists(atPath: storeURL.path) else { continue }
            do {
                try importStore(at: storeURL, itemsDirectory: folder.appendingPathComponent("Items"), into: store)
            } catch {
                // Sin marcar como hecho: se reintenta en el proximo arranque.
                NSLog("Visor: no se pudieron importar los datos de \(source.name): \(error)")
                return
            }
        }
        defaults.set(true, forKey: doneKey)
    }

    /// Copia los elementos que aun no esten (por id), con sus archivos.
    @MainActor
    static func importStore(at storeURL: URL, itemsDirectory: URL, into store: ItemStore) throws {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory.appendingPathComponent("NookImport-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temp) }

        let copy = temp.appendingPathComponent("Legacy.store")
        try fileManager.copyItem(at: storeURL, to: copy)
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: storeURL.path + suffix)
            if fileManager.fileExists(atPath: side.path) {
                try fileManager.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        let legacy = try ModelContainer(for: NotchItem.self, configurations: ModelConfiguration(url: copy))
        let legacyContext = ModelContext(legacy)
        let oldItems = try legacyContext.fetch(FetchDescriptor<NotchItem>())
        let existing = Set(try store.context.fetch(FetchDescriptor<NotchItem>()).map(\.id))

        for old in oldItems where !existing.contains(old.id) {
            if old.storedPath != nil {
                let source = itemsDirectory.appendingPathComponent(old.id.uuidString, isDirectory: true)
                let target = store.itemsDirectory.appendingPathComponent(old.id.uuidString, isDirectory: true)
                // Sin su archivo el elemento no sirve: se omite.
                guard (try? fileManager.copyItem(at: source, to: target)) != nil else { continue }
            }
            store.insert(NotchItem(
                id: old.id, kind: old.kind, origin: old.origin, createdAt: old.createdAt,
                text: old.text, fileName: old.fileName, storedPath: old.storedPath,
                externalPath: old.externalPath, contentHash: old.contentHash, isPinned: old.isPinned
            ))
        }
    }
}
