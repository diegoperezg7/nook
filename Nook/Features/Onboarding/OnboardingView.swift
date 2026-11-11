import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Primer arranque: que es Nook, conectar calendario y correo, permisos avanzados y
/// que atajos y avisos activar. Todo se puede saltar y cambiar luego en Ajustes.
struct OnboardingView: View {
    let calendar: CalendarService
    let mail: MailService
    let screenshots: ScreenshotLibrary
    let permissions: PermissionState
    let finish: () -> Void

    enum Step: Int, CaseIterable { case welcome, accounts, extras, permissions, shortcuts, done }
    @State private var step: Step = Self.initialStep
    @State private var forward = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page(step)
                    .id(step)
                    // El contenido nuevo entra escalonado (`rise`); la pagina que sale
                    // solo se desliza un poco y se funde.
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .offset(x: AppMotion.reduceMotion ? 0 : (forward ? -36 : 36)).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
            footer
                .padding(.horizontal, 28)
                .frame(height: 64)
        }
        .frame(width: 640, height: 560)
        .background(AppColors.panel)
        .tint(AppColors.accent)
    }

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .welcome: WelcomePage()
        case .accounts: AccountsPage(calendar: calendar, mail: mail)
        case .extras: ExtrasPage(screenshots: screenshots)
        case .permissions: PermissionsPage(permissions: permissions)
        case .shortcuts: ShortcutsPage()
        case .done: DonePage()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step == .welcome {
                Button("Saltar", action: finish)
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Button("Atrás") { go(-1) }
                    .controlSize(.large)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? AppColors.accent : AppColors.controlTrack)
                        .frame(width: item == step ? 18 : 7, height: 7)
                }
            }
            .animation(AppMotion.snappy, value: step)
            Spacer()
            Button(action: { step == .done ? finish() : go(1) }) {
                Text(step == .done ? "Empezar" : step == .welcome ? "Configurar" : "Siguiente")
                    .frame(minWidth: 90)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private static var initialStep: Step {
        #if DEBUG
        // `-NookOnboardingStep 2` abre directamente ese paso (para revisarlo).
        if let step = Step(rawValue: UserDefaults.standard.integer(forKey: "NookOnboardingStep")) { return step }
        #endif
        return Step(rawValue: UserDefaults.standard.integer(forKey: Self.stepKey)) ?? .welcome
    }

    /// Paso en el que se quedo: al dar Acceso total al disco macOS reinicia Visor, y
    /// la introduccion sigue donde iba en vez de volver al principio.
    static let stepKey = "onboardingStep"

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(AppMotion.reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.9)) { step = next }
        UserDefaults.standard.set(next.rawValue, forKey: Self.stepKey)
    }
}

/// Titulo y explicacion de cada paso.
private struct PageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            Text(subtitle).font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 480)
        .rise(0)
    }
}

/// Entrada escalonada de cada bloque de un paso: sube 14 pt, se enfoca y aparece.
/// Con "Reducir movimiento", solo un fundido.
private struct Rise: ViewModifier {
    let order: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        let still = shown || AppMotion.reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .offset(y: still ? 0 : 14)
            .blur(radius: still ? 0 : 4)
            .onAppear {
                let animation: Animation = AppMotion.reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.5, dampingFraction: 0.86).delay(0.06 + Double(order) * 0.07)
                withAnimation(animation) { shown = true }
            }
    }
}

private extension View {
    func rise(_ order: Int) -> some View { modifier(Rise(order: order)) }
}

// MARK: - Bienvenida

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 22) {
            NotchDemo()
                .rise(0)
            PageHeader(
                title: "Bienvenido a Visor",
                subtitle: "Tu notch se convierte en un sitio útil: deja archivos, recupera lo que copiaste, mira tu agenda y tus correos, y recibe avisos sin que nada te tape la pantalla."
            )
            HStack(spacing: 10) {
                Hint(symbol: "cursorarrow.motionlines", text: "Pasa el ratón por el notch")
                Hint(symbol: "hand.draw", text: "Arrastra archivos encima")
                Hint(symbol: "command", text: "⌥Espacio para el lanzador")
            }
            .rise(2)
        }
        .padding(.horizontal, 32)
    }
}

private struct Hint: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.accent)
            Text(text).font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColors.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppColors.cardBorder, lineWidth: 1))
    }
}

/// Una barra de menus en miniatura cuyo notch se abre y se cierra solo.
private struct NotchDemo: View {
    /// Lo que enseña el panel de muestra: las mismas pestañas e iconos que el de verdad.
    private enum Scene: Int, CaseIterable { case shelf, clipboard, calendar }

    @State private var open = false
    /// El contenido se va antes de que el notch se recoja, para que no se quede
    /// flotando mientras encoge.
    @State private var items = false
    @State private var scene = Scene.shelf

    private var shape: NotchShape { NotchShape(topRadius: open ? 8 : 4, bottomRadius: open ? 18 : 6) }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.52), Color(red: 0.33, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(.white.opacity(0.18)).frame(height: 16)
            shape
                .fill(.black)
                .frame(width: open ? 316 : 64, height: open ? 124 : 16)
                .overlay(alignment: .top) {
                    if items {
                        VStack(spacing: 10) {
                            tabs
                            content
                                .frame(height: 58)
                                .id(scene)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 6)).animation(AppMotion.snappy),
                                    removal: .opacity.animation(.easeOut(duration: 0.1))
                                ))
                        }
                        .padding(.top, 24)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity).animation(AppMotion.snappy),
                            removal: .opacity.animation(.easeOut(duration: 0.12))
                        ))
                    }
                }
                // Nada se sale de la forma mientras crece o encoge.
                .clipShape(shape)
            Image(systemName: "cursorarrow")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .offset(x: cursorX, y: open ? 36 : 56)
                .animation(AppMotion.snappy, value: scene)
        }
        .frame(width: 380, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task {
            guard !AppMotion.reduceMotion else { open = true; items = true; return }
            while !Task.isCancelled {
                scene = .shelf
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(AppMotion.open) { open = true }
                // El contenido entra cuando la forma ya casi ha crecido.
                try? await Task.sleep(for: .seconds(0.18))
                items = true
                for next in Scene.allCases.dropFirst() {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(AppMotion.snappy) { scene = next }
                }
                try? await Task.sleep(for: .seconds(1.8))
                items = false
                try? await Task.sleep(for: .seconds(0.14))
                withAnimation(AppMotion.close) { open = false }
            }
        }
    }

    /// El cursor va a la pestaña que se abre.
    private var cursorX: CGFloat {
        guard open else { return 60 }
        return [-54, -28, 24][scene.rawValue]
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                tab("tray.full.fill", selected: scene == .shelf)
                tab("list.clipboard.fill", selected: scene == .clipboard)
                tab("camera.viewfinder", logo: AgentIcons.screenshot)
                tab("calendar", logo: AgentIcons.calendar, selected: scene == .calendar)
                tab("envelope", logo: AgentIcons.mail(.mail))
            }
            .padding(2)
            .background(Capsule().fill(.white.opacity(0.1)))
            Group {
                if let claude = AgentIcons.claude {
                    Image(nsImage: claude).resizable().frame(width: 14, height: 14)
                } else {
                    Image(systemName: "brain").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                }
            }
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(0.1)))
        }
    }

    private func tab(_ symbol: String, logo: NSImage? = nil, selected: Bool = false) -> some View {
        Group {
            if let logo {
                Image(nsImage: logo).resizable().frame(width: 13, height: 13)
            } else {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 24, height: 18)
        .background { if selected { Capsule().fill(AppColors.accent) } }
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case .shelf:
            HStack(spacing: 10) {
                ForEach(Array(["pdf", "png", "key", "zip"].enumerated()), id: \.offset) { index, ext in
                    VStack(spacing: 3) {
                        Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data))
                            .resizable()
                            .frame(width: 36, height: 36)
                        Text(verbatim: ["Q3.pdf", "logo.png", "Pitch.key", "assets.zip"][index])
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .transition(.scale(scale: 0.7).combined(with: .opacity).animation(AppMotion.stagger(index)))
                }
            }
        case .clipboard:
            HStack(spacing: 6) {
                clip(symbol: "link", text: "github.com/visor")
                clip(symbol: "terminal", text: "git push")
                clip(symbol: "paintpalette", text: "#4C7DFF")
            }
        case .calendar:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(.red).frame(width: 3, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reunión de equipo").font(.system(size: 11, weight: .semibold))
                    Text(verbatim: "10:00 · 30 min").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 10)
                Label("Unirse", systemImage: "video.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(AppColors.accent))
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
            .padding(.horizontal, 16)
        }
    }

    private func clip(symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(AppColors.accent)
            Text(verbatim: text).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 76, height: 46, alignment: .topLeading)
        .padding(.horizontal, 8).padding(.top, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
    }
}

// MARK: - Calendario y correo

private struct AccountsPage: View {
    let calendar: CalendarService
    let mail: MailService
    @AppStorage(SettingsKey.mailEnabled) private var mailEnabled = true
    @AppStorage(SettingsKey.mailSource) private var mailSource = MailService.Source.mail.rawValue

    var body: some View {
        VStack(spacing: 18) {
            PageHeader(
                title: "Calendario y correo",
                subtitle: "Tus reuniones, recordatorios y correos sin leer, a un vistazo desde el notch."
            )

            VStack(spacing: 10) {
                PermissionRow(
                    title: "Calendario",
                    detail: "Eventos y cuenta atrás de reuniones con botón para unirte.",
                    granted: calendar.access == .granted,
                    actionTitle: calendar.access == .denied ? "Abrir Ajustes" : "Permitir",
                    action: { calendar.access == .denied ? calendar.openPrivacySettings() : calendar.requestAccess() }
                ) { AppBadge(image: AgentIcons.calendar, symbol: "calendar", color: .red) }

                PermissionRow(
                    title: "Recordatorios",
                    detail: "Los pendientes de hoy, con su casilla para completarlos.",
                    granted: calendar.remindersAccess == .granted,
                    actionTitle: calendar.remindersAccess == .denied ? "Abrir Ajustes" : "Permitir",
                    action: {
                        if calendar.remindersAccess == .denied {
                            SystemSettingsLink.open("com.apple.preference.security?Privacy_Reminders")
                        } else {
                            calendar.requestRemindersAccess()
                        }
                    }
                ) { AppBadge(image: AgentIcons.icon("com.apple.reminders"), symbol: "checklist", color: .orange) }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppColors.textSecondary)
                    Text("¿Outlook, Google o Exchange? Añade la cuenta en Cuentas de Internet y sus calendarios aparecen en Visor.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Cuentas de Internet", action: SystemSettingsLink.internetAccounts)
                        .controlSize(.small)
                        .fixedSize()
                }
                .padding(.horizontal, 4)
            }
            .rise(1)

            VStack(alignment: .leading, spacing: 10) {
                Text("Correo sin leer").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                HStack(spacing: 10) {
                    MailChoice(title: "Mail de Apple", detail: "Cualquier cuenta de Cuentas de Internet",
                               image: AgentIcons.icon(MailService.Source.mail.bundleID), symbol: "envelope.fill", selected: mailEnabled && mailSource == MailService.Source.mail.rawValue) {
                        select(.mail)
                    }
                    MailChoice(title: "Outlook", detail: "La versión clásica, por AppleScript",
                               image: AgentIcons.icon(MailService.Source.outlook.bundleID), symbol: "envelope.fill", selected: mailEnabled && mailSource == MailService.Source.outlook.rawValue) {
                        select(.outlook)
                    }
                    MailChoice(title: "Sin correo", detail: "No mirar el correo",
                               image: nil, symbol: "envelope.badge.shield.half.filled", selected: !mailEnabled) {
                        mailEnabled = false
                    }
                }
                .frame(height: 112)
                if mailEnabled {
                    HStack(spacing: 8) {
                        Text(mailStatus).font(.system(size: 11))
                            .foregroundStyle(mail.state == .ok ? AppColors.success : AppColors.textSecondary)
                        Spacer()
                        if mail.state != .ok {
                            Button(mail.state == .denied ? "Abrir Ajustes" : "Conectar") {
                                mail.state == .denied ? mail.openPrivacySettings() : mail.launchSource()
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .rise(2)
        }
        .padding(.horizontal, 40)
    }

    private func select(_ source: MailService.Source) {
        mailEnabled = true
        mailSource = source.rawValue
        mail.refresh()
    }

    private var mailStatus: LocalizedStringKey {
        switch mail.state {
        case .ok: return "Conectado"
        case .denied: return "Falta el permiso de Automatización"
        case .unsupported: return "Esta versión no deja leer el correo (el Outlook nuevo no tiene AppleScript)"
        case .notRunning, .idle: return "Al conectar, macOS pedirá permiso para leer el correo"
        }
    }
}

private struct MailChoice: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let image: NSImage?
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AppBadge(image: image, symbol: symbol, color: image == nil && symbol == "envelope.fill" ? Color(red: 0.0, green: 0.45, blue: 0.85) : .gray)
                    .frame(width: 30, height: 30)
                Text(title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(detail).font(.system(size: 10))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? AppColors.accentWell : AppColors.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? AppColors.accentBorder : AppColors.cardBorder, lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(AppMotion.snappy, value: selected)
    }
}

// MARK: - Capturas y agentes

/// Lo que en un Mac nuevo no funciona solo: la carpeta de capturas, la miniatura de
/// macOS que las retrasa y el consumo de Claude (claude-hud).
private struct ExtrasPage: View {
    let screenshots: ScreenshotLibrary
    @State private var instant = ScreenshotLibrary.instantCaptures
    @State private var usage = ClaudeUsageSetup.state()

    var body: some View {
        VStack(spacing: 18) {
            PageHeader(
                title: "Capturas y agentes de IA",
                subtitle: "Dos ajustes de un clic para que las capturas y el consumo de Claude aparezcan solos."
            )

            VStack(spacing: 10) {
                PermissionRow(
                    title: "Carpeta de capturas",
                    detail: "Visor muestra las capturas que macOS guarda en \(ScreenshotLibrary.systemFolder.lastPathComponent).",
                    granted: screenshots.usesSystemFolder,
                    actionTitle: "Usar esa carpeta",
                    action: screenshots.useSystemFolder
                ) { AppBadge(image: AgentIcons.screenshot, symbol: "camera.viewfinder", color: .gray) }

                PermissionRow(
                    title: "Capturas al instante",
                    detail: "Quita la miniatura flotante de macOS, que retrasa unos 5 segundos cada captura.",
                    granted: instant,
                    actionTitle: "Activar",
                    action: {
                        ScreenshotLibrary.setInstantCaptures(true)
                        instant = ScreenshotLibrary.instantCaptures
                    }
                ) { AppBadge(symbol: "bolt.fill", color: .yellow) }

                if usage != .noClaude {
                    PermissionRow(
                        title: "Consumo de Claude",
                        detail: usageDetail,
                        granted: usage == .connected,
                        actionTitle: usage == .noPlugin ? "Instalar claude-hud" : "Conectar",
                        action: {
                            if usage == .noPlugin {
                                NSWorkspace.shared.open(ClaudeUsageSetup.pluginURL)
                            } else {
                                try? ClaudeUsageSetup.connect()
                                usage = ClaudeUsageSetup.state()
                            }
                        }
                    ) { AppBadge(image: AgentIcons.claude, symbol: "gauge.with.dots.needle.67percent", color: .orange) }
                }
            }
            .rise(1)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(AppColors.warning)
                Text("Las sesiones de Claude Code y Codex se ven solas en la pestaña de agentes. El consumo lo escribe la barra de estado claude-hud cada vez que usas Claude Code.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            .rise(2)
        }
        .padding(.horizontal, 40)
        // Al volver de instalar claude-hud en el navegador.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            usage = ClaudeUsageSetup.state()
            instant = ScreenshotLibrary.instantCaptures
        }
    }

    private var usageDetail: LocalizedStringKey {
        switch usage {
        case .connected: return "Conectado: el % de 5 h y de la semana aparece al usar Claude Code."
        case .needsConnection: return "claude-hud está instalado: falta que guarde el consumo para Visor."
        case .noPlugin, .noClaude: return "Instala en Claude Code la barra de estado claude-hud y vuelve aquí para conectarla."
        }
    }
}

// MARK: - Permisos avanzados

private struct PermissionsPage: View {
    let permissions: PermissionState

    var body: some View {
        VStack(spacing: 18) {
            PageHeader(
                title: "Permisos avanzados",
                subtitle: "Son opcionales: cada uno desbloquea algo concreto. Visor no envía nada fuera de tu Mac."
            )

            VStack(spacing: 10) {
                PermissionRow(
                    title: "Accesibilidad",
                    detail: "Pegar desde el historial, ajustar ventanas con ⌃⌥, acciones del texto seleccionado, controles de reunión y que los avisos no tapen los iconos de la barra.",
                    granted: permissions.accessibility,
                    actionTitle: "Permitir",
                    action: { AXAccess.request(); AXAccess.openSettings() }
                ) { AppBadge(symbol: "accessibility", color: .blue) }

                if PermissionState.fullDiskAccessNeeded {
                    PermissionRow(
                        title: "Acceso total al disco",
                        detail: "Mostrar en el notch las notificaciones que entrega macOS. Solo se leen las nuevas y no se guardan.",
                        granted: permissions.fullDiskAccess,
                        actionTitle: "Abrir Ajustes",
                        action: { SystemSettingsLink.open("com.apple.preference.security?Privacy_AllFiles") }
                    ) { AppBadge(symbol: "internaldrive.fill", color: .gray) }
                }
            }
            .rise(1)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(AppColors.warning)
                Group {
                    if PermissionState.fullDiskAccessNeeded {
                        Text("En Ajustes del Sistema, activa Visor en la lista (o añádelo con +). Al volver aquí, el estado se actualiza solo; el acceso al disco puede pedir reabrir Visor.")
                    } else {
                        Text("En Ajustes del Sistema, activa Visor en la lista (o añádelo con +). Al volver aquí, el estado se actualiza solo.")
                    }
                }
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            .rise(2)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Atajos y avisos

private struct ShortcutsPage: View {
    @AppStorage(SettingsKey.launcher) private var launcher = true
    @AppStorage(SettingsKey.hotKeyEnabled) private var clipboardKey = true
    @AppStorage(SettingsKey.actionRing) private var ring = true
    @AppStorage(SettingsKey.windowSnap) private var snap = true
    @AppStorage(SettingsKey.selectionActions) private var selection = true
    @AppStorage(SettingsKey.basketOnShake) private var basket = true

    var body: some View {
        VStack(spacing: 18) {
            PageHeader(
                title: "Atajos y avisos",
                subtitle: "Activa lo que vayas a usar. Todo se puede cambiar después en Ajustes."
            )

            VStack(spacing: 0) {
                ShortcutToggle(keys: "⌥ Espacio", title: "Lanzador: apps, archivos y cuentas", isOn: $launcher)
                Divider().padding(.leading, 12)
                ShortcutToggle(keys: "⌃⌘ V", title: "Historial del portapapeles", isOn: $clipboardKey)
                Divider().padding(.leading, 12)
                ShortcutToggle(keys: "⌃⌥ Espacio", title: "Anillo de acciones junto al cursor", isOn: $ring)
                Divider().padding(.leading, 12)
                ShortcutToggle(keys: "⌃⌥ ← →", title: "Ajustar ventanas", isOn: $snap)
                Divider().padding(.leading, 12)
                ShortcutToggle(keys: "Seleccionar", title: "Acciones sobre el texto seleccionado", isOn: $selection)
                Divider().padding(.leading, 12)
                ShortcutToggle(keys: "Agitar", title: "Cesta al agitar el ratón arrastrando", isOn: $basket)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColors.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppColors.cardBorder, lineWidth: 1))
            .rise(1)

            NoticeGrid()
                .rise(2)
        }
        .padding(.horizontal, 40)
    }
}

private struct ShortcutToggle: View {
    let keys: LocalizedStringKey
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 7)
                .frame(minWidth: 82, minHeight: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(AppColors.controlTrack))
            Text(title).font(.system(size: 12))
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

/// Avisos del notch como fichas que se encienden y apagan.
struct NoticeGrid: View {
    @AppStorage(SettingsKey.hudVolume) private var volume = true
    @AppStorage(SettingsKey.hudBattery) private var battery = true
    @AppStorage(SettingsKey.hudDevices) private var devices = true
    @AppStorage(SettingsKey.hudDownloads) private var downloads = true
    @AppStorage(SettingsKey.hudCapsLock) private var capsLock = false
    @AppStorage(SettingsKey.hudNetwork) private var network = true
    @AppStorage(SettingsKey.hudMediaInUse) private var media = true
    @AppStorage(SettingsKey.hudMeetings) private var meetings = true
    @AppStorage(SettingsKey.hudMail) private var mailNotice = true
    @AppStorage(SettingsKey.notifications) private var notifications = true
    @AppStorage(SettingsKey.hudAgents) private var agents = true
    @AppStorage(SettingsKey.hudUsage) private var usage = true
    @AppStorage(SettingsKey.hudFocus) private var focusMode = true

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            Chip(symbol: "speaker.wave.2.fill", title: "Volumen", isOn: $volume)
            Chip(symbol: "battery.75percent", title: "Batería", isOn: $battery)
            Chip(symbol: "airpods", title: "Bluetooth", isOn: $devices)
            Chip(symbol: "arrow.down.circle.fill", title: "Descargas", isOn: $downloads)
            Chip(symbol: "capslock.fill", title: "Bloq Mayús", isOn: $capsLock)
            Chip(symbol: "wifi", title: "Conexión", isOn: $network)
            Chip(symbol: "mic.fill", title: "Llamadas", isOn: $media)
            Chip(symbol: "video.fill", title: "Reuniones", isOn: $meetings)
            Chip(symbol: "envelope.fill", title: "Correo", isOn: $mailNotice)
            Chip(symbol: "bell.fill", title: "Notificaciones", isOn: $notifications)
            Chip(symbol: "sparkles", title: "Agentes de IA", isOn: $agents)
            Chip(symbol: "gauge.with.dots.needle.67percent", title: "Consumo de Claude", isOn: $usage)
            Chip(symbol: "moon.fill", title: "Concentración", isOn: $focusMode)
        }
    }
}

private struct Chip: View {
    let symbol: String
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                    .frame(height: 18)
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(isOn ? AppColors.accent : AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isOn ? AppColors.accentWell : AppColors.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isOn ? AppColors.accentBorder : AppColors.cardBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(AppMotion.snappy, value: isOn)
        .accessibilityValue(Text(isOn ? "Activado" : "Desactivado"))
    }
}

// MARK: - Listo

private struct DonePage: View {
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 96, height: 96)
                .rise(0)
            PageHeader(
                title: "Todo listo",
                subtitle: "Pasa el ratón por el notch para abrir Visor. Los ajustes están en el menú ⋯ del panel."
            )
            Toggle("Abrir Visor al iniciar sesión", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, on in launchAtLogin = LoginItem.set(on) }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColors.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppColors.cardBorder, lineWidth: 1))
                .rise(2)
        }
        .padding(.horizontal, 40)
    }
}
