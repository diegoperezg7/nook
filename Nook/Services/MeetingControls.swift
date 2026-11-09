import CoreAudio
import AppKit

/// Controles de reunion: con el microfono en uso y una llamada abierta, el notch
/// pulsa por ti los atajos de la app (silenciar, camara, colgar). Pulsar atajos en
/// otra app necesita Accesibilidad.
enum MeetingControls {
    struct Target: Equatable {
        let bundleID: String
        let name: String
        let mic: (CGKeyCode, CGEventFlags)
        let camera: (CGKeyCode, CGEventFlags)
        /// Sin colgar en el navegador: ⌘W cerraria la pestaña que tenga el foco.
        let leave: (CGKeyCode, CGEventFlags)?

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.bundleID == rhs.bundleID }
    }

    private static let command: CGEventFlags = .maskCommand
    private static let commandShift: CGEventFlags = [.maskCommand, .maskShift]

    /// Apps de llamada por orden de preferencia.
    private static let apps: [Target] = [
        // Zoom: ⌘⇧A micro, ⌘⇧V video, ⌘W salir.
        Target(bundleID: "us.zoom.xos", name: "Zoom", mic: (0, commandShift), camera: (9, commandShift), leave: (13, command)),
        // Teams (nuevo y clasico): ⌘⇧M micro, ⌘⇧O camara, ⌘⇧H colgar.
        Target(bundleID: "com.microsoft.teams2", name: "Teams", mic: (46, commandShift), camera: (31, commandShift), leave: (4, commandShift)),
        Target(bundleID: "com.microsoft.teams", name: "Teams", mic: (46, commandShift), camera: (31, commandShift), leave: (4, commandShift)),
    ]

    /// Navegadores para Google Meet: ⌘D micro, ⌘E camara.
    private static let browsers = [
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "com.brave.Browser", "org.mozilla.firefox",
    ]

    /// La llamada en curso, si el microfono esta en uso. Cuenta solo la app que de
    /// verdad esta grabando (CoreAudio): tener Teams abierto mientras dictas no es
    /// una llamada.
    @MainActor
    static func current(micInUse: Bool) -> Target? {
        guard micInUse else { return nil }
        let users = micUsers()
        let recording: (String) -> Bool = { id in users.map { $0.contains { $0.hasPrefix(id) } } ?? true }
        let running = NSWorkspace.shared.runningApplications
        if let app = apps.first(where: { target in
            running.contains { $0.bundleIdentifier == target.bundleID } && recording(target.bundleID)
        }) {
            return app
        }
        // Meet: el navegador que esta delante y graba (Safari lo hace desde WebKit).
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let browser = browsers.first(where: { $0 == front }),
              recording(browser) || (browser == "com.apple.Safari" && recording("com.apple.WebKit")) else { return nil }
        return Target(bundleID: browser, name: "Meet", mic: (2, command), camera: (14, command), leave: nil)
    }

    enum Action { case mic, camera, leave }

    /// Lleva la app de la llamada delante, pulsa el atajo y vuelve a la app de antes.
    @MainActor
    static func perform(_ action: Action, on target: Target) -> Bool {
        guard AXAccess.isTrusted else { return false }
        let shortcut: (CGKeyCode, CGEventFlags)?
        switch action {
        case .mic: shortcut = target.mic
        case .camera: shortcut = target.camera
        case .leave: shortcut = target.leave
        }
        guard let shortcut,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first else { return true }
        let previous = NSWorkspace.shared.frontmostApplication
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            AXAccess.press(shortcut.0, shortcut.1)
            if action != .leave, let previous, previous.bundleIdentifier != target.bundleID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { previous.activate() }
            }
        }
        return true
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

