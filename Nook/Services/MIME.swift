import Foundation

/// Lectura minima de un correo en bruto (MIME): saca la parte HTML y las imagenes
/// incrustadas (cid:) para enseñarlo como en Mail. Sin dependencias.
enum MIME {
    struct Part {
        let contentType: String
        let parameters: [String: String]
        let contentID: String?
        let body: Data
    }

    /// El HTML del correo con las imagenes incrustadas como data: (nil si no tiene).
    static func html(fromSource source: String) -> String? {
        let parts = leafParts(of: Data(source.utf8))
        guard let htmlPart = parts.first(where: { $0.contentType == "text/html" }) else { return nil }
        var html = decodeText(htmlPart)
        for part in parts where part.contentType.hasPrefix("image/") {
            guard let id = part.contentID else { continue }
            let uri = "data:\(part.contentType);base64,\(part.body.base64EncodedString())"
            html = html.replacingOccurrences(of: "cid:\(id)", with: uri)
        }
        return html
    }

    /// Partes finales (no multipart), recorriendo las anidadas.
    static func leafParts(of data: Data) -> [Part] {
        let (headers, body) = splitHeaders(data)
        let (type, parameters) = parseContentType(headers["content-type"] ?? "text/plain")
        if type.hasPrefix("multipart/"), let boundary = parameters["boundary"] {
            return split(body, boundary: boundary).flatMap(leafParts(of:))
        }
        let encoding = (headers["content-transfer-encoding"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let decoded: Data
        switch encoding {
        case "base64": decoded = Data(base64Encoded: String(decoding: body, as: UTF8.self).filter { !$0.isWhitespace }) ?? Data()
        case "quoted-printable": decoded = quotedPrintable(body)
        default: decoded = body
        }
        let cid = headers["content-id"].map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t")) }
        return [Part(contentType: type, parameters: parameters, contentID: cid, body: decoded)]
    }

    static func decodeText(_ part: Part) -> String {
        if let charset = part.parameters["charset"] {
            let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cf != kCFStringEncodingInvalidId,
               let text = String(data: part.body, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) {
                return text
            }
        }
        return String(data: part.body, encoding: .utf8) ?? String(decoding: part.body, as: UTF8.self)
    }

    // MARK: - Piezas

    /// Cabeceras (en minusculas, con las lineas plegadas unidas) y cuerpo.
    static func splitHeaders(_ data: Data) -> ([String: String], Data) {
        let text = String(decoding: data, as: UTF8.self)
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard let range = normalized.range(of: "\n\n") else { return ([:], Data()) }
        let headerText = normalized[..<range.lowerBound]
        let body = Data(normalized[range.upperBound...].utf8)
        var headers: [String: String] = [:]
        var lastKey: String?
        for line in headerText.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, first == " " || first == "\t", let key = lastKey {
                headers[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].lowercased()
                headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                lastKey = key
            }
        }
        return (headers, body)
    }

    /// "text/html; charset=UTF-8" -> ("text/html", ["charset": "UTF-8"]).
    static func parseContentType(_ value: String) -> (String, [String: String]) {
        let pieces = value.split(separator: ";")
        let type = pieces.first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "text/plain"
        var parameters: [String: String] = [:]
        for piece in pieces.dropFirst() {
            let pair = piece.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            parameters[key] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
        }
        return (type, parameters)
    }

    static func split(_ body: Data, boundary: String) -> [Data] {
        let text = String(decoding: body, as: UTF8.self)
        let marker = "--" + boundary
        return text.components(separatedBy: marker)
            .dropFirst()
            .filter { !$0.hasPrefix("--") }
            .map { chunk in
                var part = chunk
                if part.hasPrefix("\n") { part.removeFirst() }
                return Data(part.utf8)
            }
    }

    static func quotedPrintable(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "=\n", with: "")
        var bytes: [UInt8] = []
        var index = text.utf8.startIndex
        let utf8 = text.utf8
        while index < utf8.endIndex {
            let byte = utf8[index]
            if byte == UInt8(ascii: "="),
               let first = utf8.index(index, offsetBy: 1, limitedBy: utf8.endIndex), first < utf8.endIndex,
               let second = utf8.index(index, offsetBy: 2, limitedBy: utf8.endIndex), second < utf8.endIndex,
               let value = UInt8(String(decoding: [utf8[first], utf8[second]], as: UTF8.self), radix: 16) {
                bytes.append(value)
                index = utf8.index(after: second)
            } else {
                bytes.append(byte)
                index = utf8.index(after: index)
            }
        }
        return Data(bytes)
    }
}
