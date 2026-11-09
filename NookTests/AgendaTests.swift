import AppKit
import XCTest
@testable import Nook

final class AgendaTests: XCTestCase {
    private func event(_ id: String, dayOffset: Int, hour: Int, hours: Int = 1, allDay: Bool = false) -> CalendarService.Event {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: .now))!
        let start = allDay ? day : cal.date(byAdding: .hour, value: hour, to: day)!
        let end = allDay ? cal.date(byAdding: .day, value: 1, to: day)! : cal.date(byAdding: .hour, value: hours, to: start)!
        return CalendarService.Event(id: id, title: id, start: start, end: end, isAllDay: allDay, color: .systemBlue)
    }

    /// El primer dia siempre sale; los vacios siguientes no. Todo el dia, primero.
    func testGroupsByDaySkippingEmptyOnes() {
        let events = [event("tarde", dayOffset: 0, hour: 18), event("fiesta", dayOffset: 0, hour: 0, allDay: true),
                      event("pasado", dayOffset: 2, hour: 9)]
        let agenda = CalendarService.groupByDay(events, from: .now, days: 4)
        XCTAssertEqual(agenda.count, 2)
        XCTAssertEqual(agenda[0].events.map(\.id), ["fiesta", "tarde"])
        XCTAssertEqual(agenda[1].events.map(\.id), ["pasado"])
        XCTAssertTrue(CalendarService.groupByDay([], from: .now, days: 4).count == 1, "hoy aunque este vacio")
    }

    /// Un evento que cruza la medianoche sale en los dos dias.
    func testOvernightEventInBothDays() {
        let overnight = event("viaje", dayOffset: 0, hour: 22, hours: 4)
        let agenda = CalendarService.groupByDay([overnight], from: .now, days: 4)
        XCTAssertEqual(agenda.map { $0.events.count }, [1, 1])
    }
}
