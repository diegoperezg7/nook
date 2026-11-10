import AppKit
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum FileActionError: Error {
    case failed
}

/// Formatos a los que se puede convertir una imagen.
enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic

    var id: String { rawValue }
    var type: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }
    var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }
    var label: String { rawValue.uppercased() }
}

/// Acciones sobre archivos de la bandeja. Todas dejan el resultado en una carpeta
/// temporal; quien llama lo registra como elemento nuevo.
enum FileActions {
    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    static func isVideo(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
    }

    static func isPDF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
    }

    static func format(of url: URL) -> ImageFormat? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        return ImageFormat.allCases.first { type.conforms(to: $0.type) }
    }

    /// Comprime con ditto, como hace Finder (mantiene la carpeta y los metadatos).
    static func zip(_ url: URL) throws -> URL {
        let output = try temporaryFolder()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, output.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FileActionError.failed }
        return output
    }

    static func convert(_ url: URL, to format: ImageFormat) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw FileActionError.failed }
        let output = try temporaryFolder().appendingPathComponent(
            url.deletingPathExtension().lastPathComponent + "." + format.fileExtension
        )
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, format.type.identifier as CFString, 1, nil
        ) else { throw FileActionError.failed }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImageFromSource(destination, source, 0, options)
        guard CGImageDestinationFinalize(destination) else { throw FileActionError.failed }
        return output
    }

    /// OCR local (Vision): no sale nada del Mac.
    static func recognizeText(in url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw FileActionError.failed }
        func run(_ level: VNRequestTextRecognitionLevel) throws -> VNRecognizeTextRequest {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["es-ES", "en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            return request
        }
        // El modelo preciso a veces no carga (error E5RT 13 del motor neuronal, visto
        // en todo el sistema): entonces se usa el rapido, que no depende de el.
        let request: VNRecognizeTextRequest
        do {
            request = try run(.accurate)
        } catch {
            request = try run(.fast)
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - Transformar

    /// Quita el fondo y deja el sujeto en un PNG transparente (Vision, en el Mac).
    static func removeBackground(_ url: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw FileActionError.failed }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw FileActionError.failed }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        let output = try temporaryFolder().appendingPathComponent(url.deletingPathExtension().lastPathComponent + " sin fondo.png")
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw FileActionError.failed }
        try CIContext().writePNGRepresentation(of: CIImage(cvPixelBuffer: buffer), to: output, format: .RGBA8, colorSpace: space)
        return output
    }

    /// Vuelve a codificar el video en H.264 a calidad media: suele quedarse en una
    /// fraccion del tamaño y se reproduce en cualquier sitio.
    static func compressVideo(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw FileActionError.failed
        }
        let output = try temporaryFolder().appendingPathComponent(url.deletingPathExtension().lastPathComponent + " comprimido.mp4")
        export.outputURL = output
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        await export.export()
        guard export.status == .completed else { throw FileActionError.failed }
        return output
    }

    /// GIF en bucle de los primeros 15 s, a 10 fotogramas por segundo y 480 px.
    static func videoToGIF(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else { throw FileActionError.failed }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)

        let fps = 10.0
        let frames = Int(min(duration, 15) * fps)
        let output = try temporaryFolder().appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".gif")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames, nil) else {
            throw FileActionError.failed
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps],
        ] as CFDictionary
        for index in 0..<max(frames, 1) {
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            let image = try await generator.image(at: time).image
            CGImageDestinationAddImage(destination, image, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw FileActionError.failed }
        return output
    }

    /// Une PDFs en uno, en el orden recibido; las imagenes entran como paginas.
    static func makePDF(from urls: [URL], name: String) throws -> URL {
        let document = PDFDocument()
        for url in urls {
            if isPDF(url), let pdf = PDFDocument(url: url) {
                for index in 0..<pdf.pageCount {
                    if let page = pdf.page(at: index) { document.insert(page, at: document.pageCount) }
                }
            } else if isImage(url), let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                document.insert(page, at: document.pageCount)
            }
        }
        guard document.pageCount > 0 else { throw FileActionError.failed }
        let output = try temporaryFolder().appendingPathComponent(name + ".pdf")
        guard document.write(to: output) else { throw FileActionError.failed }
        return output
    }

    static func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Codigo QR del texto, nitido (sin suavizado) al tamaño pedido. nil si no cabe
    /// en un QR (unos 2.900 bytes).
    static func qrCode(for text: String, side: CGFloat = 220) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = (side / output.extent.width).rounded(.down)
        let image = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: image)
        let result = NSImage(size: rep.size)
        result.addRepresentation(rep)
        return result
    }

    /// Color en "#RRGGBB" (sRGB), como lo pide la web.
    static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let parts = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
    }
}
