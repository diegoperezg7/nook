import XCTest
@testable import Nook

/// Que capturas aparecen en la seccion de capturas, y en que orden.
final class ScreenshotLibraryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    private func file(_ name: String, created: Date = .now, markedAsCapture: Bool = false) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        if markedAsCapture {
            // Lo que pone macOS: un plist binario con `true`.
            let value = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
            _ = value.withUnsafeBytes {
                setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, value.count, 0, 0)
            }
        }
        return url
    }

    func testFindsScreenshotsByMarkOrName() throws {
        try file("Captura de pantalla 2026-11-09 a las 14.05.03.png")
        try file("Screenshot 2026-11-09 at 14.05.03.png")
        try file("cualquier nombre.png", markedAsCapture: true)
        try file("foto de vacaciones.png")
        try file("Captura de pantalla notas.txt")
        try file(".Captura de pantalla oculta.png")

        let names = Set(ScreenshotLibrary.screenshots(in: folder).map(\.url.lastPathComponent))
        XCTAssertEqual(names, [
            "Captura de pantalla 2026-11-09 a las 14.05.03.png",
            "Screenshot 2026-11-09 at 14.05.03.png",
            "cualquier nombre.png",
        ])
    }

    func testNewestFirst() throws {
        try file("Screenshot A.png", created: .now.addingTimeInterval(-3600))
        try file("Screenshot B.png", created: .now)
        try file("Screenshot C.png", created: .now.addingTimeInterval(-60))

        let names = ScreenshotLibrary.screenshots(in: folder).map(\.url.lastPathComponent)
        XCTAssertEqual(names, ["Screenshot B.png", "Screenshot C.png", "Screenshot A.png"])
    }
}
