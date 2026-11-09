import AppKit
import XCTest
@testable import Nook

/// Agitar el raton arrastrando archivos abre la cesta; moverlo normal, no.
@MainActor
final class ShakeDetectorTests: XCTestCase {
    private func run(_ xs: [CGFloat], every step: TimeInterval = 0.03) -> Int {
        let detector = ShakeDetector()
        var shakes = 0
        detector.onShake = { _ in shakes += 1 }
        detector.simulateFileDrag()
        let start = Date.now
        for (index, x) in xs.enumerated() {
            detector.moved(to: NSPoint(x: x, y: 300), at: start.addingTimeInterval(Double(index) * step))
        }
        return shakes
    }

    /// Ida y vuelta de 80 pt varias veces.
    private var shake: [CGFloat] {
        var xs: [CGFloat] = []
        for swing in 0..<5 {
            let range = stride(from: 0, through: 80, by: 20).map(CGFloat.init)
            xs += (swing.isMultiple(of: 2) ? range : range.reversed()).map { $0 + 400 }
        }
        return xs
    }

    func testShakeOpensOnce() {
        XCTAssertEqual(run(shake), 1)
    }

    func testStraightDragDoesNothing() {
        XCTAssertEqual(run(stride(from: 0, through: 600, by: 10).map(CGFloat.init)), 0)
    }

    func testSmallJitterDoesNothing() {
        XCTAssertEqual(run([400, 410, 400, 410, 400, 410, 400, 410, 400]), 0)
    }

    func testSlowSwingsDoNothing() {
        XCTAssertEqual(run(shake, every: 0.3), 0)
    }
}
