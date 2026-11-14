import AppKit
import SwiftUI

/// Curvas de animacion compartidas. Con "Reducir movimiento" activado todo pasa
/// a fundidos cortos, sin muelles ni desplazamientos.
/// `resize`, `dismiss` y `press` toman los valores de islandcn (MIT, (c) 2026 Leo;
/// ver THIRD_PARTY_NOTICES.md), que usa los mismos parametros que SwiftUI.
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

    /// Un aviso cambia de tamaño sin desaparecer (de volumen a red, por ejemplo): la
    /// forma se ajusta sin pasar por cerrada (0,5 / 0,82, `resize` de islandcn).
    static var resize: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.82)
    }

    /// Un aviso se va y el notch vuelve a su tamaño: casi sin rebote (0,442 / 0,97,
    /// `dismiss` de islandcn).
    static var dismiss: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.442, dampingFraction: 0.97)
    }

    /// Al pulsar un aviso se hincha un poco desde arriba, y vuelve sobreamortiguado
    /// (0,30 / 1,5, `press.release` de islandcn), sin rebote.
    static var press: Animation {
        reduceMotion ? .easeInOut(duration: 0.08) : .spring(response: 0.3, dampingFraction: 1)
    }

    /// Microinteracciones: hover, seleccion de pestaña, insercion de elementos.
    static var snappy: Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.82)
    }

    /// Entrada del contenido de un aviso del notch cerrado: a la vez que crece la
    /// forma, sin retardo, para que los dos lados aparezcan juntos.
    static var noticeIn: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .easeOut(duration: 0.22)
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
