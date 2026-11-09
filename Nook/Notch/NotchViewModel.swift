import AppKit
import SwiftUI

@Observable
@MainActor
final class NotchViewModel {
    enum Tab: Hashable { case shelf, clipboard }

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
    /// La forma se anima en dos ejes con muelles distintos: primero se ensancha y
    /// luego "gotea" hacia abajo (al cerrar, al reves). Es lo que da el efecto liquido.
    private(set) var expandedWidth = false
    private(set) var expandedHeight = false
    /// El raton se acerca al notch: se asoma un poco antes de abrirse.
    private(set) var isPeeking = false
    /// Cuenta las aperturas: cada una dispara el brote del panel desde la gota.
    private(set) var revealTrigger = 0
    /// Cada incremento hace pasar un destello de luz por el cristal.
    private(set) var glintTrigger = 0
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

    @ObservationIgnored var onDidClose: (() -> Void)?
    @ObservationIgnored var onDropTargetChanged: ((Bool) -> Void)?
    @ObservationIgnored var onDragOutStarted: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored private var closeToken = 0

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
        withAnimation(AppMotion.openWidth) {
            isOpen = true
            expandedWidth = true
        }
        withAnimation(AppMotion.openHeight) {
            isPeeking = false
            expandedHeight = true
        }
        // El cristal del panel nace de la gota: un circulo que crece desde ella.
        if !AppMotion.reduceMotion { revealTrigger += 1 }
        if !AppMotion.reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self, self.isOpen else { return }
                self.glintTrigger += 1
            }
        }
    }

    func close() {
        guard isOpen else { return }
        closeToken += 1
        let token = closeToken
        isOpen = false
        withAnimation(AppMotion.closeHeight) { expandedHeight = false }
        withAnimation(AppMotion.closeWidth) {
            expandedWidth = false
        } completion: { [weak self] in
            guard let self, !self.isOpen, token == self.closeToken else { return }
            self.searchText = ""
            self.onDidClose?()
        }
    }

    /// Asomarse: el notch crece un poco al acercar el raton, antes de abrirse.
    func setPeeking(_ peeking: Bool) {
        guard !isOpen, peeking != isPeeking, !AppMotion.reduceMotion else { return }
        withAnimation(AppMotion.peek) { isPeeking = peeking }
    }

    /// Destello al guardar algo en la bandeja.
    func celebrateDrop() {
        guard !AppMotion.reduceMotion else { return }
        glintTrigger += 1
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
