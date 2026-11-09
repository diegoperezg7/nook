import AppKit
import QuickLookUI

/// Vista previa con Quick Look. El panel del sistema busca quien lo controla en la
/// cadena de respuesta; NotchPanel delega aqui (ver `acceptsPreviewPanelControl`).
@MainActor
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookPresenter()
    private var urls: [URL] = []

    func show(_ url: URL) {
        urls = [url]
        // Quick Look necesita que la app este activa para salir delante.
        NSApp.activate()
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
