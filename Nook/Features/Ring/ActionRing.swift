import AppKit
import SwiftUI

/// Anillo de acciones: con un atajo aparece alrededor del cursor un circulo de
/// herramientas y, en el centro, el tiempo y el uso del Mac. Escape o un clic fuera
/// lo cierran.
@MainActor
final class ActionRingController {
    struct Action: Identifiable {
        let id: String
        let title: String
        let icon: String
        let run: () -> Void
    }

    var actions: [Action] = []
    let weather: Weather
    private var panel: RingPanel?
    private var outsideClick: Any?

    static let size = CGSize(width: 320, height: 320)

    init(weather: Weather) {
        self.weather = weather
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show(at: NSEvent.mouseLocation) }
    }

    func show(at point: NSPoint) {
        weather.refreshIfNeeded()
        let panel = self.panel ?? RingPanel()
        panel.onCancel = { [weak self] in self?.hide() }
        self.panel = panel
        panel.contentView = NSHostingView(rootView: RingView(actions: actions, weather: weather) { [weak self] action in
            self?.hide()
            // Que el anillo se haya ido antes de, por ejemplo, la seleccion de pantalla.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { action.run() }
        })
        let size = Self.size
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let frame = screen.frame
            origin.x = min(max(origin.x, frame.minX), frame.maxX - size.width)
            origin.y = min(max(origin.y, frame.minY), frame.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
    }
}

/// Panel sin bordes que si recibe teclado (Escape) sin activar la app.
final class RingPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private struct RingView: View {
    let actions: [ActionRingController.Action]
    let weather: Weather
    let onPick: (ActionRingController.Action) -> Void

    @State private var appeared = false
    @State private var hovered: String?
    @State private var stats = SystemStats.read()

    private let radius: CGFloat = 104

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.floating)
                .overlay(Circle().strokeBorder(AppColors.notchText.opacity(0.12), lineWidth: 1))
                .frame(width: 2 * radius + 72, height: 2 * radius + 72)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)

            center
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)

            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                let angle = Angle.degrees(-90 + 360 * Double(index) / Double(max(actions.count, 1)))
                RingButton(action: action, hovered: $hovered) { onPick(action) }
                    .offset(x: appeared ? cos(angle.radians) * radius : 0,
                            y: appeared ? sin(angle.radians) * radius : 0)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
                    .animation(AppMotion.reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72).delay(Double(index) * 0.025), value: appeared)
            }
        }
        .frame(width: ActionRingController.size.width, height: ActionRingController.size.height)
        .animation(AppMotion.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: appeared)
        .onAppear { appeared = true }
        .task {
            // Segunda lectura para que la CPU sea el uso de este momento.
            try? await Task.sleep(for: .milliseconds(500))
            stats = SystemStats.read()
        }
    }

    /// Centro: la accion bajo el raton o, si no, tiempo y uso del Mac.
    @ViewBuilder
    private var center: some View {
        VStack(spacing: 5) {
            if let hovered, let action = actions.first(where: { $0.id == hovered }) {
                Text(verbatim: action.title)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.notchText)
                    .multilineTextAlignment(.center)
                    .frame(width: 96)
                    .transition(.opacity)
            } else {
                if let current = weather.current {
                    HStack(spacing: 4) {
                        Image(systemName: current.symbol).symbolRenderingMode(.multicolor)
                        Text(verbatim: "\(Int(current.temperature.rounded()))°")
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(AppColors.notchText)
                    Text(verbatim: current.city)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppColors.notchText.opacity(0.6))
                        .lineLimit(1)
                        .frame(width: 90)
                } else {
                    Text(Date.now, format: .dateTime.hour().minute())
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppColors.notchText)
                }
                VStack(spacing: 2) {
                    statLine("cpu", value: stats.cpu, warn: stats.cpu > 0.85)
                    statLine("memorychip", value: stats.memory, warn: stats.memory > 0.9)
                    if let battery = stats.battery {
                        statLine("battery.75percent", value: Double(battery) / 100, warn: battery <= 20)
                    }
                }
            }
        }
        .animation(AppMotion.snappy, value: hovered)
    }

    /// Ambar cuando algo pide atencion (CPU o memoria altas, poca bateria).
    private func statLine(_ icon: String, value: Double, warn: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8, weight: .semibold)).frame(width: 12)
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.notchText.opacity(0.15))
                Capsule().fill(warn ? AppColors.warning : AppColors.notchText.opacity(0.85))
                    .frame(width: max(2, 40 * value))
            }
            .frame(width: 40, height: 4)
            Text(verbatim: "\(Int((value * 100).rounded())) %")
                .font(.system(size: 8, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .frame(width: 30, alignment: .trailing)
        }
        .foregroundStyle(AppColors.notchText.opacity(0.75))
    }
}

private struct RingButton: View {
    let action: ActionRingController.Action
    @Binding var hovered: String?
    let onTap: () -> Void

    private var isHovered: Bool { hovered == action.id }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: action.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isHovered ? AppColors.onAccent : AppColors.notchText)
                .frame(width: 50, height: 50)
                .background(Circle().fill(isHovered ? AppColors.accent : AppColors.notchText.opacity(0.1)))
                .scaleEffect(isHovered && !AppMotion.reduceMotion ? 1.12 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = action.id } else if hovered == action.id { hovered = nil }
        }
        .animation(AppMotion.snappy, value: isHovered)
        .accessibilityLabel(Text(verbatim: action.title))
    }
}
