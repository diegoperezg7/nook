import AppKit
import EventKit
import ServiceManagement
import SwiftUI

/// Estado de los permisos que no avisan al cambiar (Accesibilidad y Acceso total al
/// disco): se vuelven a leer al volver a Nook desde Ajustes del Sistema.
@Observable
@MainActor
final class PermissionState {
    private(set) var accessibility = AXAccess.isTrusted
    private(set) var fullDiskAccess = PermissionState.readsNotifications
    @ObservationIgnored private var calendar = PermissionState.calendarGranted
    /// Se llama cuando un permiso pasa a concedido.
    @ObservationIgnored var onGranted: (() -> Void)?

    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var timer: Timer?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Mientras la ventana esta abierta: el permiso puede llegar sin volver a Nook.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func refresh() {
        let ax = AXAccess.isTrusted, disk = Self.readsNotifications, cal = Self.calendarGranted
        let granted = (ax && !accessibility) || (disk && !fullDiskAccess) || (cal && !calendar)
        if ax != accessibility { accessibility = ax }
        if disk != fullDiskAccess { fullDiskAccess = disk }
        calendar = cal
        if granted { onGranted?() }
    }

    private static var calendarGranted: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    private static var readsNotifications: Bool {
        FileManager.default.isReadableFile(atPath: NotificationFeed.databasePath)
    }
}

/// Fila de un permiso o una conexion: icono, que desbloquea, estado y boton.
struct PermissionRow<Icon: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let actionTitle: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 12) {
            icon()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(detail).font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if granted {
                Label("Listo", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.success)
                    .symbolEffect(.bounce, options: .nonRepeating, value: granted)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Button(action: action) {
                    Text(actionTitle).font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .fixedSize()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColors.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(granted ? AppColors.success.opacity(0.45) : AppColors.cardBorder, lineWidth: 1))
        .animation(AppMotion.snappy, value: granted)
    }
}

/// Icono de una app instalada (logo oficial) o un simbolo sobre fondo de color.
struct AppBadge: View {
    var image: NSImage?
    var symbol: String
    var color: Color = AppColors.accent

    var body: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.gradient)
                .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
        }
    }
}

enum SystemSettingsLink {
    static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:\(anchor)") { NSWorkspace.shared.open(url) }
    }

    static func internetAccounts() { open("com.apple.Internet-Accounts-Settings.extension") }
}

/// Abrir al iniciar sesion.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Devuelve el estado real tras intentarlo.
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        return isEnabled
    }
}
