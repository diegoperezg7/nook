import SwiftUI

/// Raiz del panel. La ventana tiene siempre el tamaño abierto y lo que se anima es la
/// forma de dentro: asi no hay tirones de redimensionado de ventana.
///
/// Animacion: al entrar, el panel sale del centro del notch y se agranda (ancho y alto
/// a la vez, con un rebote suave). Es negro como el notch, asi parece el notch
/// creciendo; el contenido aparece despues, creciendo desde el centro.
struct NotchRootView: View {
    @Bindable var model: NotchViewModel
    let store: ItemStore
    @Environment(SystemHUD.self) private var hud

    var body: some View {
        let metrics = model.metrics
        let open = metrics.openSize(searchRow: model.tab.hasToolbar)
        // Cerrado, el notch se ensancha para un aviso (volumen, bateria...).
        let notice = model.isOpen ? nil : hud.current
        let side = notice.map(HUDActivity.side(for:)) ?? 0
        let closedWidth = metrics.closedSize.width + side * 2
        let width = model.expandedWidth ? open.width : closedWidth
        let height = model.expandedHeight ? open.height : metrics.closedSize.height
        let shape = NotchShape(
            topRadius: model.expandedWidth ? NotchMetrics.openEar : NotchMetrics.closedEar,
            bottomRadius: model.expandedHeight ? NotchMetrics.openBottomRadius : metrics.closedBottomRadius
        )

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchBackground(shape: shape)

                if let notice {
                    HUDActivity(kind: notice, metrics: metrics)
                        .frame(width: closedWidth)
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }

                if model.isOpen {
                    NotchContentView(model: model, store: store)
                        .frame(width: open.width, height: open.height)
                        .transition(contentTransition)
                }
            }
            .frame(width: width, height: height, alignment: .top)
            .clipShape(shape)
            .overlay {
                if model.isDropTargeted, model.isOpen {
                    DropGlow(shape: shape)
                }
            }
            .shadow(color: AppColors.shadow.opacity(model.expandedHeight ? 0.8 : 0), radius: 16, y: 8)
            .animation(AppMotion.open, value: notice == nil)
            // Cerrado y con el raton encima, se asoma un poco desde arriba.
            .scaleEffect(model.isPeeking && !model.isOpen && !AppMotion.reduceMotion ? 1.02 : 1, anchor: .top)
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

/// Fondo del panel: negro solido, el mismo del notch fisico, para que parezca el
/// propio notch creciendo. El Liquid Glass queda para lo de dentro.
private struct NotchBackground: View {
    let shape: NotchShape

    var body: some View {
        shape.fill(AppColors.notch)
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
            .scaleEffect(0.86 + 0.14 * progress, anchor: .center)
    }
}
