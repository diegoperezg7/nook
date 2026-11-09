import SwiftUI

/// Fila horizontal de tarjetas con flechas, como los carruseles de las apps de
/// Apple: se puede desplazar con el trackpad y, al pasar el raton por encima,
/// aparecen flechas que pasan una pagina entera (las tarjetas que caben) con una
/// animacion suave. Siempre se ven tarjetas enteras: el hueco entre ellas se
/// estira para que no quede ninguna cortada en el borde.
struct Carousel<Data: RandomAccessCollection, Card: View>: View where Data.Element: Identifiable {
    let data: Data
    var minSpacing: CGFloat = 12
    @ViewBuilder let card: (Int, Data.Element) -> Card
    @State private var cardWidth: CGFloat = 0

    @State private var position: Data.Element.ID?
    @State private var content: CGRect = .zero
    @State private var viewport: CGFloat = 0
    @State private var hovering = false

    private static var space: String { "carousel" }
    private let margin = NotchContentView.margin

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                    card(index, element)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                            if index == 0 { cardWidth = width }
                        }
                }
            }
            .scrollTargetLayout()
            // Margen vertical para que el zoom y la sombra del hover no se corten.
            .padding(.vertical, 8)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { content = $0 }
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .leading)
        .coordinateSpace(.named(Self.space))
        // El zoom del hover y la sombra pueden asomar un poco por los lados, pero
        // la tarjeta siguiente (a `spacing` de distancia) queda tapada.
        .scrollClipDisabled()
        .mask(Rectangle().padding(.horizontal, -6))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewport = $0 }
        .overlay(alignment: .leading) {
            if hovering, canGoBack { arrow(-1).offset(x: -10) }
        }
        .overlay(alignment: .trailing) {
            if hovering, canGoForward { arrow(1).offset(x: 10) }
        }
        .animation(AppMotion.snappy, value: hovering)
        .animation(AppMotion.snappy, value: canGoBack)
        .animation(AppMotion.snappy, value: canGoForward)
        .padding(.horizontal, margin)
        .onContinuousHover { phase in
            if case .active = phase { hovering = true } else { hovering = false }
        }
    }

    /// Hueco para que quepan tarjetas enteras: tantas como entren con el minimo y
    /// lo que sobra se reparte entre ellas.
    private var spacing: CGFloat {
        guard cardWidth > 0, viewport > cardWidth else { return minSpacing }
        let fit = max(1, Int((viewport + minSpacing) / (cardWidth + minSpacing)))
        guard fit > 1, data.count > fit else { return minSpacing }
        return (viewport - CGFloat(fit) * cardWidth) / CGFloat(fit - 1)
    }

    private var ids: [Data.Element.ID] { data.map(\.id) }
    private var canGoBack: Bool { content.minX < -2 }
    private var canGoForward: Bool { content.maxX > viewport + 2 }

    /// Tarjetas que caben a la vez (minimo una).
    private var perPage: Int {
        guard cardWidth > 0 else { return 1 }
        return max(1, Int((viewport + spacing + 1) / (cardWidth + spacing)))
    }

    private func page(_ step: Int) {
        let ids = ids
        guard !ids.isEmpty else { return }
        let current = position.flatMap { ids.firstIndex(of: $0) } ?? 0
        let target = min(max(current + step * perPage, 0), ids.count - 1)
        withAnimation(AppMotion.reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86)) {
            position = ids[target]
        }
    }

    private func arrow(_ step: Int) -> some View {
        CarouselArrow(icon: step < 0 ? "chevron.left" : "chevron.right") { page(step) }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

private struct CarouselArrow: View {
    let icon: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(AppColors.cardBorder, lineWidth: 1))
                .shadow(color: AppColors.shadow, radius: 6, y: 2)
                .scaleEffect(hovering && !AppMotion.reduceMotion ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppMotion.snappy, value: hovering)
        .accessibilityLabel(Text(icon == "chevron.left" ? "Anteriores" : "Siguientes"))
    }
}
