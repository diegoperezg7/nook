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
    @AppStorage(SettingsKey.captureClipboard) private var captureEnabled = true

    private var visibleItems: [NotchItem] {
        let query = model.searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? items : items.filter { $0.matches(query) }
        return filtered.filter(\.isPinned) + filtered.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                searchField
                if let notice {
                    notice
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NotchContentView.margin)
            .padding(.top, 2)
            .padding(.bottom, 4)

            if visibleItems.isEmpty {
                emptyState
            } else {
                ItemStrip(items: visibleItems, store: store, model: model)
            }
        }
        .onChange(of: model.searchFocusRequest, initial: true) { _, _ in
            if model.openReason == .hotKey { searchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            TextField("Buscar en el historial", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .focused($searchFocused)
                .onSubmit(copyFirst)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .frame(maxWidth: 260)
        .background(Capsule().fill(AppColors.controlTrack))
        .overlay(
            Capsule()
                .strokeBorder(searchFocused ? AppColors.accent : AppColors.cardBorder, lineWidth: searchFocused ? 1.5 : 0.5)
        )
        .contentShape(Capsule())
        .onTapGesture { searchFocused = true }
        .animation(AppMotion.snappy, value: searchFocused)
    }

    /// Aviso cuando el historial no se esta guardando y por que.
    private var notice: AnyView? {
        if !captureEnabled {
            return AnyView(NoticePill(text: "Captura desactivada", action: "Ajustes") { model.onOpenSettings?() })
        }
        switch model.clipboardAccess {
        case .allowed:
            return nil
        case .needsPermission, .denied:
            return AnyView(NoticePill(text: "Sin acceso al portapapeles", action: "Permitir…") {
                NSWorkspace.shared.open(ClipboardAccess.settingsURL)
            })
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.searchText.isEmpty ? "list.clipboard" : "magnifyingglass")
                .font(.system(size: 22, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColors.textPrimary)
            Text(model.searchText.isEmpty ? "Copia algo y aparecerá aquí" : "Sin resultados")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
            if model.searchText.isEmpty {
                Text("⌃⌘V abre el historial desde cualquier app")
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private func copyFirst() {
        guard let first = visibleItems.first else { return }
        store.copyToPasteboard(first)
        model.didCopy()
    }
}

private struct NoticePill: View {
    let text: LocalizedStringKey
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
    }
}
