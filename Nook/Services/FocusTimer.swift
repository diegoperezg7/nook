import AppKit
import IOKit.pwr_mgt
import Observation

/// Temporizador (Pomodoro) y "Mantener despierto". Mientras estan activos se ven
/// en el notch cerrado; al acabar el temporizador suena y avisa.
@Observable
@MainActor
final class FocusTimer {
    private(set) var end: Date?
    private(set) var total: TimeInterval = 0
    /// Mantener despierto: activo y hasta cuando (nil = hasta que se pare).
    private(set) var isAwake = false
    private(set) var awakeUntil: Date?

    /// Se llama al terminar el temporizador.
    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var finishWork: DispatchWorkItem?
    @ObservationIgnored private var awakeWork: DispatchWorkItem?
    @ObservationIgnored private var assertion = IOPMAssertionID(0)

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
