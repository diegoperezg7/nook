import SwiftUI

/// Silueta del notch: borde superior recto pegado a la pantalla, "orejas" concavas
/// arriba que la funden con la barra de menus y esquinas inferiores continuas.
/// Los dos radios son animables, asi la forma se transforma al abrir y cerrar.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// false: sin el tramo recto de arriba (el que queda bajo el notch fisico).
    var closesTop = true

    /// Suavizado de las esquinas inferiores (0 = arco circular).
    static let smoothing: CGFloat = 0.72

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = max(0, min(bottomRadius, (rect.width - top * 2) / 2, rect.height - top))
        let side = rect.height - top
        let across = (rect.width - top * 2) / 2

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        ContinuousCorner.add(
            to: &path, corner: CGPoint(x: rect.minX + top, y: rect.maxY),
            back: CGVector(dx: 0, dy: -1), forward: CGVector(dx: 1, dy: 0),
            radius: bottom, smoothing: Self.smoothing, roomIn: side / 2, roomOut: across
        )
        ContinuousCorner.add(
            to: &path, corner: CGPoint(x: rect.maxX - top, y: rect.maxY),
            back: CGVector(dx: -1, dy: 0), forward: CGVector(dx: 0, dy: -1),
            radius: bottom, smoothing: Self.smoothing, roomIn: across, roomOut: side / 2
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        if closesTop { path.closeSubpath() }
        return path
    }
}

/// Esquina continua: un arco de radio r en el centro y, a cada lado, una cubica que
/// entra en la curvatura poco a poco desde el borde recto, en vez de cambiar de golpe
/// en el punto de tangencia. `smoothing` (0 a 1) es cuanto del arco se comen las
/// transiciones: cada una 45 x smoothing grados, y empieza a (1 + smoothing) x r de la
/// esquina. Un borde sin sitio para eso usa solo el suavizado que le cabe.
///
/// Portado de islandcn (`lib/island/path.ts`, `edgeEase` y `continuousRectPath`),
/// MIT, (c) 2026 Leo. Ver THIRD_PARTY_NOTICES.md.
enum ContinuousCorner {
    struct Ease {
        /// Donde la curva deja el borde, medido desde la esquina.
        let p: CGFloat
        /// Largo de los tiradores de la cubica, sobre el borde.
        let a: CGFloat
        let b: CGFloat
        /// Final del arco por este lado: a lo largo del borde y hacia dentro.
        let along: CGFloat
        let across: CGFloat
    }

    static func ease(radius r: CGFloat, smoothing: CGFloat, room: CGFloat) -> Ease {
        let s = max(0, min(smoothing, room / max(r, 0.001) - 1))
        let angle = CGFloat.pi / 4 * s
        let p = (1 + s) * r
        let along = r * (1 - sin(angle))
        let across = r * (1 - cos(angle))
        let c = r * tan(angle / 2) * cos(angle)
        let b = max(0, (p - c - along) / 3)
        return Ease(p: p, a: 2 * b, b: b, along: along, across: across)
    }

    /// Añade al trazado la linea hasta la esquina `corner` y la esquina. `back` apunta
    /// hacia atras por el borde por el que se llega; `forward`, por el que se sale.
    /// `roomIn` y `roomOut` son la mitad de lo que mide cada borde.
    static func add(
        to path: inout Path, corner k: CGPoint, back u: CGVector, forward v: CGVector,
        radius r: CGFloat, smoothing: CGFloat, roomIn: CGFloat, roomOut: CGFloat
    ) {
        guard r > 0.01 else {
            path.addLine(to: k)
            return
        }
        func point(_ du: CGFloat, _ dv: CGFloat, alongIn: Bool) -> CGPoint {
            // alongIn: du va por el borde de llegada (u) y dv hacia dentro (v); si no, al reves.
            let first = alongIn ? u : v, second = alongIn ? v : u
            return CGPoint(x: k.x + first.dx * du + second.dx * dv, y: k.y + first.dy * du + second.dy * dv)
        }
        let inc = ease(radius: r, smoothing: smoothing, room: roomIn)
        let out = ease(radius: r, smoothing: smoothing, room: roomOut)
        let arcStart = point(inc.along, inc.across, alongIn: true)
        let arcEnd = point(out.along, out.across, alongIn: false)

        path.addLine(to: point(inc.p, 0, alongIn: true))
        path.addCurve(to: arcStart, control1: point(inc.p - inc.a, 0, alongIn: true), control2: point(inc.p - inc.a - inc.b, 0, alongIn: true))

        // El arco, como una cubica (para menos de 90 grados el error es inapreciable).
        let center = CGPoint(x: k.x + (u.dx + v.dx) * r, y: k.y + (u.dy + v.dy) * r)
        let ra = CGVector(dx: (arcStart.x - center.x) / r, dy: (arcStart.y - center.y) / r)
        let rb = CGVector(dx: (arcEnd.x - center.x) / r, dy: (arcEnd.y - center.y) / r)
        let theta = acos(max(-1, min(1, ra.dx * rb.dx + ra.dy * rb.dy)))
        let handle = 4 / 3 * tan(theta / 4) * r
        let chord = CGVector(dx: arcEnd.x - arcStart.x, dy: arcEnd.y - arcStart.y)
        func tangent(_ radial: CGVector) -> CGVector {
            let t = CGVector(dx: -radial.dy, dy: radial.dx)
            return t.dx * chord.dx + t.dy * chord.dy >= 0 ? t : CGVector(dx: -t.dx, dy: -t.dy)
        }
        let ta = tangent(ra), tb = tangent(rb)
        path.addCurve(
            to: arcEnd,
            control1: CGPoint(x: arcStart.x + ta.dx * handle, y: arcStart.y + ta.dy * handle),
            control2: CGPoint(x: arcEnd.x - tb.dx * handle, y: arcEnd.y - tb.dy * handle)
        )

        path.addCurve(
            to: point(out.p, 0, alongIn: false),
            control1: point(out.p - out.a - out.b, 0, alongIn: false), control2: point(out.p - out.a, 0, alongIn: false)
        )
    }
}
