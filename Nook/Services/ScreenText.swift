import AppKit

/// Herramientas de captura: el usuario elige una zona de la pantalla con la
/// seleccion del sistema (`screencapture -i`) y Nook lee su texto o la guarda.
enum ScreenGrab {
    /// Devuelve la imagen elegida o nil si se cancelo con Escape.
    static func region() async -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nook-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(String(localized: "Captura") + " " + Date.now.formatted(.dateTime.hour().minute().second()) + ".png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-o", file.path]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume() }
        }
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}
