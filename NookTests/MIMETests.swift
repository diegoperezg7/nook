import XCTest
@testable import Nook

final class MIMETests: XCTestCase {
    private let source = """
    From: Ana <ana@ejemplo.com>
    Subject: Hola
    Content-Type: multipart/related;
     boundary="REL"

    --REL
    Content-Type: multipart/alternative; boundary="ALT"

    --ALT
    Content-Type: text/plain; charset=utf-8

    Hola en texto
    --ALT
    Content-Type: text/html; charset="iso-8859-1"
    Content-Transfer-Encoding: quoted-printable

    <p>Caf=E9 con <b>Ana</b> ma=
    =F1ana</p><img src=3D"cid:logo@x">
    --ALT--
    --REL
    Content-Type: image/png
    Content-Transfer-Encoding: base64
    Content-ID: <logo@x>

    iVBORw0KGgo=
    --REL--
    """

    func testExtractsHTMLWithCharsetAndInlineImage() throws {
        let html = try XCTUnwrap(MIME.html(fromSource: source))
        XCTAssertTrue(html.contains("<p>Café con <b>Ana</b> mañana</p>"), html)
        XCTAssertTrue(html.contains("src=\"data:image/png;base64,iVBORw0KGgo=\""), html)
        XCTAssertFalse(html.contains("cid:"))
    }

    func testPlainOnlyHasNoHTML() {
        XCTAssertNil(MIME.html(fromSource: "Content-Type: text/plain\n\nsolo texto"))
    }

    func testFoldedHeadersAndParameters() {
        let (type, parameters) = MIME.parseContentType("Multipart/Mixed; boundary=\"abc\"; charset=UTF-8")
        XCTAssertEqual(type, "multipart/mixed")
        XCTAssertEqual(parameters["boundary"], "abc")
        XCTAssertEqual(parameters["charset"], "UTF-8")
    }
}
