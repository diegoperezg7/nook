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
        /// Enlace de videollamada (Zoom, Meet, Teams...) si el evento lo tiene.
        var meetingURL: URL? = nil
    }

    private(set) var access: Access = .unknown
    /// Dia elegido en la vista de mes (por defecto, hoy).
    var selectedDay = Calendar.current.startOfDay(for: .now) {
        didSet { reloadDay(); filterReminders() }
    }
    /// Mes que se ve (primer dia del mes).
    var visibleMonth = CalendarService.monthStart(of: .now) {
        didSet { reloadMonth() }
    }
    private(set) var dayEvents: [Event] = []
    /// Agenda: el dia elegido y los tres siguientes, solo los que tienen algo (el
    /// primero siempre, aunque este vacio).
    private(set) var agenda: [AgendaDay] = []

    struct AgendaDay: Identifiable, Equatable {
        var id: Date { day }
        let day: Date
        let events: [Event]

        /// Hoy, sin los eventos que ya terminaron (los de todo el dia se quedan).
        /// Los demas dias, tal cual: si miras ayer, ves lo que hubo.
        func upcoming(at now: Date) -> AgendaDay {
            guard Calendar.current.isDate(day, inSameDayAs: now) else { return self }
            return AgendaDay(day: day, events: events.filter { $0.isAllDay || $0.end > now })
        }
    }

    static let agendaDays = 4
    private(set) var todayEvents: [Event] = []
    /// Dias del mes visible que tienen algun evento.
    private(set) var busyDays: Set<Date> = []

    /// Calendarios del Mac agrupados por cuenta (iCloud, Exchange/Outlook, Google...).
    struct Account: Identifiable {
        let id: String
        let title: String
        let calendars: [Info]
    }
    struct Info: Identifiable {
        let id: String
        let title: String
        let color: NSColor
    }
    private(set) var accounts: [Account] = []
    /// Calendarios quitados en Ajustes (por defecto se ven todos).
    private(set) var hidden: Set<String> = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.hiddenCalendars) ?? [])

    func isVisible(_ id: String) -> Bool { !hidden.contains(id) }

    func setVisible(_ id: String, _ visible: Bool) {
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        UserDefaults.standard.set(Array(hidden), forKey: SettingsKey.hiddenCalendars)
        reloadAll()
    }

    // MARK: Recordatorios

    struct Reminder: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let color: NSColor
        var isOverdue: Bool { due.map { $0 < .now } ?? false }
    }

    private(set) var remindersAccess: Access = .unknown
    /// Pendientes del dia elegido (hoy: tambien los atrasados y los que no tienen fecha).
    private(set) var dayReminders: [Reminder] = []
    @ObservationIgnored private var allReminders: [Reminder] = []

    func requestRemindersAccess() {
        Task {
            _ = try? await store.requestFullAccessToReminders()
            updateAccess()
            reloadReminders()
        }
    }

    func complete(_ reminder: Reminder) {
        guard let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        try? store.save(item, commit: true)
        allReminders.removeAll { $0.id == reminder.id }
        filterReminders()
    }

    func openInReminders() {
        if let url = URL(string: "x-apple-reminderkit://") { NSWorkspace.shared.open(url) }
    }

    private func reloadReminders() {
        guard remindersAccess == .granted else { allReminders = []; dayReminders = []; return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let mapped = (reminders ?? []).map { reminder in
                Reminder(
                    id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                    due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                    color: reminder.calendar?.color ?? .systemOrange
                )
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.allReminders = mapped
                    self?.filterReminders()
                }
            }
        }
    }

    private func filterReminders() {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(selectedDay)
        let end = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        dayReminders = allReminders.filter { reminder in
            guard let due = reminder.due else { return isToday }
            return isToday ? due < end : calendar.isDate(due, inSameDayAs: selectedDay)
        }
        .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        .prefix(30)
        .map { $0 }
    }

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

    /// Reunion con enlace que empieza en 10 min o menos (o empezo hace menos de 5).
    func imminentMeeting(at now: Date = .now) -> Event? {
        todayEvents.first { event in
            guard !event.isAllDay, event.meetingURL != nil else { return false }
            let until = event.start.timeIntervalSince(now)
            return until <= 10 * 60 && until > -5 * 60
        }
    }

    func join(_ event: Event) {
        guard let url = event.meetingURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Proximo evento de hoy que aun no ha terminado.
    var nextEvent: Event? {
        todayEvents.first { !$0.isAllDay && $0.end > .now } ?? todayEvents.first { $0.isAllDay }
    }

    // MARK: - Alta rapida

    enum Added: Equatable {
        case event(Event)
        case reminder(title: String, due: Date?)
    }

    /// Una frase se convierte en evento si tiene fecha; sin fecha, o si empieza por
    /// "recuérdame" / "recordatorio", en recordatorio.
    @discardableResult
    func addAnything(_ sentence: String) -> Added? {
        let (isReminder, rest) = QuickEventParser.reminderIntent(sentence)
        let parsed = QuickEventParser.parse(rest)
        if isReminder || parsed == nil {
            // Sin permiso de recordatorios: si hay fecha, al menos se crea el evento.
            guard remindersAccess == .granted else { return parsed == nil ? nil : add(rest).map(Added.event) }
            let title = parsed?.title ?? rest.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let due = parsed?.start
            guard addReminder(title: title, due: due, allDay: parsed?.isAllDay ?? true) else { return nil }
            return .reminder(title: title, due: due)
        }
        return add(rest).map(Added.event)
    }

    private func addReminder(title: String, due: Date?, allDay: Bool) -> Bool {
        guard let list = store.defaultCalendarForNewReminders() else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            var components: Set<Calendar.Component> = [.year, .month, .day]
            if !allDay { components.formUnion([.hour, .minute]) }
            reminder.dueDateComponents = Calendar.current.dateComponents(components, from: due)
            if !allDay { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        guard (try? store.save(reminder, commit: true)) != nil else { return false }
        reloadReminders()
        return true
    }

    /// Crea un evento a partir de una frase. Devuelve el evento o nil si no se
    /// encontro una fecha en el texto.
    @discardableResult
    func add(_ sentence: String) -> Event? {
        guard access == .granted, let parsed = QuickEventParser.parse(sentence),
              let calendar = calendarForNewEvents else { return nil }
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
        access = Self.access(for: .event)
        remindersAccess = Self.access(for: .reminder)
    }

    private static func access(for type: EKEntityType) -> Access {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .unknown
        default: return .denied
        }
    }

    /// El calendario por defecto si se ve; si no, el primero visible que se pueda editar.
    private var calendarForNewEvents: EKCalendar? {
        if let preferred = store.defaultCalendarForNewEvents, isVisible(preferred.calendarIdentifier) { return preferred }
        return store.calendars(for: .event).first { isVisible($0.calendarIdentifier) && $0.allowsContentModifications }
            ?? store.defaultCalendarForNewEvents
    }

    private func reloadAccounts() {
        let calendars = store.calendars(for: .event)
        let grouped = Dictionary(grouping: calendars) { $0.source?.sourceIdentifier ?? "" }
        accounts = grouped.compactMap { _, calendars in
            guard let source = calendars.first?.source else { return nil }
            let title = source.sourceType == .exchange ? String(localized: "Outlook / Exchange · \(source.title)") : source.title
            return Account(
                id: source.sourceIdentifier, title: title,
                calendars: calendars
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    .map { Info(id: $0.calendarIdentifier, title: $0.title, color: $0.color ?? .controlAccentColor) }
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func reloadAll() {
        reloadReminders()
        guard access == .granted else { return }
        reloadAccounts()
        let today = Calendar.current.startOfDay(for: .now)
        todayEvents = events(from: today, to: Calendar.current.date(byAdding: .day, value: 1, to: today)!)
        reloadDay()
        reloadMonth()
    }

    private func reloadDay() {
        guard access == .granted else { return }
        dayEvents = events(from: selectedDay, to: Calendar.current.date(byAdding: .day, value: 1, to: selectedDay)!)
        let end = Calendar.current.date(byAdding: .day, value: Self.agendaDays, to: selectedDay)!
        agenda = Self.groupByDay(events(from: selectedDay, to: end), from: selectedDay, days: Self.agendaDays)
        #if DEBUG
        // `-VisorDemoEvents YES`: eventos de ejemplo de hoy, sin tocar el calendario real.
        if UserDefaults.standard.bool(forKey: "VisorDemoEvents") {
            let now = Date.now, today = Calendar.current.startOfDay(for: now)
            func demo(_ title: String, _ from: TimeInterval, _ hours: TimeInterval, allDay: Bool = false) -> Event {
                let start = allDay ? today : now.addingTimeInterval(from * 3600)
                return Event(id: title, title: title, start: start, end: allDay ? today.addingTimeInterval(86400) : start.addingTimeInterval(hours * 3600), isAllDay: allDay, color: .systemBlue)
            }
            let events = [demo("Terminó hace 1 h", -2, 1), demo("En curso", -0.5, 1), demo("Esta tarde", 3, 1), demo("Todo el día", 0, 0, allDay: true)]
            agenda = Self.groupByDay(events, from: selectedDay, days: Self.agendaDays)
        }
        #endif
    }

    /// Agrupa por dia de inicio (los de varios dias salen en cada dia que tocan).
    nonisolated static func groupByDay(_ events: [Event], from start: Date, days: Int) -> [AgendaDay] {
        let cal = Calendar.current
        return (0..<days).compactMap { offset in
            let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: start))!
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            let list = events.filter { $0.start < next && $0.end > day }
                .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
            return offset == 0 || !list.isEmpty ? AgendaDay(day: day, events: list) : nil
        }
    }

    private func reloadMonth() {
        guard access == .granted,
              let end = Calendar.current.date(byAdding: .month, value: 1, to: visibleMonth) else { return }
        busyDays = Set(events(from: visibleMonth, to: end).flatMap { event in
            Self.days(from: event.start, to: event.end)
        })
    }

    private func events(from start: Date, to end: Date) -> [Event] {
        // Sin filtro (nil) se ven todos; si el usuario quito todos, nada.
        var calendars: [EKCalendar]?
        if !hidden.isEmpty {
            calendars = store.calendars(for: .event).filter { isVisible($0.calendarIdentifier) }
            if calendars?.isEmpty == true { return [] }
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
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
            color: event.calendar?.color ?? .controlAccentColor,
            meetingURL: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
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

    /// "Recuérdame llamar a Ana mañana" -> (true, "llamar a Ana mañana").
    static func reminderIntent(_ sentence: String) -> (Bool, String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["recuérdame que ", "recuérdame ", "recuerdame que ", "recuerdame ", "recordatorio: ", "recordatorio ", "remind me to ", "remind me "]
        where text.lowercased().hasPrefix(prefix) {
            return (true, String(text.dropFirst(prefix.count)))
        }
        return (false, text)
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

/// Busca un enlace de videollamada en los campos de un evento.
enum MeetingLink {
    private static let hosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "facetime.apple.com", "meet.jit.si", "around.co",
    ]

    static func find(in fields: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for field in fields.compactMap({ $0 }) {
            let matches = detector.matches(in: field, range: NSRange(field.startIndex..., in: field))
            for match in matches {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}
