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

    func testEmptyInbox() {
        XCTAssertTrue(MailService.parse("").isEmpty)
    }
}
