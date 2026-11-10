import AppKit
import SwiftUI

/// Sesiones de IA: consumo de la suscripcion arriba y una tarjeta por sesion con la
/// herramienta, el proyecto, el estado y el consumo que exponga su fuente.
struct AgentsView: View {
    let monitor: AgentMonitor

    var body: some View {
        VStack(spacing: 0) {
            // Solo la suscripcion de lo que se esta usando.
            HStack(spacing: 8) {
                ForEach(monitor.activeFamilies, id: \.self) { family in
                    UsageChip(
                        icon: family == .claude ? AgentIcons.claude : AgentIcons.codex,
                        name: family == .claude ? "Claude" : "Codex",
                        usage: monitor.usage(for: family)
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(AppMotion.snappy, value: monitor.activeFamilies)
            .padding(.horizontal, NotchContentView.margin)
            .frame(height: NotchMetrics.searchRowHeight - 10)
            .padding(.bottom, 10)

            if monitor.sessions.isEmpty {
                Text("No hay ninguna sesión activa")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: NotchMetrics.cardRowHeight)
            } else {
                Carousel(data: monitor.sessions, minSpacing: 8) { _, session in
                    Button { monitor.focus(session) } label: { AgentCard(session: session) }
                        .buttonStyle(.plain)
                        .help(Text("Ir a su terminal"))
                }
                .frame(height: NotchMetrics.cardRowHeight)
            }
        }
        // Mientras se ve la pestaña se relee cada 3 s (archivos pequeños y dos
        // consultas de solo lectura).
        .task {
            while !Task.isCancelled {
                await monitor.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

/// Logos oficiales: los iconos de las propias apps instaladas en el Mac.
enum AgentIcons {
    static let claude: NSImage? = icon("com.anthropic.claudefordesktop")
    static let codex: NSImage? = icon("com.openai.codex")
    static let vscode: NSImage? = icon("com.microsoft.VSCode")

    // Apps del sistema para las demas secciones (iconos oficiales instalados).
    static let calendar: NSImage? = icon("com.apple.iCal")
    static let clock: NSImage? = icon("com.apple.clock")
    static let screenshot: NSImage? = icon("com.apple.screenshot.launcher")
    /// Mail u Outlook, segun de donde se lea la bandeja (Mail si no esta Outlook).
    static func mail(_ source: MailService.Source) -> NSImage? {
        icon(source.bundleID) ?? icon(MailService.Source.mail.bundleID)
    }

    static func icon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// Consumo de una suscripcion: sus ventanas en porcentaje, o que no hay dato.
private struct UsageChip: View {
    let icon: NSImage?
    let name: String
    let usage: SubscriptionUsage?

    var body: some View {
        HStack(spacing: 14) {
            Logo(image: icon, size: 18)
                .help(Text(verbatim: name))
            if let usage {
                ForEach(usage.windows, id: \.label) { window in
                    UsageWindow(window: window)
                }
            } else {
                UsageSetupHint()
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        // Todo el ancho: las barras se estiran y el texto nunca se corta.
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 28)
        .liquidGlass(in: Capsule())
    }

}

/// Sin dato de consumo: dice por que y lo arregla si se puede con un clic.
private struct UsageSetupHint: View {
    @State private var state = ClaudeUsageSetup.state()

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            switch state {
            case .needsConnection:
                Button("Conectar") {
                    try? ClaudeUsageSetup.connect()
                    state = ClaudeUsageSetup.state()
                }
                .buttonStyle(.plain)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColors.accent)
            case .noPlugin:
                Link("Instalar claude-hud", destination: ClaudeUsageSetup.pluginURL)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.accent)
            case .connected, .noClaude:
                EmptyView()
            }
        }
    }

    private var message: LocalizedStringKey {
        switch state {
        case .connected: return "El consumo aparece al usar Claude Code"
        case .needsConnection: return "Consumo sin conectar"
        case .noPlugin: return "Para ver el consumo hace falta la barra de estado claude-hud"
        case .noClaude: return "Consumo no disponible"
        }
    }
}

/// Una ventana de uso (5 h, semanal): barra con lo gastado y lo que queda.
private struct UsageWindow: View {
    let window: SubscriptionUsage.Window

    var body: some View {
        // El snapshot solo se actualiza mientras hay una sesion abierta: si la ventana
        // ya se reinicio desde entonces, el porcentaje guardado no vale.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let reset = window.resetsAt.map { $0 <= context.date } ?? false
            let used = reset ? 0 : min(max(window.usedPercent, 0), 100)
            let color = used >= 90 ? AppColors.danger : used >= 70 ? AppColors.warning : AppColors.accent
            HStack(spacing: 6) {
                Text(verbatim: window.label)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize()
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColors.controlTrack)
                        Capsule().fill(color).frame(width: max(3, proxy.size.width * used / 100))
                    }
                }
                .frame(minWidth: 46, maxWidth: .infinity)
                .frame(height: 5)
                Group {
                    if reset {
                        Text("reiniciada")
                    } else {
                        Text(verbatim: "\(window.usedRounded) %")
                    }
                }
                .font(AppTypography.bodyStrong.monospacedDigit())
                .foregroundStyle(used >= 70 ? color : AppColors.textPrimary)
                .fixedSize()
                if !reset, let time = window.resetLabel(now: context.date) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                        Text(verbatim: time)
                    }
                    .font(AppTypography.body.monospacedDigit())
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize()
                }
            }
        }
        .help(Text("Consumido \(window.usedRounded) %") + (window.resetsAt.map { Text(verbatim: " · ") + Text("Se reinicia \(AgeText.format($0, now: .now))") } ?? Text(verbatim: "")))
    }
}

/// Icono de app con esquinas; sin app instalada, un simbolo neutro.
private struct Logo: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        if let image {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "brain")
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: size, height: size)
        }
    }
}

/// Tarjeta de una sesion.
private struct AgentCard: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Logo(image: mainIcon, size: 28)
                    if let badge = badgeIcon {
                        Logo(image: badge, size: 14).offset(x: 4, y: 4)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: toolName)
                        .font(AppTypography.cardTitle.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(verbatim: [whereLabel, session.project].compactMap { $0 }.joined(separator: " · "))
                        .font(AppTypography.cardCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .truncationMode(.middle)
                }
                .lineLimit(1)
            }

            StatusPill(status: session.status)

            VStack(alignment: .leading, spacing: 1) {
                // El consumo solo si la fuente lo da (Codex); si no, nada que decir.
                if let consumption {
                    Text(verbatim: consumption)
                        .foregroundStyle(AppColors.textPrimary)
                }
                AgeText(date: session.updatedAt)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .font(AppTypography.cardCaption)
            .lineLimit(1)
        }
        .padding(10)
        .frame(width: 168, height: 120, alignment: .topLeading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var mainIcon: NSImage? {
        if case .codex = session.tool { return AgentIcons.codex }
        return AgentIcons.claude
    }

    private var badgeIcon: NSImage? {
        session.tool == .claudeVSCode ? AgentIcons.vscode : nil
    }

    private var toolName: String {
        if case .codex = session.tool { return "Codex" }
        return "Claude Code"
    }

    private var whereLabel: String? {
        switch session.tool {
        case .claudeTerminal: return String(localized: "Terminal")
        case .claudeVSCode: return "VS Code"
        case let .claudeOther(entry): return entry
        case let .codex(source): return source == "vscode" ? String(localized: "App") : source
        }
    }

    private var consumption: String? {
        guard let tokens = session.tokens else { return nil }
        let formatted = tokens.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        return String(localized: "\(formatted) tokens")
    }
}

private struct StatusPill: View {
    let status: AgentSession.Status

    var body: some View {
        HStack(spacing: 5) {
            if status == .running {
                ProgressView().controlSize(.mini).tint(color)
            } else {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            }
            Text(verbatim: label).lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(color.opacity(0.15)))
    }

    private var label: String {
        switch status {
        case .running: return String(localized: "En curso")
        case let .pending(reason):
            switch reason {
            case "input needed": return String(localized: "Pendiente: te pregunta")
            case "dialog open": return String(localized: "Pendiente: diálogo abierto")
            case "sandbox request": return String(localized: "Pendiente: pide permiso")
            default: return String(localized: "Pendiente")
            }
        case .finished: return String(localized: "Terminada")
        case .interrupted: return String(localized: "Interrumpida")
        case .failed: return String(localized: "Con error")
        case let .unknown(raw): return String(localized: "Estado desconocido (\(raw))")
        }
    }

    private var icon: String {
        switch status {
        case .pending: return "hand.raised.fill"
        case .finished: return "checkmark"
        case .interrupted: return "stop.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "questionmark"
        }
    }

    private var color: Color {
        switch status {
        case .running: return AppColors.accent
        case .pending: return AppColors.warning
        case .finished: return AppColors.success
        case .failed: return AppColors.danger
        default: return AppColors.textSecondary
        }
    }
}
