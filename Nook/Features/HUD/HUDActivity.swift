import SwiftUI

/// Aviso breve a los lados del notch cerrado: icono a la izquierda, valor a la
/// derecha. El notch se ensancha lo justo para cada tipo.
struct HUDActivity: View {
    let kind: SystemHUD.Kind
    let metrics: NotchMetrics
    /// Lo que crece el notch a cada lado (segun el hueco libre de la barra de menus).
    let sides: HUDSides
    @Environment(SystemHUD.self) private var hud
    /// Como isla: icono y valor en una fila bajo el notch, centrados.
    var island = false

    /// Ancho que pide cada lado del notch para este aviso.
    static func side(for kind: SystemHUD.Kind) -> CGFloat {
        switch kind {
        // El nombre entero ("AirPods Pro de Diego"), sin puntos suspensivos: el lado
        // crece con el (con tope); si la barra no deja sitio, el aviso sale como isla.
        case let .audioDevice(name, _):
            return min(190, max(112, textWidth(name, size: 11) + 14))
        case let .accessory(name, _, _, low) where low:
            return min(220, max(112, textWidth(name, size: 10) + 6 + 14 + 6 + textWidth("100 %", size: 12) + 14))
        case .volume, .battery: return 58
        case .mediaInUse: return 44
        case .timer, .stayAwake: return 70
        case .capsLock, .timerDone, .alarm: return 96
        case .network, .meeting: return 104
        case .download, .mail, .notice: return 112
        case .dictation: return 140
        case .accessory: return 112
        case .notification: return 150
        case .agent: return 84
        case .usage: return 96
        case .music: return 50
        }
    }

    /// Avisos que salen como isla (bajo el notch) en vez de en las alas: ancho del
    /// contenido y alto bajo el notch, o nil si va en las alas. Una notificacion
    /// siempre; cualquier otro aviso, si a un lado no le cabe lo que pide (los iconos
    /// de la barra llegan al notch). Antes iba entero al otro lado y se veia descuadrado.
    static func island(for kind: SystemHUD.Kind, leftFree: CGFloat?, rightFree: CGFloat?) -> (content: CGFloat, extra: CGFloat)? {
        if case .notification = kind { return (NotificationIsland.contentWidth(for: kind), NotchMetrics.islandExtra) }
        let desired = side(for: kind)
        let sides = HUDSides.make(desired: desired, leftFree: leftFree, rightFree: rightFree)
        guard sides.merged || sides.left < desired || sides.right < desired else { return nil }
        return (desired * 2 - 24, NotchMetrics.islandRowExtra)
    }

    var body: some View {
        if island { islandRow } else { wings }
    }

    private var islandRow: some View {
        HStack(spacing: 10) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .lineLimit(1)
        .foregroundStyle(AppColors.notchText)
        .frame(height: NotchMetrics.islandRowExtra)
        .padding(.horizontal, NotchMetrics.islandPadding)
        .padding(.top, metrics.notchHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var wings: some View {
        let ear = NotchMetrics.closedEar
        return HStack(spacing: 0) {
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
            CountdownRing(end: end, total: total, color: AppColors.clock)
                .frame(width: 15, height: 15)
        case let .mediaInUse(_, _, call):
            // La app de la llamada (FaceTime, Teams...); el punto de la derecha dice
            // si usa micro (naranja, como macOS) o camara (verde).
            CallAppIcon(call: call, size: 18)
        case .stayAwake:
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 13, weight: .semibold))
        case .agent:
            // Sin rebote propio: el aviso entra de una vez, con la forma.
            Self.logo(AgentIcons.claude, fallback: "sparkles")
        case .usage:
            Self.logo(AgentIcons.claude, fallback: "sparkles")
        case .music:
            // Caratula de la cancion (o el icono de la app mientras carga).
            if let image = hud.nowPlaying?.artwork ?? hud.nowPlaying?.player?.icon {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "music.note").font(.system(size: 13, weight: .semibold))
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
            Text(verbatim: name).font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
        case let .battery(level, _):
            Text(verbatim: "\(level) %").font(.system(size: 12, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText(value: Double(level)))
                .animation(AppMotion.snappy, value: level)
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
                        .layoutPriority(1)
                }
                ProgressRing(value: Double(level) / 100, color: low ? AppColors.danger : AppColors.success)
                    .frame(width: 14, height: 14)
                Text(verbatim: "\(level) %").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(low ? AppColors.danger : AppColors.notchText)
                    .contentTransition(.numericText(value: Double(level)))
            }
            .animation(AppMotion.snappy, value: level)
        case let .notice(_, text):
            Text(verbatim: text).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        case let .dictation(text):
            // Las ultimas palabras: el principio se pierde con un fundido.
            TailText(text: text.isEmpty ? String(localized: "Escuchando…") : text, font: .system(size: 11, weight: .semibold))
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
                    .contentTransition(.numericText(countsDown: true))
                    .animation(AppMotion.snappy, value: minutes)
            }
        case let .timer(end, _):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = end.timeIntervalSince(context.date)
                Text(verbatim: Self.clock(left))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppColors.clock)
                    // Solo cambia la cifra que cambia, y se ve cambiar.
                    .contentTransition(.numericText(countsDown: true))
                    .animation(AppMotion.snappy, value: Self.clock(left))
            }
        case let .mediaInUse(mic, camera, _):
            if mic && camera {
                Image(systemName: "video.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppColors.success)
            } else {
                Circle().fill(mic ? AppColors.warning : AppColors.success).frame(width: 6, height: 6)
            }
        case let .stayAwake(until):
            if let until {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let left = until.timeIntervalSince(context.date)
                    Text(verbatim: Self.clock(left))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .animation(AppMotion.snappy, value: Self.clock(left))
                }
            } else {
                Image(systemName: "infinity").font(.system(size: 12, weight: .bold))
            }
        case let .agent(_, waiting):
            // Una sola linea; el proyecto sale en la tarjeta al pulsar.
            Text(waiting ? "Te espera" : "Terminó")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(waiting ? AppColors.warning : AppColors.success)
                .lineLimit(1)
        case let .usage(percent, window):
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: "\(percent) %")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(percent >= 95 ? AppColors.danger : AppColors.warning)
                    .contentTransition(.numericText(value: Double(percent)))
                    .animation(AppMotion.snappy, value: percent)
                Text(verbatim: window).font(.system(size: 9, weight: .medium)).opacity(0.75)
            }
            .lineLimit(1)
        case .music:
            MusicBars()
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

    /// Ancho de una linea en la fuente del sistema, semibold.
    static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)]).width)
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

/// Notificacion como la Isla Dinamica: bajo el notch, el icono de la app, quien
/// escribe y el mensaje en una linea. Al pulsarla sale la tarjeta (responder, abrir).
struct NotificationIsland: View {
    let kind: SystemHUD.Kind
    let metrics: NotchMetrics

    /// Ancho que pide el mensaje (sin margenes): icono y la linea mas larga.
    static func contentWidth(for kind: SystemHUD.Kind) -> CGFloat {
        guard case let .notification(_, title, body) = kind else { return 0 }
        func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
        }
        return 26 + 10 + ceil(max(width(title, 12, .semibold), width(body, 11, .regular)))
    }

    var body: some View {
        if case let .notification(bundleID, title, body) = kind {
            HStack(spacing: 10) {
                if let icon = AgentIcons.icon(bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                } else {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(AppColors.notchText.opacity(0.14)))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).font(AppTypography.bodyStrong).lineLimit(1)
                    if !body.isEmpty {
                        Text(verbatim: body).font(AppTypography.subtitle).lineLimit(1)
                            .foregroundStyle(AppColors.notchText.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .truncationMode(.tail)
            .foregroundStyle(AppColors.notchText)
            .padding(.horizontal, NotchMetrics.islandPadding)
            .padding(.top, metrics.notchHeight + 4)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Tarjeta que sale al pulsar un aviso: que ha pasado y un boton para ir a su origen.
struct HUDPreviewCard: View {
    let preview: SystemHUD.Preview
    let metrics: NotchMetrics
    let onExtra: (SystemHUD.Preview.Extra) -> Void
    let onAction: () -> Void
    @State private var thumbnail: NSImage?

    private static let iconSize: CGFloat = 32
    private static let spacing: CGFloat = 12
    private static let lineSpacing: CGFloat = 1
    private static let extraSize: CGFloat = 30

    /// Tamaño que pide el contenido de la tarjeta (sin margenes), con las mismas
    /// fuentes que `AppTypography`: la tarjeta crece lo justo para su texto.
    static func contentSize(for preview: SystemHUD.Preview) -> CGSize {
        func measure(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight) -> CGSize {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            let width = text.isEmpty ? 0 : (text as NSString).size(withAttributes: [.font: font]).width
            return CGSize(width: ceil(width), height: ceil(font.ascender - font.descender + font.leading))
        }
        var lines = [measure(preview.title, 13, .semibold)]
        if !preview.subtitle.isEmpty { lines.append(measure(preview.subtitle, 12, .regular)) }
        if !preview.body.isEmpty { lines.append(measure(preview.body, 11, .regular)) }
        let text = CGSize(
            width: lines.map(\.width).max() ?? 0,
            height: lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(lines.count - 1)
        )
        let button = measure(preview.actionTitle, 12, .semibold).width + 28
        let extras = CGFloat(preview.extras.count) * (extraSize + spacing)
        return CGSize(
            width: iconSize + spacing + text.width + spacing + extras + button,
            height: max(iconSize, text.height)
        )
    }

    var body: some View {
        summaryRow
            .foregroundStyle(AppColors.notchText)
            .padding(.horizontal, NotchMetrics.sideMargin)
            .padding(.top, metrics.notchHeight + NotchMetrics.previewTop)
            .padding(.bottom, NotchMetrics.previewBottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task(id: preview.file) {
                guard let file = preview.file else { return }
                thumbnail = await Thumbnails.image(for: file, size: CGSize(width: 80, height: 80))
            }
    }

    private var summaryRow: some View {
        HStack(spacing: Self.spacing) {
            icon
            VStack(alignment: .leading, spacing: Self.lineSpacing) {
                Text(preview.title).font(AppTypography.title).lineLimit(1)
                // Sobre el cristal, el texto secundario necesita mas opacidad que sobre negro.
                if !preview.subtitle.isEmpty {
                    Text(preview.subtitle).font(AppTypography.body).lineLimit(1)
                        .foregroundStyle(AppColors.notchText.opacity(0.9))
                }
                if !preview.body.isEmpty {
                    Text(preview.body).font(AppTypography.subtitle).lineLimit(1)
                        .foregroundStyle(AppColors.notchText.opacity(0.8))
                }
            }
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(preview.extras.indices, id: \.self) { index in
                let extra = preview.extras[index]
                Button { onExtra(extra) } label: {
                    Image(systemName: extra.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: Self.extraSize, height: Self.extraSize)
                        .background(Circle().fill(AppColors.notchText.opacity(0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: extra.title))
                .accessibilityLabel(Text(verbatim: extra.title))
            }
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
    }

    @ViewBuilder
    private var icon: some View {
        if let image = thumbnail ?? preview.appIcon {
            Image(nsImage: image).resizable().scaledToFit().frame(width: Self.iconSize, height: Self.iconSize)
        } else {
            Image(systemName: preview.symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: Self.iconSize, height: Self.iconSize)
                .background(Circle().fill(AppColors.notchText.opacity(0.12)))
        }
    }
}

/// Barras de ecualizador mientras suena la musica. Con "Reducir movimiento", quietas.
private struct MusicBars: View {
    var body: some View {
        if AppMotion.reduceMotion {
            bars(at: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func bars(at time: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                let phase = time * (3.1 + Double(index) * 0.9) + Double(index) * 1.7
                Capsule()
                    .fill(AppColors.success)
                    .frame(width: 2.5, height: 4 + 9 * (0.5 + 0.5 * sin(phase)))
            }
        }
        .frame(width: 18, height: 14)
    }
}

extension SystemHUD.Kind {
    /// El tipo de aviso sin sus valores: el mismo tipo con otro valor (el volumen que
    /// sube) se actualiza en su sitio; otro tipo se cruza con el anterior.
    var family: String {
        switch self {
        case .volume: "volume"
        case .audioDevice: "audioDevice"
        case .battery: "battery"
        case .download: "download"
        case .capsLock: "capsLock"
        case .network: "network"
        case .timerDone: "timerDone"
        case .mail: "mail"
        case .notice: "notice"
        case .dictation: "dictation"
        case .accessory: "accessory"
        case .notification: "notification"
        case .agent: "agent"
        case .usage: "usage"
        case .meeting: "meeting"
        case .timer: "timer"
        case .mediaInUse: "mediaInUse"
        case .stayAwake: "stayAwake"
        case .alarm: "alarm"
        case .music: "music"
        }
    }
}
