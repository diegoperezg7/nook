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
