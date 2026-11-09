import AppKit
import ApplicationServices
import Observation

/// Hueco libre en la barra de menus a cada lado del notch: donde acaban los menus de la
/// app activa y donde empiezan los iconos de estado. Se lee por Accesibilidad; sin ese
/// permiso no se sabe y los avisos usan su ancho normal.
@Observable
@MainActor
final class MenuBarSpace {
    /// Borde derecho del ultimo menu de la app activa (x de pantalla), si se conoce.
    private(set) var menusEnd: CGFloat?
    /// Borde izquierdo del primer icono de estado a la derecha del notch, si se conoce.
    private(set) var extrasStart: CGFloat?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private let queue = DispatchQueue(label: "com.diegoperez.nook.menubar", qos: .utility)
    @ObservationIgnored private var notchRange: ClosedRange<CGFloat> = 0...0
    /// Borde superior de la pantalla del notch en coordenadas de Accesibilidad.
    @ObservationIgnored private var top: CGFloat = 0

    func start(for screen: NSScreen, notchWidth: CGFloat) {
        notchRange = (screen.frame.midX - notchWidth / 2)...(screen.frame.midX + notchWidth / 2)
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        top = primaryHeight - screen.frame.maxY
        guard timer == nil else { return refresh() }
        refresh()
        // Los iconos de estado cambian poco; los menus, al cambiar de app.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Hueco libre a la izquierda y a la derecha del notch (nil si no se conoce).
    var free: (left: CGFloat?, right: CGFloat?) {
        (menusEnd.map { notchRange.lowerBound - $0 }, extrasStart.map { $0 - notchRange.upperBound })
    }

    func refresh() {
        guard AXAccess.isTrusted, !scanning else { return }
        scanning = true
        let range = notchRange, top = top
        let onBar: (CGRect) -> Bool = { abs($0.minY - top) < 4 }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pids = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        queue.async {
            let menus = front.map { Self.frames(of: $0, attribute: kAXMenuBarAttribute) } ?? []
            let extras = pids.flatMap { Self.frames(of: $0, attribute: "AXExtrasMenuBar") }
            // Si los menus no caben, macOS sigue poniendolos a la derecha del notch:
            // tambien cuentan para el lado derecho.
            let menusEnd = menus.filter { onBar($0) && $0.maxX <= range.lowerBound + 1 }.map(\.maxX).max()
            let extrasStart = (extras + menus).filter { onBar($0) && $0.minX >= range.upperBound - 1 }.map(\.minX).min()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.scanning = false
                    if self.menusEnd != menusEnd { self.menusEnd = menusEnd }
                    if self.extrasStart != extrasStart { self.extrasStart = extrasStart }
                }
            }
        }
    }

    /// Marcos (coordenadas de Accesibilidad: origen arriba a la izquierda) de los hijos
    /// de la barra indicada de una app.
    nonisolated private static func frames(of pid: pid_t, attribute: String) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var children: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return [] }
        return items.compactMap { item in
            var position: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size else { return nil }
            var point = CGPoint.zero, extent = CGSize.zero
            // swiftlint:disable force_cast
            AXValueGetValue(position as! AXValue, .cgPoint, &point)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            // swiftlint:enable force_cast
            return CGRect(origin: point, size: extent)
        }
    }
}

/// Reparto del ensanche de un aviso entre los dos lados del notch.
struct HUDSides: Equatable {
    var left: CGFloat
    var right: CGFloat
    /// Todo el aviso va en un lado (el otro no tiene sitio).
    var merged: Bool

    /// Menos de esto no da para mostrar nada en un lado.
    static let minimum: CGFloat = 30

    /// `leftFree` y `rightFree` son el hueco libre de la barra a cada lado (nil si no
    /// se conoce). Cada lado crece lo que pide el aviso o lo que haya libre; si un lado
    /// no llega al minimo, el aviso entero pasa al otro.
    static func make(desired: CGFloat, leftFree: CGFloat?, rightFree: CGFloat?) -> HUDSides {
        guard desired > 0 else { return HUDSides(left: 0, right: 0, merged: false) }
        let margin: CGFloat = 4
        let left = leftFree.map { max(0, $0 - margin) } ?? desired
        let right = rightFree.map { max(0, $0 - margin) } ?? desired
        let fitsLeft = left >= minimum, fitsRight = right >= minimum
        switch (fitsLeft, fitsRight) {
        case (true, true):
            return HUDSides(left: min(desired, left), right: min(desired, right), merged: false)
        case (true, false):
            return HUDSides(left: min(desired * 2, left), right: 0, merged: true)
        case (false, true):
            return HUDSides(left: 0, right: min(desired * 2, right), merged: true)
        case (false, false):
            // Sin hueco en ningun lado: lo minimo, aunque tape un poco.
            return HUDSides(left: minimum, right: minimum, merged: false)
        }
    }
}
