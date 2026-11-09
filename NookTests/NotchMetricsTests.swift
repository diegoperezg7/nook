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
}
