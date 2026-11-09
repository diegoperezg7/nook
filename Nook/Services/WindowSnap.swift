import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Colocar la ventana activa en mitades, cuartos y tercios con ⌃⌥ + tecla
/// (Accesibilidad). Atajos registrados con Carbon: no hace falta monitor de teclado.
enum WindowLayout: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds

    /// Tecla (con ⌃⌥) de cada colocacion.
    var keyCode: Int {
        switch self {
        case .leftHalf: return kVK_LeftArrow
        case .rightHalf: return kVK_RightArrow
        case .topHalf: return kVK_UpArrow
        case .bottomHalf: return kVK_DownArrow
        case .maximize: return kVK_Return
        case .center: return kVK_ANSI_C
        case .topLeft: return kVK_ANSI_U
        case .topRight: return kVK_ANSI_I
        case .bottomLeft: return kVK_ANSI_J
        case .bottomRight: return kVK_ANSI_K
        case .leftThird: return kVK_ANSI_D
        case .centerThird: return kVK_ANSI_F
        case .rightThird: return kVK_ANSI_G
        case .leftTwoThirds: return kVK_ANSI_E
        case .rightTwoThirds: return kVK_ANSI_T
        }
    }

    /// Marco en coordenadas de Cocoa (origen abajo a la izquierda) dentro del area
    /// util de la pantalla. `current` solo se usa para centrar.
    func frame(in area: CGRect, current: CGRect) -> CGRect {
        // Redondeo de cada valor (no `integral`, que agranda un punto al centrar).
        let raw = rawFrame(in: area, current: current)
        return CGRect(x: raw.minX.rounded(), y: raw.minY.rounded(), width: raw.width.rounded(), height: raw.height.rounded())
    }

    private func rawFrame(in area: CGRect, current: CGRect) -> CGRect {
        let w = area.width, h = area.height, x = area.minX, y = area.minY
        switch self {
        case .leftHalf: return CGRect(x: x, y: y, width: w / 2, height: h)
        case .rightHalf: return CGRect(x: x + w / 2, y: y, width: w / 2, height: h)
        case .topHalf: return CGRect(x: x, y: y + h / 2, width: w, height: h / 2)
        case .bottomHalf: return CGRect(x: x, y: y, width: w, height: h / 2)
        case .maximize: return area
        case .center:
            let size = CGSize(width: min(current.width, w), height: min(current.height, h))
            return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        case .topLeft: return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
        case .topRight: return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
        case .bottomLeft: return CGRect(x: x, y: y, width: w / 2, height: h / 2)
        case .bottomRight: return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
        case .leftThird: return CGRect(x: x, y: y, width: w / 3, height: h)
        case .centerThird: return CGRect(x: x + w / 3, y: y, width: w / 3, height: h)
        case .rightThird: return CGRect(x: x + 2 * w / 3, y: y, width: w / 3, height: h)
        case .leftTwoThirds: return CGRect(x: x, y: y, width: 2 * w / 3, height: h)
        case .rightTwoThirds: return CGRect(x: x + w / 3, y: y, width: 2 * w / 3, height: h)
        }
    }

    /// De Cocoa a Accesibilidad (origen arriba a la izquierda de la pantalla principal).
    static func toAX(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

@MainActor
final class WindowSnap {
    private var hotKeys: [HotKey] = []
    var onNeedsPermission: (() -> Void)?

    func apply() {
        let enabled = UserDefaults.standard.bool(forKey: SettingsKey.windowSnap)
        if enabled, hotKeys.isEmpty {
            hotKeys = WindowLayout.allCases.enumerated().map { index, layout in
                HotKey(keyCode: UInt32(layout.keyCode), modifiers: UInt32(controlKey | optionKey), id: UInt32(100 + index)) { [weak self] in
                    MainActor.assumeIsolated { self?.snap(layout) }
                }
            }
        } else if !enabled {
            hotKeys = []
        }
    }

    func snap(_ layout: WindowLayout) {
        guard AXAccess.isTrusted else { onNeedsPermission?(); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID() else { return }
        let axWindow = window as! AXUIElement // swiftlint:disable:this force_cast
        guard let primary = NSScreen.screens.first, let current = frame(of: axWindow, primaryHeight: primary.frame.height) else { return }
        // La pantalla donde esta la mayor parte de la ventana.
        let screen = NSScreen.screens.max { $0.frame.intersection(current).area < $1.frame.intersection(current).area } ?? primary
        let target = WindowLayout.toAX(layout.frame(in: screen.visibleFrame, current: current), primaryHeight: primary.frame.height)
        set(axWindow, origin: target.origin, size: target.size)
    }

    /// Marco actual en Cocoa.
    private func frame(of window: AXUIElement, primaryHeight: CGFloat) -> CGRect? {
        var positionRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin) // swiftlint:disable:this force_cast
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) // swiftlint:disable:this force_cast
        return CGRect(x: origin.x, y: primaryHeight - origin.y - size.height, width: size.width, height: size.height)
    }

    private func set(_ window: AXUIElement, origin: CGPoint, size: CGSize) {
        var origin = origin, size = size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        // Tamaño, posicion y otra vez tamaño: al cambiar de pantalla el primer tamaño
        // puede quedar limitado por la pantalla de origen.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
