import AppKit
import SwiftData
import SwiftUI

/// Coloca el panel sobre el notch y decide cuando abrir y cerrar segun el raton.
///
/// La ventana tiene siempre el tamaño del panel abierto y nunca se redimensiona:
/// - Redimensionarla en mitad de un arrastre hacia que el sistema no entregara el
///   soltado (el destino se calcula con la ventana del principio del arrastre).
/// - Su zona transparente bloquearia los clics de la barra de menus, asi que solo
///   acepta raton cuando el cursor esta sobre la forma visible (`ignoresMouseEvents`).
@MainActor
final class NotchController {
    let model: NotchViewModel
    private let panel = NotchPanel()
    private let store: ItemStore
    private var monitors: [Any] = []
    private var pendingOpen: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var previousApp: NSRunningApplication?
    /// Menu contextual o de opciones abierto: suele salirse del panel, y elegir una
    /// opcion con el cursor fuera no debe cerrarlo antes de que la accion termine.
    private var isMenuOpen = false

    init(store: ItemStore, container: ModelContainer) {
        self.store = store
        let screen = Self.targetScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        model = NotchViewModel(metrics: NotchMetrics.make(for: screen))

        let root = NotchRootView(model: model, store: store).modelContainer(container)
        // La vista SwiftUI va dentro de un contenedor con autoresizing: como
        // contentView directo, redimensionar la ventana provocaba un bucle de
        // "Update Constraints in Window" y AppKit abortaba la app.
        let hosting = NotchHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        let container = NSView()
        container.addSubview(hosting)
        panel.contentView = container
        hosting.frame = container.bounds
        panel.onCancel = { [weak self] in self?.model.close() }

        model.onDidClose = { [weak self] in self?.didClose() }
        // Durante el arrastre no llegan eventos: se programa ya la comprobacion,
        // que esperara a que se suelte el boton.
        model.onDragOutStarted = { [weak self] in self?.scheduleClose() }
        model.onDropTargetChanged = { [weak self] targeted in
            if !targeted { self?.scheduleCloseIfMouseOutside() }
        }
    }

    func start() {
        refreshScreen()
        installMouseMonitors()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreen() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isMenuOpen = true }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isMenuOpen = false
                // La accion elegida puede tardar (OCR, zip): margen antes de cerrar.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.scheduleCloseIfMouseOutside() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.openReason == .hotKey else { return }
                self.model.close()
            }
        })
    }

    /// Con notch: la pantalla con notch. Sin notch: la principal, si el ajuste lo permite.
    static func targetScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) { return notched }
        guard UserDefaults.standard.bool(forKey: SettingsKey.showWithoutNotch) else { return nil }
        return NSScreen.main ?? NSScreen.screens.first
    }

    func refreshScreen() {
        guard let screen = Self.targetScreen() else {
            model.close()
            panel.orderOut(nil)
            return
        }
        let metrics = NotchMetrics.make(for: screen)
        if metrics != model.metrics { model.metrics = metrics }
        panel.setFrame(metrics.openWindowFrame, display: true, animate: false)
        updateMouseInteraction()
        panel.orderFrontRegardless()
    }

    func toggleFromHotKey() {
        if model.isOpen {
            model.close()
        } else {
            // Un panel que no activa la app no recibe teclado si se abre por codigo:
            // hay que activar la app. Al cerrar se devuelve el foco a la anterior
            // para que ⌘V pegue donde estaba el usuario.
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            model.open(reason: .hotKey, tab: .clipboard)
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Ventana

    private func didClose() {
        updateMouseInteraction()
        if let previousApp {
            previousApp.activate()
            self.previousApp = nil
        }
        // Soltar el teclado: si no, el panel cerrado seguiria siendo key.
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Raton

    /// Los monitores globales de raton no piden permisos (los de teclado si).
    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouse() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouse() }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Solo la forma visible acepta raton; el resto de la ventana deja pasar los clics.
    private func updateMouseInteraction() {
        let point = NSEvent.mouseLocation
        let hotRect = model.isOpen ? model.metrics.openHotRect : model.metrics.closedHotRect
        let interactive = hotRect.contains(point)
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }

    private func handleMouse() {
        guard panel.isVisible else { return }
        updateMouseInteraction()
        let point = NSEvent.mouseLocation
        if model.isOpen {
            guard model.openReason == .hover || model.openReason == .drag else { return }
            if model.metrics.openHotRect.contains(point) || model.isDropTargeted {
                cancelClose()
            } else {
                scheduleClose()
            }
        } else if model.metrics.closedHotRect.contains(point) {
            model.setPeeking(true)
            scheduleOpen()
        } else {
            pendingOpen?.cancel()
            pendingOpen = nil
            // Cerca del notch se asoma; al alejarse vuelve a su sitio.
            model.setPeeking(model.metrics.closedHotRect.insetBy(dx: -48, dy: -28).contains(point))
        }
    }

    /// Un respiro de 100 ms evita abrir al cruzar el notch de paso hacia un menu (y deja
    /// ver como se asoma).
    private func scheduleOpen() {
        guard pendingOpen == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingOpen = nil
            if self.model.metrics.closedHotRect.contains(NSEvent.mouseLocation) {
                self.model.open(reason: .hover)
            }
        }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func scheduleClose() {
        guard pendingClose == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingClose = nil
            // Mientras dura un arrastre hacia fuera no llegan eventos de raton:
            // se vuelve a mirar hasta que se suelte el boton.
            if self.model.isDraggingOut {
                if NSEvent.pressedMouseButtons & 1 != 0 {
                    self.scheduleClose()
                    return
                }
                self.model.isDraggingOut = false
            }
            if self.isMenuOpen { return }
            if !self.model.metrics.openHotRect.contains(NSEvent.mouseLocation), !self.model.isDropTargeted {
                self.model.close()
            }
        }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func scheduleCloseIfMouseOutside() {
        guard model.isOpen, model.openReason == .hover || model.openReason == .drag else { return }
        if !model.metrics.openHotRect.contains(NSEvent.mouseLocation) { scheduleClose() }
    }

    private func cancelClose() {
        pendingClose?.cancel()
        pendingClose = nil
    }

    #if DEBUG
    /// Abre el panel para capturas: `-PerchOpen shelf|clipboard`.
    func applyDebugLaunchArguments() {
        guard let value = UserDefaults.standard.string(forKey: "PerchOpen") else { return }
        model.open(reason: .pinned, tab: value == "clipboard" ? .clipboard : .shelf)
    }
    #endif
}
