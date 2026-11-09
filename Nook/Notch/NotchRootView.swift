import SwiftUI

/// Raiz del panel. La ventana tiene siempre el tamaño abierto y lo que se anima es la
/// forma de dentro: asi no hay tirones de redimensionado de ventana.
///
/// Animacion:
/// 1. Al acercar el raton, del notch cuelga una gota de agua de cristal.
/// 2. Al entrar, el panel sale del propio notch: crece hacia abajo y a los lados a la
///    vez, mientras el negro se disuelve en Liquid Glass y la gota se funde con el.
/// 3. El contenido aparece con un leve zoom desde arriba.
struct NotchRootView: View {
    @Bindable var model: NotchViewModel
    let store: ItemStore

    var body: some View {
        let metrics = model.metrics
        let open = metrics.openSize(searchRow: model.tab == .clipboard)
        let width = model.expandedWidth ? open.width : metrics.closedSize.width
        let height = model.expandedHeight ? open.height : metrics.closedSize.height
        let shape = NotchShape(
            topRadius: model.expandedWidth ? NotchMetrics.openEar : NotchMetrics.closedEar,
            bottomRadius: model.expandedHeight ? NotchMetrics.openBottomRadius : metrics.closedBottomRadius
        )

        ZStack(alignment: .top) {
            droplet

            ZStack(alignment: .top) {
                GlassBackground(shape: shape, isGlass: model.expandedHeight)

                if model.isOpen {
                    NotchContentView(model: model, store: store)
                        .frame(width: open.width, height: open.height)
                        .transition(contentTransition)
                }
            }
            .frame(width: width, height: height, alignment: .top)
            .clipShape(shape)
            .overlay(shape.stroke(AppColors.panelBorder.opacity(model.expandedHeight ? 1 : 0), lineWidth: 0.75))
            .overlay {
                if model.isDropTargeted, model.isOpen {
                    DropGlow(shape: shape)
                }
            }
            .shadow(color: AppColors.shadow.opacity(model.expandedHeight ? 0.8 : 0), radius: 16, y: 8)
            // Al arrastrar algo encima, el panel "respira" hacia abajo.
            .scaleEffect(model.isDropTargeted && model.isOpen && !AppMotion.reduceMotion ? 1.03 : 1, anchor: .top)
            .animation(AppMotion.snappy, value: model.isDropTargeted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: DropReader.types, isTargeted: $model.isDropTargeted) { providers in
            // Una tarjeta arrastrada y soltada en el propio panel no se duplica.
            guard !model.isDraggingOut else { return false }
            DropReader.read(providers, into: store)
            return true
        }
        .onChange(of: model.isDropTargeted) { _, targeted in
            model.dropTargetChanged(targeted)
        }
    }

    /// Gota de agua de cristal bajo el notch. Cerca del notch se forma con rebote;
    /// al abrir, el panel crece sobre ella y la gota se funde con el.
    private var droplet: some View {
        let metrics = model.metrics
        let drop: (radius: CGFloat, length: CGFloat, opacity: Double)
        if model.expandedHeight {
            drop = (14, 26, 0)
        } else if model.isPeeking {
            drop = (12, 22, 1)
        } else {
            drop = (3, 0, 0)
        }
        return GlassDroplet(attachY: metrics.closedSize.height, radius: drop.radius, length: drop.length)
            .opacity(drop.opacity)
            .frame(width: 120, height: metrics.openSize.height)
            .allowsHitTesting(false)
    }

    /// El contenido entra cuando el panel ya ha salido, con un leve zoom desde arriba
    /// y desenfoque; sale con un fundido rapido para no estorbar al cierre.
    private var contentTransition: AnyTransition {
        if AppMotion.reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: RevealModifier(progress: 0),
                identity: RevealModifier(progress: 1)
            ).animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.1)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }
}

/// Cerrado: negro opaco, para fundirse con el notch fisico. Abierto: cristal.
/// La capa negra se disuelve encima del cristal, asi el notch parece "licuarse".
private struct GlassBackground: View {
    let shape: NotchShape
    let isGlass: Bool

    var body: some View {
        ZStack {
            glass
            shape.fill(AppColors.notch).opacity(isGlass ? 0 : 1)
        }
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

/// Borde azul que late mientras se arrastra algo encima.
private struct DropGlow: View {
    let shape: NotchShape

    var body: some View {
        shape
            .stroke(AppColors.accent, lineWidth: 2)
            .shadow(color: AppColors.accent.opacity(0.8), radius: 8)
            .phaseAnimator([0.45, 1]) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.55)
            }
            .allowsHitTesting(false)
    }
}

private struct RevealModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 6)
            .scaleEffect(0.94 + 0.06 * progress, anchor: .top)
    }
}
