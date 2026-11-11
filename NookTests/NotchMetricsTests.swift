import XCTest
@testable import Nook

final class NotchMetricsTests: XCTestCase {
    /// MacBook Air 13" (1470x956 pt): notch de 32 pt de alto.
    func testNotchedScreenUsesPhysicalNotch() {
        let frame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let metrics = NotchMetrics.make(
            screenFrame: frame,
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 924, width: 640, height: 32),
            auxiliaryTopRight: CGRect(x: 830, y: 924, width: 640, height: 32),
            visibleFrameMaxY: 924
        )
        XCTAssertTrue(metrics.hasNotch)
        XCTAssertEqual(metrics.notchWidth, 190)
        XCTAssertEqual(metrics.closedSize, CGSize(width: 190 + NotchMetrics.closedEar * 2, height: 32))
        // Cerrado: centrado y pegado al borde superior.
        XCTAssertEqual(metrics.closedWindowFrame.midX, frame.midX)
        XCTAssertEqual(metrics.closedWindowFrame.maxY, frame.maxY)
        // Abierto: la ventana cubre la forma y el margen de la sombra.
        XCTAssertEqual(metrics.openWindowFrame.maxY, frame.maxY)
        XCTAssertGreaterThan(metrics.openWindowFrame.width, metrics.openSize.width)
        XCTAssertTrue(metrics.openHotRect.contains(CGPoint(x: frame.midX, y: frame.maxY - 1)))
    }

    /// El Air da 32 pt de zona segura con una barra de 33: manda la barra, que llega
    /// al borde del recorte. Con la barra oculta se queda la zona segura.
    func testNotchHeightFollowsMenuBar() {
        let frame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        func height(_ visibleMaxY: CGFloat) -> CGFloat {
            NotchMetrics.make(
                screenFrame: frame, safeAreaTop: 32,
                auxiliaryTopLeft: CGRect(x: 0, y: 924, width: 645.5, height: 32),
                auxiliaryTopRight: CGRect(x: 824.5, y: 924, width: 645.5, height: 32),
                visibleFrameMaxY: visibleMaxY
            ).notchHeight
        }
        XCTAssertEqual(height(923), 33)
        XCTAssertEqual(height(956), 32)
        XCTAssertEqual(height(900), 32)
    }

    func testScreenWithoutNotchUsesMenuBarPill() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let metrics = NotchMetrics.make(
            screenFrame: frame, safeAreaTop: 0,
            auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero,
            visibleFrameMaxY: 1415
        )
        XCTAssertFalse(metrics.hasNotch)
        XCTAssertEqual(metrics.notchWidth, NotchMetrics.pillWidth)
        XCTAssertEqual(metrics.notchHeight, 25)
        XCTAssertEqual(metrics.closedBottomRadius, 12.5)
        XCTAssertEqual(metrics.headerHeight, 36)
    }

    func testHiddenMenuBarFallsBackToDefaultHeight() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let metrics = NotchMetrics.make(
            screenFrame: frame, safeAreaTop: 0,
            auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero,
            visibleFrameMaxY: 1080
        )
        XCTAssertEqual(metrics.notchHeight, 24)
    }

    /// En una pantalla externa a la derecha, todo se calcula en sus coordenadas.
    func testSecondaryScreenOffsets() {
        let frame = CGRect(x: 1470, y: 0, width: 1920, height: 1080)
        let metrics = NotchMetrics.make(
            screenFrame: frame, safeAreaTop: 0,
            auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero,
            visibleFrameMaxY: 1055
        )
        XCTAssertEqual(metrics.closedWindowFrame.midX, frame.midX)
        XCTAssertTrue(metrics.closedHotRect.contains(CGPoint(x: frame.midX, y: frame.maxY - 2)))
        XCTAssertFalse(metrics.closedHotRect.contains(CGPoint(x: 735, y: frame.maxY - 2)))
    }

    /// La zona clicable del aviso coincide con la forma: crece por cada lado lo suyo
    /// y el notch fisico no se mueve (tambien con todo el aviso a un lado).
    func testClosedNoticeRectFollowsSides() {
        let metrics = NotchMetrics(hasNotch: true, screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956), notchWidth: 190, notchHeight: 32)
        let closed = metrics.closedWindowFrame
        XCTAssertEqual(metrics.closedNoticeRect(sides: HUDSides(left: 0, right: 0, merged: false)), closed)
        let both = metrics.closedNoticeRect(sides: HUDSides(left: 58, right: 58, merged: false))
        XCTAssertEqual(both, CGRect(x: closed.minX - 58, y: closed.minY, width: closed.width + 116, height: closed.height))
        XCTAssertEqual(both.midX, closed.midX)
        let merged = metrics.closedNoticeRect(sides: HUDSides(left: 224, right: 0, merged: true))
        XCTAssertEqual(merged.maxX, closed.maxX)
        XCTAssertEqual(merged.minX, closed.minX - 224)
        // Mismo ancho y centro que NotchRootView: closedWidth centrado y desplazado `shift`.
        let sides = HUDSides(left: 0, right: 150, merged: true)
        let width = metrics.closedSize.width + sides.left + sides.right
        let center = closed.midX + (sides.right - sides.left) / 2
        let rect = metrics.closedNoticeRect(sides: sides)
        XCTAssertEqual(rect.width, width)
        XCTAssertEqual(rect.midX, center)
    }

    /// La tarjeta de un aviso pulsado es mas alta que el notch y mas baja que el panel.
    func testPreviewCardSitsBetweenNoticeAndPanel() {
        let metrics = NotchMetrics(hasNotch: true, screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956), notchWidth: 190, notchHeight: 32)
        XCTAssertGreaterThan(metrics.previewSize.height, metrics.closedSize.height)
        XCTAssertLessThan(metrics.previewSize.height, metrics.openSize(searchRow: false).height)
        XCTAssertEqual(metrics.previewHotRect.midX, 735)
        XCTAssertEqual(metrics.previewHotRect.maxY, 956 + 8)
        XCTAssertTrue(metrics.previewHotRect.contains(metrics.closedNoticeRect(sides: HUDSides(left: 150, right: 150, merged: false))))
    }

    /// En llamada la cabecera derecha lleva cinco botones (micro, camara, colgar,
    /// bateria, menu): tienen que caber con aire hasta el notch en el Air y los Pro.
    func testCallButtonsFitBesideTheNotch() {
        let screens: [(CGFloat, CGFloat, CGFloat)] = [
            (1470, 956, 645.5), // Air 13"
            (1512, 982, 662), // Pro 14"
            (1728, 1117, 770), // Pro 16"
        ]
        for (width, height, leftWidth) in screens {
            let notch: CGFloat = 190
            let metrics = NotchMetrics.make(
                screenFrame: CGRect(x: 0, y: 0, width: width, height: height), safeAreaTop: 32,
                auxiliaryTopLeft: CGRect(x: 0, y: height - 32, width: leftWidth, height: 32),
                auxiliaryTopRight: CGRect(x: leftWidth + notch, y: height - 32, width: width - leftWidth - notch, height: 32),
                visibleFrameMaxY: height - 33
            )
            let five = NotchMetrics.headerButton * 5 + NotchMetrics.callButtonSpacing * 4
            XCTAssertLessThanOrEqual(five + 8, metrics.headerSideWidth, "pantalla de \(width) pt")
            // Con la separacion normal no cabrian: por eso va mas junta en llamada.
            let wide = NotchMetrics.headerButton * 5 + NotchMetrics.headerButtonSpacing * 4
            XCTAssertGreaterThan(wide, metrics.headerSideWidth)
        }
    }
}
