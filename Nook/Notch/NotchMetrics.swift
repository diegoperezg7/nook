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
    /// Isla de una notificacion: el notch crece un poco a cada lado y hacia abajo,
    /// como la Isla Dinamica, y el mensaje va debajo del notch fisico.
    /// El ancho va con el texto (`content`, sin margenes): de `islandMinSide` a
    /// `islandMaxSide` mas a cada lado; lo que no cabe se corta con puntos.
    static let islandMinSide: CGFloat = 40
    static let islandMaxSide: CGFloat = 130
    static let islandPadding: CGFloat = 18
    static let islandExtra: CGFloat = 46
    /// Alto bajo el notch de una isla de una sola fila (un aviso que no cabia en las alas).
    static let islandRowExtra: CGFloat = 30
    static let islandBottomRadius: CGFloat = 20

    func islandSize(content: CGFloat, extra: CGFloat = Self.islandExtra) -> CGSize {
        let width = content + Self.islandPadding * 2
        let low = closedSize.width + Self.islandMinSide * 2
        let high = closedSize.width + Self.islandMaxSide * 2
        return CGSize(width: min(max(width.rounded(.up), low), high), height: notchHeight + extra)
    }

    /// Zona de la isla (centrada en el notch).
    func islandRect(content: CGFloat, extra: CGFloat = Self.islandExtra) -> CGRect {
        let size = islandSize(content: content, extra: extra)
        return CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Botones redondos de la cabecera y su separacion normal y en llamada.
    static let headerButton: CGFloat = 30
    static let headerButtonSpacing: CGFloat = 8
    static let callButtonSpacing: CGFloat = 4

    /// Ancho util a cada lado del notch en la cabecera del panel abierto.
    /// Separacion de los botones de la cabecera: con cinco, la justa para que quepan
    /// junto al notch (con 8 el primero quedaba debajo de la camara).
    static func headerSpacing(buttons: Int) -> CGFloat {
        buttons >= 5 ? callButtonSpacing : headerButtonSpacing
    }

    var headerSideWidth: CGFloat {
        (openSize(searchRow: false).width - Self.openEar * 2 - Self.sideMargin * 2 - (hasNotch ? notchWidth : 0)) / 2
    }
    /// Alto extra de la pestaña de correo, para leer un mensaje sin salir del notch.
    static let readerExtra: CGFloat = 200
    /// Lo que la fila de una actividad (llamada, musica) ocupa menos que la
    /// fila de tarjetas.
    static let activityRowSaving: CGFloat = 40
    /// Aire de la tarjeta de un aviso pulsado por encima (bajo la fila del notch) y
    /// por debajo de su contenido.
    static let previewTop: CGFloat = 8
    static let previewBottom: CGFloat = 12

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
    func openSize(searchRow: Bool, extra: CGFloat = 0) -> CGSize {
        // ~210 pt a cada lado del notch: pestañas (control compacto) a un lado,
        // botones al otro. Compacto: no se ensancha al añadir pestañas.
        let width = min(max(notchWidth + 420, 600), screenFrame.width - 40)
        let content = Self.topSpacing + (searchRow ? Self.searchRowHeight : 0) + Self.cardRowHeight + Self.bottomMargin
        return CGSize(width: width, height: headerHeight + content + extra)
    }

    /// El mayor de los tamaños: el de la ventana.
    var openSize: CGSize { openSize(searchRow: true, extra: Self.readerExtra) }

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

    /// Forma del notch cerrado con un aviso: crece `sides.left` a la izquierda y
    /// `sides.right` a la derecha con el notch fisico en su sitio (como el `shift`
    /// de `NotchRootView`).
    func closedNoticeRect(sides: HUDSides) -> CGRect {
        let frame = closedWindowFrame
        return CGRect(x: frame.minX - sides.left, y: frame.minY, width: frame.width + sides.left + sides.right, height: frame.height)
    }

    /// Tarjeta de un aviso pulsado: lo justo para su contenido (`content`, sin los
    /// margenes), nunca mas estrecha que la isla mas pequeña ni mas ancha que el
    /// panel abierto.
    func previewSize(content: CGSize) -> CGSize {
        let width = content.width + Self.sideMargin * 2
        return CGSize(
            width: min(max(width.rounded(.up), closedSize.width + Self.islandMinSide * 2), openSize(searchRow: false).width),
            height: notchHeight + Self.previewTop + content.height.rounded(.up) + Self.previewBottom
        )
    }

    /// Zona de la tarjeta (con el mismo margen que el panel abierto).
    func previewHotRect(content: CGSize) -> CGRect {
        let size = previewSize(content: content)
        return CGRect(
            x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
            width: size.width, height: size.height
        ).insetBy(dx: -8, dy: -8)
    }

    /// Zona que mantiene el panel abierto: la forma visible mas un pequeño margen.
    func openHotRect(searchRow: Bool, extra: CGFloat = 0) -> CGRect {
        let size = openSize(searchRow: searchRow, extra: extra)
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
            // La zona segura se queda un punto por debajo del recorte fisico (Air 13":
            // 32 frente a la barra de 33). La barra de menus llega justo al borde del
            // notch; si esta oculta (visibleFrame sin barra) se usa la zona segura.
            let menuBar = screenFrame.maxY - visibleFrameMaxY
            let height = menuBar > safeAreaTop && menuBar <= safeAreaTop + 4 ? menuBar : safeAreaTop
            return NotchMetrics(hasNotch: true, screenFrame: screenFrame, notchWidth: width, notchHeight: height)
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
