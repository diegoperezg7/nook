import AppKit
import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Archivo ya copiado a la carpeta de la app, listo para registrarlo en la bandeja.
struct StagedFile: Sendable {
    let id: UUID
    let name: String
    let relativePath: String
}

/// Persistencia de la bandeja y del historial: SwiftData para los metadatos y una
/// carpeta por elemento para los archivos e imagenes.
@MainActor
final class ItemStore {
    let context: ModelContext
    let itemsDirectory: URL
    /// changeCount tras la ultima escritura propia: el monitor no la recaptura.
    private(set) var ownChangeCount = -1
    var historyLimit: () -> Int = {
        UserDefaults.standard.integer(forKey: SettingsKey.historyLimit)
    }

    init(context: ModelContext, itemsDirectory: URL) {
        self.context = context
        self.itemsDirectory = itemsDirectory
        try? FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
    }

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Nook", isDirectory: true)
    }

    // MARK: - Bandeja

    /// Copia un archivo soltado en el notch. Se llama fuera del hilo principal,
    /// dentro del callback del drop, que es cuando el sandbox da acceso al archivo.
    nonisolated static func stageFile(_ url: URL, in directory: URL) throws -> StagedFile {
        let id = UUID()
        let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
        return StagedFile(id: id, name: name, relativePath: "\(id.uuidString)/\(name)")
    }

    func addShelfFile(_ staged: StagedFile, kind: ItemKind = .file) {
        insert(NotchItem(
            id: staged.id, kind: kind, origin: .shelf, fileName: staged.name,
            storedPath: staged.relativePath, contentHash: staged.id.uuidString
        ))
    }

    /// Registra en la bandeja un archivo generado (zip, conversion) y borra el temporal.
    func addGeneratedFile(_ url: URL) throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        addShelfFile(try Self.stageFile(url, in: itemsDirectory))
    }

    /// Copia un elemento del historial a la bandeja, donde no rota.
    func saveToShelf(_ item: NotchItem) {
        switch item.kind {
        case .text:
            addShelfText(item.text ?? "")
        case .image, .file:
            guard let url = fileURL(for: item) else { return }
            if let staged = try? Self.stageFile(url, in: itemsDirectory) {
                addShelfFile(staged, kind: item.kind)
            } else {
                // Un archivo copiado en Finder: el sandbox no deja leerlo, asi que
                // la bandeja guarda la referencia (se sigue pudiendo arrastrar).
                insert(NotchItem(
                    kind: .file, origin: .shelf, fileName: item.fileName,
                    externalPath: item.externalPath, contentHash: item.contentHash
                ))
            }
        }
    }

    func addShelfText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        insert(NotchItem(kind: .text, origin: .shelf, text: text, contentHash: Self.hash(text)))
    }

    func addShelfImage(_ data: Data) {
        guard let item = makeImageItem(data, origin: .shelf) else { return }
        insert(item)
    }

    // MARK: - Historial

    func captureText(_ text: String, source: String? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let hash = Self.hash(text)
        guard !bumpExisting(hash: hash) else { return }
        insert(NotchItem(kind: .text, origin: .clipboard, text: text, contentHash: hash, sourceBundleID: source))
        trimHistory()
    }

    func captureImage(_ data: Data, source: String? = nil) {
        let hash = Self.hash(data)
        guard !bumpExisting(hash: hash) else { return }
        guard let item = makeImageItem(data, origin: .clipboard, hash: hash) else { return }
        item.sourceBundleID = source
        insert(item)
        trimHistory()
    }

    func captureFile(_ url: URL, source: String? = nil) {
        let hash = Self.hash(url.path)
        guard !bumpExisting(hash: hash) else { return }
        insert(NotchItem(
            kind: .file, origin: .clipboard, fileName: url.lastPathComponent,
            externalPath: url.path, contentHash: hash, sourceBundleID: source
        ))
        trimHistory()
    }

    /// Si el contenido ya esta en el historial, lo sube arriba en vez de duplicarlo.
    private func bumpExisting(hash: String) -> Bool {
        let clipboard = ItemOrigin.clipboard.rawValue
        var descriptor = FetchDescriptor<NotchItem>(
            predicate: #Predicate { $0.originRaw == clipboard && $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        guard let existing = try? context.fetch(descriptor).first else { return false }
        existing.createdAt = .now
        save()
        return true
    }

    /// Borra lo mas antiguo por encima del limite, solo si el usuario ha puesto uno
    /// (por defecto no hay). Los fijados no cuentan ni se borran.
    func trimHistory() {
        let limit = historyLimit()
        guard limit > 0 else { return }
        let clipboard = ItemOrigin.clipboard.rawValue
        let descriptor = FetchDescriptor<NotchItem>(
            predicate: #Predicate { $0.originRaw == clipboard && $0.isPinned == false },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else { return }
        guard items.count > limit else { return }
        items[limit...].forEach(removeFilesAndDelete)
        save()
    }

    // MARK: - Acciones

    func delete(_ item: NotchItem) {
        removeFilesAndDelete(item)
        save()
    }

    func togglePin(_ item: NotchItem) {
        item.isPinned.toggle()
        save()
        if !item.isPinned { trimHistory() }
    }

    func clearShelf() {
        deleteAll(origin: .shelf, keepPinned: false)
    }

    /// Borra el historial excepto los fijados.
    func clearHistory() {
        deleteAll(origin: .clipboard, keepPinned: true)
    }

    private func deleteAll(origin: ItemOrigin, keepPinned: Bool) {
        let raw = origin.rawValue
        let descriptor = FetchDescriptor<NotchItem>(predicate: #Predicate { $0.originRaw == raw })
        let items = (try? context.fetch(descriptor)) ?? []
        items.filter { !(keepPinned && $0.isPinned) }.forEach(removeFilesAndDelete)
        save()
    }

    /// Pone el elemento en el portapapeles. Un elemento del historial sube arriba.
    func copyToPasteboard(_ item: NotchItem, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image, .file:
            guard let url = fileURL(for: item) else { return }
            pasteboard.writeObjects([Self.pasteboardItem(for: url)])
        }
        ownChangeCount = pasteboard.changeCount
        if item.origin == .clipboard {
            item.createdAt = .now
            save()
        }
    }

    /// Un archivo en el portapapeles con varias representaciones: Finder y Mail usan
    /// la URL (pegan el archivo); un chat o un documento usan la imagen o el PDF.
    nonisolated static func pasteboardItem(for url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if FileActions.isImage(url), let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
            if let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                item.setData(png, forType: .png)
            }
        } else if url.pathExtension.lowercased() == "pdf",
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 50_000_000,
                  let pdf = try? Data(contentsOf: url) {
            item.setData(pdf, forType: .pdf)
        }
        return item
    }

    func fileURL(for item: NotchItem) -> URL? {
        if let stored = item.storedPath { return itemsDirectory.appendingPathComponent(stored) }
        if let external = item.externalPath { return URL(fileURLWithPath: external) }
        return nil
    }

    /// Lo que viaja al arrastrar fuera del notch.
    func itemProvider(for item: NotchItem) -> NSItemProvider {
        switch item.kind {
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .image, .file:
            guard let url = fileURL(for: item) else { return NSItemProvider() }
            // Se ofrece la URL del archivo (public.file-url): es lo que esperan Finder,
            // Mail o el navegador. Con contentsOf: solo viajaba el contenido.
            let provider = NSItemProvider(object: url as NSURL)
            provider.suggestedName = item.fileName ?? url.lastPathComponent
            return provider
        }
    }

    // MARK: - Internos

    private func makeImageItem(_ data: Data, origin: ItemOrigin, hash: String? = nil) -> NotchItem? {
        guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return nil }
        let id = UUID()
        let name = String(localized: "Imagen") + ".png"
        let folder = itemsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent(name))
        } catch {
            return nil
        }
        return NotchItem(
            id: id, kind: .image, origin: origin, fileName: name,
            storedPath: "\(id.uuidString)/\(name)", contentHash: hash ?? Self.hash(png)
        )
    }

    func insert(_ item: NotchItem) {
        context.insert(item)
        save()
        recognizeText(in: item)
    }

    /// Busca texto en las imagenes guardadas para poder encontrarlas al buscar.
    /// Se hace en segundo plano; `recognizedText` queda vacio si no hay texto.
    func recognizeText(in item: NotchItem) {
        guard item.recognizedText == nil, item.storedPath != nil,
              let url = fileURL(for: item), FileActions.isImage(url) else { return }
        let id = item.id
        Task.detached(priority: .utility) { [weak self] in
            let text = (try? FileActions.recognizeText(in: url)) ?? ""
            await self?.setRecognizedText(text, forItem: id)
        }
    }

    private func setRecognizedText(_ text: String, forItem id: UUID) {
        var descriptor = FetchDescriptor<NotchItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        // El elemento pudo borrarse mientras se analizaba.
        guard let item = try? context.fetch(descriptor).first else { return }
        item.recognizedText = text
        save()
    }

    /// Imagenes guardadas antes de que existiera la busqueda por texto.
    func recognizeMissingText() {
        let descriptor = FetchDescriptor<NotchItem>(predicate: #Predicate { $0.recognizedText == nil })
        (try? context.fetch(descriptor))?.forEach(recognizeText)
    }

    private func removeFilesAndDelete(_ item: NotchItem) {
        if item.storedPath != nil {
            let folder = itemsDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
        }
        context.delete(item)
    }

    private func save() {
        try? context.save()
    }

    static func hash(_ text: String) -> String { hash(Data(text.utf8)) }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
