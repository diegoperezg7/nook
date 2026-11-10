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
    @Environment(FocusTimer.self) private var focus
    @Environment(MenuBarSpace.self) private var menuBar
    /// Lados del aviso en el ultimo cambio: deciden si la forma crece o se recoge.
    @State private var lastSides = HUDSides(left: 0, right: 0, merged: false)

    var body: some View {
        let metrics = model.metrics
        let open = metrics.openSize(searchRow: model.tab.hasToolbar, extra: model.tab.extraHeight)
        // Cerrado, el notch se ensancha para un aviso breve (volumen, bateria...) o,
        // si no hay ninguno, para lo que este en marcha (reunion, temporizador...).
        // Al pulsar un aviso, en su lugar sale su tarjeta (mas alta que el aviso).
        let preview = model.isOpen || model.isCollapsing ? nil : hud.activated
        let notice = model.isOpen || model.isCollapsing || preview != nil ? nil : (hud.current ?? hud.ambient)
        let card = metrics.previewSize
        // Cada lado crece hasta donde empiezan los menus o los iconos de la barra.
        let free = menuBar.free
        let sides = HUDSides.make(desired: notice.map(HUDActivity.side(for:)) ?? 0, leftFree: free.left, rightFree: free.right)
        let closedWidth = metrics.closedSize.width + sides.left + sides.right
        let width = model.expandedWidth ? open.width : preview != nil ? card.width : closedWidth
        // Si un lado crece mas que el otro, la forma se desplaza para que el notch
        // fisico siga en su sitio.
        let shift = model.expandedWidth || preview != nil ? 0 : (sides.right - sides.left) / 2
        let height = model.expandedHeight ? open.height : preview != nil ? card.height : metrics.closedSize.height
        let shape = NotchShape(
            topRadius: model.expandedWidth || preview != nil ? NotchMetrics.openEar : NotchMetrics.closedEar,
            bottomRadius: model.expandedHeight || preview != nil ? NotchMetrics.openBottomRadius : metrics.closedBottomRadius
        )

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchBackground(shape: shape)

                if let notice {
                    HUDActivity(kind: notice, metrics: metrics, sides: sides)
                        .frame(width: closedWidth)
                        .contentShape(Rectangle())
                        .onTapGesture { hud.activate() }
                        .transition(noticeTransition)
                }

                if let preview {
                    HUDPreviewCard(preview: preview, metrics: metrics) { hud.performActivated() }
                        .frame(width: card.width, height: card.height)
                        .transition(contentTransition)
                }

                if model.isOpen {
                    NotchContentView(model: model, store: store)
                        .frame(width: open.width, height: open.height)
                        .transition(contentTransition)
                }
            }
            .frame(width: width, height: height, alignment: .top)
            .clipShape(shape)
            .offset(x: shift)
            // Tarjeta de un aviso: resplandor detras (solo se ve por fuera) y borde encima.
            .background {
                if preview != nil { SiriGlow(shape: shape, halo: true).transition(.opacity) }
            }
            .overlay {
                if model.isDropTargeted, model.isOpen {
                    DropGlow(shape: shape)
                } else if preview != nil {
                    SiriGlow(shape: shape, halo: false).transition(.opacity)
                }
            }
            .shadow(color: AppColors.shadow.opacity(model.expandedHeight ? 0.8 : 0), radius: 16, y: 8)
            // Crece con muelle; al recogerse, sin rebote.
            .animation(sides.grows(from: lastSides) ? AppMotion.open : AppMotion.close, value: sides)
            .onChange(of: sides) { _, new in lastSides = new }
            .animation(AppMotion.open, value: preview != nil)
            // Abrir el notch silencia la alarma que esta sonando y cierra la tarjeta.
            .onChange(of: model.isOpen) { _, open in
                if open {
                    focus.silence()
                    hud.dismissActivated()
                }
            }
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
    /// y un desenfoque ligero; sale con un fundido rapido para no estorbar al cierre.
    private var contentTransition: AnyTransition {
        if AppMotion.reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: RevealModifier(progress: 0),
                identity: RevealModifier(progress: 1)
            ).animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }

    /// Aviso del notch cerrado: entra con fundido cuando la forma ya ha crecido algo y
    /// sale con fundido y leve escala mientras la forma se recoge.
    private var noticeTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(AppMotion.noticeIn),
            removal: (AppMotion.reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .scale(scale: 0.94)))
                .animation(AppMotion.noticeOut)
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

/// Borde de la tarjeta de un aviso pulsado, como la nueva Siri: un degradado
/// multicolor que recorre el contorno. `halo` es el resplandor difuso de detras.
/// Con "Reducir movimiento", el degradado queda quieto.
private struct SiriGlow: View {
    let shape: NotchShape
    let halo: Bool

    var body: some View {
        Group {
            if AppMotion.reduceMotion {
                ring(.zero)
            } else {
                TimelineView(.animation) { context in
                    // Una vuelta cada 4 s.
                    ring(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90))
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func ring(_ angle: Angle) -> some View {
        let gradient = AngularGradient(colors: AppColors.glow, center: .center, angle: angle)
        if halo {
            shape.stroke(gradient, lineWidth: 8).blur(radius: 12).opacity(0.85)
        } else {
            shape.stroke(gradient, lineWidth: 1.5)
        }
    }
}

private struct RevealModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 2)
            .scaleEffect(0.86 + 0.14 * progress, anchor: .center)
    }
}
