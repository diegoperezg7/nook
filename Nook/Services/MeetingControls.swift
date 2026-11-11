import AppKit
import ApplicationServices
import CoreAudio
import os

/// Controles de reunion para cualquier app de llamadas. Con el microfono en uso, la
/// app que graba es la llamada si es conocida (Teams, Zoom), si es un navegador en
/// una web de reuniones (Meet...) o si tiene boton de colgar (FaceTime, Discord...).
/// Cada accion se intenta por este orden:
/// 1. Pulsar el boton o el menu de la propia app por Accesibilidad, sin traerla delante.
/// 2. El atajo conocido de la app, trayendo antes su ventana delante por Accesibilidad
///    (desde macOS 14, `activate()` desde una app de fondo como Visor se ignora y el
///    atajo acababa en la app que estuviera delante).
/// 3. Solo el micro: silenciar la entrada de audio del sistema.
/// Todo necesita el permiso de Accesibilidad.
enum MeetingControls {
    typealias Shortcut = (key: CGKeyCode, flags: CGEventFlags)

    struct Target: Equatable {
        let bundleID: String
        let pid: pid_t
        let name: String
        let mic: Shortcut?
        let camera: Shortcut?
        let leave: Shortcut?
        /// Hay forma de apagar la camara: atajo conocido o boton encontrado.
        var hasCamera: Bool

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.pid == rhs.pid && lhs.name == rhs.name && lhs.hasCamera == rhs.hasCamera
        }
    }

    private static let log = Logger(subsystem: "com.diegoperez.visor", category: "meeting")
    private static let command: CGEventFlags = .maskCommand
    private static let commandShift: CGEventFlags = [.maskCommand, .maskShift]

    /// Atajos conocidos. Zoom: ⌘⇧A, ⌘⇧V, ⌘W. Teams: ⌘⇧M, ⌘⇧O, ⌘⇧H.
    private static let known: [String: (name: String, mic: Shortcut, camera: Shortcut, leave: Shortcut?)] = [
        "us.zoom.xos": ("Zoom", (0, commandShift), (9, commandShift), (13, command)),
        "com.microsoft.teams2": ("Teams", (46, commandShift), (31, commandShift), (4, commandShift)),
        "com.microsoft.teams": ("Teams", (46, commandShift), (31, commandShift), (4, commandShift)),
    ]

    static let browsers: Set<String> = [
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "com.brave.Browser", "org.mozilla.firefox",
    ]

    // MARK: - Deteccion

    /// La llamada en curso, si el microfono esta en uso.
    @MainActor
    static func current(micInUse: Bool) -> Target? {
        #if DEBUG
        // `-VisorDemoCall <bundle id>`: finge una llamada en esa app (capturas).
        if let demo = UserDefaults.standard.string(forKey: "VisorDemoCall"),
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: demo).first {
            let id = app.bundleIdentifier ?? demo
            return Target(bundleID: id, pid: app.processIdentifier, name: app.localizedName ?? id, mic: nil, camera: nil, leave: nil, hasCamera: true)
        }
        #endif
        guard micInUse else { return nil }
        let running = NSWorkspace.shared.runningApplications
        guard let users = micUsers() else {
            // Sin lista de procesos: la primera app conocida abierta.
            return running.first { known[$0.bundleIdentifier ?? ""] != nil }.flatMap(target(for:))
        }
        let candidates = users.compactMap { owner(of: $0, in: running) }
        // Las conocidas primero; luego cualquier otra app con ventanas.
        let ordered = candidates.filter { known[$0.bundleIdentifier ?? ""] != nil } + candidates
        return ordered.lazy.compactMap(target(for:)).first
    }

    /// En el navegador solo es llamada si una ventana es de un servicio de reuniones:
    /// dictar en una web tambien graba, y colgar podria pulsar cualquier "Leave".
    static let meetingSites = ["Meet", "Teams", "Zoom", "Webex", "Jitsi", "Whereby", "Discord", "Slack", "Huddle", "FaceTime"]

    static func meetingSite(in titles: [String]) -> String? {
        meetingSites.first { site in titles.contains { $0.localizedCaseInsensitiveContains(site) } }
    }

    /// App con ventanas a la que pertenece un proceso que graba: el propio app, su
    /// helper (`com.google.Chrome.helper`) o WebKit (Safari). Nil para Visor, el
    /// sistema (Dictado, Siri, Notas de voz) y apps de menu sin ventanas.
    static func owner(of processID: String, in running: [NSRunningApplication]) -> NSRunningApplication? {
        let apps = running.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        let match: NSRunningApplication?
        if processID.hasPrefix("com.apple.WebKit") {
            match = apps.first { $0.bundleIdentifier == "com.apple.Safari" }
        } else {
            match = apps.first { app in
                let id = app.bundleIdentifier!
                return processID == id || processID.hasPrefix(id + ".")
            }
        }
        guard let match, let id = match.bundleIdentifier, isCallCandidate(id) else { return nil }
        return match
    }

    /// Visor y las apps del sistema que graban sin ser llamadas no cuentan.
    static func isCallCandidate(_ bundleID: String) -> Bool {
        if bundleID.hasPrefix(Bundle.main.bundleIdentifier ?? "com.diegoperez.visor") || bundleID.hasPrefix("com.diegoperez.") {
            return false
        }
        if bundleID.hasPrefix("com.apple.") {
            return bundleID == "com.apple.FaceTime" || bundleID == "com.apple.Safari"
        }
        return true
    }

    /// Nombre y atajos. En el navegador, por el titulo de sus ventanas; nil si
    /// ninguna es de un servicio de reuniones.
    @MainActor
    private static func target(for app: NSRunningApplication) -> Target? {
        let id = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? id
        if let entry = known[id] {
            return Target(bundleID: id, pid: app.processIdentifier, name: entry.name, mic: entry.mic, camera: entry.camera, leave: entry.leave, hasCamera: true)
        }
        if browsers.contains(id) {
            guard let site = meetingSite(in: AXTree.windowTitles(pid: app.processIdentifier)) else { return nil }
            switch site {
            case "Meet":
                // Meet: ⌘D micro, ⌘E camara; colgar no tiene atajo (⌘W cerraria la pestaña).
                return Target(bundleID: id, pid: app.processIdentifier, name: "Meet", mic: (2, command), camera: (14, command), leave: nil, hasCamera: true)
            case "Teams":
                let teams = known["com.microsoft.teams2"]!
                return Target(bundleID: id, pid: app.processIdentifier, name: teams.name, mic: teams.mic, camera: teams.camera, leave: teams.leave, hasCamera: true)
            default:
                return Target(bundleID: id, pid: app.processIdentifier, name: site, mic: nil, camera: nil, leave: nil,
                              hasCamera: controlExists(.camera, pid: app.processIdentifier))
            }
        }
        // Una app cualquiera que graba solo es llamada si tiene boton de colgar: asi
        // dictar en otra app (Codex, un chat con voz) no saca los controles.
        guard controlExists(.leave, pid: app.processIdentifier) else { return nil }
        return Target(bundleID: id, pid: app.processIdentifier, name: name, mic: nil, camera: nil, leave: nil,
                      hasCamera: controlExists(.camera, pid: app.processIdentifier))
    }

    /// Si la app tiene ese control en sus ventanas o menus. Se busca como mucho cada
    /// 10 s por app y control: la cabecera se dibuja a menudo.
    @MainActor private static var controlCache: [String: (found: Bool, at: Date)] = [:]

    @MainActor
    private static func controlExists(_ action: Action, pid: pid_t) -> Bool {
        let key = "\(pid)-\(action)"
        if let cached = controlCache[key], Date.now.timeIntervalSince(cached.at) < 10 { return cached.found }
        let found = AXAccess.isTrusted && AXTree.find(action, pid: pid) != nil
        controlCache[key] = (found, .now)
        return found
    }

    // MARK: - Acciones

    enum Action { case mic, camera, leave }

    enum Outcome { case pressed, shortcut, systemMute, failed, needsPermission }

    @MainActor
    @discardableResult
    static func perform(_ action: Action, on target: Target) -> Outcome {
        guard AXAccess.isTrusted else {
            log.notice("perform \(String(describing: action)) en \(target.bundleID): sin Accesibilidad")
            return .needsPermission
        }
        if let element = AXTree.find(action, pid: target.pid), AXTree.press(element) {
            log.notice("perform \(String(describing: action)) en \(target.bundleID): boton pulsado")
            return .pressed
        }
        let shortcut: Shortcut? = switch action {
        case .mic: target.mic
        case .camera: target.camera
        case .leave: target.leave
        }
        if let shortcut, pressShortcut(shortcut, in: target, restoreFocus: action != .leave) {
            log.notice("perform \(String(describing: action)) en \(target.bundleID): atajo")
            return .shortcut
        }
        if action == .mic, SystemMic.toggle() {
            log.notice("perform mic en \(target.bundleID): entrada del sistema")
            return .systemMute
        }
        log.notice("perform \(String(describing: action)) en \(target.bundleID): nada que pulsar")
        return .failed
    }

    /// Trae la app delante por Accesibilidad (AXFrontmost y la ventana principal arriba),
    /// pulsa el atajo y vuelve a la app de antes.
    @MainActor
    private static func pressShortcut(_ shortcut: Shortcut, in target: Target, restoreFocus: Bool) -> Bool {
        let previous = NSWorkspace.shared.frontmostApplication
        guard AXTree.bringToFront(pid: target.pid) else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            log.notice("atajo: delante \(front ?? -1), llamada \(target.pid)")
            guard front == target.pid else { return }
            AXAccess.press(shortcut.key, shortcut.flags)
            if restoreFocus, let previous, previous.processIdentifier != target.pid {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { _ = AXTree.bringToFront(pid: previous.processIdentifier) }
            }
        }
        return true
    }

    /// Al acabar la llamada, el micro del sistema vuelve como estaba.
    @MainActor
    static func callEnded() {
        SystemMic.restore()
    }
}

// MARK: - Palabras de cada accion

extension MeetingControls.Action {
    /// Comienzos de etiqueta (titulo o descripcion de Accesibilidad, sin mayusculas ni
    /// acentos) que identifican el control. Nunca "salir de…" a secas: en un menu es
    /// "Salir de FaceTime" (⌘Q).
    var labelPrefixes: [String] {
        switch self {
        case .mic:
            ["mute", "unmute", "silenciar", "activar sonido", "activar el sonido", "quitar silencio", "desactivar silencio",
             "turn off microphone", "turn on microphone", "desactivar microfono", "activar microfono",
             "desactivar el microfono", "activar el microfono", "microphone off", "microphone on"]
        case .camera:
            ["turn off camera", "turn on camera", "turn camera off", "turn camera on", "stop video", "start video",
             "camera off", "camera on", "video off", "video on", "desactivar camara", "activar camara",
             "desactivar la camara", "activar la camara", "apagar camara", "encender camara", "apagar la camara",
             "encender la camara", "detener video", "iniciar video", "desactivar video", "activar video"]
        case .leave:
            ["leave", "hang up", "end call", "end meeting", "disconnect", "colgar", "abandonar", "finalizar llamada",
             "terminar llamada", "salir de la reunion", "salir de la llamada", "desconectar"]
        }
    }

    /// Si una etiqueta corresponde a esta accion.
    func matches(_ label: String) -> Bool {
        let text = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        // Teams y Meet: "Salir" a secas es colgar en el boton de la reunion.
        if self == .leave, text == "salir" { return true }
        return labelPrefixes.contains { prefix in
            guard text.hasPrefix(prefix) else { return false }
            // Palabra completa: "mute" no vale para "muted…".
            let rest = text.dropFirst(prefix.count)
            return rest.first.map { !$0.isLetter } ?? true
        }
    }
}

// MARK: - Arbol de Accesibilidad

/// Busqueda de controles en otra app por Accesibilidad.
enum AXTree {
    private static let pressRoles: Set<String> = [
        kAXButtonRole as String, kAXMenuItemRole as String, kAXCheckBoxRole as String, "AXToggle",
    ]

    /// Control de la accion en la app: primero las ventanas (el boton de la reunion),
    /// luego la barra de menus. Limitado en profundidad y en nodos.
    static func find(_ action: MeetingControls.Action, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        // Chrome y las apps Electron solo exponen su contenido web si se les pide.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let windows = (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        for window in windows {
            if let hit = search(window, action, menus: false) { return hit }
        }
        if let bar = value(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            // swiftlint:disable:next force_cast
            return search(bar as! AXUIElement, action, menus: true)
        }
        return nil
    }

    private static func search(_ root: AXUIElement, _ action: MeetingControls.Action, menus: Bool) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 6000 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = value(element, kAXRoleAttribute) as? String ?? ""
            if pressRoles.contains(role), isEnabled(element), labels(element).contains(where: action.matches) {
                // En menus nunca lo que cierra la app (⌘Q).
                if !(menus && (value(element, kAXMenuItemCmdCharAttribute) as? String)?.uppercased() == "Q") {
                    return element
                }
            }
            guard depth < 40 else { continue }
            if let children = value(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }
        return nil
    }

    private static func labels(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { value(element, $0) as? String }
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        (value(element, kAXEnabledAttribute) as? Bool) ?? true
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func windowTitles(pid: pid_t) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let windows = (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.compactMap { value($0, kAXTitleAttribute) as? String }
    }

    /// Pone la app delante y su ventana principal arriba. A diferencia de
    /// `NSRunningApplication.activate()`, macOS lo respeta aunque Visor no este activo.
    static func bringToFront(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        if let window = value(app, kAXMainWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() {
            // swiftlint:disable:next force_cast
            AXUIElementPerformAction(window as! AXUIElement, kAXRaiseAction as CFString)
        }
        return AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
}

// MARK: - Micro del sistema

/// Ultimo recurso para silenciar: la entrada de audio por defecto en mute (o a
/// volumen 0 si el dispositivo no tiene mute). Se deshace al pulsar otra vez o al
/// acabar la llamada.
@MainActor
enum SystemMic {
    private static var savedVolume: Float32?
    private static var mutedByUs = false

    static func toggle() -> Bool {
        mutedByUs ? restore() : mute()
    }

    private static func mute() -> Bool {
        guard let device = defaultInput() else { return false }
        if set(UInt32(1), device, muteAddress) {
            mutedByUs = true
            return true
        }
        guard let volume: Float32 = read(device, volumeAddress), set(Float32(0), device, volumeAddress) else { return false }
        savedVolume = volume
        mutedByUs = true
        return true
    }

    @discardableResult
    static func restore() -> Bool {
        guard mutedByUs, let device = defaultInput() else { return false }
        if let volume = savedVolume {
            _ = set(volume, device, volumeAddress)
        } else {
            _ = set(UInt32(0), device, muteAddress)
        }
        savedVolume = nil
        mutedByUs = false
        return true
    }

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain
    )
    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain
    )

    private static func defaultInput() -> AudioObjectID? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        let device: AudioObjectID? = read(AudioObjectID(kAudioObjectSystemObject), address)
        return device.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    private static func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func set<T>(_ value: T, _ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address),
              AudioObjectIsPropertySettable(object, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }
}

extension MeetingControls {
    /// Apps que estan grabando del microfono ahora (macOS 14.2+). Nil si no se puede
    /// saber: entonces vale cualquier app de la lista.
    nonisolated static func micUsers() -> Set<String>? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processes) == noErr else { return nil }
        var users = Set<String>()
        for process in processes {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(process, &inputAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr,
               let id = bundle?.takeRetainedValue() as String? {
                users.insert(id)
            }
        }
        return users
    }
}
