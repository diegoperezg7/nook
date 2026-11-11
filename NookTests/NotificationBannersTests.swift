import XCTest
@testable import Nook

/// Avisos de macOS leidos por Accesibilidad: app, textos y si se puede responder.
final class NotificationBannersTests: XCTestCase {
    private let reply = "Name:\u{200E}Responder\nTarget:0x0\nSelector:(null)"
    private let details = "Name:Mostrar detalles\nTarget:0x0\nSelector:(null)"

    func testWhatsAppBannerCanReply() throws {
        let banner = try XCTUnwrap(NotificationBanners.parse(
            id: "A1", description: "\u{200E}WhatsApp, Ana, Hola",
            texts: ["title": "Ana", "body": "\u{200E}Hola"], actions: ["AXPress", details, reply]
        ))
        XCTAssertEqual(banner.appName, "WhatsApp")
        XCTAssertEqual(banner.title, "Ana")
        XCTAssertEqual(banner.body, "Hola")
        XCTAssertTrue(banner.canReply)
    }

    func testBannerWithoutReply() throws {
        let banner = try XCTUnwrap(NotificationBanners.parse(
            id: "B2", description: "Editor de scripts, Prueba, Visor, Hola",
            texts: ["title": "Prueba", "subtitle": "Visor", "body": "Hola"], actions: ["AXPress", details]
        ))
        XCTAssertEqual(banner.appName, "Editor de scripts")
        XCTAssertEqual(banner.subtitle, "Visor")
        XCTAssertFalse(banner.canReply)
    }

    func testEmptyBannerIsIgnored() {
        XCTAssertNil(NotificationBanners.parse(id: "C3", description: "WhatsApp", texts: [:], actions: []))
        XCTAssertNil(NotificationBanners.parse(id: "C4", description: "", texts: ["title": "x"], actions: []))
    }

    func testActionTitles() {
        XCTAssertEqual(NotificationBanners.actionTitle(reply), "Responder")
        XCTAssertEqual(NotificationBanners.actionTitle("AXPress"), "AXPress")
        XCTAssertTrue(NotificationBanners.isReply("Reply"))
        XCTAssertTrue(NotificationBanners.isSend(NotificationBanners.actionTitle("Name:\u{200E}Enviar\nTarget:0x0")))
        XCTAssertFalse(NotificationBanners.isReply("Mostrar"))
    }
}
