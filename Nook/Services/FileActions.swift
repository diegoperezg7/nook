import Foundation
import ImageIO
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
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["es-ES", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    static func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
