import AppKit
import ApplicationServices
import NaturalLanguage
import SwiftUI

/// Texto seleccionado: al soltar el raton tras seleccionar (arrastrando o con doble
/// clic) en cualquier app, sale junto al cursor una pastilla con acciones. El texto
/// se lee por Accesibilidad (AXSelectedText) y no se guarda en ningun sitio.
@MainActor
final class SelectionActions {
    private let store: ItemStore
    private var monitors: [Any] = []
    private var downPoint: NSPoint?
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    init(store: ItemStore) {
        self.store = store
    }

    func apply() {
        let enabled = UserDefaults.standard.bool(forKey: SettingsKey.selectionActions)
        if enabled, monitors.isEmpty {
            let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
                let isLeftDown = event.type == .leftMouseDown
                MainActor.assumeIsolated {
                    self?.hide()
                    if isLeftDown { self?.downPoint = NSEvent.mouseLocation }
                }
            }
            let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                let clicks = event.clickCount
                MainActor.assumeIsolated { self?.mouseUp(clicks: clicks) }
            }
            monitors = [down, up].compactMap { $0 }
        } else if !enabled {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            hide()
        }
    }

    private func mouseUp(clicks: Int) {
        let point = NSEvent.mouseLocation
        let dragged = downPoint.map { hypot($0.x - point.x, $0.y - point.y) > 6 } ?? false
        guard dragged || clicks >= 2, AXAccess.isTrusted,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        // La app actualiza la seleccion justo despues del mouseUp.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let text = Self.selectedText(), !text.isEmpty else { return }
            self?.show(text, at: point)
        }
    }

    static func selectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 10_000 ? String(trimmed.prefix(10_000)) : trimmed
    }

    private func show(_ text: String, at point: NSPoint) {
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        let view = SelectionPill { [weak self] action in
            self?.run(action, text)
            self?.hide()
        }
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        let size = hosting.fittingSize
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 14)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            origin.x = min(max(origin.x, screen.frame.minX + 6), screen.frame.maxX - size.width - 6)
            if origin.y + size.height > screen.visibleFrame.maxY { origin.y = point.y - size.height - 14 }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppMotion.reduceMotion ? 0 : 0.15
            panel.animator().alphaValue = 1
        }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func hide() {
        hideWork?.cancel()
        guard let panel, panel.isVisible else { return }
        // Un clic en la pastilla es un evento local, no global: este cierre no se
        // adelanta a la accion.
        panel.orderOut(nil)
    }

    enum Action { case copy, search, translate, shelf }

    private func run(_ action: Action, _ text: String) {
        switch action {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .search:
            open("https://www.google.com/search", ["q": text])
        case .translate:
            // Al idioma del sistema; si ya esta en el, al ingles.
            let mine = Locale.current.language.languageCode?.identifier ?? "es"
            let detected = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
            open("https://translate.google.com/", ["sl": "auto", "tl": detected == mine ? "en" : mine, "text": text, "op": "translate"])
        case .shelf:
            withAnimation(AppMotion.snappy) { store.addShelfText(text) }
        }
    }

    private func open(_ base: String, _ query: [String: String]) {
        var components = URLComponents(string: base)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}

private struct SelectionPill: View {
    let onAction: (SelectionActions.Action) -> Void
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 2) {
            PillButton(icon: "doc.on.doc", title: "Copiar") { onAction(.copy) }
            PillButton(icon: "magnifyingglass", title: "Buscar") { onAction(.search) }
            PillButton(icon: "character.bubble", title: "Traducir") { onAction(.translate) }
            PillButton(icon: "tray.and.arrow.down", title: "A la bandeja") { onAction(.shelf) }
        }
        .padding(4)
        .background(Capsule().fill(AppColors.floating))
        .overlay(Capsule().strokeBorder(AppColors.notchText.opacity(0.14), lineWidth: 1))
        .scaleEffect(appeared || AppMotion.reduceMotion ? 1 : 0.85)
        .padding(6)
        .onAppear { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { appeared = true } }
    }
}

private struct PillButton: View {
    let icon: String
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(hovering ? AppColors.onAccent : AppColors.notchText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(hovering ? AppColors.accent : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppMotion.snappy, value: hovering)
    }
}
