import XCTest
@testable import Nook

/// "Copiar como" del historial: cada transformacion de texto.
final class TextTransformTests: XCTestCase {
    private let es = Locale(identifier: "es_ES")

    func testPlainKeepsText() {
        XCTAssertEqual(TextTransform.plain.apply("Hola\n  mundo"), "Hola\n  mundo")
    }

    func testUppercaseWithAccents() {
        XCTAssertEqual(TextTransform.uppercase.apply("año acción pingüino", locale: es), "AÑO ACCIÓN PINGÜINO")
    }

    func testLowercaseWithAccents() {
        XCTAssertEqual(TextTransform.lowercase.apply("ÑANDÚ ÉXITO", locale: es), "ñandú éxito")
    }

    func testTitleCase() {
        XCTAssertEqual(TextTransform.titleCase.apply("ñandú EN el árbol", locale: es), "Ñandú En El Árbol")
    }

    func testPrettyJSON() {
        let result = TextTransform.prettyJSON.apply(#"{"b":[1,2],"a":"x/y"}"#)
        XCTAssertEqual(result, "{\n  \"a\" : \"x/y\",\n  \"b\" : [\n    1,\n    2\n  ]\n}")
    }

    func testInvalidJSONIsNil() {
        XCTAssertNil(TextTransform.prettyJSON.apply("{no es json"))
        XCTAssertNil(TextTransform.prettyJSON.apply("hola"))
        XCTAssertNil(TextTransform.prettyJSON.apply(""))
    }

    func testSingleLine() {
        XCTAssertEqual(TextTransform.singleLine.apply("  uno   dos\r\ntres\n\n\tcuatro  "), "uno dos tres cuatro")
    }
}
