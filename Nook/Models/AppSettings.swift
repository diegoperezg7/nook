import Foundation

/// Claves de UserDefaults. Los valores por defecto se registran al arrancar.
enum SettingsKey {
    static let captureClipboard = "captureClipboard"
    static let historyLimit = "historyLimit"
    static let hotKeyEnabled = "hotKeyEnabled"
    static let showWithoutNotch = "showWithoutNotch"

    /// 0 = sin limite: el historial solo se borra cuando lo pide el usuario.
    static let unlimitedHistory = 0
    static let historyLimitOptions = [unlimitedHistory, 100, 250, 500, 1000]

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            captureClipboard: true,
            historyLimit: unlimitedHistory,
            hotKeyEnabled: true,
            showWithoutNotch: true,
        ])
    }
}
