import AppKit
import QuickLookUI
import SwiftUI

/// Ventana sin borde por encima de la barra de menus. No activa la app al pulsarla
/// (la app de delante sigue siendo la de delante) y solo pasa a ser key cuando hace
/// falta teclado: el buscador o el atajo global.
final class NotchPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        // Siempre oscuro, como la Dynamic Island: el panel es negro como el notch y su
        // contenido (y los popovers y menus que salen de el) tiene que leerse sobre negro.
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit baja las ventanas que tocan la barra de menus; esta tiene que estar ahi.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Escape cierra el panel.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    // Quick Look busca su controlador en la cadena de respuesta.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookPresenter.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
}

/// El primer clic sobre el panel actua directamente aunque la app no este activa.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
