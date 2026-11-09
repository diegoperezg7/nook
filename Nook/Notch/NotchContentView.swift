import AppKit
import SwiftUI

/// Contenido del panel abierto: control segmentado (bandeja / historial) a un lado del
/// notch, menu de opciones al otro y, debajo, la seccion elegida.
struct NotchContentView: View {
    @Bindable var model: NotchViewModel
    let store: ItemStore
    @Namespace private var tabNamespace

    static let margin: CGFloat = 16

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
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            tabs.frame(maxWidth: .infinity, alignment: .leading)
            // Hueco del notch fisico: ahi no se ve nada.
            Color.clear.frame(width: model.metrics.hasNotch ? model.metrics.notchWidth : 0)
            menu.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, 4)
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
        let selected = model.tab == tab
        return Button {
            withAnimation(AppMotion.snappy) { model.tab = tab }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? AppColors.onAccent : AppColors.textPrimary.opacity(0.85))
                .frame(width: 36, height: 24)
                .background { if selected { selectionPill } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityLabel(Text(title))
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
                Button("Vaciar bandeja", systemImage: "trash", role: .destructive) { store.clearShelf() }
            } else {
                Button("Borrar historial (salvo fijados)", systemImage: "trash", role: .destructive) {
                    store.clearHistory()
                }
            }
            Divider()
            Button("Salir de Nook", systemImage: "power") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.textPrimary.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(Circle().fill(AppColors.controlTrack))
                .overlay(Circle().strokeBorder(AppColors.cardBorder, lineWidth: 0.5))
                .contentShape(Circle())
        }
        // Estilo boton + plain: respeta la etiqueta propia (el borderless la recorta).
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Más opciones"))
    }
}
