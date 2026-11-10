import AppKit
import SwiftUI

/// Paleta centralizada. El panel es de cristal (Liquid Glass): las superficies son
/// velos translucidos con un borde fino, no colores opacos.
/// Acento: azul electrico. No cae en la familia del semaforo (verde/ambar/rojo).
enum AppColors {
    /// El notch cerrado siempre es negro: tiene que fundirse con el hardware.
    static let notch = Color.black
    /// Fondo de las ventanas flotantes (cesta, anillo). Casi negro: en un panel con
    /// fondo transparente el negro puro se veia transparente sobre otras ventanas.
    static let floating = Color(white: 0.07)

    /// Fondo de respaldo sin Liquid Glass (macOS 14-15) y del boton de borrar.
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x000000)
    /// Brillo del borde del cristal.
    static let panelBorder = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.55, darkAlpha: 0.14)
    /// Velo de las tarjetas sobre el cristal.
    static let card = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.5, darkAlpha: 0.07)
    static let cardHover = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.75, darkAlpha: 0.13)
    static let cardBorder = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.1)
    /// Fondo de la zona de vista previa dentro de una tarjeta.
    static let previewWell = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.04, darkAlpha: 0.06)
    /// Carril de los controles (pestañas, buscador, boton de opciones).
    static let controlTrack = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.1)

    static let textPrimary = dynamic(light: 0x0B0D12, dark: 0xF4F5F8)
    static let textSecondary = dynamic(light: 0x5D6372, dark: 0x9BA1AE)

    static let accent = dynamic(light: 0x1F5BFF, dark: 0x4C7DFF)
    /// Relleno de boton con texto blanco: el tono claro del acento en los dos modos
    /// (blanco sobre 0x4C7DFF da 3,69:1, por debajo de AA; sobre 0x1F5BFF, 5,25:1).
    static let accentFill = Color(nsColor: NSColor(hex: 0x1F5BFF, alpha: 1))
    static let accentSoft = dynamic(light: 0x1F5BFF, dark: 0x4C7DFF, lightAlpha: 0.16, darkAlpha: 0.22)
    static let onAccent = Color.white
    /// Texto e iconos sobre el negro del notch (siempre negro, en claro y en oscuro).
    static let notchText = Color.white
    /// Velo y borde azul de las zonas interactivas en reposo (caja de soltar, controles).
    static let accentWell = dynamic(light: 0x1F5BFF, dark: 0x4C7DFF, lightAlpha: 0.06, darkAlpha: 0.1)
    static let accentBorder = dynamic(light: 0x1F5BFF, dark: 0x4C7DFF, lightAlpha: 0.4, darkAlpha: 0.5)

    static let danger = dynamic(light: 0xD93036, dark: 0xF2555A)
    static let success = dynamic(light: 0x1E9E5A, dark: 0x3CCB7F)
    /// Ambar del semaforo: algo espera al usuario.
    static let warning = dynamic(light: 0xB86E00, dark: 0xF2A93B)

    /// Naranja del Reloj de Apple: temporizador y alarmas, como en el sistema.
    static let clock = Color(nsColor: .systemOrange)

    static let shadow = Color.black.opacity(0.28)

    /// Borde luminoso de la tarjeta de un aviso pulsado (estilo Apple Intelligence):
    /// azul, morado, rosa y naranja; repite el primero para cerrar el degradado.
    static let glow: [Color] = [0x3B82F6, 0x8B5CF6, 0xEC4899, 0xF97316, 0x3B82F6]
        .map { Color(nsColor: NSColor(hex: $0, alpha: 1)) }

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Icono de la app leido del propio paquete. `NSApp.applicationIconImage` pasa por la
/// cache de iconos del sistema y puede devolver uno antiguo tras cambiarlo.
enum AppIcon {
    @MainActor static var image: NSImage { Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage }
}
