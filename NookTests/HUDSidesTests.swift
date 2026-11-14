import XCTest
@testable import Nook

final class HUDSidesTests: XCTestCase {
    func testUnknownSpaceUsesDesiredWidth() {
        XCTAssertEqual(HUDSides.make(desired: 58, leftFree: nil, rightFree: nil), HUDSides(left: 58, right: 58, merged: false))
    }

    func testBothSidesMatchTheNarrowerOne() {
        let sides = HUDSides.make(desired: 112, leftFree: 280, rightFree: 60)
        XCTAssertEqual(sides, HUDSides(left: 56, right: 56, merged: false))
    }

    /// Barra llena a la derecha (20 pt libres): todo el aviso pasa a la izquierda.
    func testCrowdedSideMovesEverythingToTheOther() {
        let sides = HUDSides.make(desired: 112, leftFree: 280, rightFree: 20)
        XCTAssertEqual(sides, HUDSides(left: 224, right: 0, merged: true))
        let narrow = HUDSides.make(desired: 112, leftFree: 100, rightFree: 20)
        XCTAssertEqual(narrow.left, 96)
    }

    func testGrowsComparesTotalWidth() {
        let none = HUDSides(left: 0, right: 0, merged: false)
        let pair = HUDSides(left: 40, right: 40, merged: false)
        let merged = HUDSides(left: 90, right: 0, merged: true)
        XCTAssertTrue(pair.grows(from: none))
        XCTAssertFalse(none.grows(from: pair))
        XCTAssertTrue(merged.grows(from: pair))
        XCTAssertFalse(pair.grows(from: merged))
        XCTAssertFalse(pair.grows(from: pair))
    }

    /// El nombre de unos auriculares cabe entero: el lado crece con el, con tope.
    func testDeviceNameFits() {
        let name = "AirPods Pro de Diego"
        let side = HUDActivity.side(for: .audioDevice(name: name, icon: "airpods.pro"))
        XCTAssertGreaterThanOrEqual(side - 10, HUDActivity.textWidth(name, size: 11), "contenido = lado menos el margen")
        XCTAssertEqual(HUDActivity.side(for: .audioDevice(name: "JBL", icon: "headphones")), 112)
        XCTAssertEqual(HUDActivity.side(for: .audioDevice(name: String(repeating: "x", count: 80), icon: "headphones")), 190)
        // Si la barra no deja ese sitio, va como isla bajo el notch.
        XCTAssertNotNil(HUDActivity.island(for: .audioDevice(name: name, icon: "airpods.pro"), leftFree: 300, rightFree: 80))
    }

    func testNoNoticeNoGrowth() {
        XCTAssertEqual(HUDSides.make(desired: 0, leftFree: 10, rightFree: 10), HUDSides(left: 0, right: 0, merged: false))
    }
}
@MainActor
final class SystemHUDTests: XCTestCase {
    private func makeHUD() -> SystemHUD {
        SystemHUD(defaults: UserDefaults(suiteName: "SystemHUDTests-\(UUID().uuidString)")!)
    }

    private func preview(_ action: @escaping () -> Void) -> SystemHUD.Preview {
        SystemHUD.Preview(symbol: "envelope.fill", title: "Ana", subtitle: "Factura", body: "Hola", actionTitle: "Abrir correo", action: action)
    }

    /// Pulsar el aviso abre su tarjeta con los datos, sin ir aun al origen.
    func testActivateKeepsPreviewWithoutRunningAction() {
        let hud = makeHUD()
        var opened = 0
        hud.show(.mail(sender: "Ana"), for: nil, preview: preview { opened += 1 })
        XCTAssertTrue(hud.isActionable)
        hud.activate()
        XCTAssertEqual(opened, 0)
        XCTAssertNil(hud.current)
        XCTAssertEqual(hud.activated?.subtitle, "Factura")
        XCTAssertEqual(hud.activated?.actionTitle, "Abrir correo")
    }

    /// El boton principal va al origen una sola vez y cierra la tarjeta.
    func testPrimaryButtonRunsActionAndCloses() {
        let hud = makeHUD()
        var opened = 0
        hud.show(.mail(sender: "Ana"), for: nil, preview: preview { opened += 1 })
        hud.activate()
        hud.performActivated()
        XCTAssertEqual(opened, 1)
        XCTAssertNil(hud.activated)
        hud.performActivated()
        XCTAssertEqual(opened, 1)
    }

    func testDismissClosesWithoutAction() {
        let hud = makeHUD()
        var opened = false
        hud.show(.mail(sender: "Ana"), for: nil, preview: preview { opened = true })
        hud.activate()
        hud.dismissActivated()
        XCTAssertNil(hud.activated)
        XCTAssertFalse(opened)
    }

    func testNewNoticeDropsPreviousPreview() {
        let hud = makeHUD()
        hud.show(.mail(sender: "Ana"), for: nil, preview: preview {})
        hud.show(.volume(level: 0.5, muted: false), for: nil)
        XCTAssertFalse(hud.isActionable)
        hud.activate()
        XCTAssertNil(hud.activated)
        // Sin tarjeta, el aviso se queda.
        XCTAssertEqual(hud.current, .volume(level: 0.5, muted: false))
    }
}
