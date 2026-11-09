import AppKit
import ServiceManagement
import SwiftUI

/// Ajustes por pestañas, como en las apps de Apple: cada una cabe sin desplazarse
/// mucho y lo de cada tema esta junto.
struct SettingsView: View {
    let calendar: CalendarService
    let mail: MailService
    let permissions: PermissionState
    let showOnboarding: () -> Void

    @AppStorage(SettingsKey.captureClipboard) private var captureClipboard = true
    @AppStorage(SettingsKey.historyLimit) private var historyLimit = SettingsKey.unlimitedHistory
    @AppStorage(SettingsKey.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(SettingsKey.showWithoutNotch) private var showWithoutNotch = true
    @AppStorage(SettingsKey.hideFromCaptures) private var hideFromCaptures = true
    @AppStorage(SettingsKey.openDelay) private var openDelay = 0.1
    @AppStorage(SettingsKey.closeDelay) private var closeDelay = 0.18
    @AppStorage(SettingsKey.mailEnabled) private var mailEnabled = true
    @AppStorage(SettingsKey.mailSource) private var mailSource = MailService.Source.mail.rawValue
    @AppStorage(SettingsKey.basketOnShake) private var basketOnShake = true
    @AppStorage(SettingsKey.actionRing) private var actionRing = true
    @AppStorage(SettingsKey.pasteOnSelect) private var pasteOnSelect = true
    @AppStorage(SettingsKey.windowSnap) private var windowSnap = true
    @AppStorage(SettingsKey.selectionActions) private var selectionActions = true
    @AppStorage(SettingsKey.launcher) private var launcherOn = true
    @AppStorage(SettingsKey.weatherCity) private var weatherCity = ""
    @State private var cityQuery = ""
    @State private var citySearch: CitySearch = .idle
    private enum CitySearch: Equatable { case idle, searching, notFound }
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var access = ClipboardAccess.current
    @State private var tab = Self.initialTab

    var body: some View {
        TabView(selection: $tab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            notices.tabItem { Label("Avisos", systemImage: "bell.badge") }.tag(1)
            clipboard.tabItem { Label("Portapapeles", systemImage: "doc.on.clipboard") }.tag(2)
            accounts.tabItem { Label("Calendario y correo", systemImage: "calendar") }.tag(3)
            shortcuts.tabItem { Label("Atajos", systemImage: "command") }.tag(4)
            privacy.tabItem { Label("Permisos", systemImage: "lock.shield") }.tag(5)
        }
        .frame(width: 560, height: 520)
        .tint(AppColors.accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access = ClipboardAccess.current
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private static var initialTab: Int {
        #if DEBUG
        // `-NookSettingsTab 3` abre esa pestaña (para revisarla).
        return UserDefaults.standard.integer(forKey: "NookSettingsTab")
        #else
        return 0
        #endif
    }

    // MARK: Pestañas

    private var general: some View {
        Form {
            Section {
                Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in launchAtLogin = LoginItem.set(on) }
                Toggle("Mostrar en pantallas sin notch", isOn: $showWithoutNotch)
                Toggle("Ocultar en capturas de pantalla", isOn: $hideFromCaptures)
            }
            Section("Panel") {
                Picker("Abrir al pasar el ratón", selection: $openDelay) {
                    ForEach(SettingsKey.openDelayOptions, id: \.self) { Text(Self.delayLabel($0)).tag($0) }
                }
                Picker("Cerrar al salir", selection: $closeDelay) {
                    ForEach(SettingsKey.closeDelayOptions, id: \.self) { Text(Self.delayLabel($0)).tag($0) }
                }
                Toggle("Cesta al agitar el ratón arrastrando archivos", isOn: $basketOnShake)
            }
            Section {
                LabeledContent("Introducción") {
                    Button("Ver de nuevo…", action: showOnboarding)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var notices: some View {
        Form {
            Section {
                NoticeGrid()
                    .padding(.vertical, 4)
            } header: {
                Text("Avisos del notch cerrado")
            } footer: {
                Text("Cada aviso se ensancha solo hasta los menús y los iconos de la barra, sin taparlos (necesita Accesibilidad).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var clipboard: some View {
        Form {
            Section {
                Toggle("Guardar el historial del portapapeles", isOn: $captureClipboard)
                Picker("Elementos en el historial", selection: $historyLimit) {
                    ForEach(SettingsKey.historyLimitOptions, id: \.self) { limit in
                        if limit == SettingsKey.unlimitedHistory {
                            Text("Sin límite").tag(limit)
                        } else {
                            Text(verbatim: "\(limit)").tag(limit)
                        }
                    }
                }
                LabeledContent("Acceso al portapapeles") {
                    HStack(spacing: 8) {
                        Text(accessLabel).foregroundStyle(access == .allowed ? AppColors.success : AppColors.danger)
                        if access != .allowed {
                            Button("Abrir Ajustes del Sistema") {
                                NSWorkspace.shared.open(ClipboardAccess.settingsURL)
                            }
                        }
                    }
                }
            } footer: {
                Text("No se guarda lo que los gestores de contraseñas marcan como privado. El historial se queda en este Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("⌃⌘V") {
                Toggle("Abrir el historial con ⌃⌘V", isOn: $hotKeyEnabled)
                Toggle("Pegar al elegir (con ⌃⌘V)", isOn: $pasteOnSelect)
                    .onChange(of: pasteOnSelect) { _, on in if on, !permissions.accessibility { AXAccess.request() } }
            }
        }
        .formStyle(.grouped)
    }

    private var accounts: some View {
        Form {
            Section {
                Toggle("Ver los correos sin leer en el notch", isOn: $mailEnabled)
                Picker("Leer de", selection: $mailSource) {
                    Text("Mail de Apple").tag(MailService.Source.mail.rawValue)
                    Text("Outlook (clásico)").tag(MailService.Source.outlook.rawValue)
                }
                .disabled(!mailEnabled)
            } header: {
                Text("Correo")
            } footer: {
                Text("Solo remitente, asunto y hora, y solo si la app está abierta. El Outlook nuevo no deja leer el correo: usa Mail con la cuenta en Cuentas de Internet o el Outlook clásico.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if calendar.accounts.isEmpty {
                    LabeledContent("Sin acceso al calendario") {
                        Button("Permitir") { calendar.requestAccess() }
                    }
                }
                ForEach(calendar.accounts) { account in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: account.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(account.calendars) { info in
                            Toggle(isOn: Binding(
                                get: { calendar.isVisible(info.id) },
                                set: { calendar.setVisible(info.id, $0) }
                            )) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(nsColor: info.color)).frame(width: 9, height: 9)
                                    Text(verbatim: info.title)
                                }
                            }
                        }
                    }
                }
                LabeledContent("Outlook, Google o Exchange") {
                    Button("Cuentas de Internet…", action: SystemSettingsLink.internetAccounts)
                }
            } header: {
                Text("Calendarios")
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section {
                Toggle("Lanzador con ⌥Espacio", isOn: $launcherOn)
                Toggle("Anillo de acciones con ⌃⌥Espacio", isOn: $actionRing)
                Toggle("Acciones al seleccionar texto", isOn: $selectionActions)
                Toggle("Ajustar ventanas con ⌃⌥", isOn: $windowSnap)
            } footer: {
                Text("⌃⌥ + ← → ↑ ↓ mitades · U I J K cuartos · D F G tercios · E T dos tercios · ↩ maximizar · C centrar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Ciudad") {
                    HStack(spacing: 8) {
                        TextField("Ciudad", text: $cityQuery, prompt: Text(weatherCity.isEmpty ? String(localized: "Ciudad") : weatherCity))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            .onSubmit(searchCity)
                        Button(citySearch == .searching ? "Buscando…" : "Buscar", action: searchCity)
                            .disabled(cityQuery.trimmingCharacters(in: .whitespaces).isEmpty || citySearch == .searching)
                        if !weatherCity.isEmpty {
                            Button("Quitar") { saveCity(nil) }
                        }
                    }
                }
            } header: {
                Text("Tiempo en el anillo")
            } footer: {
                Text(citySearch == .notFound
                     ? String(localized: "No encuentro esa ciudad.")
                     : String(localized: "El tiempo sale en el centro del anillo. Se pide a Open-Meteo solo con las coordenadas de la ciudad elegida."))
                    .font(.footnote)
                    .foregroundStyle(citySearch == .notFound ? AppColors.danger : .secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var privacy: some View {
        ScrollView {
            VStack(spacing: 10) {
                PermissionRow(
                    title: "Calendario",
                    detail: "Eventos y controles de reunión.",
                    granted: calendar.access == .granted,
                    actionTitle: calendar.access == .denied ? "Abrir Ajustes" : "Permitir",
                    action: { calendar.access == .denied ? calendar.openPrivacySettings() : calendar.requestAccess() }
                ) { AppBadge(image: AgentIcons.calendar, symbol: "calendar", color: .red) }
                PermissionRow(
                    title: "Recordatorios",
                    detail: "Los pendientes de hoy en el calendario.",
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
                if mailEnabled {
                    PermissionRow(
                        title: "Correo",
                        detail: "Automatización de Mail u Outlook para ver los no leídos.",
                        granted: mail.state == .ok,
                        actionTitle: mail.state == .denied ? "Abrir Ajustes" : "Conectar",
                        action: { mail.state == .denied ? mail.openPrivacySettings() : mail.launchSource() }
                    ) { AppBadge(image: AgentIcons.mail(mail.source), symbol: "envelope.fill") }
                }
                PermissionRow(
                    title: "Accesibilidad",
                    detail: "Pegar, ajustar ventanas, texto seleccionado, reuniones y avisos que no tapan la barra.",
                    granted: permissions.accessibility,
                    actionTitle: "Permitir",
                    action: { AXAccess.request(); AXAccess.openSettings() }
                ) { AppBadge(symbol: "accessibility", color: .blue) }
                PermissionRow(
                    title: "Acceso total al disco",
                    detail: "Notificaciones del sistema en el notch. Solo las nuevas; nada se guarda.",
                    granted: permissions.fullDiskAccess,
                    actionTitle: "Abrir Ajustes",
                    action: { SystemSettingsLink.open("com.apple.preference.security?Privacy_AllFiles") }
                ) { AppBadge(symbol: "internaldrive.fill", color: .gray) }
            }
            .padding(20)
        }
    }

    private func searchCity() {
        let query = cityQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        citySearch = .searching
        Task {
            if let place = await Weather.search(query) {
                saveCity(place)
                cityQuery = ""
                citySearch = .idle
            } else {
                citySearch = .notFound
            }
        }
    }

    private func saveCity(_ place: Weather.Place?) {
        let defaults = UserDefaults.standard
        defaults.set(place?.name ?? "", forKey: SettingsKey.weatherCity)
        defaults.set(place?.latitude ?? 0, forKey: SettingsKey.weatherLatitude)
        defaults.set(place?.longitude ?? 0, forKey: SettingsKey.weatherLongitude)
    }

    private static func delayLabel(_ seconds: Double) -> String {
        seconds <= 0 ? String(localized: "Al instante")
            : seconds.formatted(.number.precision(.fractionLength(0...2))) + " s"
    }

    private var accessLabel: LocalizedStringKey {
        switch access {
        case .allowed: return "Permitido"
        case .needsPermission: return "Pendiente: elige «Permitir siempre»"
        case .denied: return "Denegado"
        }
    }
}
