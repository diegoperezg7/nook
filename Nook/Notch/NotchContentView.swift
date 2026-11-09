import AppKit
import SwiftUI

/// Contenido del panel abierto: control segmentado (bandeja / historial) a un lado del
/// notch, menu de opciones al otro y, debajo, la seccion elegida.
struct NotchContentView: View {
    @Bindable var model: NotchViewModel
    let store: ItemStore
    @Environment(ScreenshotLibrary.self) private var screenshots
    @Environment(AgentMonitor.self) private var agents
    @Environment(CalendarService.self) private var calendarService
    @Namespace private var tabNamespace

    /// Margen interior entre el borde visible del panel y su contenido.
    static let margin = NotchMetrics.sideMargin

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch model.tab {
                case .shelf:
                    ShelfView(model: model, store: store)
                case .clipboard:
                    ClipboardView(model: model, store: store)
                case .screenshots:
                    ScreenshotsView(model: model, store: store, library: screenshots)
                case .calendar:
                    CalendarView(calendar: calendarService)
                case .agents:
                    AgentsView(monitor: agents)
                }
            }
            .padding(.top, NotchMetrics.topSpacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // La forma abierta tiene orejas concavas arriba: su cuerpo visible es mas
        // estrecho que la ventana. Sin esto los margenes se quedaban en 2 pt.
        .padding(.horizontal, NotchMetrics.openEar)
    }

    private var header: some View {
        HStack(spacing: 0) {
            tabs.frame(maxWidth: .infinity, alignment: .leading)
            // Hueco del notch fisico: ahi no se ve nada.
            Color.clear.frame(width: model.metrics.hasNotch ? model.metrics.notchWidth : 0)
            HStack(spacing: 8) {
                if model.tab == .shelf {
                    Button { chooseFiles() } label: {
                        CircleIconLabel(icon: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(Text("Añadir archivos…"))
                    .accessibilityLabel(Text("Añadir archivos…"))
                    .transition(.scale.combined(with: .opacity))
                }
                menu
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(AppMotion.snappy, value: model.tab)
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, 4)
        .frame(height: model.metrics.headerHeight)
    }

    /// Pestañas: dos capsulas de cristal; la activa, tintada con el acento.
    /// Pestañas juntas en una sola capsula de cristal (control segmentado); la activa
    /// lleva una pildora azul que se desliza. Asi caben todas en el lado del notch.
    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton(.shelf, title: "Bandeja", icon: "tray.full.fill")
            tabButton(.clipboard, title: "Portapapeles", icon: "list.clipboard.fill")
            tabButton(.screenshots, title: "Capturas", icon: "camera.viewfinder")
            tabButton(.calendar, title: "Calendario", icon: "calendar")
            tabButton(.agents, title: "Agentes de IA", icon: "brain", logo: AgentIcons.claude)
        }
        .padding(3)
        .liquidGlass(in: Capsule())
    }

    private func tabButton(_ tab: NotchViewModel.Tab, title: LocalizedStringKey, icon: String, logo: NSImage? = nil) -> some View {
        TabButton(title: title, icon: icon, logo: logo, selected: model.tab == tab, namespace: tabNamespace) {
            withAnimation(AppMotion.snappy) { model.tab = tab }
        }
    }

    private var menu: some View {
        Menu {
            Button("Ajustes…", systemImage: "gearshape") { model.onOpenSettings?() }
            Divider()
            switch model.tab {
            case .shelf:
                Button("Añadir archivos…", systemImage: "plus") { chooseFiles() }
                Button("Vaciar bandeja…", systemImage: "trash", role: .destructive) { confirmClearShelf() }
            case .clipboard:
                Button("Borrar historial…", systemImage: "trash", role: .destructive) { confirmClearHistory() }
            case .agents, .calendar:
                EmptyView()
            case .screenshots:
                Button("Cambiar carpeta de capturas…", systemImage: "folder.badge.gearshape") {
                    model.close()
                    screenshots.chooseFolder()
                }
                if screenshots.folder != nil {
                    Button("Mostrar la carpeta en Finder", systemImage: "folder") { screenshots.showFolderInFinder() }
                }
            }
            Divider()
            Button("Salir de Nook", systemImage: "power") { NSApp.terminate(nil) }
        } label: {
            CircleIconLabel(icon: "ellipsis")
        }
        // Estilo boton + plain: respeta la etiqueta propia (el borderless la recorta).
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Más opciones"))
    }

    /// El notch esta por encima de todo: se cierra para no tapar el dialogo.
    private func chooseFiles() {
        model.close()
        FileImporter.chooseFiles(into: store)
    }

    // MARK: - Borrar con confirmacion

    /// Borrar es lo unico que pierde datos: siempre se pregunta antes.
    private func confirmClearShelf() {
        guard confirm(
            title: String(localized: "¿Vaciar la bandeja?"),
            message: String(localized: "Se borrarán todos los elementos de la bandeja. No se puede deshacer."),
            action: String(localized: "Vaciar")
        ) else { return }
        store.clearShelf()
    }

    private func confirmClearHistory() {
        guard confirm(
            title: String(localized: "¿Borrar el historial?"),
            message: String(localized: "Se borrarán todos los elementos del historial salvo los fijados. No se puede deshacer."),
            action: String(localized: "Borrar")
        ) else { return }
        store.clearHistory()
    }

    private func confirm(title: String, message: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        let destructive = alert.addButton(withTitle: action)
        destructive.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancelar"))
        // El notch esta por encima de todo: se cierra para no tapar la alerta.
        model.close()
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Segmento del control de pestañas. La activa, sobre una pildora azul solida (un
/// cristal tintado sobre el panel pierde el color) que se desliza entre segmentos.
private struct TabButton: View {
    let title: LocalizedStringKey
    let icon: String
    /// Logo oficial de una app (Spotify, Claude...) en lugar del simbolo.
    var logo: NSImage?
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .frame(width: 17, height: 17)
                        .scaleEffect(hovering && !selected ? 1.08 : 1)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? AppColors.onAccent : (hovering ? AppColors.accent : AppColors.textPrimary.opacity(0.85)))
                }
            }
                .frame(width: 30, height: 24)
                .background {
                    if selected {
                        Capsule()
                            .fill(AppColors.accent)
                            .shadow(color: AppColors.accent.opacity(0.4), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    } else if hovering {
                        Capsule().fill(AppColors.notchText.opacity(0.08))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppMotion.snappy, value: hovering)
        .animation(AppMotion.snappy, value: selected)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}

/// Boton redondo de cristal de la cabecera: el icono se tiñe de azul al pasar.
private struct CircleIconLabel: View {
    let icon: String
    @State private var hovering = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(hovering ? AppColors.accent : AppColors.textPrimary.opacity(0.85))
            .frame(width: 30, height: 30)
            .liquidGlass(in: Circle(), interactive: true)
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(AppMotion.snappy, value: hovering)
    }
}
