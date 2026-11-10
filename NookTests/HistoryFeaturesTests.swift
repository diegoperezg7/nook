import AppKit
import SwiftData
import XCTest
@testable import Nook

/// Busqueda dentro de imagenes, filtros por tipo y app de origen.
@MainActor
final class HistoryFeaturesTests: XCTestCase {
    private var container: ModelContainer!
    private var directory: URL!
    private var store: ItemStore!

    override func setUp() async throws {
        container = try ModelContainer(
            for: NotchItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = ItemStore(context: container.mainContext, itemsDirectory: directory)
        store.historyLimit = { 0 }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func history() throws -> [NotchItem] {
        try container.mainContext.fetch(FetchDescriptor<NotchItem>())
    }

    private func imageData(text: String) throws -> Data {
        let size = NSSize(width: 900, height: 220)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 40, y: 70), withAttributes: [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.black,
        ])
        image.unlockFocus()
        return try XCTUnwrap(image.tiffRepresentation)
    }

    func testCopiedImageIsFoundByTheTextInside() async throws {
        await store.captureImage(try imageData(text: "Factura 2026"))
        let image = try XCTUnwrap(try history().first)

        // El OCR va en segundo plano: se espera a que termine.
        for _ in 0..<100 where image.recognizedText == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(image.matches("factura"), "texto reconocido: \(image.recognizedText ?? "nil")")
        XCTAssertFalse(image.matches("presupuesto"))
    }

    func testFiltersByKind() throws {
        store.captureText("hola")
        store.captureText("https://example.com/precios")
        store.captureFile(URL(fileURLWithPath: "/tmp/informe.pdf"))
        let items = try history()

        func titles(_ filter: HistoryFilter) -> Set<String> {
            Set(items.filter(filter.includes).compactMap { $0.text ?? $0.fileName })
        }
        XCTAssertEqual(titles(.all).count, 3)
        XCTAssertEqual(titles(.text), ["hola"])
        XCTAssertEqual(titles(.links), ["https://example.com/precios"])
        XCTAssertEqual(titles(.files), ["informe.pdf"])
        XCTAssertTrue(titles(.images).isEmpty)
    }

    /// Un archivo copiado en Finder se guarda como copia propia: al copiarlo desde el
    /// historial se pega esa copia (que Nook si puede leer), aunque el original cambie.
    func testCopiedFileKeepsOwnCopyThatPastesBack() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-notas.txt")
        try "hola".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        store.captureFile(source)
        let item = try XCTUnwrap(try history().first)
        XCTAssertNotNil(item.storedPath)
        let kept = try XCTUnwrap(store.fileURL(for: item))
        XCTAssertTrue(kept.path.hasPrefix(directory.path))
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "hola")

        try FileManager.default.removeItem(at: source)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NookTest-\(UUID().uuidString)"))
        store.copyToPasteboard(item, pasteboard: pasteboard)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.first?.standardizedFileURL, kept.standardizedFileURL)
        pasteboard.releaseGlobally()
    }

    func testPinnedFilterShowsOnlyPinned() throws {
        store.captureText("IBAN ES00 0000")
        store.captureText("otra cosa")
        let iban = try XCTUnwrap(try history().first { $0.text == "IBAN ES00 0000" })
        store.togglePin(iban)
        let pinned = try history().filter(HistoryFilter.pinned.includes)
        XCTAssertEqual(pinned.map(\.text), ["IBAN ES00 0000"])
    }

    func testShelfExpiryRemovesOnlyOldShelfItems() throws {
        store.addShelfText("vieja")
        store.addShelfText("nueva")
        store.captureText("historial viejo")
        let now = Date()
        for item in try history() where item.text != "nueva" {
            item.createdAt = now.addingTimeInterval(-10 * 86_400)
        }
        XCTAssertEqual(store.expireShelf(days: 0, now: now), 0, "0 = nunca")
        XCTAssertEqual(store.expireShelf(days: 7, now: now), 1)
        let left = Set(try history().compactMap(\.text))
        XCTAssertEqual(left, ["nueva", "historial viejo"])
    }

    func testTextWithALinkInsideIsNotALink() throws {
        store.captureText("mira https://example.com")
        XCTAssertFalse(try XCTUnwrap(try history().first).isLink)
    }

    func testRemembersSourceApp() throws {
        store.captureText("copiado en Safari", source: "com.apple.Safari")
        XCTAssertEqual(try history().first?.sourceBundleID, "com.apple.Safari")
    }
}
