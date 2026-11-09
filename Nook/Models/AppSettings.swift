import Foundation

/// Claves de UserDefaults. Los valores por defecto se registran al arrancar.
enum SettingsKey {
    static let captureClipboard = "captureClipboard"
    static let historyLimit = "historyLimit"
    static let hotKeyEnabled = "hotKeyEnabled"
    static let showWithoutNotch = "showWithoutNotch"
    /// El panel no sale en capturas ni grabaciones de pantalla.
    static let hideFromCaptures = "hideFromCaptures"
    /// Avisos que salen del notch cerrado.
    static let hudVolume = "hudVolume"
    static let hudDevices = "hudDevices"
    static let hudBattery = "hudBattery"
    static let hudDownloads = "hudDownloads"

    /// 0 = sin limite: el historial solo se borra cuando lo pide el usuario.
    static let unlimitedHistory = 0
    static let historyLimitOptions = [unlimitedHistory, 100, 250, 500, 1000]

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            captureClipboard: true,
            historyLimit: unlimitedHistory,
            hotKeyEnabled: true,
            showWithoutNotch: true,
            hideFromCaptures: true,
            hudVolume: true,
            hudDevices: true,
            hudBattery: true,
            hudDownloads: true,
        ])
    }
}
