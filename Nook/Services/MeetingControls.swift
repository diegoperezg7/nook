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

    /// La llamada en curso, si el microfono esta en uso.
    @MainActor
    static func current(micInUse: Bool) -> Target? {
        guard micInUse else { return nil }
        let running = NSWorkspace.shared.runningApplications
        if let app = apps.first(where: { target in running.contains { $0.bundleIdentifier == target.bundleID } }) {
            return app
        }
        // Meet: el navegador que este delante o, si no, el primero abierto.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let browser = browsers.first { $0 == front } ?? browsers.first { id in running.contains { $0.bundleIdentifier == id } }
        guard let browser else { return nil }
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
