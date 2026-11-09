import XCTest
@testable import Nook

/// Colocaciones de ventana: marcos dentro del area util y paso a coordenadas AX.
final class WindowLayoutTests: XCTestCase {
    // Pantalla de 1512x982 con barra de menus de 37 y Dock de 70 abajo.
    private let area = CGRect(x: 0, y: 70, width: 1512, height: 875)
    private let current = CGRect(x: 100, y: 200, width: 800, height: 600)

    func testHalvesCoverTheArea() {
        let left = WindowLayout.leftHalf.frame(in: area, current: current)
        let right = WindowLayout.rightHalf.frame(in: area, current: current)
        XCTAssertEqual(left, CGRect(x: 0, y: 70, width: 756, height: 875))
        XCTAssertEqual(left.union(right), area)
    }

    func testQuartersAndThirds() {
        XCTAssertEqual(WindowLayout.topLeft.frame(in: area, current: current), CGRect(x: 0, y: 508, width: 756, height: 438))
        let thirds = [WindowLayout.leftThird, .centerThird, .rightThird].map { $0.frame(in: area, current: current) }
        XCTAssertEqual(thirds[0].width, 504)
        XCTAssertEqual(thirds[2].maxX, area.maxX)
    }

    func testCenterKeepsTheSize() {
        let centered = WindowLayout.center.frame(in: area, current: current)
        XCTAssertEqual(centered.size, current.size)
        XCTAssertEqual(centered.midX, area.midX, accuracy: 1)
    }

    func testCocoaToAX() {
        // Arriba del todo en Cocoa = y 37 (bajo la barra) en AX.
        let top = CGRect(x: 0, y: 945 - 100, width: 200, height: 100)
        XCTAssertEqual(WindowLayout.toAX(top, primaryHeight: 982).minY, 37)
    }
}
