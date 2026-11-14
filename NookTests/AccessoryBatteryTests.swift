import AppKit
import XCTest
@testable import Nook

/// Bateria de accesorios a partir de la salida de system_profiler.
final class AccessoryBatteryTests: XCTestCase {
    private let sample = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
      "device_connected":[
        {"AirPods Pro de Diego":{"device_address":"AA","device_batteryLevelCase":"40%","device_batteryLevelLeft":"100%","device_batteryLevelRight":"15%","device_minorType":"Headphones"}},
        {"Altavoz":{"device_address":"BB","device_minorType":"Speaker"}},
        {"Magic Mouse":{"device_batteryLevelMain":"62%","device_minorType":"Mouse"}}
      ],
      "device_not_connected":[{"AirPods Max":{"device_batteryLevelMain":"80%"}}]
    }]}
    """

    func testReadsConnectedDevicesWithBattery() {
        let devices = AccessoryBattery.parse(profiler: Data(sample.utf8))
        XCTAssertEqual(devices.map(\.name), ["AirPods Pro de Diego", "Magic Mouse"], "sin bateria o desconectados no salen")
        let airpods = devices[0]
        XCTAssertEqual(airpods.icon, AccessoryBattery.firstAvailable(["airpods.pro", "airpodspro"]), "sin product ID, por el nombre")
        XCTAssertEqual(airpods.levels.map(\.part), ["L", "R", AccessoryBattery.casePart])
        XCTAssertEqual(airpods.lowest, 15, "el estuche no cuenta para el aviso")
        XCTAssertEqual(devices[1].icon, "magicmouse.fill")
        XCTAssertEqual(devices[1].lowest, 62)
    }

    /// El modelo sale del product ID aunque el nombre no lo diga.
    func testModelFromProductID() {
        let pro = AccessoryBattery.firstAvailable(["airpods.pro", "airpodspro"])
        XCTAssertEqual(AccessoryBattery.icon(for: "AirPods de Ana", type: "Headphones", productID: "0x2014"), pro)
        XCTAssertEqual(AccessoryBattery.icon(for: "Cascos", type: "Headphones", productID: "0x2013"), "airpods.gen3")
        XCTAssertEqual(AccessoryBattery.icon(for: "AirPods Max", type: nil, productID: "0x9999"), AccessoryBattery.firstAvailable(["airpods.max", "airpodsmax"]))
        XCTAssertEqual(AccessoryBattery.icon(for: "x", type: nil, productID: "0x200f"), "airpods", "el product ID en minusculas tambien vale")
    }

    /// Los AirPods Pro 3 (0x2027) tienen su propio simbolo en macOS 27 y caen al de
    /// los Pro en macOS anteriores.
    func testAirPodsPro3() {
        let icon = AccessoryBattery.icon(for: "AirPods Pro de Diego", type: "Headphones", productID: "0x2027")
        if NSImage(systemSymbolName: "airpods.pro.gen3", accessibilityDescription: nil) != nil {
            XCTAssertEqual(icon, "airpods.pro.gen3")
        } else {
            XCTAssertTrue(["airpods.pro", "airpodspro"].contains(icon))
        }
        XCTAssertNotNil(NSImage(systemSymbolName: icon, accessibilityDescription: nil))
    }

    /// Al conectar aun no hay bateria: el modelo se lee igual del perfil de Bluetooth,
    /// y nunca sale el simbolo de los AirPods de primera generacion para unos Pro.
    func testIconWhenConnecting() {
        let json = """
        {"SPBluetoothDataType":[{
          "device_connected":[{"AirPods Pro de Diego":{"device_address":"34:0E","device_productID":"0x2027","device_minorType":"Headphones"}}],
          "device_not_connected":[{"Cascos de Ana":{"device_productID":"0x2019","device_minorType":"Headphones"}}]
        }]}
        """
        let data = Data(json.utf8)
        let pro3 = AccessoryBattery.audioIcon(named: "AirPods Pro de Diego", profiler: data)
        XCTAssertNotEqual(pro3, "airpods")
        XCTAssertEqual(pro3, AccessoryBattery.icon(for: "", type: nil, productID: "0x2027"))
        XCTAssertEqual(AccessoryBattery.audioIcon(named: "Cascos de Ana", profiler: data), AccessoryBattery.firstAvailable(["airpods.gen4", "airpods.gen3"]))
        XCTAssertEqual(AccessoryBattery.audioIcon(named: "Altavoz JBL", profiler: data), "headphones", "desconocido: auriculares genericos")
        XCTAssertEqual(AccessoryBattery.audioIcon(named: "Altavoz JBL", profiler: nil), "headphones")
    }

    /// Cada pieza tiene su simbolo y todos existen en SF Symbols.
    func testPartSymbolsExist() {
        for model in Set(AccessoryBattery.airPodsModels.values.flatMap { $0 })
            where NSImage(systemSymbolName: model, accessibilityDescription: nil) != nil {
            for part in ["L", "R", AccessoryBattery.casePart, ""] {
                let name = AccessoryBattery.partSymbol(part, model: model)
                XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(model) \(part): \(name)")
            }
        }
    }

    /// En la cabecera solo cuentan los auriculares (el raton no).
    func testOnlyHeadphonesCount() {
        XCTAssertTrue(BatteryCenter.isAudio("airpodspro"))
        XCTAssertTrue(BatteryCenter.isAudio("airpods.gen3"))
        XCTAssertTrue(BatteryCenter.isAudio("beats.headphones"))
        XCTAssertFalse(BatteryCenter.isAudio("magicmouse.fill"))
        XCTAssertFalse(BatteryCenter.isAudio("keyboard"))
    }

    func testBrokenOutputIsEmpty() {
        XCTAssertTrue(AccessoryBattery.parse(profiler: Data("no json".utf8)).isEmpty)
    }

    /// Los mismos AirPods listados dos veces (uno solo con el estuche) salen una vez,
    /// con izquierdo, derecho y estuche.
    func testDuplicatedAirPodsMerge() {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"AirPods Pro de Diego":{"device_batteryLevelCase":"49 %"}},
          {"AirPods Pro de Diego":{"device_batteryLevelCase":"49 %","device_batteryLevelLeft":"77 %","device_batteryLevelRight":"76 %"}}
        ]}]}
        """
        let devices = AccessoryBattery.parse(profiler: Data(json.utf8))
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.levels.map(\.part), ["L", "R", AccessoryBattery.casePart])
        XCTAssertEqual(devices.first?.levels.map(\.level), [77, 76, 49])
        XCTAssertEqual(devices.first?.onlyCase, false)
    }
}
