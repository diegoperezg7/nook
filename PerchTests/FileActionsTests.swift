import AppKit
import XCTest
@testable import Perch

final class FileActionsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try FileActions.temporaryFolder()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// PNG con un texto grande, para el OCR.
    private func makeImage(text: String) throws -> URL {
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
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let url = folder.appendingPathComponent("texto.png")
        try png.write(to: url)
        return url
    }

    func testRecognizesTextInImage() throws {
        let text = try FileActions.recognizeText(in: try makeImage(text: "Hola Perch"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Perch"), "OCR devolvio: \(text)")
    }

    func testConvertsPNGToJPEG() throws {
        let output = try FileActions.convert(try makeImage(text: "x"), to: .jpeg)
        defer { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
        XCTAssertEqual(output.pathExtension, "jpg")
        XCTAssertEqual(FileActions.format(of: output), .jpeg)
        XCTAssertNotNil(NSImage(contentsOf: output))
    }

    func testZipsFile() throws {
        let source = folder.appendingPathComponent("nota.txt")
        try Data("hola".utf8).write(to: source)
        let output = try FileActions.zip(source)
        defer { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
        XCTAssertEqual(output.lastPathComponent, "nota.zip")
        let header = try Data(contentsOf: output).prefix(2)
        XCTAssertEqual(Array(header), [0x50, 0x4B], "Cabecera PK de zip")
    }

    func testCopiedImageCarriesFileAndImageData() throws {
        let item = ItemStore.pasteboardItem(for: try makeImage(text: "x"))
        XCTAssertNotNil(item.string(forType: .fileURL))
        XCTAssertNotNil(item.data(forType: .png))
        XCTAssertNotNil(item.data(forType: .tiff))
    }
}
