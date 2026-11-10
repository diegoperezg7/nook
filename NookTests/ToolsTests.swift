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

    @MainActor
    func testTimerPausesAndResumes() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "nook-tests-timer"))
        defer { defaults.removePersistentDomain(forName: "nook-tests-timer") }
        let timer = FocusTimer(defaults: defaults)
        timer.start(minutes: 10)
        timer.pause()
        XCTAssertFalse(timer.isRunning)
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(try XCTUnwrap(timer.pausedRemaining), 600, accuracy: 2)
        timer.resume()
        XCTAssertTrue(timer.isRunning)
        XCTAssertFalse(timer.isPaused)
        XCTAssertEqual(try XCTUnwrap(timer.end).timeIntervalSinceNow, 600, accuracy: 2)
        timer.stop()
        XCTAssertFalse(timer.isRunning || timer.isPaused)
    }
}
