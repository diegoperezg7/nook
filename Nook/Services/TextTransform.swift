import Foundation

/// "Copiar como" del historial: variantes de un texto copiado. Funciones puras;
/// nil si la transformacion no aplica (JSON invalido).
enum TextTransform: CaseIterable, Identifiable {
    case plain, uppercase, lowercase, titleCase, prettyJSON, singleLine

    var id: Self { self }

    func apply(_ text: String, locale: Locale = .current) -> String? {
        switch self {
        case .plain: return text
        case .uppercase: return text.uppercased(with: locale)
        case .lowercase: return text.lowercased(with: locale)
        case .titleCase: return text.capitalized(with: locale)
        case .prettyJSON: return Self.prettyJSON(text)
        case .singleLine:
            return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    /// Solo objetos o listas. ponytail: JSONSerialization no conserva el orden de las
    /// claves (se ordenan); un formateador propio si hiciera falta respetarlo.
    private static func prettyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}
