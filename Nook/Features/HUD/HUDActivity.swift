import SwiftUI

/// Aviso breve a los lados del notch cerrado: icono a la izquierda, valor a la
/// derecha. El notch se ensancha lo justo para cada tipo.
struct HUDActivity: View {
    let kind: SystemHUD.Kind
    let metrics: NotchMetrics
    /// Lo que crece el notch a cada lado (segun el hueco libre de la barra de menus).
    let sides: HUDSides

    /// Ancho que pide cada lado del notch para este aviso.
    static func side(for kind: SystemHUD.Kind) -> CGFloat {
        switch kind {
        case .volume, .battery: return 58
        case .mediaInUse: return 44
        case .timer, .stayAwake: return 70
        case .capsLock, .timerDone, .alarm: return 96
        case .network, .meeting: return 104
        case .audioDevice, .download, .mail, .notice: return 112
        case .dictation: return 140
        case .accessory: return 112
        case .notification: return 150
        case .agent: return 120
        }
    }

    var body: some View {
        let ear = NotchMetrics.closedEar
        HStack(spacing: 0) {
            Group {
                if sides.merged, sides.left > 0 {
                    HStack(spacing: 8) { leading; trailing }
                } else if sides.left > 0 {
                    leading
                }
            }
            .padding(.leading, ear + 10)
            .frame(width: sides.left + ear, alignment: .leading)

            Color.clear.frame(width: metrics.notchWidth)

            Group {
                if sides.merged, sides.right > 0 {
                    HStack(spacing: 8) { leading; trailing }
                } else if sides.right > 0 {
                    trailing
                }
            }
            .padding(.trailing, ear + 10)
            .frame(width: sides.right + ear, alignment: .trailing)
        }
        .foregroundStyle(AppColors.notchText)
        .frame(height: metrics.notchHeight)
        .clipped()
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
            if #available(macOS 15, *) {
                Self.logo(AgentIcons.clock, fallback: "timer")
                    .symbolEffect(.bounce, options: .repeat(3))
            } else {
                Self.logo(AgentIcons.clock, fallback: "timer")
            }
        case let .notification(bundleID, _, _):
            if let icon = AgentIcons.icon(bundleID) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "bell.fill").font(.system(size: 13, weight: .semibold))
            }
        case let .accessory(_, icon, _, _):
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
        case let .notice(icon, _):
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.accent)
        case .dictation:
            Image(systemName: "mic.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.danger)
                .symbolEffect(.pulse)
        case .mail:
            Self.logo(AgentIcons.mail(MailService.Source(rawValue: UserDefaults.standard.string(forKey: SettingsKey.mailSource) ?? "") ?? .mail), fallback: "envelope.fill")
        case .alarm:
            Self.logo(AgentIcons.clock, fallback: "alarm.fill")
                .symbolEffect(.pulse)
        case .meeting:
            Self.logo(AgentIcons.calendar, fallback: "video.fill")
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
        case let .agent(_, waiting):
            if #available(macOS 15, *) {
                Self.logo(AgentIcons.claude, fallback: "sparkles")
                    .symbolEffect(.bounce, options: .repeat(waiting ? 2 : 1))
            } else {
                Self.logo(AgentIcons.claude, fallback: "sparkles")
            }
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
        case let .notification(_, title, body):
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: title).font(.system(size: 10, weight: .bold)).lineLimit(1)
                if !body.isEmpty {
                    Text(verbatim: body).font(.system(size: 9, weight: .medium)).opacity(0.75).lineLimit(1)
                }
            }
            .truncationMode(.tail)
        case let .accessory(name, _, level, low):
            HStack(spacing: 6) {
                if low {
                    Text(verbatim: name).font(.system(size: 10, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                }
                ZStack {
                    Circle().stroke(AppColors.notchText.opacity(0.2), lineWidth: 2.5)
                    Circle().trim(from: 0, to: CGFloat(level) / 100)
                        .stroke(low ? AppColors.danger : AppColors.success, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
                Text(verbatim: "\(level) %").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(low ? AppColors.danger : AppColors.notchText)
            }
        case let .notice(_, text):
            Text(verbatim: text).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        case let .dictation(text):
            // Las ultimas palabras: el principio se corta.
            Text(text.isEmpty ? String(localized: "Escuchando…") : text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.head)
        case let .mail(sender):
            Text(verbatim: sender).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.tail)
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
        case let .agent(project, waiting):
            VStack(alignment: .trailing, spacing: 0) {
                Text(waiting ? "Te espera" : "Terminó")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(waiting ? AppColors.warning : AppColors.success)
                if let project {
                    Text(verbatim: project).font(.system(size: 9, weight: .medium)).opacity(0.75)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
        }
    }

    /// Icono oficial de la app (Reloj, Mail, Calendario) o el simbolo si no esta.
    @ViewBuilder
    private static func logo(_ image: NSImage?, fallback: String) -> some View {
        if let image {
            Image(nsImage: image).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: fallback).font(.system(size: 13, weight: .semibold))
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

/// Tarjeta que sale al pulsar un aviso: que ha pasado y un boton para ir a su origen.
struct HUDPreviewCard: View {
    let preview: SystemHUD.Preview
    let metrics: NotchMetrics
    let onAction: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.title).font(AppTypography.title).lineLimit(1)
                if !preview.subtitle.isEmpty {
                    Text(preview.subtitle).font(AppTypography.body).lineLimit(1)
                        .foregroundStyle(AppColors.notchText.opacity(0.75))
                }
                if !preview.body.isEmpty {
                    Text(preview.body).font(AppTypography.subtitle).lineLimit(2)
                        .foregroundStyle(AppColors.notchText.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onAction) {
                Text(preview.actionTitle)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AppColors.accentFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppColors.notchText)
        .padding(.horizontal, NotchMetrics.sideMargin)
        .padding(.top, metrics.notchHeight + 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: preview.file) {
            guard let file = preview.file else { return }
            thumbnail = await Thumbnails.image(for: file, size: CGSize(width: 80, height: 80))
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = thumbnail ?? preview.appIcon {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 40, height: 40)
        } else {
            Image(systemName: preview.symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppColors.notchText.opacity(0.12)))
        }
    }
}
