import XCTest
@testable import Nook

/// Copia de los datos del contenedor al App Group: completa o nada, sin borrar.
final class DataHomeTests: XCTestCase {
    private var root: URL!
    private var legacy: URL { root.appendingPathComponent("contenedor/Nook") }
    private var group: URL { root.appendingPathComponent("grupo/Library/Application Support/Nook") }
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("DataHome-\(UUID().uuidString)")
        try fm.createDirectory(at: legacy.appendingPathComponent("Items/abc"), withIntermediateDirectories: true)
        try Data("almacen".utf8).write(to: legacy.appendingPathComponent("Nook.store"))
        try Data("wal".utf8).write(to: legacy.appendingPathComponent("Nook.store-wal"))
        try Data("foto".utf8).write(to: legacy.appendingPathComponent("Items/abc/foto.png"))
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    func testCopiesEverythingAndKeepsTheOriginal() throws {
        let result = DataHome.migrate(from: legacy, to: group)
        XCTAssertTrue(result.useGroup, result.message)
        XCTAssertEqual(try String(contentsOf: group.appendingPathComponent("Items/abc/foto.png"), encoding: .utf8), "foto")
        XCTAssertTrue(fm.fileExists(atPath: group.appendingPathComponent("Nook.store-wal").path))
        XCTAssertTrue(fm.fileExists(atPath: legacy.appendingPathComponent("Nook.store").path), "el original no se toca")
    }

    func testSecondLaunchDoesNotCopyAgain() throws {
        _ = DataHome.migrate(from: legacy, to: group)
        // Cambios hechos ya en el grupo no se pisan con el contenedor viejo.
        try Data("nuevo".utf8).write(to: group.appendingPathComponent("Nook.store"))
        let result = DataHome.migrate(from: legacy, to: group)
        XCTAssertTrue(result.useGroup)
        XCTAssertEqual(try String(contentsOf: group.appendingPathComponent("Nook.store"), encoding: .utf8), "nuevo")
    }

    func testFreshInstallUsesTheGroup() throws {
        try fm.removeItem(at: legacy)
        let result = DataHome.migrate(from: legacy, to: group)
        XCTAssertTrue(result.useGroup)
        XCTAssertTrue(fm.fileExists(atPath: group.path))
    }

    func testEmptyGroupFolderIsSetAsideNotDeleted() throws {
        try fm.createDirectory(at: group, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: group.appendingPathComponent("suelto.txt"))
        let result = DataHome.migrate(from: legacy, to: group)
        XCTAssertTrue(result.useGroup, result.message)
        XCTAssertTrue(fm.fileExists(atPath: group.appendingPathComponent("Nook.store").path))
        let siblings = try fm.contentsOfDirectory(atPath: group.deletingLastPathComponent().path)
        XCTAssertTrue(siblings.contains { $0.hasPrefix("Nook-anterior-") }, "la carpeta previa se aparta")
    }

    func testFailedCopyFallsBackToTheContainer() throws {
        // El destino no se puede crear: hay un archivo donde deberia ir la carpeta.
        try fm.createDirectory(at: root.appendingPathComponent("grupo/Library"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("grupo/Library/Application Support"))
        let result = DataHome.migrate(from: legacy, to: group)
        XCTAssertFalse(result.useGroup, result.message)
        XCTAssertTrue(fm.fileExists(atPath: legacy.appendingPathComponent("Nook.store").path))
    }
}
