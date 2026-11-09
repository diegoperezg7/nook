import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.captureClipboard) private var captureClipboard = true
    @AppStorage(SettingsKey.historyLimit) private var historyLimit = 100
    @AppStorage(SettingsKey.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(SettingsKey.showWithoutNotch) private var showWithoutNotch = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var access = ClipboardAccess.current

    var body: some View {
        Form {
            Section("Portapapeles") {
                Toggle("Guardar el historial del portapapeles", isOn: $captureClipboard)
                Picker("Elementos en el historial", selection: $historyLimit) {
                    ForEach(SettingsKey.historyLimitOptions, id: \.self) { Text(verbatim: "\($0)").tag($0) }
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

            Section("General") {
                Toggle("Mostrar en pantallas sin notch", isOn: $showWithoutNotch)
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
