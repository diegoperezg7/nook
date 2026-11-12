import Foundation
import IOKit

/// Bateria de AirPods, auriculares, teclados y ratones Bluetooth.
/// - AirPods y auriculares: `system_profiler SPBluetoothDataType -json` (izquierdo,
///   derecho y estuche).
/// - Teclados, ratones y trackpads de Apple: IOKit (`BatteryPercent`).
struct AccessoryBattery: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    /// Niveles por pieza ("L", "R", "Estuche" o "" para uno solo), en %.
    let levels: [(part: String, level: Int)]

    /// El mas bajo sin contar el estuche (lo que avisa de "poca bateria").
    var lowest: Int? {
        levels.filter { $0.part != Self.casePart }.map(\.level).min() ?? levels.map(\.level).min()
    }

    static let casePart = "Estuche"

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.icon == rhs.icon && lhs.levels.map(\.part) == rhs.levels.map(\.part)
            && lhs.levels.map(\.level) == rhs.levels.map(\.level)
    }

    /// Todos los accesorios conectados con bateria conocida.
    static func readAll() async -> [AccessoryBattery] {
        let profiler = await Task.detached { () -> [AccessoryBattery] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parse(profiler: data)
        }.value
        let hid = readHID()
        // Si un teclado sale por las dos vias, gana la de IOKit (mas precisa).
        return hid + profiler.filter { device in !hid.contains { $0.name == device.name } }
    }

    static func parse(profiler data: Data) -> [AccessoryBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [AccessoryBattery] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let parts: [(String, String)] = [
                        ("L", "device_batteryLevelLeft"), ("R", "device_batteryLevelRight"),
                        (casePart, "device_batteryLevelCase"), ("", "device_batteryLevelMain"),
                    ]
                    let levels = parts.compactMap { part, key -> (part: String, level: Int)? in
                        guard let text = info[key] as? String, let level = Int(text.filter(\.isNumber)) else { return nil }
                        return (part, level)
                    }
                    guard !levels.isEmpty else { continue }
                    let device = AccessoryBattery(name: name, icon: icon(for: name, type: info["device_minorType"] as? String, productID: info["device_productID"] as? String), levels: levels)
                    // Recien conectados, macOS a veces lista los mismos AirPods dos veces
                    // (y solo con el estuche): se juntan en uno con todas las piezas.
                    if let index = result.firstIndex(where: { $0.name == name }) {
                        result[index] = result[index].merged(with: device)
                    } else {
                        result.append(device)
                    }
                }
            }
        }
        return result
    }

    /// Las piezas de los dos, sin repetir (si una pieza sale dos veces, la primera).
    func merged(with other: AccessoryBattery) -> AccessoryBattery {
        var levels = self.levels
        for item in other.levels where !levels.contains(where: { $0.part == item.part }) {
            levels.append(item)
        }
        let order = ["L", "R", Self.casePart, ""]
        levels.sort { (order.firstIndex(of: $0.part) ?? 9) < (order.firstIndex(of: $1.part) ?? 9) }
        return AccessoryBattery(name: name, icon: icon, levels: levels)
    }

    /// Solo se sabe la del estuche: los auriculares aun no han dicho la suya.
    var onlyCase: Bool { !levels.isEmpty && levels.allSatisfy { $0.part == Self.casePart } }

    /// Modelo de AirPods por su product ID (el nombre se puede cambiar).
    static let airPodsModels: [String: String] = [
        "0x2002": "airpods", "0x200F": "airpods",
        "0x2013": "airpods.gen3",
        "0x2019": "airpods.gen4", "0x201B": "airpods.gen4",
        "0x200E": "airpodspro", "0x2014": "airpodspro", "0x2024": "airpodspro",
        "0x200A": "airpodsmax", "0x201F": "airpodsmax",
    ]

    static func icon(for name: String, type: String?, productID: String? = nil) -> String {
        if let productID, let model = airPodsModels[productID.uppercased().replacingOccurrences(of: "0X", with: "0x")] { return model }
        let lower = name.lowercased(), kind = (type ?? "").lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if kind.contains("headphones") || kind.contains("headset") { return "headphones" }
        if kind.contains("keyboard") || lower.contains("keyboard") || lower.contains("teclado") { return "keyboard" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if kind.contains("mouse") || lower.contains("mouse") || lower.contains("ratón") { return "magicmouse.fill" }
        return "dot.radiowaves.left.and.right"
    }

    /// Simbolo de cada pieza: auricular izquierdo, derecho y estuche del modelo.
    static func partSymbol(_ part: String, model: String) -> String {
        let pieces: (left: String, right: String, case: String)
        switch model {
        case "airpodspro": pieces = ("airpodpro.left", "airpodpro.right", "airpodspro.chargingcase.wireless.fill")
        case "airpods.gen3": pieces = ("airpod.gen3.left", "airpod.gen3.right", "airpods.gen3.chargingcase.wireless.fill")
        case "airpods.gen4": pieces = ("airpod.gen3.left", "airpod.gen3.right", "airpods.gen4.chargingcase.wireless.fill")
        case "airpods": pieces = ("airpod.left", "airpod.right", "airpods.chargingcase.fill")
        default: return model
        }
        switch part {
        case "L": return pieces.left
        case "R": return pieces.right
        case casePart: return pieces.case
        default: return model
        }
    }

    /// Accesorios HID de Apple (Magic Keyboard, Mouse, Trackpad) con su bateria.
    private static func readHID() -> [AccessoryBattery] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [AccessoryBattery] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let level = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int,
                  let name = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String,
                  !result.contains(where: { $0.name == name }) else { continue }
            result.append(AccessoryBattery(name: name, icon: icon(for: name, type: nil), levels: [("", level)]))
        }
        return result
    }
}
