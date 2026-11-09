import AppKit
import SwiftData
import XCTest
@testable import Nook

@MainActor
final class ItemStoreTests: XCTestCase {
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
        store.historyLimit = { 3 }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func items(_ origin: ItemOrigin) throws -> [NotchItem] {
        let raw = origin.rawValue
        return try container.mainContext.fetch(FetchDescriptor<NotchItem>(
            predicate: #Predicate { $0.originRaw == raw },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    func testCopyingSameTextTwiceMovesItToTopWithoutDuplicating() throws {
        store.captureText("uno")
        store.captureText("dos")
        store.captureText("uno")
        let history = try items(.clipboard)
        XCTAssertEqual(history.map(\.text), ["uno", "dos"])
    }

    func testBlankTextIsIgnored() throws {
        store.captureText("   \n")
        XCTAssertTrue(try items(.clipboard).isEmpty)
    }

    func testHistoryIsTrimmedButPinnedItemsSurvive() throws {
        store.captureText("fijado")
        try items(.clipboard).first.map(store.togglePin)
        for text in ["a", "b", "c", "d"] { store.captureText(text) }

        let history = try items(.clipboard)
        XCTAssertEqual(history.filter { !$0.isPinned }.map(\.text), ["d", "c", "b"])
        XCTAssertEqual(history.filter(\.isPinned).map(\.text), ["fijado"])
    }

    func testClearHistoryKeepsPinned() throws {
        store.captureText("a")
        store.captureText("b")
        try items(.clipboard).first.map(store.togglePin)
        store.clearHistory()
        XCTAssertEqual(try items(.clipboard).map(\.text), ["b"])
    }

    func testShelfFileIsCopiedAndRemovedWithItsFolder() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("nota-\(UUID().uuidString).txt")
        try Data("hola".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let staged = try ItemStore.stageFile(source, in: directory)
        store.addShelfFile(staged)

        let item = try XCTUnwrap(try items(.shelf).first)
        let copy = try XCTUnwrap(store.fileURL(for: item))
        XCTAssertNotEqual(copy, source)
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "hola")

        store.delete(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "El original no se toca")
    }

    func testImageIsStoredAsPNG() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        store.captureImage(try XCTUnwrap(image.tiffRepresentation))

        let item = try XCTUnwrap(try items(.clipboard).first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(store.fileURL(for: item)?.pathExtension, "png")
    }

    func testOwnPasteboardWriteIsRemembered() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        store.captureText("hola")
        let item = try XCTUnwrap(try items(.clipboard).first)

        store.copyToPasteboard(item, pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "hola")
        XCTAssertEqual(store.ownChangeCount, pasteboard.changeCount)
    }

    func testPasswordManagerContentIsIgnored() {
        XCTAssertTrue(ClipboardFilter.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ClipboardFilter.shouldIgnore(types: ["public.utf8-plain-text"]))
    }

    func testSearchMatchesTextAndFileNames() {
        let text = NotchItem(kind: .text, origin: .clipboard, text: "Factura Marzo", contentHash: "1")
        let file = NotchItem(kind: .file, origin: .clipboard, fileName: "informe.pdf", contentHash: "2")
        XCTAssertTrue(text.matches("factura"))
        XCTAssertTrue(file.matches("INFORME"))
        XCTAssertFalse(file.matches("factura"))
    }
}
