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
                Spacer(minLength: 0)
            }
            .animation(AppMotion.snappy, value: monitor.activeFamilies)
            .padding(.horizontal, NotchContentView.margin)
            .frame(height: NotchMetrics.searchRowHeight - 10)
            .padding(.bottom, 10)

            if monitor.sessions.isEmpty {
                Text("No hay sesiones de Claude Code ni de Codex")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: NotchMetrics.cardRowHeight)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(monitor.sessions) { session in
                            AgentCard(session: session)
                        }
                    }
                    .padding(.horizontal, NotchContentView.margin)
                    .padding(.vertical, 8)
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
    static var claude: NSImage? { icon("com.anthropic.claudefordesktop") }
    static var codex: NSImage? { icon("com.openai.codex") }
    static var vscode: NSImage? { icon("com.microsoft.VSCode") }

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
        HStack(spacing: 7) {
            Logo(image: icon, size: 18)
            Text(verbatim: name).font(AppTypography.bodyStrong).foregroundStyle(AppColors.textPrimary)
            if let usage {
                ForEach(usage.windows, id: \.label) { window in
                    UsageWindow(window: window)
                }
            } else {
                Text("Consumo no disponible")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .liquidGlass(in: Capsule())
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
            let left = 100 - used
            let color = left <= 10 ? AppColors.danger : left <= 30 ? AppColors.warning : AppColors.accent
            HStack(spacing: 6) {
                Text(verbatim: window.label)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.textSecondary)
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.controlTrack)
                    Capsule().fill(color).frame(width: max(3, 46 * used / 100))
                }
                .frame(width: 46, height: 5)
                Group {
                    if reset {
                        Text("reiniciada")
                    } else {
                        Text("quedan \(Int(left.rounded())) %")
                    }
                }
                .font(AppTypography.bodyStrong.monospacedDigit())
                .foregroundStyle(left <= 30 ? color : AppColors.textPrimary)
            }
        }
        .help(window.resetsAt.map { Text("Se reinicia \(AgeText.format($0, now: .now))") } ?? Text(verbatim: ""))
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
                Text(verbatim: consumption)
                    .foregroundStyle(session.tokens == nil ? AppColors.textSecondary : AppColors.textPrimary)
                AgeText(date: session.updatedAt)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .font(AppTypography.cardCaption)
            .lineLimit(1)
        }
        .padding(10)
        .frame(width: 200, height: 120, alignment: .topLeading)
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

    /// Lo que de verdad da la fuente; si no lo da, se dice.
    private var consumption: String {
        guard let tokens = session.tokens else { return String(localized: "Consumo: no lo expone") }
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
