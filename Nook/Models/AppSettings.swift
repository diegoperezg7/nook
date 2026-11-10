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
    /// Remitentes que avisan de correo nuevo, separados por comas (vacio = todos).
    static let mailImportant = "mailImportant"
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
    /// Aviso cuando un agente termina o te espera.
    static let hudAgents = "hudAgents"
    /// Aviso cuando el consumo de Claude cruza el 80 % o el 95 %.
    static let hudUsage = "hudUsage"
    /// Aviso al activar o quitar No molestar / Concentracion.
    static let hudFocus = "hudFocus"
    /// Introduccion del primer arranque ya vista.
    static let onboardingDone = "onboardingDone"
    /// Lanzador con ⌥Espacio.
    static let launcher = "launcher"
    /// Ciudad del tiempo (vacia = sin tiempo) y sus coordenadas.
    static let weatherCity = "weatherCity"
    static let weatherLatitude = "weatherLatitude"
    static let weatherLongitude = "weatherLongitude"

    /// 0 = sin limite: el historial solo se borra cuando lo pide el usuario.
    static let unlimitedHistory = 0
    static let historyLimitOptions = [unlimitedHistory, 100, 250, 500, 1000]

    /// Dias que se queda algo en la bandeja antes de quitarse solo (0 = nunca).
    static let shelfExpiryDays = "shelfExpiryDays"
    static let shelfExpiryOptions = [0, 1, 7, 30]

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            captureClipboard: true,
            historyLimit: unlimitedHistory,
            shelfExpiryDays: 0,
            hotKeyEnabled: true,
            showWithoutNotch: true,
            hideFromCaptures: true,
            openDelay: 0.1,
            closeDelay: 0.18,
            hudVolume: true,
            hudDevices: true,
            hudBattery: true,
            hudDownloads: true,
            // macOS ya muestra Bloq Mayus junto al cursor: el aviso propio va apagado.
            // El de micro y camara solo sale en llamadas.
            hudCapsLock: false,
            hudNetwork: true,
            hudMediaInUse: true,
            hudMeetings: true,
            hudMail: true,
            hudAgents: true,
            hudUsage: true,
            hudFocus: true,
            mailEnabled: true,
            mailSource: "mail",
            basketOnShake: true,
            actionRing: true,
            pasteOnSelect: true,
            windowSnap: true,
            selectionActions: true,
            notifications: true,
            launcher: true,
        ])
    }
}
