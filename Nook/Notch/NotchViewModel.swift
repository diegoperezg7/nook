import AppKit
import SwiftUI

@Observable
@MainActor
final class NotchViewModel {
    enum Tab: Hashable {
        case shelf, clipboard, screenshots, music

        /// El historial y las capturas tienen una fila de herramientas sobre las tarjetas.
        var hasToolbar: Bool { self == .clipboard || self == .screenshots }
    }

    enum OpenReason {
        /// Se cierra al sacar el raton.
        case hover, drag
        /// Se cierra con Escape, al pulsar fuera o al copiar.
        case hotKey
        /// Solo para capturas en Debug: no se cierra solo.
        case pinned
    }

    var metrics: NotchMetrics
    /// Abierto a efectos de logica (zonas de raton, contenido visible).
    private(set) var isOpen = false
    /// La forma crece desde el notch, en ancho y alto a la vez.
    private(set) var expandedWidth = false
    private(set) var expandedHeight = false
    var tab: Tab = .shelf
    private(set) var openReason: OpenReason = .hover
    var isDropTargeted = false
    var searchText = ""
    /// Cada incremento pide foco para el buscador.
    private(set) var searchFocusRequest = 0
    var clipboardAccess = ClipboardAccess.current
    /// Hay un arrastre que sale del panel: cerrarlo ahora retiraria la tarjeta de
    /// origen y el sistema cancelaria el arrastre.
    @ObservationIgnored var isDraggingOut = false
    /// Vista previa grande de una tarjeta abierta (es otra ventana: el cursor sale
    /// del panel y no por eso hay que cerrarlo).
    @ObservationIgnored var isPreviewing = false {
        didSet { if !isPreviewing, oldValue { onPreviewEnded?() } }
    }
    @ObservationIgnored var onPreviewEnded: (() -> Void)?

    @ObservationIgnored var onDidClose: (() -> Void)?
    @ObservationIgnored var onDropTargetChanged: ((Bool) -> Void)?
    @ObservationIgnored var onDragOutStarted: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored private var closeToken = 0
    /// Mientras suena musica el notch cerrado es mas ancho (caratula y barras).
    @ObservationIgnored var nowPlaying: NowPlaying?

    init(metrics: NotchMetrics) {
        self.metrics = metrics
    }

    func open(reason: OpenReason, tab: Tab? = nil) {
        if let tab {
            withAnimation(isOpen ? AppMotion.snappy : nil) { self.tab = tab }
        }
        openReason = reason
        if reason == .hotKey { searchFocusRequest += 1 }
        guard !isOpen else { return }
        closeToken += 1
        withAnimation(AppMotion.open) {
            isOpen = true
            expandedWidth = true
            expandedHeight = true
        }
    }

    /// Zona del panel visible, segun la pestaña (la bandeja es mas baja).
    var openHotRect: CGRect {
        metrics.openHotRect(searchRow: tab.hasToolbar)
    }

    /// Zona del notch cerrado que lo abre, incluida la actividad de musica.
    var closedHotRect: CGRect {
        let rect = metrics.closedHotRect
        guard nowPlaying?.isPlaying == true else { return rect }
        return rect.insetBy(dx: -NotchMetrics.activitySide, dy: 0)
    }

    func close() {
        guard isOpen else { return }
        closeToken += 1
        let token = closeToken
        isOpen = false
        withAnimation(AppMotion.close) {
            expandedWidth = false
            expandedHeight = false
        } completion: { [weak self] in
            guard let self, !self.isOpen, token == self.closeToken else { return }
            self.searchText = ""
            self.onDidClose?()
        }
    }

    /// Tras copiar un elemento: con el atajo el usuario quiere volver a pegar ya.
    func didCopy() {
        if openReason == .hotKey { close() }
    }

    func beginDragOut() {
        isDraggingOut = true
        onDragOutStarted?()
    }

    func dropTargetChanged(_ targeted: Bool) {
        if targeted, !isDraggingOut {
            open(reason: isOpen ? openReason : .drag, tab: .shelf)
        }
        onDropTargetChanged?(targeted)
    }
}
