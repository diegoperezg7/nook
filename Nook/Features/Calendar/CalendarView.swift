import AppKit
import SwiftUI

/// Calendario: arriba se añade un evento escribiendo; debajo, el mes (con un punto
/// en los dias con algo) y lo que hay el dia elegido.
struct CalendarView: View {
    @Bindable var calendar: CalendarService
    @State private var draft = ""
    @State private var feedback: Feedback?
    @FocusState private var focused: Bool

    private enum Feedback: Equatable { case added(String), notUnderstood }

    var body: some View {
        VStack(spacing: 0) {
            if calendar.access == .granted {
                addField
                    .padding(.horizontal, NotchContentView.margin)
                    .frame(height: NotchMetrics.searchRowHeight - 10)
                    .padding(.bottom, 10)
                HStack(alignment: .top, spacing: 16) {
                    MonthGrid(calendar: calendar)
                        .frame(width: 196)
                    DayList(calendar: calendar)
                }
                .padding(.horizontal, NotchContentView.margin)
                .frame(height: NotchMetrics.cardRowHeight, alignment: .top)
            } else {
                accessPrompt
                    .padding(.top, NotchMetrics.searchRowHeight)
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 7) {
            Image(systemName: feedbackIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(feedback == .notUnderstood ? AppColors.warning : AppColors.accent)
                .contentTransition(.symbolEffect(.replace))
            if let feedback, draft.isEmpty {
                Text(feedbackText(feedback))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { self.feedback = nil; focused = true }
            } else {
                TextField("Añade un evento: «Café con Ana mañana a las 10»", text: $draft)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .focused($focused)
                    .onSubmit(add)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .liquidGlass(in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? AppColors.accent : .clear, lineWidth: 1.5))
        .animation(AppMotion.snappy, value: feedback)
    }

    private var feedbackIcon: String {
        switch feedback {
        case .added: return "checkmark.circle.fill"
        case .notUnderstood: return "questionmark.circle.fill"
        case nil: return "plus.circle.fill"
        }
    }

    private func feedbackText(_ feedback: Feedback) -> String {
        switch feedback {
        case let .added(summary): return String(localized: "Añadido: \(summary)")
        case .notUnderstood: return String(localized: "No encuentro la fecha. Prueba «mañana a las 10» o «el viernes»")
        }
    }

    private func add() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let event = calendar.add(text) {
            let when = event.isAllDay
                ? event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                : event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            feedback = .added("\(event.title), \(when)")
            draft = ""
        } else {
            feedback = .notUnderstood
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if draft.isEmpty { feedback = nil }
        }
    }

    private var accessPrompt: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return shape
            .fill(AppColors.accentWell)
            .overlay(shape.strokeBorder(AppColors.accentBorder, style: StrokeStyle(lineWidth: 1.25, dash: [6, 5])))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(AppColors.accent))
                    Text("Tus eventos, a un vistazo")
                        .font(AppTypography.title)
                        .foregroundStyle(AppColors.textPrimary)
                    Button {
                        calendar.access == .denied ? calendar.openPrivacySettings() : calendar.requestAccess()
                    } label: {
                        Text(calendar.access == .denied ? "Permitir en Ajustes del Sistema…" : "Permitir acceso al calendario")
                            .font(AppTypography.bodyStrong)
                            .foregroundStyle(AppColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: NotchMetrics.cardRowHeight)
            .padding(.horizontal, NotchContentView.margin)
    }
}

/// Mes con iniciales de los dias, punto en los dias con eventos, hoy con aro y el
/// elegido en azul.
private struct MonthGrid: View {
    @Bindable var calendar: CalendarService
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(verbatim: calendar.visibleMonth.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                arrow("chevron.left", -1)
                arrow("chevron.right", 1)
            }
            .frame(height: 16)
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 15) }
                }
            }
        }
    }

    private func arrow(_ icon: String, _ step: Int) -> some View {
        Button {
            withAnimation(AppMotion.snappy) {
                calendar.visibleMonth = Calendar.current.date(byAdding: .month, value: step, to: calendar.visibleMonth) ?? calendar.visibleMonth
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 18, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = Calendar.current.isDate(day, inSameDayAs: calendar.selectedDay)
        let today = Calendar.current.isDateInToday(day)
        return Button {
            withAnimation(AppMotion.snappy) { calendar.selectedDay = day }
        } label: {
            Text(verbatim: "\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 10, weight: selected || today ? .bold : .regular).monospacedDigit())
                .foregroundStyle(selected ? AppColors.onAccent : today ? AppColors.accent : AppColors.textPrimary)
                .frame(width: 22, height: 15)
                .background {
                    if selected { Capsule().fill(AppColors.accent) } else if today { Capsule().strokeBorder(AppColors.accent, lineWidth: 1) }
                }
                .overlay(alignment: .bottom) {
                    if calendar.busyDays.contains(day), !selected {
                        Circle().fill(AppColors.textSecondary).frame(width: 2.5, height: 2.5).offset(y: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Iniciales empezando por el primer dia de la semana del usuario (lunes en España).
    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Huecos vacios hasta el primer dia y luego los dias del mes.
    private var cells: [Date?] {
        let cal = Calendar.current
        let start = calendar.visibleMonth
        guard let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let offset = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let days = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: start) }
        return Array(repeating: nil, count: offset) + days
    }
}

/// Eventos del dia elegido.
private struct DayList: View {
    let calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColors.textSecondary)
                .frame(height: 16)
            if calendar.dayEvents.isEmpty {
                Text("Nada este día")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(calendar.dayEvents) { event in
                            EventRow(event: event) { calendar.openInCalendar(event) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 8)
    }

    private var title: String {
        if Calendar.current.isDateInToday(calendar.selectedDay) { return String(localized: "Hoy") }
        if Calendar.current.isDateInTomorrow(calendar.selectedDay) { return String(localized: "Mañana") }
        return calendar.selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized
    }
}

private struct EventRow: View {
    let event: CalendarService.Event
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Capsule().fill(Color(nsColor: event.color)).frame(width: 3, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: event.title)
                        .font(AppTypography.cardTitle.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(verbatim: time)
                        .font(AppTypography.cardCaption.monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(hovering ? AppColors.accent : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text("Abrir en Calendario"))
    }

    private var time: String {
        if event.isAllDay { return String(localized: "Todo el día") }
        let format = Date.FormatStyle.dateTime.hour().minute()
        return "\(event.start.formatted(format)) – \(event.end.formatted(format))"
    }
}
