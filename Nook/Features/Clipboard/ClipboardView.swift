import AppKit
import SwiftData
import SwiftUI

/// Historial del portapapeles con buscador. Los fijados van primero.
struct ClipboardView: View {
    @Bindable var model: NotchViewModel
    let store: ItemStore

    @Query(
        filter: #Predicate<NotchItem> { $0.originRaw == "clipboard" },
        sort: \NotchItem.createdAt, order: .reverse,
        animation: .spring(response: 0.3, dampingFraction: 0.8)
    )
    private var items: [NotchItem]

    @FocusState private var searchFocused: Bool
    @State private var filter = HistoryFilter.all
    /// Tarjeta elegida con ← →; Intro la copia. Vuelve a la primera al buscar.
    @State private var highlight = 0
    @AppStorage(SettingsKey.captureClipboard) private var captureEnabled = true

    private var visibleItems: [NotchItem] {
        let query = model.searchText.trimmingCharacters(in: .whitespaces)
        let filtered = items.filter { filter.includes($0) && (query.isEmpty || $0.matches(query)) }
        return filtered.filter(\.isPinned) + filtered.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                searchField
                if let notice {
                    notice
                }
                filterBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NotchContentView.margin)
            .frame(height: NotchMetrics.searchRowHeight - 10)
            .padding(.bottom, 10)

            if visibleItems.isEmpty {
                emptyState
            } else {
                ItemStrip(items: visibleItems, store: store, model: model,
                          highlightedID: searchFocused ? visibleItems[min(highlight, visibleItems.count - 1)].id : nil)
            }
        }
        .onChange(of: model.searchFocusRequest, initial: true) { _, _ in
            if model.openReason == .hotKey { searchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(searchFocused ? AppColors.accent : AppColors.textSecondary)
            TextField("Buscar en el historial", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .focused($searchFocused)
                .onSubmit(copyFirst)
                // Con texto, las flechas mueven el cursor; sin texto, eligen tarjeta.
                .onKeyPress(.leftArrow) { move(-1) }
                .onKeyPress(.rightArrow) { move(1) }
                .onChange(of: model.searchText) { highlight = 0 }
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .liquidGlass(in: Capsule())
        .overlay {
            if searchFocused { Capsule().strokeBorder(AppColors.accent, lineWidth: 1.5) }
        }
        .contentShape(Capsule())
        .onTapGesture { searchFocused = true }
        .animation(AppMotion.snappy, value: searchFocused)
    }

    /// Filtro por tipo: iconos en un carril; el activo en azul.
    private var filterBar: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilter.allCases) { option in
                let selected = filter == option
                Button {
                    withAnimation(AppMotion.snappy) { filter = option }
                } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? AppColors.onAccent : AppColors.textPrimary.opacity(0.75))
                        .frame(width: 30, height: 26)
                        .background { if selected { Capsule().fill(AppColors.accent) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(Text(option.title))
                .accessibilityLabel(Text(option.title))
            }
        }
        .padding(3)
        .liquidGlass(in: Capsule())
        .fixedSize()
    }

    /// Aviso cuando el historial no se esta guardando y por que.
    private var notice: AnyView? {
        if !captureEnabled {
            return AnyView(NoticePill(text: "En pausa", detail: "El historial no guarda lo que copias", action: "Ajustes") { model.onOpenSettings?() })
        }
        switch model.clipboardAccess {
        case .allowed:
            return nil
        case .needsPermission, .denied:
            return AnyView(NoticePill(text: "Sin acceso", detail: "Visor no tiene acceso al portapapeles", action: "Permitir…") {
                NSWorkspace.shared.open(ClipboardAccess.settingsURL)
            })
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.searchText.isEmpty && filter == .all ? "list.clipboard" : "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 38, height: 38)
                .background(Circle().fill(AppColors.accentWell))
                .overlay(Circle().strokeBorder(AppColors.accentBorder, lineWidth: 1))
            VStack(spacing: 6) {
                Text(emptyTitle)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)
                if model.searchText.isEmpty, filter == .all {
                    HStack(spacing: 6) {
                        Text(verbatim: "⌃⌘V")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.accentWell))
                            .overlay(Capsule().strokeBorder(AppColors.accentBorder, lineWidth: 0.75))
                        Text("abre el historial desde cualquier app")
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: NotchMetrics.cardRowHeight)
        .transition(.opacity)
    }

    private var emptyTitle: LocalizedStringKey {
        if !model.searchText.isEmpty || filter != .all { return "Sin resultados" }
        return "Copia algo y aparecerá aquí"
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard model.searchText.isEmpty, !visibleItems.isEmpty else { return .ignored }
        highlight = min(max(highlight + step, 0), visibleItems.count - 1)
        return .handled
    }

    private func copyFirst() {
        guard !visibleItems.isEmpty else { return }
        let first = visibleItems[min(highlight, visibleItems.count - 1)]
        store.copyToPasteboard(first)
        model.didCopy()
    }
}

private struct NoticePill: View {
    /// Corto, para que quepa entero junto al buscador; el detalle va en la ayuda.
    let text: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: LocalizedStringKey
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
            Button(action, action: perform)
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.accent)
                .fontWeight(.semibold)
        }
        .font(AppTypography.body)
        .foregroundStyle(AppColors.textSecondary)
        .lineLimit(1)
        // Entero siempre: si falta sitio, encoge el buscador.
        .fixedSize()
        .help(Text(detail))
    }
}
