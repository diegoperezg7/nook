import AppKit

/// Detecta que el usuario agita el raton mientras arrastra archivos (en cualquier
/// app): tres cambios de sentido rapidos y amplios. Los monitores globales de raton
/// no necesitan permiso de Accesibilidad.
@MainActor
final class ShakeDetector {
    var onShake: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    /// Recorrido minimo de cada tramo y tiempo maximo para los tres cambios.
    static let minSwing: CGFloat = 40
    static let window: TimeInterval = 0.8
    static let reversalsNeeded = 3

    private var monitors: [Any] = []
    private var dragCountAtDown = 0
    private var isFileDrag: Bool?
    private var fired = false
    private var direction: CGFloat = 0
    private var extreme: CGFloat = 0
    private var segmentStart: CGFloat = 0
    private var reversals: [Date] = []
    private var started = false

    func start() {
        guard monitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
        let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.moved(to: NSEvent.mouseLocation, at: .now) }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDragEnded?() }
        }
        monitors = [down, drag, up].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func reset() {
        dragCountAtDown = NSPasteboard(name: .drag).changeCount
        isFileDrag = nil
        fired = false
        direction = 0
        reversals = []
        started = false
    }

    /// Solo cuenta si lo que se arrastra son archivos (el portapapeles de arrastre
    /// cambia al empezar un arrastre nuevo).
    private var draggingFiles: Bool {
        if let isFileDrag { return isFileDrag }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragCountAtDown else { return false }
        let result = pasteboard.types?.contains(.fileURL) == true
        isFileDrag = result
        return result
    }

    func moved(to point: NSPoint, at time: Date) {
        guard !fired, draggingFiles else { return }
        let x = point.x
        guard started else {
            started = true
            extreme = x
            segmentStart = x
            return
        }
        if direction == 0 {
            if abs(x - segmentStart) > 4 {
                direction = x > segmentStart ? 1 : -1
                extreme = x
            }
            return
        }
        if (x - extreme) * direction > 0 {
            extreme = x
        } else if abs(x - extreme) > 12 {
            // Cambio de sentido: cuenta si el tramo anterior fue amplio.
            if abs(extreme - segmentStart) >= Self.minSwing { reversals.append(time) }
            reversals.removeAll { time.timeIntervalSince($0) > Self.window }
            segmentStart = extreme
            extreme = x
            direction = -direction
            if reversals.count >= Self.reversalsNeeded {
                fired = true
                onShake?(point)
            }
        }
    }

    /// Para los tests: empieza un arrastre de archivos sin mirar el portapapeles.
    func simulateFileDrag() {
        reset()
        isFileDrag = true
    }
}
