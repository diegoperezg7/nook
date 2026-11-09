import AppKit
import IOKit.pwr_mgt
import Observation

/// Temporizador (Pomodoro), alarmas y "Mantener despierto". Mientras estan activos
/// se ven en el notch cerrado; al acabar el temporizador o llegar una alarma suena.
@Observable
@MainActor
final class FocusTimer {
    private(set) var end: Date?
    private(set) var total: TimeInterval = 0
    /// Mantener despierto: activo y hasta cuando (nil = hasta que se pare).
    private(set) var isAwake = false
    private(set) var awakeUntil: Date?
    /// Alarmas pendientes, ordenadas. Se guardan para sobrevivir a un reinicio.
    private(set) var alarms: [Date] = []
    /// Alarma que esta sonando ahora (hasta que se abre el notch o pasa un minuto).
    private(set) var ringing: Date?

    /// Se llama al terminar el temporizador.
    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var finishWork: DispatchWorkItem?
    @ObservationIgnored private var awakeWork: DispatchWorkItem?
    @ObservationIgnored private var assertion = IOPMAssertionID(0)
    @ObservationIgnored private var alarmWork: [Date: DispatchWorkItem] = [:]
    @ObservationIgnored private var sound: NSSound?
    @ObservationIgnored private let defaults: UserDefaults
    private static let alarmsKey = "alarms"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = (defaults.array(forKey: Self.alarmsKey) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
        for date in saved where date > .now { schedule(date) }
        save()
    }

    static let timerPresets = [5, 15, 25, 45, 60]
    static let awakePresets = [30, 60, 120]

    var isRunning: Bool { end != nil }

    func start(minutes: Int) {
        stop()
        total = TimeInterval(minutes * 60)
        end = Date.now.addingTimeInterval(total)
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + total, execute: work)
    }

    func stop() {
        finishWork?.cancel()
        finishWork = nil
        end = nil
    }

    private func finish() {
        end = nil
        NSSound(named: "Glass")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        onFinish?()
    }

    // MARK: - Alarmas

    /// Proxima vez que el reloj marca esa hora (hoy o mañana).
    static func nextOccurrence(of time: Date, after now: Date = .now) -> Date {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return Calendar.current.nextDate(after: now, matching: DateComponents(hour: parts.hour, minute: parts.minute, second: 0), matchingPolicy: .nextTime) ?? time
    }

    func addAlarm(at time: Date) {
        let date = Self.nextOccurrence(of: time)
        guard !alarms.contains(date) else { return }
        schedule(date)
        save()
    }

    func removeAlarm(_ date: Date) {
        alarmWork.removeValue(forKey: date)?.cancel()
        alarms.removeAll { $0 == date }
        save()
    }

    /// Para el sonido de la alarma (al abrir el notch o al minuto).
    func silence() {
        guard ringing != nil else { return }
        sound?.stop()
        sound = nil
        ringing = nil
    }

    private func schedule(_ date: Date) {
        alarms.append(date)
        alarms.sort()
        let work = DispatchWorkItem { [weak self] in self?.ring(date) }
        alarmWork[date] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, date.timeIntervalSinceNow), execute: work)
    }

    private func ring(_ date: Date) {
        alarmWork[date] = nil
        alarms.removeAll { $0 == date }
        save()
        silence()
        ringing = date
        let sound = NSSound(named: "Radar") ?? NSSound(named: "Glass")
        sound?.loops = true
        sound?.play()
        self.sound = sound
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            if self?.ringing == date { self?.silence() }
        }
    }

    private func save() {
        defaults.set(alarms.map(\.timeIntervalSince1970), forKey: Self.alarmsKey)
    }

    /// Impide que la pantalla se apague (y el Mac se duerma) durante `minutes`, o
    /// hasta que se pare si es nil.
    func stayAwake(minutes: Int?) {
        stopAwake()
        let reason = "Nook: mantener despierto" as CFString
        guard IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion
        ) == kIOReturnSuccess else { return }
        isAwake = true
        guard let minutes else { awakeUntil = nil; return }
        awakeUntil = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        let work = DispatchWorkItem { [weak self] in self?.stopAwake() }
        awakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(minutes * 60), execute: work)
    }

    func stopAwake() {
        awakeWork?.cancel()
        awakeWork = nil
        if isAwake { IOPMAssertionRelease(assertion) }
        isAwake = false
        awakeUntil = nil
    }
}
