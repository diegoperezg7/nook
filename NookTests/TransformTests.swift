import AppKit
import AVFoundation
import ImageIO
import PDFKit
import XCTest
@testable import Nook

/// Transformar archivos: PDF, video comprimido y GIF, con archivos creados aqui.
final class TransformTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try FileActions.temporaryFolder()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func png(_ name: String) throws -> URL {
        let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
            NSColor.systemBlue.setFill(); rect.fill(); return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let url = folder.appendingPathComponent(name)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    /// Un segundo de video de 64x64 a 10 fps.
    private func video() async throws -> URL {
        let url = folder.appendingPathComponent("clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 20), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    func testMergesPDFsAndImagesInOrder() throws {
        let image = try png("foto.png")
        let first = try FileActions.makePDF(from: [image], name: "uno")
        let merged = try FileActions.makePDF(from: [first, image, first], name: "todo")
        XCTAssertEqual(PDFDocument(url: merged)?.pageCount, 3)
        XCTAssertEqual(merged.lastPathComponent, "todo.pdf")
    }

    func testNothingToMergeFails() {
        XCTAssertThrowsError(try FileActions.makePDF(from: [folder.appendingPathComponent("no.txt")], name: "x"))
    }

    func testVideoToGIFLoopsWithFrames() async throws {
        let gif = try await FileActions.videoToGIF(try await video())
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
        XCTAssertGreaterThanOrEqual(CGImageSourceGetCount(source), 9)
        XCTAssertEqual(gif.pathExtension, "gif")
    }

    func testCompressesVideoToMP4() async throws {
        let output = try await FileActions.compressVideo(try await video())
        XCTAssertEqual(output.pathExtension, "mp4")
        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
    }

    /// Un objeto (el icono de Safari) sobre fondo blanco: el resultado es un PNG con
    /// las esquinas transparentes.
    func testRemovesBackground() throws {
        let icon = NSWorkspace.shared.icon(forFile: "/Applications/Safari.app")
        let image = NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            icon.draw(in: rect.insetBy(dx: 120, dy: 120))
            return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let url = folder.appendingPathComponent("objeto.png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)

        let output = try FileActions.removeBackground(url)
        let result = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: output)))
        XCTAssertEqual(result.colorAt(x: 2, y: 2)?.alphaComponent ?? 1, 0, accuracy: 0.05, "fondo transparente")
        XCTAssertGreaterThan(result.colorAt(x: result.pixelsWide / 2, y: result.pixelsHigh / 2)?.alphaComponent ?? 0, 0.9, "sujeto opaco")
    }

    func testKindsByExtension() {
        XCTAssertTrue(FileActions.isVideo(URL(fileURLWithPath: "/a.mov")))
        XCTAssertTrue(FileActions.isPDF(URL(fileURLWithPath: "/a.pdf")))
        XCTAssertFalse(FileActions.isVideo(URL(fileURLWithPath: "/a.png")))
    }
}
