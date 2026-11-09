import AppKit
import SwiftUI

/// Curvas de animacion compartidas. Con "Reducir movimiento" activado todo pasa
/// a fundidos cortos, sin muelles ni desplazamientos.
enum AppMotion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Apertura: el panel sale del notch hacia abajo con un rebote suave.
    static var open: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.46, dampingFraction: 0.78)
    }

    /// Cierre: mas rapido y sin rebote, para que no "tiemble" al recogerse.
    static var close: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.95)
    }

    /// Asomarse al acercar el raton.
    static var peek: Animation {
        // Rebote marcado: la gota se forma, se estira y se asienta.
        .spring(response: 0.42, dampingFraction: 0.5)
    }

    /// Microinteracciones: hover, seleccion de pestaña, insercion de elementos.
    static var snappy: Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.82)
    }

    /// Retardo escalonado de entrada de las tarjetas al abrir.
    static func stagger(_ index: Int) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : snappy.delay(Double(min(index, 8)) * 0.03 + 0.06)
    }
}
