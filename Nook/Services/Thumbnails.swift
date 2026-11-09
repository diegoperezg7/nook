import AppKit
import QuickLookThumbnailing

/// Vistas previas reales con Quick Look: la primera pagina de un PDF, el texto de
/// un documento, la propia imagen... Si Quick Look no puede, el icono del archivo.
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for url: URL, size: CGSize = CGSize(width: 160, height: 120)) async -> NSImage {
        let key = "\(url.path)#\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        let image: NSImage
        if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = thumbnail.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
