import SwiftUI

/// Aviso breve a los lados del notch cerrado: icono a la izquierda, valor a la
/// derecha. El notch se ensancha lo justo para cada tipo.
struct HUDActivity: View {
    let kind: SystemHUD.Kind
    let metrics: NotchMetrics

    /// Ancho que crece el notch a cada lado para este aviso.
    static func side(for kind: SystemHUD.Kind) -> CGFloat {
        switch kind {
        case .volume, .battery: return 58
        case .mediaInUse: return 44
        case .timer, .stayAwake: return 70
        case .capsLock, .timerDone, .alarm: return 96
        case .network, .meeting: return 104
        case .audioDevice, .download: return 112
        }
    }

    var body: some View {
        let side = Self.side(for: kind)
        HStack(spacing: 0) {
            leading
                .frame(width: side - 8, alignment: .leading)
                .padding(.leading, NotchMetrics.closedEar + 12)
            Spacer(minLength: metrics.notchWidth)
            trailing
                .frame(width: side - 8, alignment: .trailing)
                .padding(.trailing, NotchMetrics.closedEar + 12)
        }
        .foregroundStyle(AppColors.notchText)
        .frame(height: metrics.notchHeight)
    }

    @ViewBuilder
    private var leading: some View {
        switch kind {
        case let .volume(level, muted):
            Image(systemName: muted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: level)
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        case let .audioDevice(_, icon):
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
        case let .battery(level, charging):
            Image(systemName: charging ? "battery.100percent.bolt" : Self.batterySymbol(level))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(charging ? AppColors.success : level <= 10 ? AppColors.danger : level <= 20 ? AppColors.warning : AppColors.notchText)
        case let .download(_, done):
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.success)
                    .transition(.scale.combined(with: .opacity))
            } else {
                ProgressView().controlSize(.small).tint(AppColors.accent)
            }
        case let .capsLock(on):
            Image(systemName: on ? "capslock.fill" : "capslock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? AppColors.accent : AppColors.notchText)
        case let .network(online, vpn):
            Image(systemName: !online ? "wifi.slash" : vpn ? "lock.shield.fill" : "wifi")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(online ? AppColors.success : AppColors.danger)
        case .timerDone:
            Image(systemName: "timer").font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.clock)
                .symbolEffect(.bounce, options: .repeat(3))
        case .alarm:
            Image(systemName: "alarm.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.clock)
                .symbolEffect(.pulse)
        case .meeting:
            Image(systemName: "video.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.accent)
        case let .timer(end, total):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, end.timeIntervalSince(context.date))
                ZStack {
                    Circle().stroke(AppColors.notchText.opacity(0.2), lineWidth: 2.5)
                    Circle().trim(from: 0, to: total > 0 ? left / total : 0)
                        .stroke(AppColors.clock, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
            }
        case let .mediaInUse(mic, _):
            Image(systemName: mic ? "mic.fill" : "video.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mic ? AppColors.warning : AppColors.success)
        case .stayAwake:
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 13, weight: .semibold))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch kind {
        case let .volume(level, muted):
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.notchText.opacity(0.2))
                Capsule().fill(muted ? AppColors.notchText.opacity(0.4) : AppColors.notchText)
                    .frame(width: max(4, 40 * (muted ? 0 : level)))
            }
            .frame(width: 40, height: 5)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: level)
        case let .audioDevice(name, _):
            Text(verbatim: name).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.tail)
        case let .battery(level, _):
            Text(verbatim: "\(level) %").font(.system(size: 12, weight: .semibold).monospacedDigit())
        case let .download(name, _):
            Text(verbatim: name).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.middle)
        case let .capsLock(on):
            Text(on ? "Mayúsculas" : "Minúsculas").font(.system(size: 11, weight: .semibold))
        case let .network(online, vpn):
            Text(!online ? "Sin conexión" : vpn ? "VPN" : "Conectado").font(.system(size: 11, weight: .semibold))
        case .timerDone:
            Text("¡Tiempo!").font(.system(size: 12, weight: .bold))
        case let .alarm(time):
            Text(verbatim: time.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(AppColors.clock)
        case let .meeting(_, start):
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let minutes = Int((start.timeIntervalSince(context.date) / 60).rounded(.up))
                Text(minutes <= 0 ? String(localized: "Ahora") : String(localized: "en \(minutes) min"))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(minutes <= 1 ? AppColors.accent : AppColors.notchText)
            }
        case let .timer(end, _):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(verbatim: Self.clock(end.timeIntervalSince(context.date)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppColors.clock)
            }
        case let .mediaInUse(mic, camera):
            if mic && camera {
                Image(systemName: "video.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppColors.success)
            } else {
                Circle().fill(mic ? AppColors.warning : AppColors.success).frame(width: 6, height: 6)
            }
        case let .stayAwake(until):
            if let until {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(verbatim: Self.clock(until.timeIntervalSince(context.date)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
            } else {
                Image(systemName: "infinity").font(.system(size: 12, weight: .bold))
            }
        }
    }

    /// 24:59, o 1:20:00 si pasa de una hora.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    private static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
