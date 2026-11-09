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

    func testBrokenOutputIsEmpty() {
        XCTAssertTrue(AccessoryBattery.parse(profiler: Data("no json".utf8)).isEmpty)
    }
}
