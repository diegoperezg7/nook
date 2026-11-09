import XCTest
@testable import Nook

final class MailHTMLTests: XCTestCase {
    func testHandWrittenMailIsDark() {
        XCTAssertTrue(MailHTMLView.isPlain("<div>Hola, <b>Ana</b></div><p style=\"color:#000\">Gracias</p>"))
        XCTAssertTrue(MailHTMLView.isPlain("<td style=\"background: transparent\">x</td>"))
        XCTAssertTrue(MailHTMLView.wrap("<p>hola</p>").contains("content=\"dark\""))
    }

    func testDesignedMailStaysLight() {
        XCTAssertFalse(MailHTMLView.isPlain("<table bgcolor=\"#f4f4f4\"><tr><td>Oferta</td></tr></table>"))
        XCTAssertFalse(MailHTMLView.isPlain("<div style=\"background-color:#fff\">Factura</div>"))
        XCTAssertFalse(MailHTMLView.isPlain("<style>.h{background:#123}</style>"))
        XCTAssertTrue(MailHTMLView.wrap("<div style=\"background:#fff\">x</div>").contains("content=\"light\""))
    }
}
