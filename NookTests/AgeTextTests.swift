import XCTest
@testable import Nook

/// Segundos solo el primer minuto; despues, minutos u horas sin segundos.
final class AgeTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let spanish = Locale(identifier: "es_ES")

    private func age(_ seconds: TimeInterval) -> String {
        AgeText.format(now.addingTimeInterval(-seconds), now: now, locale: spanish)
    }

    func testShowsSecondsDuringTheFirstMinute() {
        XCTAssertEqual(age(20), "hace 20 s")
    }

    func testShowsWholeMinutesAfterwards() {
        XCTAssertEqual(age(5 * 60 + 37), "hace 5 min")
    }

    func testShowsHours() {
        XCTAssertEqual(age(2 * 3600 + 120), "hace 2 h")
    }
}
