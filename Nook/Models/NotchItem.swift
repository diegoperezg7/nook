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
    /// Texto reconocido en una imagen (OCR local): la busqueda tambien mira aqui.
    /// Vacio si no se encontro texto; nil si aun no se ha analizado.
    var recognizedText: String?
    /// App desde la que se copio (historial).
    var sourceBundleID: String?

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
        isPinned: Bool = false,
        recognizedText: String? = nil,
        sourceBundleID: String? = nil
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
        self.recognizedText = recognizedText
        self.sourceBundleID = sourceBundleID
    }

    var kind: ItemKind { ItemKind(rawValue: kindRaw) ?? .text }
    var origin: ItemOrigin { ItemOrigin(rawValue: originRaw) ?? .clipboard }

    func matches(_ query: String) -> Bool {
        let haystack = [text, fileName, recognizedText].compactMap { $0 }
        return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Filtro por tipo del historial.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, text, links, images, files, pinned

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .all: return "Todo"
        case .text: return "Texto"
        case .links: return "Enlaces"
        case .images: return "Imágenes"
        case .files: return "Archivos"
        case .pinned: return "Fijados"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .links: return "link"
        case .images: return "photo"
        case .files: return "doc"
        case .pinned: return "pin"
        }
    }

    func includes(_ item: NotchItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text && !item.isLink
        case .links: return item.isLink
        case .images: return item.kind == .image
        case .files: return item.kind == .file
        case .pinned: return item.isPinned
        }
    }
}

extension NotchItem {
    /// Texto que es solo un enlace web.
    var isLink: Bool {
        guard kind == .text, let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: \.isWhitespace),
              let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}
