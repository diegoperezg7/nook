import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.captureClipboard) private var captureClipboard = true
    @AppStorage(SettingsKey.historyLimit) private var historyLimit = SettingsKey.unlimitedHistory
    @AppStorage(SettingsKey.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(SettingsKey.showWithoutNotch) private var showWithoutNotch = true
    @AppStorage(SettingsKey.hideFromCaptures) private var hideFromCaptures = true
    @AppStorage(SettingsKey.openDelay) private var openDelay = 0.1
    @AppStorage(SettingsKey.closeDelay) private var closeDelay = 0.18
    @AppStorage(SettingsKey.hudVolume) private var hudVolume = true
    @AppStorage(SettingsKey.hudDevices) private var hudDevices = true
    @AppStorage(SettingsKey.hudBattery) private var hudBattery = true
    @AppStorage(SettingsKey.hudDownloads) private var hudDownloads = true
    @AppStorage(SettingsKey.hudCapsLock) private var hudCapsLock = true
    @AppStorage(SettingsKey.hudNetwork) private var hudNetwork = true
    @AppStorage(SettingsKey.hudMediaInUse) private var hudMediaInUse = true
    @AppStorage(SettingsKey.hudMeetings) private var hudMeetings = true
    @AppStorage(SettingsKey.hudMail) private var hudMail = true
    @AppStorage(SettingsKey.mailEnabled) private var mailEnabled = true
    @AppStorage(SettingsKey.mailSource) private var mailSource = MailService.Source.mail.rawValue
    @AppStorage(SettingsKey.basketOnShake) private var basketOnShake = true
    @AppStorage(SettingsKey.actionRing) private var actionRing = true
    @AppStorage(SettingsKey.weatherCity) private var weatherCity = ""
    @State private var cityQuery = ""
    @State private var citySearch: CitySearch = .idle
    private enum CitySearch: Equatable { case idle, searching, notFound }
    let calendar: CalendarService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var access = ClipboardAccess.current

    var body: some View {
        Form {
            Section("Portapapeles") {
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
                Toggle("Abrir el historial con ⌃⌘V", isOn: $hotKeyEnabled)
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
                Text("No se guarda lo que los gestores de contraseñas marcan como privado. El historial se queda en este Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Avisos en el notch") {
                Toggle("Volumen", isOn: $hudVolume)
                Toggle("Auriculares y altavoces Bluetooth", isOn: $hudDevices)
                Toggle("Batería y cargador", isOn: $hudBattery)
                Toggle("Descargas", isOn: $hudDownloads)
                Toggle("Bloq Mayús", isOn: $hudCapsLock)
                Toggle("Conexión a internet y VPN", isOn: $hudNetwork)
                Toggle("Micrófono o cámara en uso", isOn: $hudMediaInUse)
                Toggle("Cuenta atrás de reuniones", isOn: $hudMeetings)
                Toggle("Correo nuevo", isOn: $hudMail)
            }

            Section("Bandeja de entrada") {
                Toggle("Ver los correos sin leer en el notch", isOn: $mailEnabled)
                Picker("Leer de", selection: $mailSource) {
                    Text("Mail").tag(MailService.Source.mail.rawValue)
                    Text("Outlook (clásico)").tag(MailService.Source.outlook.rawValue)
                }
                .disabled(!mailEnabled)
                Text("Solo remitente, asunto y hora, y solo si la app está abierta. Nada sale de este Mac. El Outlook nuevo no deja leer el correo: usa Mail con la cuenta añadida en Cuentas de Internet o el Outlook clásico.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Calendarios") {
                if calendar.accounts.isEmpty {
                    Text("Da acceso al calendario desde la pestaña Calendario del notch.")
                        .foregroundStyle(.secondary)
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
                Text("Para ver Outlook, añade la cuenta de Microsoft 365 en Ajustes del Sistema > Cuentas de Internet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Herramientas") {
                Toggle("Anillo de acciones con ⌃⌥Espacio", isOn: $actionRing)
                LabeledContent("Tiempo") {
                    HStack(spacing: 8) {
                        TextField("Ciudad", text: $cityQuery, prompt: Text(weatherCity.isEmpty ? String(localized: "Ciudad") : weatherCity))
                            .frame(width: 160)
                            .onSubmit(searchCity)
                        Button(citySearch == .searching ? "Buscando…" : "Buscar", action: searchCity)
                            .disabled(cityQuery.trimmingCharacters(in: .whitespaces).isEmpty || citySearch == .searching)
                        if !weatherCity.isEmpty {
                            Button("Quitar") { saveCity(nil) }
                        }
                    }
                }
                Text(citySearch == .notFound
                     ? String(localized: "No encuentro esa ciudad.")
                     : String(localized: "El tiempo sale en el centro del anillo. Se pide a Open-Meteo solo con las coordenadas de la ciudad elegida."))
                    .font(.footnote)
                    .foregroundStyle(citySearch == .notFound ? AppColors.danger : .secondary)
            }

            Section("Notch") {
                Picker("Abrir al pasar el ratón", selection: $openDelay) {
                    ForEach(SettingsKey.openDelayOptions, id: \.self) { Text(Self.delayLabel($0)).tag($0) }
                }
                Picker("Cerrar al salir", selection: $closeDelay) {
                    ForEach(SettingsKey.closeDelayOptions, id: \.self) { Text(Self.delayLabel($0)).tag($0) }
                }
            }

            Section("General") {
                Toggle("Mostrar en pantallas sin notch", isOn: $showWithoutNotch)
                Toggle("Cesta al agitar el ratón arrastrando archivos", isOn: $basketOnShake)
                Toggle("Ocultar en capturas de pantalla", isOn: $hideFromCaptures)
                Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .tint(AppColors.accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access = ClipboardAccess.current
            launchAtLogin = SMAppService.mainApp.status == .enabled
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

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
