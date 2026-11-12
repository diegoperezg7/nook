import XCTest
@testable import Nook

/// Avisos de macOS leidos por Accesibilidad: app y textos.
final class NotificationBannersTests: XCTestCase {
    func testWhatsAppBanner() throws {
        let banner = try XCTUnwrap(NotificationBanners.parse(
            id: "A1", description: "\u{200E}WhatsApp, Ana, Hola", texts: ["title": "Ana", "body": "\u{200E}Hola"]
        ))
        XCTAssertEqual(banner.appName, "WhatsApp")
        XCTAssertEqual(banner.title, "Ana")
        XCTAssertEqual(banner.body, "Hola")
    }

    func testBannerWithSubtitle() throws {
        let banner = try XCTUnwrap(NotificationBanners.parse(
            id: "B2", description: "Editor de scripts, Prueba, Visor, Hola",
            texts: ["title": "Prueba", "subtitle": "Visor", "body": "Hola"]
        ))
        XCTAssertEqual(banner.appName, "Editor de scripts")
        XCTAssertEqual(banner.subtitle, "Visor")
    }

    func testEmptyBannerIsIgnored() {
        XCTAssertNil(NotificationBanners.parse(id: "C3", description: "WhatsApp", texts: [:]))
        XCTAssertNil(NotificationBanners.parse(id: "C4", description: "", texts: ["title": "x"]))
    }

    /// El siguiente mensaje reutiliza el mismo aviso: cuenta como nuevo si cambia.
    func testSameBannerWithNewMessageIsNew() throws {
        let first = try XCTUnwrap(NotificationBanners.parse(id: "D5", description: "WhatsApp, Ana, Hola", texts: ["title": "Ana", "body": "Hola"]))
        let second = try XCTUnwrap(NotificationBanners.parse(id: "D5", description: "WhatsApp, Ana, Vienes?", texts: ["title": "Ana", "body": "Vienes?"]))
        XCTAssertNotEqual(first.key, second.key)
    }
}
