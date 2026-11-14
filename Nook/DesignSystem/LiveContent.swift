import SwiftUI

// Piezas para contenido que cambia en vivo dentro del notch. La idea viene de los
// componentes de islandcn (progress-ring, countdown-ring, tail-text, shimmer-text);
// el codigo es propio, con las APIs de SwiftUI.

/// Anillo de progreso con extremos redondos que empieza a las 12. Sin progreso no
/// se pinta el extremo (se veria un punto).
struct ProgressRing: View {
    /// De 0 a 1.
    let value: Double
    let color: Color
    var track: Color = AppColors.notchText.opacity(0.2)
    var lineWidth: CGFloat = 2.5

    var body: some View {
        let clamped = min(1, max(0, value))
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle().trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(clamped > 0.001 ? 1 : 0)
        }
    }
}

/// Anillo de lo que queda hasta `end`: se vacia de forma continua, no a saltos de un
/// segundo. Con "Reducir movimiento", un paso por segundo.
struct CountdownRing: View {
    let end: Date
    let total: TimeInterval
    let color: Color

    var body: some View {
        if AppMotion.reduceMotion {
            TimelineView(.periodic(from: .now, by: 1)) { ring(at: $0.date) }
        } else {
            // 20 veces por segundo basta para que un anillo de 15 pt se lea continuo.
            TimelineView(.animation(minimumInterval: 0.05)) { ring(at: $0.date) }
        }
    }

    private func ring(at date: Date) -> some View {
        let left = max(0, end.timeIntervalSince(date))
        return ProgressRing(value: total > 0 ? left / total : 0, color: color)
    }
}

/// Una linea que crece por el final (un dictado): mientras cabe se ve entera; cuando
/// no, se ve el final y el principio se pierde con un fundido, sin puntos suspensivos.
struct TailText: View {
    let text: String
    let font: Font
    /// Lo que ocupa el fundido del principio.
    var fade: CGFloat = 16

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line
            Text(verbatim: "A").font(font).hidden()
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) { line }
                .clipped()
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: fade)
                        Color.black
                    }
                }
        }
    }

    private var line: some View {
        Text(verbatim: text).font(font).lineLimit(1).fixedSize()
    }
}

/// Etiqueta con un brillo que la recorre de izquierda a derecha, para esperas sin
/// final conocido ("En curso"). Con "Reducir movimiento", quieta.
struct ShimmerText: View {
    let text: String
    var period: TimeInterval = 1.8

    var body: some View {
        if AppMotion.reduceMotion {
            Text(verbatim: text)
        } else {
            Text(verbatim: text)
                .overlay {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                        GeometryReader { proxy in
                            let band = proxy.size.width * 0.6
                            LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: band)
                                .offset(x: -band + (proxy.size.width + band) * phase)
                        }
                    }
                    .mask(Text(verbatim: text))
                    .allowsHitTesting(false)
                }
        }
    }
}
