import AppKit
import SwiftUI

/// Curvas de animacion compartidas. Con "Reducir movimiento" activado todo pasa
/// a fundidos cortos, sin muelles ni desplazamientos.
enum AppMotion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Apertura: el panel sale del centro del notch y se agranda con un rebote suave
    /// (muelle 0,47 / 0,76).
    static var open: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.47, dampingFraction: 0.76)
    }

    /// Cierre: sin rebote, para que no "tiemble" al recogerse (0,54 / 0,90).
    static var close: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.54, dampingFraction: 0.9)
    }

    /// El notch cerrado se asoma al pasar el raton (escala 1,02 desde arriba).
    static var peek: Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.36, dampingFraction: 0.9)
    }

    /// Microinteracciones: hover, seleccion de pestaña, insercion de elementos.
    static var snappy: Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.82)
    }

    /// Entrada del texto de un aviso del notch cerrado: fundido algo retrasado para
    /// no verse recortado mientras la forma aun crece.
    static var noticeIn: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .easeOut(duration: 0.2).delay(0.08)
    }

    /// Salida del texto de un aviso: dura lo que tarda la forma en recogerse con
    /// `close`, para que las alas no se queden vacias.
    static var noticeOut: Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .easeOut(duration: 0.25)
    }

    /// Retardo escalonado de entrada de las tarjetas al abrir.
    static func stagger(_ index: Int) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : snappy.delay(Double(min(index, 8)) * 0.03 + 0.06)
    }
}
