import XCTest
@testable import Nook

/// Alta rapida de eventos escribiendo en lenguaje natural.
final class QuickEventParserTests: XCTestCase {
    private func hour(_ date: Date) -> (Int, Int) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? -1, parts.minute ?? -1)
    }

    func testTomorrowAtTen() throws {
        let event = try XCTUnwrap(QuickEventParser.parse("Café con Ana mañana a las 10"))
        XCTAssertEqual(event.title, "Café con Ana")
        XCTAssertFalse(event.isAllDay)
        XCTAssertTrue(Calendar.current.isDateInTomorrow(event.start))
        XCTAssertTrue(hour(event.start) == (10, 0))
        XCTAssertEqual(event.end.timeIntervalSince(event.start), 3600, "una hora por defecto")
    }

    func testWeekdayWithMinutes() throws {
        let event = try XCTUnwrap(QuickEventParser.parse("Dentista el viernes a las 17:30"))
        XCTAssertEqual(event.title, "Dentista")
        XCTAssertEqual(Calendar.current.component(.weekday, from: event.start), 6)
        XCTAssertTrue(hour(event.start) == (17, 30))
    }

    func testDateWithTheTimeApart() throws {
        let event = try XCTUnwrap(QuickEventParser.parse("Cena con Laura el 14 de noviembre a las 21h"))
        XCTAssertEqual(event.title, "Cena con Laura")
        XCTAssertEqual(Calendar.current.component(.day, from: event.start), 14)
        XCTAssertTrue(hour(event.start) == (21, 0))
    }

    func testWithoutTimeIsAllDay() throws {
        let event = try XCTUnwrap(QuickEventParser.parse("Llamar a mamá pasado mañana"))
        XCTAssertEqual(event.title, "Llamar a mamá")
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.start, Calendar.current.startOfDay(for: event.start))
    }

    func testEnglish() throws {
        let event = try XCTUnwrap(QuickEventParser.parse("Lunch with Tom tomorrow at 1pm"))
        XCTAssertEqual(event.title, "Lunch with Tom")
        XCTAssertTrue(hour(event.start) == (13, 0))
    }

    func testNoDateNoEvent() {
        XCTAssertNil(QuickEventParser.parse("Comprar leche"))
        XCTAssertNil(QuickEventParser.parse("   "))
    }

    func testMultiDayEventMarksEveryDay() {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 22))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 0))!
        XCTAssertEqual(CalendarService.days(from: start, to: end).count, 2, "el final es exclusivo")
    }
}
