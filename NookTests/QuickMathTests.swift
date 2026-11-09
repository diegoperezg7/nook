import XCTest
@testable import Nook

/// Cuentas y conversiones del lanzador.
final class QuickMathTests: XCTestCase {
    func testArithmetic() {
        XCTAssertEqual(QuickMath.evaluate("12*7+3"), 87)
        XCTAssertEqual(QuickMath.evaluate("(2+3)^2"), 25)
        XCTAssertEqual(QuickMath.evaluate("2,5 * 4"), 10)
        XCTAssertEqual(QuickMath.evaluate("-3 + 10 / 4"), -0.5)
        XCTAssertEqual(QuickMath.evaluate("15% de 80"), 12)
    }

    func testNotMath() {
        XCTAssertNil(QuickMath.evaluate("safari"))
        XCTAssertNil(QuickMath.evaluate("42"), "un numero solo no es una cuenta")
        XCTAssertNil(QuickMath.evaluate("2+"))
        XCTAssertNil(QuickMath.evaluate("1/0"), "infinito no se muestra")
    }

    func testUnits() {
        XCTAssertEqual(QuickMath.convert("10 km en mi")?.hasSuffix("mi"), true)
        XCTAssertEqual(QuickMath.convert("100 C en F").map { $0.hasPrefix("212") }, true)
        XCTAssertEqual(QuickMath.convert("1 kg to lb").map { $0.hasPrefix("2") }, true)
        XCTAssertNil(QuickMath.convert("10 km en kg"), "magnitudes distintas")
        XCTAssertNil(QuickMath.convert("hola mundo"))
    }
}
