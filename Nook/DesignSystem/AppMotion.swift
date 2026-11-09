import AppKit
import SwiftUI

/// Curvas de animacion compartidas. Con "Reducir movimiento" activado todo pasa
/// a fundidos cortos, sin muelles ni desplazamientos.
enum AppMotion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Apertura: muelle con un rebote apenas perceptible.
    static var open: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.8)
    }

    /// Cierre: mas rapido y sin rebote, para que no "tiemble" al recogerse.
    static var close: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.95)
    }

    /// Apertura liquida: el ancho se abre rapido y con rebote...
    static var openWidth: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.68)
    }

    /// ...y el alto le sigue, mas lento, como una gota que cae.
    static var openHeight: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.72).delay(0.05)
    }

    /// Cierre: primero se recoge el alto y despues el ancho, sin rebote.
    static var closeHeight: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.92)
    }

    static var closeWidth: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.9).delay(0.06)
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
