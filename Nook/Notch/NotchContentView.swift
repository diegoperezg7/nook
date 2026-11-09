import AppKit
import SwiftUI

/// Contenido del panel abierto: control segmentado (bandeja / historial) a un lado del
/// notch, menu de opciones al otro y, debajo, la seccion elegida.
struct NotchContentView: View {
    @Bindable var model: NotchViewModel
    let store: ItemStore
    @Namespace private var tabNamespace

    /// Margen interior uniforme entre el borde visible del panel y su contenido.
    static let margin: CGFloat = 16
    /// Espacio entre bloques (cabecera, buscador, contenido).
    static let spacing: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch model.tab {
                case .shelf:
                    ShelfView(model: model, store: store)
                case .clipboard:
                    ClipboardView(model: model, store: store)
                }
            }
            .padding(.top, Self.spacing)
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
        .padding(.top, 6)
        .frame(height: model.metrics.headerHeight)
    }

    /// Control segmentado al estilo del Centro de control: carril translucido y la
    /// pestaña activa rellena con el acento, que se desliza al cambiar.
    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton(.shelf, title: "Bandeja", icon: "tray.full.fill")
            tabButton(.clipboard, title: "Portapapeles", icon: "list.clipboard.fill")
        }
        .padding(2)
        .background(Capsule().fill(AppColors.controlTrack))
        .overlay(Capsule().strokeBorder(AppColors.cardBorder, lineWidth: 0.5))
    }

    private func tabButton(_ tab: NotchViewModel.Tab, title: LocalizedStringKey, icon: String) -> some View {
        TabButton(
            title: title, icon: icon, selected: model.tab == tab,
            selection: selectionPill
        ) {
            withAnimation(AppMotion.snappy) { model.tab = tab }
        }
    }

    /// Un cristal tintado aqui se compone encima del icono y, sobre el panel de
    /// cristal, pierde el color: la seleccion es una capsula solida que se desliza.
    private var selectionPill: some View {
        Capsule()
            .fill(AppColors.accent)
            .shadow(color: AppColors.accent.opacity(0.45), radius: 4, y: 1)
            .matchedGeometryEffect(id: "tab", in: tabNamespace)
    }

    private var menu: some View {
        Menu {
            Button("Ajustes…", systemImage: "gearshape") { model.onOpenSettings?() }
            Divider()
            if model.tab == .shelf {
                Button("Añadir archivos…", systemImage: "plus") { chooseFiles() }
                Button("Vaciar bandeja…", systemImage: "trash", role: .destructive) { confirmClearShelf() }
            } else {
                Button("Borrar historial…", systemImage: "trash", role: .destructive) { confirmClearHistory() }
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

/// Pestaña del control segmentado: la activa en azul; las demas se iluminan al pasar.
private struct TabButton<Selection: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let selected: Bool
    let selection: Selection
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? AppColors.onAccent : (hovering ? AppColors.accent : AppColors.textPrimary.opacity(0.8)))
                .frame(width: 38, height: 26)
                .background {
                    if selected {
                        selection
                    } else if hovering {
                        Capsule().fill(AppColors.accentWell)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppMotion.snappy, value: hovering)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}

/// Boton redondo de la cabecera: se tiñe de azul al pasar el raton.
private struct CircleIconLabel: View {
    let icon: String
    @State private var hovering = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(hovering ? AppColors.accent : AppColors.textPrimary.opacity(0.8))
            .frame(width: 30, height: 30)
            .background(Circle().fill(hovering ? AppColors.accentWell : AppColors.controlTrack))
            .overlay(Circle().strokeBorder(hovering ? AppColors.accentBorder : AppColors.cardBorder, lineWidth: hovering ? 1 : 0.5))
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(AppMotion.snappy, value: hovering)
    }
}
