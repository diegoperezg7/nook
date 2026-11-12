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
        XCTAssertEqual(airpods.icon, "airpodspro")
        XCTAssertEqual(airpods.levels.map(\.part), ["L", "R", AccessoryBattery.casePart])
        XCTAssertEqual(airpods.lowest, 15, "el estuche no cuenta para el aviso")
        XCTAssertEqual(devices[1].icon, "magicmouse.fill")
        XCTAssertEqual(devices[1].lowest, 62)
    }

    /// El modelo sale del product ID aunque el nombre no lo diga.
    func testModelFromProductID() {
        XCTAssertEqual(AccessoryBattery.icon(for: "AirPods de Ana", type: "Headphones", productID: "0x2014"), "airpodspro")
        XCTAssertEqual(AccessoryBattery.icon(for: "Cascos", type: "Headphones", productID: "0x2013"), "airpods.gen3")
        XCTAssertEqual(AccessoryBattery.icon(for: "AirPods Max", type: nil, productID: "0x9999"), "airpodsmax")
    }

    /// Cada pieza tiene su simbolo y todos existen en SF Symbols.
    func testPartSymbolsExist() {
        for model in Set(AccessoryBattery.airPodsModels.values) {
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
