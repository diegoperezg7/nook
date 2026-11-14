import Foundation
import Observation

/// Bateria de los AirPods y auriculares Bluetooth para el boton de la cabecera. La
/// del Mac no: ya se ve en la barra de menus. Se lee al abrir el panel y cada 2 minutos.
@Observable
@MainActor
final class BatteryCenter {
    private(set) var headphones: [AccessoryBattery] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var caseRetries = 0

    func start() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: true) }
        }
    }

    /// Como mucho cada 20 s salvo que se fuerce (system_profiler tarda).
    func refresh(force: Bool = false) {
        if !force, let lastRead, Date().timeIntervalSince(lastRead) < 20 { return }
        guard !loading else { return }
        loading = true
        Task {
            var list = await AccessoryBattery.readAll().filter { Self.isAudio($0.icon) }
            #if DEBUG
            // `-VisorDemoBattery YES`: unos AirPods de ejemplo para probar el boton sin tenerlos.
            if UserDefaults.standard.bool(forKey: "VisorDemoBattery") {
                list = [AccessoryBattery(name: "AirPods Pro", icon: AccessoryBattery.firstAvailable(["airpods.pro.gen3", "airpods.pro", "airpodspro"]), levels: [("L", 82), ("R", 79), (AccessoryBattery.casePart, 64)])]
            }
            #endif
            loading = false
            lastRead = Date()
            if list != headphones { headphones = list }
            // Recien conectados solo se sabe el estuche: se vuelve a mirar cada 10 s,
            // como mucho un minuto (con los auriculares guardados no llega nada mas).
            if list.contains(where: \.onlyCase), caseRetries < 6 {
                caseRetries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.refresh(force: true) }
            } else if !list.contains(where: \.onlyCase) {
                caseRetries = 0
            }
        }
    }

    /// Lo que se ve en el boton: los primeros auriculares conectados.
    var headline: (symbol: String, level: Int)? {
        guard let buds = headphones.first, let level = buds.lowest else { return nil }
        return (buds.icon, level)
    }

    nonisolated static func isAudio(_ icon: String) -> Bool {
        icon.hasPrefix("airpods") || icon.contains("headphones")
    }
}
