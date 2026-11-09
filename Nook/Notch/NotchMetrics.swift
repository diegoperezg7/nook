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
    /// Fila de tarjetas: 120 pt de tarjeta mas aire para el zoom y la sombra del hover.
    static let cardRowHeight: CGFloat = 136
    /// Buscador y filtros del historial (32 pt mas su separacion).
    static let searchRowHeight: CGFloat = 42
    /// Margenes del contenido: a los lados y abajo casi iguales, para que respire.
    static let sideMargin: CGFloat = 22
    static let topSpacing: CGFloat = 10
    static let bottomMargin: CGFloat = 18
    static let pillWidth: CGFloat = 180
    /// Lo que crece el notch cerrado a cada lado mientras suena musica.
    static let activitySide: CGFloat = 38

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

    /// Tamaño del panel abierto. La bandeja no tiene buscador y es mas baja: el panel
    /// se ajusta al contenido en vez de dejar un hueco abajo.
    func openSize(searchRow: Bool) -> CGSize {
        // ~250 pt a cada lado del notch: pestañas a un lado, botones al otro, con aire.
        let width = min(max(notchWidth + 500, 680), screenFrame.width - 40)
        let content = Self.topSpacing + (searchRow ? Self.searchRowHeight : 0) + Self.cardRowHeight + Self.bottomMargin
        return CGSize(width: width, height: headerHeight + content)
    }

    /// El mayor de los tamaños: el de la ventana.
    var openSize: CGSize { openSize(searchRow: true) }

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
    func openHotRect(searchRow: Bool) -> CGRect {
        let size = openSize(searchRow: searchRow)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width, height: size.height
        ).insetBy(dx: -8, dy: -8)
    }

    var openHotRect: CGRect { openHotRect(searchRow: true) }

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
