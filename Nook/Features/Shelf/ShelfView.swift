import SwiftData
import SwiftUI

/// Bandeja: lo que el usuario deja en el notch para usarlo despues.
struct ShelfView: View {
    let model: NotchViewModel
    let store: ItemStore

    @Query(
        filter: #Predicate<NotchItem> { $0.originRaw == "shelf" },
        sort: \NotchItem.createdAt, order: .reverse,
        animation: .spring(response: 0.3, dampingFraction: 0.8)
    )
    private var items: [NotchItem]

    var body: some View {
        ZStack {
            if items.isEmpty {
                DropHint(isTargeted: model.isDropTargeted) {
                    // El notch esta por encima de todo: se cierra para no tapar el dialogo.
                    model.close()
                    FileImporter.chooseFiles(into: store)
                }
                    .frame(height: NotchMetrics.cardRowHeight)
                    .padding(.horizontal, NotchContentView.margin)
            } else {
                ItemStrip(items: items, store: store, model: model)
                    .overlay {
                        if model.isDropTargeted {
                            DropHint(isTargeted: true, overlay: true)
                                .frame(height: NotchMetrics.cardRowHeight)
                                .padding(.horizontal, NotchContentView.margin)
                                .transition(.opacity)
                        }
                    }
            }
        }
        .animation(AppMotion.snappy, value: model.isDropTargeted)
    }
}

/// Fila horizontal de tarjetas, comun a la bandeja y al historial.
struct ItemStrip: View {
    let items: [NotchItem]
    let store: ItemStore
    let model: NotchViewModel

    var body: some View {
        Carousel(data: items) { index, item in
            ItemCard(
                item: item, store: store, index: index,
                onCopied: model.didCopy,
                onDragStart: model.beginDragOut,
                onPreviewChange: { model.isPreviewing = $0 }
            )
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
        .frame(height: NotchMetrics.cardRowHeight)
    }
}

/// Zona de soltar: velo azul con borde discontinuo; al arrastrar encima se enciende.
/// Esquinas de 16 pt: concentricas con las del panel (28 pt) a 16 pt de margen.
struct DropHint: View {
    let isTargeted: Bool
    var overlay = false
    /// Alternativa a arrastrar: abre el panel de elegir archivos.
    var onChoose: (() -> Void)?

    private static let corner: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        shape
            .fill(isTargeted ? AppColors.accentSoft : AppColors.accentWell)
            .background { if overlay { shape.fill(.regularMaterial) } }
            .overlay(
                shape.strokeBorder(
                    isTargeted ? AppColors.accent : AppColors.accentBorder,
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.25, dash: [6, 5])
                )
            )
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: isTargeted ? "arrow.down" : "tray.and.arrow.down.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(AppColors.accent))
                        .shadow(color: AppColors.accent.opacity(0.45), radius: 6, y: 2)
                        .contentTransition(.symbolEffect(.replace))
                        .scaleEffect(isTargeted && !AppMotion.reduceMotion ? 1.12 : 1)
                    VStack(spacing: 3) {
                        Text(isTargeted ? "Suelta para guardar" : "Arrastra aquí archivos, imágenes o texto")
                            .font(AppTypography.title)
                            .foregroundStyle(isTargeted ? AppColors.accent : AppColors.textPrimary)
                        Text("Se quedan a mano hasta que los saques")
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    if let onChoose, !isTargeted {
                        Button(action: onChoose) {
                            Text("o elige archivos…")
                                .font(AppTypography.bodyStrong)
                                .foregroundStyle(AppColors.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .animation(AppMotion.snappy, value: isTargeted)
    }
}
