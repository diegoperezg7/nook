import AppKit
import UniformTypeIdentifiers

/// Lee lo que se suelta en el notch: archivos, imagenes, enlaces o texto.
enum DropReader {
    static let types: [UTType] = [.fileURL, .image, .url, .plainText]

    @MainActor
    static func read(_ providers: [NSItemProvider], into store: ItemStore) {
        let directory = store.itemsDirectory
        for provider in providers {
            // Un archivo arrastrado no siempre ofrece public.file-url: suele ofrecer
            // su propio tipo (public.plain-text, public.jpeg...) como representacion
            // de archivo. Si no se mira esto primero, un .txt se guarda como texto.
            if let fileType = provider.registeredTypeIdentifiers(fileOptions: [.openInPlace]).first {
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: fileType) { url, _, _ in
                    // Copiar aqui, dentro del callback: es cuando el sandbox da acceso.
                    guard let url, let staged = try? ItemStore.stageFile(url, in: directory) else { return }
                    Task { @MainActor in store.addShelfFile(staged) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let url = url(from: item),
                          let staged = try? ItemStore.stageFile(url, in: directory) else { return }
                    Task { @MainActor in store.addShelfFile(staged) }
                }
            } else if let imageType = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .image) == true
            }) {
                provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in store.addShelfImage(data) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    guard let url = url(from: item) else { return }
                    Task { @MainActor in store.addShelfText(url.absoluteString) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    Task { @MainActor in store.addShelfText(text) }
                }
            }
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        switch item {
        case let url as URL: return url
        case let data as Data: return URL(dataRepresentation: data, relativeTo: nil)
        case let string as String: return URL(string: string)
        default: return nil
        }
    }
}
