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
        // La tarjeta mide lo que su texto; sin tarjeta guarda la ultima medida para
        // recogerse desde su tamaño.
        let card = metrics.previewSize(content: preview.map(HUDPreviewCard.contentSize(for:)) ?? .zero)
        // Cada lado crece hasta donde empiezan los menus o los iconos de la barra.
        let free = menuBar.free
        // Una notificacion, o un aviso que no cabe a los dos lados, no va en las alas:
        // sale como isla, simetrica y hacia abajo.
        let spec = notice.flatMap { HUDActivity.island(for: $0, leftFree: free.left, rightFree: free.right) }
        let island = spec != nil
        let islandSize = metrics.islandSize(content: spec?.content ?? 0, extra: spec?.extra ?? NotchMetrics.islandExtra)
        let sides = HUDSides.make(desired: island ? 0 : notice.map(HUDActivity.side(for:)) ?? 0, leftFree: free.left, rightFree: free.right)
        let closedWidth = metrics.closedSize.width + sides.left + sides.right
        let width = model.expandedWidth ? open.width : preview != nil ? card.width : island ? islandSize.width : closedWidth
        // Si un lado crece mas que el otro, la forma se desplaza para que el notch
        // fisico siga en su sitio.
        let shift = model.expandedWidth || preview != nil || island ? 0 : (sides.right - sides.left) / 2
        let height = model.expandedHeight ? open.height : preview != nil ? card.height : island ? islandSize.height : metrics.closedSize.height
        let shape = NotchShape(
            topRadius: model.expandedWidth || preview != nil ? NotchMetrics.openEar : NotchMetrics.closedEar,
            bottomRadius: model.expandedHeight || preview != nil ? NotchMetrics.openBottomRadius
                : island ? NotchMetrics.islandBottomRadius : metrics.closedBottomRadius
        )

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                // Los dos fondos estan siempre y se funden: una vista que entra con
                // transicion toma de golpe el tamaño final y no crece con la forma.
                NotchBackground(shape: shape)
                    .opacity(preview != nil ? 0 : 1)
                CardBackground(shape: shape, bandFraction: metrics.notchHeight / card.height)
                    .opacity(preview != nil ? 1 : 0)

                if let notice, island {
                    Group {
                        if case .notification = notice {
                            NotificationIsland(kind: notice, metrics: metrics)
                        } else {
                            HUDActivity(kind: notice, metrics: metrics, sides: sides, island: true)
                        }
                    }
                        .frame(width: islandSize.width, height: islandSize.height)
                        .contentShape(Rectangle())
                        .onTapGesture { hud.activate() }
                        .transition(noticeTransition)
                } else if let notice {
                    HUDActivity(kind: notice, metrics: metrics, sides: sides)
                        .frame(width: closedWidth)
                        .contentShape(Rectangle())
                        .onTapGesture { hud.activate() }
                        .transition(noticeTransition)
                }

                if let preview {
                    HUDPreviewCard(preview: preview, metrics: metrics, onExtra: hud.performExtra) { hud.performActivated() }
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
            // Igual que los fondos: siempre presente y con opacidad, para que el borde
            // crezca con la forma y no aparezca ya con el tamaño de la tarjeta.
            .background {
                SiriGlow(shape: shape, halo: true, band: metrics.notchHeight, active: preview != nil)
                    .opacity(preview != nil ? 1 : 0)
            }
            .overlay {
                SiriGlow(shape: shape, halo: false, band: metrics.notchHeight, active: preview != nil)
                    .opacity(preview != nil ? 1 : 0)
            }
            .overlay {
                if model.isDropTargeted, model.isOpen { DropGlow(shape: shape) }
            }
            .shadow(color: AppColors.shadow.opacity(model.expandedHeight ? 0.8 : 0), radius: 16, y: 8)
            .onChange(of: sides) { _, new in lastSides = new }
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
        // Crece con muelle; al recogerse, sin rebote. La animacion va aqui, por fuera
        // del marco que centra la forma: dentro, el tamaño se animaba pero el centrado
        // no, y la forma saltaba a la izquierda y crecia solo hacia la derecha.
        .animation(sides.grows(from: lastSides) ? AppMotion.open : AppMotion.close, value: sides)
        .animation(AppMotion.open, value: preview != nil)
        .animation(island ? AppMotion.open : AppMotion.close, value: island)
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

    /// El contenido entra cuando el panel ya ha salido casi entero (0,12 s: antes se
    /// veia recortado por los lados mientras la forma crecia), con un leve zoom desde
    /// el centro y un desenfoque ligero; sale con un fundido rapido para no estorbar al cierre.
    private var contentTransition: AnyTransition {
        if AppMotion.reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: RevealModifier(progress: 0),
                identity: RevealModifier(progress: 1)
            ).animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.12)),
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

/// Fondo de la tarjeta de un aviso pulsado, como la nueva Siri: arriba, la franja del
/// notch en negro; abajo, cristal (Liquid Glass en macOS 26, material antes) con un
/// velo de los colores del borde. El negro se funde hacia abajo y no queda debajo del
/// cristal: sobre un fondo opaco el cristal pierde el tinte.
private struct CardBackground: View {
    let shape: NotchShape
    /// Parte de la altura que ocupa la franja del notch.
    let bandFraction: CGFloat

    var body: some View {
        ZStack {
            Color.clear.liquidGlass(in: shape, tint: AppColors.notch.opacity(0.65))
            // El tinte del cristal apenas oscurece: este velo deja el texto blanco por
            // encima de 4,5:1 aunque detras haya una pagina blanca.
            shape.fill(AppColors.notch.opacity(0.42))
            shape.fill(LinearGradient(stops: [
                .init(color: AppColors.notch, location: 0),
                .init(color: AppColors.notch, location: bandFraction),
                .init(color: AppColors.notch.opacity(0), location: min(1, bandFraction + 0.45)),
            ], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// Borde azul que late mientras se arrastra algo encima.
private struct DropGlow: View {
    let shape: NotchShape

    var body: some View {
        // Solo los lados y el fondo: arriba el borde se cortaba con el notch real.
        NotchShape(topRadius: shape.topRadius, bottomRadius: shape.bottomRadius, closesTop: false)
            .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
/// multicolor que recorre los lados y el fondo. Arriba no: el tramo recto queda
/// pegado al borde de la pantalla, y la franja del notch se funde sin linea.
/// `halo` es el resplandor difuso de detras. Con "Reducir movimiento", quieto.
private struct SiriGlow: View {
    let shape: NotchShape
    let halo: Bool
    /// Alto de la franja del notch: ahi el borde aun no se ve.
    let band: CGFloat
    /// Sin tarjeta el borde esta oculto: el giro se para y no gasta.
    let active: Bool

    var body: some View {
        Group {
            if AppMotion.reduceMotion {
                ring(.zero)
            } else {
                TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
                    // Una vuelta cada 4 s.
                    ring(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90))
                }
            }
        }
        .mask {
            GeometryReader { proxy in
                let start = min(1, band / max(proxy.size.height, 1))
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: start * 0.6),
                    .init(color: .black, location: min(1, start + 0.15)),
                ], startPoint: .top, endPoint: .bottom)
                // El halo sale por fuera de la forma: la mascara no lo recorta de lado.
                .padding(-40)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func ring(_ angle: Angle) -> some View {
        let gradient = AngularGradient(colors: AppColors.glow, center: .center, angle: angle)
        let shape = NotchShape(topRadius: shape.topRadius, bottomRadius: shape.bottomRadius, closesTop: false)
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
