import SwiftData
import XCTest
@testable import Nook

/// Lo guardado sobrevive a cerrar la app y solo se borra cuando lo pide el usuario.
@MainActor
final class PersistenceTests: XCTestCase {
    private var directory: URL!
    /// SwiftData exige que el contenedor viva mientras se usa su contexto.
    private var containers: [ModelContainer] = []

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        containers.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(_ name: String) throws -> (ItemStore, ModelContainer) {
        let container = try ModelContainer(
            for: NotchItem.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("\(name).store"))
        )
        let store = ItemStore(
            context: container.mainContext,
            itemsDirectory: directory.appendingPathComponent("\(name)-Items", isDirectory: true)
        )
        containers.append(container)
        return (store, container)
    }

    private func allItems(_ store: ItemStore) throws -> [NotchItem] {
        try store.context.fetch(FetchDescriptor<NotchItem>())
    }

    func testHistoryAndShelfSurviveRelaunch() throws {
        do {
            let (store, _) = try makeStore("App")
            store.captureText("copiado antes de apagar")
            store.addShelfText("dejado en la bandeja")
            containers.removeAll()
        }
        let (reopened, _) = try makeStore("App")
        XCTAssertEqual(Set(try allItems(reopened).compactMap(\.text)), ["copiado antes de apagar", "dejado en la bandeja"])
    }

    func testHistoryIsNotTrimmedByDefault() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        SettingsKey.registerDefaults(defaults)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.historyLimit), SettingsKey.unlimitedHistory)

        let (store, _) = try makeStore("App")
        store.historyLimit = { defaults.integer(forKey: SettingsKey.historyLimit) }
        for index in 0..<300 { store.captureText("elemento \(index)") }
        XCTAssertEqual(try allItems(store).count, 300)
    }

    func testLegacyDataIsImportedOnceWithFiles() throws {
        let (legacy, _) = try makeStore("Legacy")
        legacy.captureText("del nombre anterior")
        let png = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!.representation(using: .png, properties: [:])!
        legacy.addShelfImage(png)
        let legacyImage = try XCTUnwrap(try allItems(legacy).first { $0.kind == .image })

        let (store, _) = try makeStore("App")
        let legacyStoreURL = directory.appendingPathComponent("Legacy.store")
        let legacyItems = directory.appendingPathComponent("Legacy-Items")
        try LegacyImport.importStore(at: legacyStoreURL, itemsDirectory: legacyItems, into: store)
        try LegacyImport.importStore(at: legacyStoreURL, itemsDirectory: legacyItems, into: store)

        let imported = try allItems(store)
        XCTAssertEqual(imported.count, 2, "importar dos veces no duplica")
        let image = try XCTUnwrap(imported.first { $0.id == legacyImage.id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(store.fileURL(for: image)).path))
        // El original sigue intacto.
        XCTAssertEqual(try allItems(legacy).count, 2)
    }
}
