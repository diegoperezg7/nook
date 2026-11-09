import XCTest
@testable import Nook

/// Herramientas del anillo: uso del Mac y tiempo.
final class ToolsTests: XCTestCase {
    func testStatsAreFractions() {
        _ = SystemStats.read()
        let stats = SystemStats.read()
        XCTAssertTrue((0...1).contains(stats.cpu))
        XCTAssertTrue((0.01...1).contains(stats.memory), "algo de memoria esta en uso")
        XCTAssertGreaterThan(stats.diskFree, 0)
    }

    func testWeatherSymbols() {
        func symbol(_ code: Int) -> String { Weather.Current(temperature: 20, code: code, city: "X").symbol }
        XCTAssertEqual(symbol(0), "sun.max.fill")
        XCTAssertEqual(symbol(63), "cloud.rain.fill")
        XCTAssertEqual(symbol(73), "cloud.snow.fill")
        XCTAssertEqual(symbol(95), "cloud.bolt.rain.fill")
    }
}
