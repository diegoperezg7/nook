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

    /// Recientes del temporizador: la ultima primero, sin repetir, tres como mucho y
    /// guardadas para la proxima vez.
    @MainActor
    func testTimerRemembersRecentDurations() throws {
        XCTAssertEqual(FocusTimer.remember(300, in: [600, 1500, 90]), [300, 600, 1500])
        XCTAssertEqual(FocusTimer.remember(1500, in: [600, 1500, 90]), [1500, 600, 90])
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "nook-tests-recents"))
        defer { defaults.removePersistentDomain(forName: "nook-tests-recents") }
        let timer = FocusTimer(defaults: defaults)
        timer.start(seconds: 90)
        timer.start(minutes: 25)
        timer.stop()
        XCTAssertEqual(FocusTimer(defaults: defaults).recents, [1500, 90])
        timer.start(seconds: 0)
        XCTAssertFalse(timer.isRunning, "cero no arranca")
    }

    func testSettingsAreImportedFromNookOnceWithoutOnboarding() throws {
        let old = "com.diegoperez.nook.import-test", new = "com.diegoperez.visor.import-test"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: new))
        defer {
            defaults.removePersistentDomain(forName: new)
            defaults.removePersistentDomain(forName: old)
        }
        defaults.setPersistentDomain([SettingsKey.mailSource: "outlook", SettingsKey.onboardingDone: true], forName: old)
        SettingsKey.importFromNook(defaults, bundleID: new)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.mailSource), "outlook")
        XCTAssertNil(defaults.object(forKey: SettingsKey.onboardingDone))
        defaults.set("mail", forKey: SettingsKey.mailSource)
        SettingsKey.importFromNook(defaults, bundleID: new)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.mailSource), "mail", "solo la primera vez")
    }
}
