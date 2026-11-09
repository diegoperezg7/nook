import AppKit
import SwiftUI

/// Lo que suena, en el panel abierto: caratula, titulo, progreso y controles.
struct MusicView: View {
    let nowPlaying: NowPlaying

    var body: some View {
        if let track = nowPlaying.track {
            HStack(spacing: 18) {
                Artwork(image: nowPlaying.artwork, size: 112, corner: 16)
                    .onTapGesture { nowPlaying.openPlayer() }
                    .help(Text("Abrir la app"))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: track.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(verbatim: [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let icon = nowPlaying.player?.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                                .help(Text(verbatim: nowPlaying.player?.scriptName ?? ""))
                        }
                    }

                    ProgressRow(nowPlaying: nowPlaying, duration: track.duration)

                    HStack(spacing: 14) {
                        ControlButton(icon: "backward.fill", size: 34) { nowPlaying.previous() }
                            .help(Text("Anterior"))
                        ControlButton(icon: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 42, prominent: true) {
                            withAnimation(AppMotion.snappy) { nowPlaying.playPause() }
                        }
                        .help(Text(nowPlaying.isPlaying ? "Pausa" : "Reproducir"))
                        ControlButton(icon: "forward.fill", size: 34) { nowPlaying.next() }
                            .help(Text("Siguiente"))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, NotchContentView.margin)
            .frame(height: NotchMetrics.cardRowHeight)
        }
    }
}

/// Barra de progreso con los tiempos; se puede pulsar o arrastrar para saltar.
private struct ProgressRow: View {
    let nowPlaying: NowPlaying
    let duration: TimeInterval
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = dragValue ?? nowPlaying.currentPosition(at: context.date)
            let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
            HStack(spacing: 8) {
                Text(verbatim: Self.format(position))
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColors.textPrimary.opacity(0.15))
                        Capsule().fill(AppColors.accent)
                            .frame(width: max(4, geometry.size.width * fraction))
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard duration > 0 else { return }
                                dragValue = min(max(value.location.x / geometry.size.width, 0), 1) * duration
                            }
                            .onEnded { _ in
                                if let dragValue { nowPlaying.seek(to: dragValue) }
                                dragValue = nil
                            }
                    )
                }
                .frame(height: 14)
                Text(verbatim: duration > 0 ? Self.format(duration) : "--:--")
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(AppColors.textSecondary)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Boton redondo de cristal; el de reproducir, azul solido.
private struct ControlButton: View {
    let icon: String
    let size: CGFloat
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(prominent ? AppColors.onAccent : (hovering ? AppColors.accent : AppColors.textPrimary))
                .frame(width: size, height: size)
                .background { if prominent { Circle().fill(AppColors.accent) } }
                .modifier(GlassUnlessProminent(prominent: prominent))
                .shadow(color: prominent ? AppColors.accent.opacity(0.4) : .clear, radius: 6, y: 2)
                .contentShape(Circle())
                .scaleEffect(hovering && !AppMotion.reduceMotion ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppMotion.snappy, value: hovering)
    }
}

private struct GlassUnlessProminent: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent { content } else { content.liquidGlass(in: Circle(), interactive: true) }
    }
}

/// Caratula con esquinas redondeadas; sin imagen, una nota musical.
struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                AppColors.accentSoft
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.35, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: .black.opacity(size > 40 ? 0.3 : 0), radius: 10, y: 4)
        .animation(.easeOut(duration: 0.25), value: image)
    }
}

/// Lo que se ve con el notch cerrado mientras suena musica: la caratula a un lado y
/// unas barras que bailan al otro, como una actividad en directo.
struct MusicActivity: View {
    let nowPlaying: NowPlaying
    let metrics: NotchMetrics

    var body: some View {
        let side = NotchMetrics.activitySide
        let art = metrics.notchHeight - 12
        HStack(spacing: 0) {
            Artwork(image: nowPlaying.artwork, size: art, corner: 6)
                .frame(width: side, alignment: .center)
                .padding(.leading, NotchMetrics.closedEar)
            Spacer(minLength: metrics.notchWidth)
            Equalizer(isPlaying: nowPlaying.isPlaying)
                .frame(width: side, alignment: .center)
                .padding(.trailing, NotchMetrics.closedEar)
        }
        .frame(height: metrics.notchHeight)
    }
}

/// Barras que suben y bajan mientras suena; quietas en pausa.
private struct Equalizer: View {
    let isPlaying: Bool
    private static let bars = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying || AppMotion.reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<Self.bars, id: \.self) { index in
                    let phase = sin(t * (5.3 + Double(index) * 1.7) + Double(index) * 1.3)
                    Capsule()
                        .fill(AppColors.accent)
                        .frame(width: 3, height: isPlaying ? 6 + 8 * CGFloat((phase + 1) / 2) : 4)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: t)
        }
        .frame(height: 16)
    }
}
