import XCTest
@testable import Nook

/// Lectura de la respuesta de AppleScript de la bandeja de entrada.
final class MailServiceTests: XCTestCase {
    private let us = "\u{1F}", rs = "\u{1E}"

    func testParsesAndSortsNewestFirst() {
        let text = ["a1", "Ana López", "Presupuesto", "2026-11-09T09:15:00"].joined(separator: us) + rs
            + ["b2", "Luis", "Reunión", "2026-11-09T11:40:00"].joined(separator: us) + rs
        let messages = MailService.parse(text)
        XCTAssertEqual(messages.map(\.id), ["b2", "a1"])
        XCTAssertEqual(messages.last?.sender, "Ana López")
        XCTAssertEqual(Calendar.current.component(.hour, from: messages[0].date), 11)
    }

    func testMissingSubjectAndBrokenRecords() {
        let text = ["c3", "Marta", "missing value", "2026-11-08T18:00:00"].joined(separator: us) + rs + "roto" + rs
        let messages = MailService.parse(text)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].subject, "")
    }

    /// El sexto campo dice si esta leido; sin el, cuenta como sin leer.
    func testReadFlag() {
        let text = ["e5", "Ana", "Hola", "2026-11-09T10:00:00", "", "true"].joined(separator: us) + rs
            + ["f6", "Luis", "Adios", "2026-11-09T09:00:00", "", "false"].joined(separator: us) + rs
            + ["g7", "Marta", "Viejo", "2026-11-09T08:00:00"].joined(separator: us) + rs
        XCTAssertEqual(MailService.parse(text).map(\.isRead), [true, false, false])
    }

    func testEmptyInbox() {
        XCTAssertTrue(MailService.parse("").isEmpty)
    }

    /// La vista previa llega en una sola linea, sin saltos.
    func testPreviewIsOneLine() {
        let text = ["d4", "Ana", "Hola", "2026-11-09T10:00:00", "Hola Diego,\r\n\r\n  te paso   el informe"].joined(separator: us) + rs
        XCTAssertEqual(MailService.parse(text).first?.preview, "Hola Diego, te paso el informe")
    }

    /// El cuerpo puede llevar el separador de campos: no se corta.
    func testDetailKeepsBodyAndCollapsesBlankLines() throws {
        let body = "Hola,\n\n\n\nAdjunto va el contrato.\u{1F}Fin\n"
        let text = ["Ana López", "ana@ejemplo.com", "missing value", "2026-11-09T09:15:00", body].joined(separator: us)
        let detail = try XCTUnwrap(MailService.parseDetail(text))
        XCTAssertEqual(detail.address, "ana@ejemplo.com")
        XCTAssertEqual(detail.subject, "")
        XCTAssertEqual(detail.body, "Hola,\n\nAdjunto va el contrato.\u{1F}Fin")
        XCTAssertNil(MailService.parseDetail("roto"))
    }

    // MARK: - Responder desde el notch

    private let tricky = "Hola \"Ana\",\nla ruta es C:\\temp\\ y\r\nseguimos. Á é ñ ü «ok» & <b>"

    /// El literal se lee igual en AppleScript (se ejecuta solo `return`, sin apps).
    func testLiteralRoundTripsInAppleScript() throws {
        var error: NSDictionary?
        let output = NSAppleScript(source: "return " + MailService.literal(tricky))?.executeAndReturnError(&error)
        XCTAssertNil(error)
        XCTAssertEqual(output?.stringValue, tricky.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    func testLiteralHasNoRawLineBreaksOrLooseQuotes() {
        let literal = MailService.literal(tricky)
        XCTAssertFalse(literal.contains("\n") || literal.contains("\r"))
        XCTAssertEqual(MailService.literal("a\"b\\c"), #""a\"b\\c""#)
    }

    func testMailReplyScriptSendsWithoutWindow() {
        let script = MailService.replyScript(for: .mail, id: "x\"1@ejemplo", text: tricky)
        XCTAssertTrue(script.hasPrefix("tell application \"Mail\""))
        XCTAssertTrue(script.contains(#"message id is "x\"1@ejemplo""#))
        XCTAssertTrue(script.contains("set r to reply m without opening window"))
        XCTAssertTrue(script.contains("set content of r to " + MailService.literal(tricky) + " & return & return & q"))
        XCTAssertTrue(script.contains("\nsend r\n"))
    }

    func testOutlookReplyScriptUsesEscapedHTML() {
        let script = MailService.replyScript(for: .outlook, id: "12a3", text: "a < b & c\nfin")
        XCTAssertTrue(script.contains("set m to message id 123\n"))
        XCTAssertTrue(script.contains("set r to reply to m without opening window"))
        XCTAssertTrue(script.contains(#"set content of r to "<div>a &lt; b &amp; c<br>fin</div><br>" & q"#))
        XCTAssertTrue(script.contains("\nsend r\n"))
    }
}
