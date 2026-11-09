import AppKit
import EventKit
import Observation

/// Calendario del Mac (EventKit): eventos de hoy, de cualquier dia del mes y alta
/// rapida escribiendo en lenguaje natural ("Cafe con Ana mañana a las 10").
@Observable
@MainActor
final class CalendarService {
    enum Access: Equatable { case unknown, granted, denied }

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: NSColor
    }

    private(set) var access: Access = .unknown
    /// Dia elegido en la vista de mes (por defecto, hoy).
    var selectedDay = Calendar.current.startOfDay(for: .now) {
        didSet { reloadDay() }
    }
    /// Mes que se ve (primer dia del mes).
    var visibleMonth = CalendarService.monthStart(of: .now) {
        didSet { reloadMonth() }
    }
    private(set) var dayEvents: [Event] = []
    private(set) var todayEvents: [Event] = []
    /// Dias del mes visible que tienen algun evento.
    private(set) var busyDays: Set<Date> = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    func start() {
        updateAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadAll() }
        }
        reloadAll()
    }

    /// Pide permiso (la primera vez macOS muestra el dialogo).
    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            updateAccess()
            reloadAll()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Proximo evento de hoy que aun no ha terminado.
    var nextEvent: Event? {
        todayEvents.first { !$0.isAllDay && $0.end > .now } ?? todayEvents.first { $0.isAllDay }
    }

    // MARK: - Alta rapida

    /// Crea un evento a partir de una frase. Devuelve el evento o nil si no se
    /// encontro una fecha en el texto.
    @discardableResult
    func add(_ sentence: String) -> Event? {
        guard access == .granted, let parsed = QuickEventParser.parse(sentence),
              let calendar = store.defaultCalendarForNewEvents else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = parsed.title
        event.startDate = parsed.start
        event.endDate = parsed.end
        event.isAllDay = parsed.isAllDay
        event.calendar = calendar
        guard (try? store.save(event, span: .thisEvent)) != nil else { return nil }
        selectedDay = Calendar.current.startOfDay(for: parsed.start)
        visibleMonth = Self.monthStart(of: parsed.start)
        reloadAll()
        return Self.map(event)
    }

    func openInCalendar(_ event: Event) {
        // ical:// abre la app Calendario en la fecha del evento.
        let seconds = Int(event.start.timeIntervalSinceReferenceDate)
        if let url = URL(string: "ical://ekevent/\(event.id)?method=show&options=more"),
           NSWorkspace.shared.open(url) { return }
        if let url = URL(string: "x-apple-calevent://\(seconds)") { NSWorkspace.shared.open(url) }
    }

    // MARK: - Carga

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    private func reloadAll() {
        guard access == .granted else { return }
        let today = Calendar.current.startOfDay(for: .now)
        todayEvents = events(from: today, to: Calendar.current.date(byAdding: .day, value: 1, to: today)!)
        reloadDay()
        reloadMonth()
    }

    private func reloadDay() {
        guard access == .granted else { return }
        dayEvents = events(from: selectedDay, to: Calendar.current.date(byAdding: .day, value: 1, to: selectedDay)!)
    }

    private func reloadMonth() {
        guard access == .granted,
              let end = Calendar.current.date(byAdding: .month, value: 1, to: visibleMonth) else { return }
        busyDays = Set(events(from: visibleMonth, to: end).flatMap { event in
            Self.days(from: event.start, to: event.end)
        })
    }

    private func events(from start: Date, to end: Date) -> [Event] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map(Self.map)
    }

    private static func map(_ event: EKEvent) -> Event {
        Event(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "",
            start: event.startDate, end: event.endDate,
            isAllDay: event.isAllDay,
            color: event.calendar?.color ?? .controlAccentColor
        )
    }

    nonisolated static func monthStart(of date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Dias (a las 0:00) que toca un evento; el final es exclusivo.
    nonisolated static func days(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end > start ? end.addingTimeInterval(-1) : start)
        var result: [Date] = []
        while day <= last, result.count < 62 {
            result.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }
}

/// Convierte una frase en un evento: la fecha la detecta NSDataDetector (entiende
/// "mañana a las 10", "el viernes", "12/11 18:30"...) y el resto es el titulo.
enum QuickEventParser {
    struct Parsed: Equatable {
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    static func parse(_ sentence: String, now: Date = .now) -> Parsed? {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let detected = match.date,
              let range = Range(match.range, in: text) else { return nil }

        var title = text
        title.removeSubrange(range)
        var date = detected
        let calendar = Calendar.current
        let matchedText = String(text[range])
        let timePattern = #"(?:\b(?:a las|a la|at)\s+)(\d{1,2})(?:[:.](\d{2}))?\s*(h|am|pm)?\b"#
        let explicitTime = matchedText.range(of: #"\d{1,2}[:.]\d{2}|\d\s*(h|am|pm)\b|a las|a la|\bat\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        var hasTime = explicitTime
        // "el 14 de noviembre a las 21h": el detector se queda con la fecha y deja la
        // hora en el resto de la frase.
        if !explicitTime, let regex = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive),
           let found = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           let hourRange = Range(found.range(at: 1), in: title), var hour = Int(title[hourRange]) {
            let minute = Range(found.range(at: 2), in: title).flatMap { Int(title[$0]) } ?? 0
            let suffix = Range(found.range(at: 3), in: title).map { title[$0].lowercased() }
            if suffix == "pm", hour < 12 { hour += 12 }
            if suffix == "am", hour == 12 { hour = 0 }
            if hour < 24, minute < 60, let fixed = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) {
                date = fixed
                hasTime = true
                if let whole = Range(found.range, in: title) { title.removeSubrange(whole) }
            }
        }
        title = title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // Restos tipicos al quitar la fecha: "Cafe con Ana el" -> "Cafe con Ana".
        for tail in [" el", " la", " a las", " a la", " de", " para", " on", " at"] where title.lowercased().hasSuffix(tail) {
            title = String(title.dropLast(tail.count)).trimmingCharacters(in: .whitespaces)
        }
        if title.isEmpty { title = String(localized: "Evento") }

        // Sin hora en la frase es un evento de dia completo.
        if !hasTime {
            let day = calendar.startOfDay(for: date)
            return Parsed(title: title, start: day, end: calendar.date(byAdding: .day, value: 1, to: day)!, isAllDay: true)
        }
        let duration = match.duration > 0 ? match.duration : 3600
        return Parsed(title: title, start: date, end: date.addingTimeInterval(duration), isAllDay: false)
    }
}
