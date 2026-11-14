import SwiftUI
import XCTest
@testable import Nook

/// Silueta del notch con esquinas inferiores continuas.
final class NotchShapeTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 300, height: 120)

    func testStaysInsideItsFrame() {
        for bottom: CGFloat in [0, 8, 20, 28, 80] {
            let box = NotchShape(topRadius: 14, bottomRadius: bottom).path(in: rect).boundingRect
            XCTAssertEqual(box.minX, rect.minX, accuracy: 0.01)
            XCTAssertEqual(box.maxX, rect.maxX, accuracy: 0.01)
            XCTAssertEqual(box.maxY, rect.maxY, accuracy: 0.01, "el borde de abajo llega al fondo (radio \(bottom))")
            XCTAssertLessThanOrEqual(box.maxY, rect.maxY + 0.01)
        }
    }

    /// La esquina continua recorta un poco mas que el arco circular cerca de los bordes
    /// y nunca sale fuera de el: no puede asomar por fuera del notch fisico.
    func testCornerIsInsideTheCircularOne() {
        let r: CGFloat = 28, top: CGFloat = 14
        let path = NotchShape(topRadius: top, bottomRadius: r).path(in: rect)
        XCTAssertTrue(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
        XCTAssertFalse(path.contains(CGPoint(x: top + 1, y: rect.maxY - 1)), "la esquina va recortada")
        // Puntos de la esquina circular por fuera del arco: tampoco estan en la continua.
        let center = CGPoint(x: top + r, y: rect.maxY - r)
        for degrees in stride(from: 95.0, through: 175.0, by: 10) {
            let angle = degrees * .pi / 180
            let outside = CGPoint(x: center.x + cos(angle) * (r + 0.5), y: center.y + sin(angle) * (r + 0.5))
            XCTAssertFalse(path.contains(outside), "\(degrees)°")
        }
    }

    func testOpenOutlineDoesNotClose() {
        let stroke = NotchShape(topRadius: 14, bottomRadius: 28, closesTop: false).path(in: rect)
        XCTAssertFalse(stroke.isEmpty)
    }
}
