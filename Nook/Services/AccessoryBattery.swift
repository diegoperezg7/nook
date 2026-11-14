import AppKit
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
            profilerData().map(parse(profiler:)) ?? []
        }.value
        let hid = readHID()
        // Si un teclado sale por las dos vias, gana la de IOKit (mas precisa).
        return hid + profiler.filter { device in !hid.contains { $0.name == device.name } }
    }

    /// Salida de `system_profiler SPBluetoothDataType -json` (unos 60 ms).
    nonisolated static func profilerData() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    /// Icono del modelo de unos auriculares recien conectados, por su nombre. Se busca
    /// en el perfil de Bluetooth aunque aun no den bateria (justo al conectar no la dan).
    static func audioIcon(named name: String) async -> String {
        let data = await Task.detached { profilerData() }.value
        return audioIcon(named: name, profiler: data)
    }

    static func audioIcon(named name: String, profiler data: Data?) -> String {
        if let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let controllers = root["SPBluetoothDataType"] as? [[String: Any]] {
            for controller in controllers {
                let entries = (controller["device_connected"] as? [[String: Any]] ?? [])
                    + (controller["device_not_connected"] as? [[String: Any]] ?? [])
                for entry in entries {
                    guard let info = entry[name] as? [String: Any] else { continue }
                    return audioFallback(icon(for: name, type: info["device_minorType"] as? String, productID: info["device_productID"] as? String))
                }
            }
        }
        return audioFallback(icon(for: name, type: nil))
    }

    /// Un altavoz o un dispositivo sin tipo conocido: auriculares genericos.
    private static func audioFallback(_ icon: String) -> String {
        icon == genericIcon ? "headphones" : icon
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

    /// Simbolos de cada modelo de AirPods por su product ID (el nombre se puede
    /// cambiar), del mas preciso al mas antiguo: los nuevos solo existen en macOS
    /// recientes (los Pro 3, desde macOS 27) y se usa el primero que haya.
    static let airPodsModels: [String: [String]] = [
        "0x2002": ["airpods"], "0x200F": ["airpods"],
        "0x2013": ["airpods.gen3"],
        "0x2019": ["airpods.gen4", "airpods.gen3"], "0x201B": ["airpods.gen4", "airpods.gen3"],
        "0x200E": ["airpods.pro.gen1", "airpodspro"],
        "0x2014": ["airpods.pro", "airpodspro"], "0x2024": ["airpods.pro", "airpodspro"],
        "0x2027": ["airpods.pro.gen3", "airpods.pro", "airpodspro"],
        "0x200A": ["airpods.max", "airpodsmax"], "0x201F": ["airpods.max", "airpodsmax"],
    ]

    static let genericIcon = "dot.radiowaves.left.and.right"

    static func icon(for name: String, type: String?, productID: String? = nil) -> String {
        if let productID, let models = airPodsModels["0x" + productID.uppercased().replacingOccurrences(of: "0X", with: "")] {
            return firstAvailable(models)
        }
        let lower = name.lowercased(), kind = (type ?? "").lowercased()
        if lower.contains("airpods max") { return firstAvailable(["airpods.max", "airpodsmax"]) }
        if lower.contains("airpods pro") { return firstAvailable(["airpods.pro", "airpodspro"]) }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if kind.contains("headphones") || kind.contains("headset") { return "headphones" }
        if kind.contains("keyboard") || lower.contains("keyboard") || lower.contains("teclado") { return "keyboard" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if kind.contains("mouse") || lower.contains("mouse") || lower.contains("ratón") { return "magicmouse.fill" }
        return genericIcon
    }

    /// El primer simbolo que existe en este macOS (el ultimo de la lista si ninguno).
    static func firstAvailable(_ symbols: [String]) -> String {
        symbols.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? symbols.last ?? genericIcon
    }

    /// Simbolo de cada pieza: auricular izquierdo, derecho y estuche del modelo.
    static func partSymbol(_ part: String, model: String) -> String {
        let pieces: (left: String, right: String, case: String)
        switch model {
        case "airpods.pro.gen3", "airpods.pro.gen1", "airpods.pro":
            pieces = (model + ".left", model + ".right", model + ".chargingcase.wireless.fill")
        case "airpodspro": pieces = ("airpodpro.left", "airpodpro.right", "airpodspro.chargingcase.wireless.fill")
        case "airpods.gen4": pieces = ("airpods.gen4.left", "airpods.gen4.right", "airpods.gen4.chargingcase.wireless.fill")
        case "airpods.gen3": pieces = ("airpod.gen3.left", "airpod.gen3.right", "airpods.gen3.chargingcase.wireless.fill")
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
