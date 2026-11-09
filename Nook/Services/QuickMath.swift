import Foundation

/// Cuentas y conversiones del lanzador. Analizador propio (no NSExpression, que
/// lanza excepciones con entradas raras).
enum QuickMath {
    /// "12*7+3", "(2+3)^2", "15% de 80", "2,5 * 4" -> numero.
    static func evaluate(_ text: String) -> Double? {
        var input = text.lowercased().replacingOccurrences(of: " ", with: "")
        // "15%de80" -> 15/100*80
        if let range = input.range(of: #"^([0-9.,]+)%(de|of)([0-9.,]+)$"#, options: .regularExpression), range == input.startIndex..<input.endIndex {
            let parts = input.replacingOccurrences(of: "of", with: "de").components(separatedBy: "%de")
            guard parts.count == 2, let a = number(parts[0]), let b = number(parts[1]) else { return nil }
            return a / 100 * b
        }
        input = input.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "x", with: "*").replacingOccurrences(of: ",", with: ".")
        guard input.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%()")) != nil,
              input.allSatisfy({ "0123456789.+-*/^%()".contains($0) }) else { return nil }
        var parser = Parser(Array(input))
        guard let value = parser.expression(), parser.atEnd, value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        init(_ chars: [Character]) { self.chars = chars }
        var atEnd: Bool { index == chars.count }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while index < chars.count, chars[index] == "+" || chars[index] == "-" {
                let op = chars[index]; index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while index < chars.count, "*/%".contains(chars[index]) {
                let op = chars[index]; index += 1
                guard let rhs = power() else { return nil }
                switch op {
                case "*": value *= rhs
                case "/": value /= rhs
                default: value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if index < chars.count, chars[index] == "^" {
                index += 1
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func unary() -> Double? {
            if index < chars.count, chars[index] == "-" { index += 1; return unary().map { -$0 } }
            if index < chars.count, chars[index] == "+" { index += 1; return unary() }
            return primary()
        }

        mutating func primary() -> Double? {
            guard index < chars.count else { return nil }
            if chars[index] == "(" {
                index += 1
                let value = expression()
                guard index < chars.count, chars[index] == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
            return index > start ? Double(String(chars[start..<index])) : nil
        }
    }

    // MARK: - Unidades

    /// "10 km en millas", "5 lb to kg", "30 °C en F" -> "6,21 mi".
    static func convert(_ text: String) -> String? {
        let pattern = #"^\s*(-?[0-9]+(?:[.,][0-9]+)?)\s*([a-zA-Zº°µ]+[0-9]?)\s+(?:en|a|to|in)\s+([a-zA-Zº°µ]+[0-9]?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text), let fromRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text),
              let value = number(String(text[valueRange])),
              let from = unit(String(text[fromRange])), let to = unit(String(text[toRange])),
              from.dimensionKind == to.dimensionKind else { return nil }
        let measurement = Measurement(value: value, unit: from)
        let converted = measurement.converted(to: to)
        return format((converted.value * 100).rounded() / 100) + " " + to.symbol
    }

    private static let units: [String: Dimension] = [
        "km": UnitLength.kilometers, "m": UnitLength.meters, "cm": UnitLength.centimeters, "mm": UnitLength.millimeters,
        "mi": UnitLength.miles, "milla": UnitLength.miles, "millas": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
        "ft": UnitLength.feet, "pie": UnitLength.feet, "pies": UnitLength.feet, "feet": UnitLength.feet,
        "in": UnitLength.inches, "pulgada": UnitLength.inches, "pulgadas": UnitLength.inches, "inch": UnitLength.inches, "inches": UnitLength.inches,
        "yd": UnitLength.yards,
        "kg": UnitMass.kilograms, "g": UnitMass.grams, "mg": UnitMass.milligrams, "lb": UnitMass.pounds, "lbs": UnitMass.pounds,
        "libra": UnitMass.pounds, "libras": UnitMass.pounds, "oz": UnitMass.ounces, "onza": UnitMass.ounces, "onzas": UnitMass.ounces,
        "c": UnitTemperature.celsius, "°c": UnitTemperature.celsius, "ºc": UnitTemperature.celsius, "celsius": UnitTemperature.celsius,
        "f": UnitTemperature.fahrenheit, "°f": UnitTemperature.fahrenheit, "ºf": UnitTemperature.fahrenheit, "fahrenheit": UnitTemperature.fahrenheit,
        "k": UnitTemperature.kelvin, "kelvin": UnitTemperature.kelvin,
        "l": UnitVolume.liters, "litro": UnitVolume.liters, "litros": UnitVolume.liters, "ml": UnitVolume.milliliters,
        "gal": UnitVolume.gallons, "galon": UnitVolume.gallons, "galones": UnitVolume.gallons,
        "kmh": UnitSpeed.kilometersPerHour, "mph": UnitSpeed.milesPerHour, "ms": UnitSpeed.metersPerSecond,
        "kb": UnitInformationStorage.kilobytes, "mb": UnitInformationStorage.megabytes, "gb": UnitInformationStorage.gigabytes,
        "tb": UnitInformationStorage.terabytes,
    ]

    private static func unit(_ text: String) -> Dimension? {
        let key = text.lowercased()
        return units[key] ?? units[key.replacingOccurrences(of: "°", with: "").replacingOccurrences(of: "º", with: "")]
    }
}

private extension Dimension {
    /// Para no convertir km en kg.
    var dimensionKind: String {
        switch self {
        case is UnitLength: return "length"
        case is UnitMass: return "mass"
        case is UnitTemperature: return "temperature"
        case is UnitVolume: return "volume"
        case is UnitSpeed: return "speed"
        case is UnitInformationStorage: return "storage"
        default: return String(describing: type(of: self))
        }
    }
}
