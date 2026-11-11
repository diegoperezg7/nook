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

    /// Hoy, lo que ya termino se va; lo que esta en curso, lo futuro y lo de todo el
    /// dia se quedan. Otro dia no se toca.
    func testTodayHidesFinishedEvents() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let now = cal.date(byAdding: .hour, value: 12, to: today)!
        func at(_ hour: Int, for hours: Int, id: String) -> CalendarService.Event {
            let start = cal.date(byAdding: .hour, value: hour, to: today)!
            return CalendarService.Event(id: id, title: id, start: start, end: cal.date(byAdding: .hour, value: hours, to: start)!, isAllDay: false, color: .systemBlue)
        }
        let allDay = CalendarService.Event(id: "fiesta", title: "fiesta", start: today, end: cal.date(byAdding: .day, value: 1, to: today)!, isAllDay: true, color: .systemBlue)
        let day = CalendarService.AgendaDay(day: today, events: [allDay, at(10, for: 1, id: "hace1h"), at(11, for: 2, id: "encurso"), at(15, for: 1, id: "tarde")])
        XCTAssertEqual(day.upcoming(at: now).events.map(\.id), ["fiesta", "encurso", "tarde"])
        // Justo al terminar ya no sale.
        XCTAssertEqual(day.upcoming(at: cal.date(byAdding: .hour, value: 13, to: today)!).events.map(\.id), ["fiesta", "tarde"])
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let past = CalendarService.AgendaDay(day: yesterday, events: [at(-14, for: 1, id: "ayer")])
        XCTAssertEqual(past.upcoming(at: now), past)
    }
}
