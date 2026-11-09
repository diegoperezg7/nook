import AppKit

/// Medidas del notch en una pantalla concreta y marcos de ventana derivados.
/// Es una funcion pura de los datos de la pantalla para poder probarla.
struct NotchMetrics: Equatable {
    /// Radio de las "orejas" concavas que unen la forma con el borde superior.
    static let closedEar: CGFloat = 6
    static let openEar: CGFloat = 14
    static let openBottomRadius: CGFloat = 28
    /// Margen transparente alrededor del panel abierto para que quepa la sombra.
    static let shadowPadding: CGFloat = 24
    static let contentHeight: CGFloat = 190
    static let pillWidth: CGFloat = 180

    var hasNotch: Bool
    var screenFrame: CGRect
    /// Ancho del notch fisico (o de la pastilla en pantallas sin notch).
    var notchWidth: CGFloat
    /// Alto del notch fisico (o de la barra de menus).
    var notchHeight: CGFloat

    var closedSize: CGSize {
        CGSize(width: notchWidth + Self.closedEar * 2, height: notchHeight)
    }

    var closedBottomRadius: CGFloat {
        hasNotch ? 9 : notchHeight / 2
    }

    /// Fila de pestañas a los lados del notch; minimo 36 para que respiren.
    var headerHeight: CGFloat { max(notchHeight + 4, 36) }

    var openSize: CGSize {
        // ~180 pt a cada lado del notch: pestañas a un lado, menu al otro, con aire.
        let width = min(max(notchWidth + 360, 540), screenFrame.width - 40)
        return CGSize(width: width, height: headerHeight + Self.contentHeight)
    }

    var closedWindowFrame: CGRect {
        CGRect(
            x: screenFrame.midX - closedSize.width / 2,
            y: screenFrame.maxY - closedSize.height,
            width: closedSize.width, height: closedSize.height
        )
    }

    var openWindowFrame: CGRect {
        let width = openSize.width + Self.shadowPadding * 2
        let height = openSize.height + Self.shadowPadding
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// Zona que abre el panel al pasar el raton.
    var closedHotRect: CGRect { closedWindowFrame }

    /// Zona que mantiene el panel abierto: la forma visible mas un pequeño margen.
    var openHotRect: CGRect {
        CGRect(
            x: screenFrame.midX - openSize.width / 2,
            y: screenFrame.maxY - openSize.height,
            width: openSize.width, height: openSize.height
        ).insetBy(dx: -8, dy: -8)
    }

    static func make(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeft: CGRect,
        auxiliaryTopRight: CGRect,
        visibleFrameMaxY: CGFloat
    ) -> NotchMetrics {
        if safeAreaTop > 0, !auxiliaryTopLeft.isEmpty, !auxiliaryTopRight.isEmpty {
            let width = screenFrame.width - auxiliaryTopLeft.width - auxiliaryTopRight.width
            return NotchMetrics(hasNotch: true, screenFrame: screenFrame, notchWidth: width, notchHeight: safeAreaTop)
        }
        let menuBar = screenFrame.maxY - visibleFrameMaxY
        return NotchMetrics(
            hasNotch: false, screenFrame: screenFrame,
            notchWidth: pillWidth, notchHeight: menuBar > 0 ? menuBar : 24
        )
    }

    static func make(for screen: NSScreen) -> NotchMetrics {
        make(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRight: screen.auxiliaryTopRightArea ?? .zero,
            visibleFrameMaxY: screen.visibleFrame.maxY
        )
    }
}
