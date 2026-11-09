import Foundation

/// Claves de UserDefaults. Los valores por defecto se registran al arrancar.
enum SettingsKey {
    static let captureClipboard = "captureClipboard"
    static let historyLimit = "historyLimit"
    static let hotKeyEnabled = "hotKeyEnabled"
    static let showWithoutNotch = "showWithoutNotch"
    /// El panel no sale en capturas ni grabaciones de pantalla.
    static let hideFromCaptures = "hideFromCaptures"
    /// Segundos con el raton sobre el notch antes de abrirlo, y fuera antes de cerrarlo.
    static let openDelay = "openDelay"
    static let closeDelay = "closeDelay"
    static let openDelayOptions: [Double] = [0.1, 0.3, 0.5, 1.0]
    static let closeDelayOptions: [Double] = [0, 0.18, 0.5, 1.0]
    /// Avisos que salen del notch cerrado.
    static let hudVolume = "hudVolume"
    static let hudDevices = "hudDevices"
    static let hudBattery = "hudBattery"
    static let hudDownloads = "hudDownloads"
    static let hudCapsLock = "hudCapsLock"
    static let hudNetwork = "hudNetwork"
    static let hudMediaInUse = "hudMediaInUse"
    static let hudMeetings = "hudMeetings"
    static let hudMail = "hudMail"
    /// Bandeja de entrada: activa y de que app se lee (mail / outlook).
    static let mailEnabled = "mailEnabled"
    static let mailSource = "mailSource"
    /// Calendarios que el usuario ha quitado (identificadores de EventKit).
    static let hiddenCalendars = "hiddenCalendars"
    /// Cesta flotante al agitar el raton arrastrando archivos.
    static let basketOnShake = "basketOnShake"
    /// Anillo de acciones con ⌃⌥Espacio.
    static let actionRing = "actionRing"
    /// Al elegir algo del historial (⌃⌘V) se pega en la app anterior.
    static let pasteOnSelect = "pasteOnSelect"
    static let windowSnap = "windowSnap"
    static let selectionActions = "selectionActions"
    static let notifications = "notifications"
    /// Ciudad del tiempo (vacia = sin tiempo) y sus coordenadas.
    static let weatherCity = "weatherCity"
    static let weatherLatitude = "weatherLatitude"
    static let weatherLongitude = "weatherLongitude"

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
            openDelay: 0.1,
            closeDelay: 0.18,
            hudVolume: true,
            hudDevices: true,
            hudBattery: true,
            hudDownloads: true,
            hudCapsLock: true,
            hudNetwork: true,
            hudMediaInUse: true,
            hudMeetings: true,
            hudMail: true,
            mailEnabled: true,
            mailSource: "mail",
            basketOnShake: true,
            actionRing: true,
            pasteOnSelect: true,
            windowSnap: true,
            selectionActions: true,
            notifications: true,
        ])
    }
}
