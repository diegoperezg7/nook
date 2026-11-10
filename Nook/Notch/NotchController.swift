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
    private let hud: SystemHUD
    private let menuBar = MenuBarSpace()
    private var monitors: [Any] = []
    private var pendingOpen: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var previousApp: NSRunningApplication?
    /// Menu contextual o de opciones abierto: suele salirse del panel, y elegir una
    /// opcion con el cursor fuera no debe cerrarlo antes de que la accion termine.
    private var isMenuOpen = false

    init(store: ItemStore, container: ModelContainer, screenshots: ScreenshotLibrary, agents: AgentMonitor, hud: SystemHUD, calendar: CalendarService, focus: FocusTimer, mail: MailService, battery: BatteryCenter) {
        self.hud = hud
        self.store = store
        let screen = Self.targetScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        model = NotchViewModel(metrics: NotchMetrics.make(for: screen))

        let root = NotchRootView(model: model, store: store)
            .modelContainer(container)
            .environment(screenshots)
            .environment(agents)
            .environment(hud)
            .environment(calendar)
            .environment(focus)
            .environment(mail)
            .environment(battery)
            .environment(menuBar)
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
        model.onPreviewEnded = { [weak self] in self?.scheduleCloseIfMouseOutside() }
        model.onDropTargetChanged = { [weak self] targeted in
            if !targeted { self?.scheduleCloseIfMouseOutside() }
        }
    }

    func start() {
        refreshScreen()
        installMouseMonitors()
        observeHUD()
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
        menuBar.start(for: screen, notchWidth: metrics.notchWidth)
        panel.setFrame(metrics.openWindowFrame, display: true, animate: false)
        updateMouseInteraction()
        panel.orderFrontRegardless()
    }

    /// Fuera de capturas y grabaciones (el notch abierto puede tener cosas privadas).
    func setHiddenFromCaptures(_ hidden: Bool) {
        panel.sharingType = hidden ? .none : .readOnly
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
        let paste = model.pasteOnClose
        model.pasteOnClose = false
        if let previousApp {
            previousApp.activate()
            self.previousApp = nil
            if paste, UserDefaults.standard.bool(forKey: SettingsKey.pasteOnSelect) {
                if AXAccess.isTrusted {
                    // Que la app anterior tenga ya el foco antes del ⌘V.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { AXAccess.paste() }
                } else {
                    hud.show(.notice(icon: "hand.raised.fill", text: String(localized: "Copiado · activa Accesibilidad para pegar")), for: 2.5)
                }
            }
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
        // Un clic en otra app cierra el panel. Hace falta aparte del cierre por perder
        // el foco: con la vista previa abierta el foco ya lo tiene su ventana, y al
        // pulsar fuera el panel no vuelve a perderlo.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeOnOutsideClick() }
        }) {
            monitors.append(outside)
        }
    }

    private func closeOnOutsideClick() {
        if !model.isOpen, hud.activated != nil, !model.metrics.previewHotRect.contains(NSEvent.mouseLocation) {
            hud.dismissActivated()
            return
        }
        guard model.isOpen, model.openReason != .pinned, !model.isDraggingOut,
              !model.openHotRect.contains(NSEvent.mouseLocation) else { return }
        model.isPreviewing = false
        model.close()
    }

    /// Solo la forma visible acepta raton; el resto de la ventana deja pasar los clics.
    /// Cerrado y con un aviso que se puede pulsar, tambien sus alas (pero abrir por
    /// hover sigue siendo solo con `closedHotRect`).
    private func updateMouseInteraction() {
        let point = NSEvent.mouseLocation
        let hotRect = model.isOpen ? model.openHotRect : closedClickRect
        let interactive = hotRect.contains(point)
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }

    /// La misma forma que dibuja `NotchRootView`: la tarjeta de un aviso pulsado o
    /// el aviso visible.
    private var closedClickRect: CGRect {
        if hud.activated != nil { return model.metrics.previewHotRect }
        guard !model.isCollapsing, hud.isActionable, let notice = hud.current ?? hud.ambient else { return model.closedHotRect }
        let free = menuBar.free
        let sides = HUDSides.make(desired: HUDActivity.side(for: notice), leftFree: free.left, rightFree: free.right)
        return model.metrics.closedNoticeRect(sides: sides)
    }

    /// Al salir o irse un aviso (o su tarjeta) la zona que acepta raton cambia: se
    /// recalcula ya, sin esperar a que se mueva el raton (si no, el primer clic sobre
    /// un ala recien aparecida atravesaria el panel).
    private func observeHUD() {
        withObservationTracking {
            _ = hud.current
            _ = hud.activated
            _ = hud.ambient
        } onChange: { [weak self] in
            // onChange llega antes del cambio: se mira en la siguiente vuelta.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.updateMouseInteraction()
                    self?.observeHUD()
                }
            }
        }
    }

    private func handleMouse() {
        guard panel.isVisible else { return }
        updateMouseInteraction()
        let point = NSEvent.mouseLocation
        if model.isOpen {
            guard model.openReason == .hover || model.openReason == .drag else { return }
            if model.openHotRect.contains(point) || model.isDropTargeted {
                cancelClose()
            } else {
                scheduleClose()
            }
        } else if hud.activated != nil {
            // Tarjeta de un aviso: se cierra al sacar el raton, como el panel.
            if model.metrics.previewHotRect.contains(point) { cancelClose() } else { scheduleClose() }
        } else if model.closedHotRect.contains(point) {
            setPeeking(true)
            scheduleOpen()
        } else {
            setPeeking(false)
            pendingOpen?.cancel()
            pendingOpen = nil
        }
    }

    /// Al entrar en el notch se asoma (escala 1,02) con un toque del trackpad.
    private func setPeeking(_ peeking: Bool) {
        guard model.isPeeking != peeking else { return }
        if peeking {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(AppMotion.peek) { model.isPeeking = peeking }
    }

    /// Un respiro (100 ms por defecto, configurable) evita abrir al cruzar el notch
    /// de paso hacia un menu y deja ver como se asoma.
    private func scheduleOpen() {
        guard pendingOpen == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingOpen = nil
            if self.model.closedHotRect.contains(NSEvent.mouseLocation) {
                // Con una reunion a punto de empezar se abre en el calendario (Unirse).
                if case .meeting = self.hud.ambient {
                    self.model.open(reason: .hover, tab: .calendar)
                } else if case .agent = self.hud.current {
                    // Con el aviso de un agente, a sus tarjetas (un clic y a su terminal).
                    self.model.open(reason: .hover, tab: .agents)
                } else if case .usage = self.hud.current {
                    self.model.open(reason: .hover, tab: .agents)
                } else if case .mail = self.hud.current {
                    self.model.open(reason: .hover, tab: .mail)
                } else {
                    self.model.open(reason: .hover)
                }
            }
        }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + UserDefaults.standard.double(forKey: SettingsKey.openDelay), execute: work)
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
            // Cerrado solo queda la tarjeta de un aviso pulsado.
            if !self.model.isOpen {
                if !self.model.metrics.previewHotRect.contains(NSEvent.mouseLocation) { self.hud.dismissActivated() }
                return
            }
            // Con un menu o la vista previa abiertos el cursor suele estar fuera del panel.
            if self.isMenuOpen || self.model.isPreviewing { return }
            if !self.model.openHotRect.contains(NSEvent.mouseLocation), !self.model.isDropTargeted {
                self.model.close()
            }
        }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + UserDefaults.standard.double(forKey: SettingsKey.closeDelay), execute: work)
    }

    private func scheduleCloseIfMouseOutside() {
        guard model.isOpen, model.openReason == .hover || model.openReason == .drag else { return }
        if !model.openHotRect.contains(NSEvent.mouseLocation) { scheduleClose() }
    }

    private func cancelClose() {
        pendingClose?.cancel()
        pendingClose = nil
    }

    #if DEBUG
    /// Abre el panel para capturas: `-NookOpen shelf|clipboard|screenshots|calendar|agents`.
    func applyDebugLaunchArguments() {
        guard let value = UserDefaults.standard.string(forKey: "NookOpen"), value != "settings" else { return }
        let tab: NotchViewModel.Tab = switch value {
        case "clipboard": .clipboard
        case "screenshots": .screenshots
        case "agents": .agents
        case "calendar": .calendar
        case "mail": .mail
        default: .shelf
        }
        model.open(reason: .pinned, tab: tab)
    }
    #endif
}
