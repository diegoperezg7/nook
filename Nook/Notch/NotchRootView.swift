import SwiftUI

/// Raiz del panel. La ventana tiene siempre el tamaño abierto y lo que se anima es la
/// forma de dentro: asi no hay tirones de redimensionado de ventana.
///
/// Animacion de apertura ("el notch se licua"):
/// 1. Al acercar el raton, del notch cuelga una gota que se forma con un rebote.
/// 2. Al entrar, la gota cae; el notch se ensancha y gotea detras de ella.
/// 3. Mientras cae, el negro se disuelve en cristal (Liquid Glass).
/// 4. Un destello de luz recorre el cristal; las tarjetas entran escalonadas.
struct NotchRootView: View {
    @Bindable var model: NotchViewModel
    let store: ItemStore

    var body: some View {
        let metrics = model.metrics
        let width = model.expandedWidth ? metrics.openSize.width : metrics.closedSize.width
        let height = model.expandedHeight ? metrics.openSize.height : metrics.closedSize.height
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
                        .frame(width: metrics.openSize.width, height: metrics.openSize.height)
                        .transition(contentTransition)
                }

                GlintOverlay(trigger: model.glintTrigger)
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
            // Todo el panel (cristal, borde y sombra) brota de la gota: en cada
            // apertura la mascara pasa de 0 (la gota) a 1 (el panel entero).
            .keyframeAnimator(initialValue: CGFloat(1), trigger: model.revealTrigger) { content, progress in
                content.mask(revealMask(width: width, height: height, progress: progress))
            } keyframes: { _ in
                MoveKeyframe(0)
                SpringKeyframe(1, duration: 0.7, spring: Spring(response: 0.6, dampingRatio: 0.86))
            }
            // Al arrastrar algo encima, el panel "respira" hacia abajo.
            .scaleEffect(model.isDropTargeted && model.isOpen && !AppMotion.reduceMotion ? 1.03 : 1, anchor: .top)
            .animation(AppMotion.snappy, value: model.isDropTargeted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: DropReader.types, isTargeted: $model.isDropTargeted) { providers in
            // Una tarjeta arrastrada y soltada en el propio panel no se duplica.
            guard !model.isDraggingOut else { return false }
            DropReader.read(providers, into: store)
            model.celebrateDrop()
            return true
        }
        .onChange(of: model.isDropTargeted) { _, targeted in
            model.dropTargetChanged(targeted)
        }
    }

    /// Gota de agua de cristal bajo el notch. Cerca del notch se forma con rebote;
    /// al abrir se hincha y se funde con el panel, que brota de ella.
    private var droplet: some View {
        let metrics = model.metrics
        let drop = dropGeometry
        return GlassDroplet(attachY: metrics.closedSize.height, radius: drop.radius, length: drop.length)
            .opacity(drop.opacity)
            .frame(width: 120, height: metrics.openSize.height)
            .allowsHitTesting(false)
    }

    private var dropGeometry: (radius: CGFloat, length: CGFloat, opacity: Double) {
        if model.expandedHeight { return (22, 30, 0) }
        if model.isPeeking { return (12, 22, 1) }
        return (3, 0, 0)
    }

    /// Mascara circular que crece desde el centro de la gota hasta cubrir el panel.
    private func revealMask(width: CGFloat, height: CGFloat, progress: CGFloat) -> some View {
        let metrics = model.metrics
        let center = CGPoint(x: width / 2, y: metrics.closedSize.height + 22)
        let full = 2 * hypot(max(width, metrics.openSize.width), max(height, metrics.openSize.height))
        let diameter = 20 + (full - 20) * min(max(progress, 0), 1.2)
        return Circle()
            .frame(width: diameter, height: diameter)
            .position(center)
            .frame(width: width, height: height)
    }

    /// El contenido entra cuando la gota ya cae, con un leve zoom desde arriba y
    /// desenfoque; sale con un fundido rapido para no estorbar al cierre.
    private var contentTransition: AnyTransition {
        if AppMotion.reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: RevealModifier(progress: 0),
                identity: RevealModifier(progress: 1)
            ).animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.12)),
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

/// Banda de luz diagonal que cruza el cristal una vez por cada `trigger`.
private struct GlintOverlay: View {
    let trigger: Int
    @State private var phase: CGFloat = -0.5

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.32), location: 0.5),
                    .init(color: .white.opacity(0), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.28, height: geometry.size.height * 3)
            .rotationEffect(.degrees(20))
            .offset(x: phase * geometry.size.width, y: -geometry.size.height)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            phase = -0.5
            withAnimation(.easeInOut(duration: 0.85)) { phase = 1.3 }
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
            .blur(radius: (1 - progress) * 8)
            .scaleEffect(0.92 + 0.08 * progress, anchor: .top)
    }
}
