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
                DropHint(isTargeted: model.isDropTargeted)
                    .padding(.horizontal, NotchContentView.margin)
                    .padding(.top, 4)
                    .padding(.bottom, NotchContentView.margin)
            } else {
                ItemStrip(items: items, store: store, model: model)
                    .overlay {
                        if model.isDropTargeted {
                            DropHint(isTargeted: true, overlay: true)
                                .padding(.horizontal, NotchContentView.margin)
                                .padding(.top, 4)
                                .padding(.bottom, NotchContentView.margin)
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
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ItemCard(
                        item: item, store: store, index: index,
                        onCopied: model.didCopy,
                        onDragStart: model.beginDragOut
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            // Margen vertical para que el zoom y la sombra del hover no se corten.
            .padding(.horizontal, NotchContentView.margin)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Zona de soltar: borde discontinuo que se vuelve azul y "late" al arrastrar encima.
struct DropHint: View {
    let isTargeted: Bool
    var overlay = false

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                isTargeted ? AppColors.accent : AppColors.textSecondary.opacity(0.35),
                style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.25, dash: [7, 6])
            )
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isTargeted ? AppColors.accentSoft : AppColors.previewWell)
                    .background {
                        if overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial) }
                    }
            )
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                        .font(.system(size: 24, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: isTargeted)
                    Text(isTargeted ? "Suelta para guardar" : "Arrastra aquí archivos, imágenes o texto")
                        .font(AppTypography.title)
                    Text("Se quedan a mano hasta que los saques")
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .foregroundStyle(isTargeted ? AppColors.accent : AppColors.textPrimary)
            }
    }
}
