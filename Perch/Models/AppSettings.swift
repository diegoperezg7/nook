import Foundation

/// Claves de UserDefaults. Los valores por defecto se registran al arrancar.
enum SettingsKey {
    static let captureClipboard = "captureClipboard"
    static let historyLimit = "historyLimit"
    static let hotKeyEnabled = "hotKeyEnabled"
    static let showWithoutNotch = "showWithoutNotch"

    static let historyLimitOptions = [25, 50, 100, 200, 500]

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            captureClipboard: true,
            historyLimit: 100,
            hotKeyEnabled: true,
            showWithoutNotch: true,
        ])
    }
}
