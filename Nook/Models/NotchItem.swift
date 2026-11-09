import Foundation
import SwiftData

enum ItemKind: String {
    case text, image, file
}

/// Donde vive el elemento: la bandeja (lo guarda el usuario a proposito) o el
/// historial del portapapeles (se captura solo y rota segun el limite).
enum ItemOrigin: String {
    case shelf, clipboard
}

@Model
final class NotchItem {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var originRaw: String
    var createdAt: Date
    var text: String?
    /// Nombre visible (archivos).
    var fileName: String?
    /// Ruta relativa dentro de la carpeta de la app: copias de la bandeja e imagenes.
    var storedPath: String?
    /// Archivo copiado al portapapeles: se guarda la referencia, no una copia.
    var externalPath: String?
    var contentHash: String
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        kind: ItemKind,
        origin: ItemOrigin,
        createdAt: Date = .now,
        text: String? = nil,
        fileName: String? = nil,
        storedPath: String? = nil,
        externalPath: String? = nil,
        contentHash: String,
        isPinned: Bool = false
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.originRaw = origin.rawValue
        self.createdAt = createdAt
        self.text = text
        self.fileName = fileName
        self.storedPath = storedPath
        self.externalPath = externalPath
        self.contentHash = contentHash
        self.isPinned = isPinned
    }

    var kind: ItemKind { ItemKind(rawValue: kindRaw) ?? .text }
    var origin: ItemOrigin { ItemOrigin(rawValue: originRaw) ?? .clipboard }

    func matches(_ query: String) -> Bool {
        let haystack = [text, fileName].compactMap { $0 }
        return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
