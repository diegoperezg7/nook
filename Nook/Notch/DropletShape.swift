import SwiftUI

/// Gota que cuelga del borde inferior del notch: un cuello que se ensancha hasta una
/// esfera. Las curvas del cuello llegan tangentes al arco, asi no hay costuras.
/// Animable en radio y caida para que pueda formarse, rebotar y caer.
struct DropletShape: Shape {
    /// Altura (desde arriba del rect) donde se une al notch.
    var attachY: CGFloat
    var radius: CGFloat
    /// Distancia del punto de union al centro de la esfera.
    var length: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, length) }
        set { radius = newValue.first; length = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard radius > 0.5 else { return path }
        let cx = rect.midX
        // Arranca unos puntos dentro del notch para que no se vea la union.
        let top = attachY - 3
        let center = CGPoint(x: cx, y: attachY + max(length, radius * 0.6))
        // Base ancha con curvas concavas (tension superficial) que se estrechan
        // y caen tangentes sobre la esfera.
        let baseHalf = radius * 1.9
        let joinAngle: CGFloat = 0.8
        let tension = radius * 0.85
        let leftJoin = CGPoint(x: center.x - radius * cos(joinAngle), y: center.y - radius * sin(joinAngle))
        let rightJoin = CGPoint(x: center.x + radius * cos(joinAngle), y: center.y - radius * sin(joinAngle))

        path.move(to: CGPoint(x: cx - baseHalf, y: top))
        path.addLine(to: CGPoint(x: cx - baseHalf, y: attachY))
        path.addCurve(
            to: leftJoin,
            control1: CGPoint(x: cx - radius * 0.55, y: attachY),
            control2: CGPoint(x: leftJoin.x + tension * sin(joinAngle), y: leftJoin.y - tension * cos(joinAngle))
        )
        // Por debajo, de un lado al otro (en coordenadas con y hacia abajo,
        // clockwise: true recorre la parte inferior).
        path.addArc(
            center: center, radius: radius,
            startAngle: .radians(.pi + joinAngle), endAngle: .radians(-joinAngle),
            clockwise: true
        )
        path.addCurve(
            to: CGPoint(x: cx + baseHalf, y: attachY),
            control1: CGPoint(x: rightJoin.x - tension * sin(joinAngle), y: rightJoin.y - tension * cos(joinAngle)),
            control2: CGPoint(x: cx + radius * 0.55, y: attachY)
        )
        path.addLine(to: CGPoint(x: cx + baseHalf, y: top))
        path.closeSubpath()
        return path
    }
}

/// Gota de agua de cristal (Liquid Glass): refracta lo que hay detras, con un brillo
/// especular arriba, luz concentrada abajo (como una lente) y un borde de luz.
struct GlassDroplet: View {
    var attachY: CGFloat
    var radius: CGFloat
    var length: CGFloat

    var body: some View {
        let shape = DropletShape(attachY: attachY, radius: radius, length: length)
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: attachY + max(length, radius * 0.6))
            ZStack {
                glass(shape)
                // Agua: algo mas oscura junto al notch, de donde cuelga.
                shape.fill(LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.05)],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: center.y / max(geometry.size.height, 1))
                ))
                // La esfera concentra la luz en su parte baja.
                Ellipse()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0)],
                        center: .center, startRadius: 0, endRadius: radius * 0.7
                    ))
                    .frame(width: radius * 1.4, height: radius * 0.8)
                    .position(x: center.x, y: center.y + radius * 0.5)
                    .blendMode(.plusLighter)
                // Reflejo especular arriba a la izquierda.
                Ellipse()
                    .fill(.white.opacity(0.92))
                    .frame(width: radius * 0.5, height: radius * 0.3)
                    .rotationEffect(.degrees(-35))
                    .position(x: center.x - radius * 0.4, y: center.y - radius * 0.38)
                    .blur(radius: 0.4)
            }
            .clipShape(shape)
            .overlay(
                // Borde de luz que se desvanece hacia el notch: el agua se funde con el.
                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0), location: (attachY + 1) / max(geometry.size.height, 1)),
                            .init(color: .white.opacity(0.7), location: (attachY + 6) / max(geometry.size.height, 1)),
                            .init(color: .white.opacity(0.85), location: (attachY + max(length, radius) + radius) / max(geometry.size.height, 1)),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            )
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        }
    }

    @ViewBuilder
    private func glass(_ shape: DropletShape) -> some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
