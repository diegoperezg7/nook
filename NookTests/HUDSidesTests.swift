import XCTest
@testable import Nook

final class HUDSidesTests: XCTestCase {
    func testUnknownSpaceUsesDesiredWidth() {
        XCTAssertEqual(HUDSides.make(desired: 58, leftFree: nil, rightFree: nil), HUDSides(left: 58, right: 58, merged: false))
    }

    func testEachSideStopsAtTheMenuBarItems() {
        let sides = HUDSides.make(desired: 112, leftFree: 280, rightFree: 60)
        XCTAssertEqual(sides, HUDSides(left: 112, right: 56, merged: false))
    }

    /// Barra llena a la derecha (20 pt libres): todo el aviso pasa a la izquierda.
    func testCrowdedSideMovesEverythingToTheOther() {
        let sides = HUDSides.make(desired: 112, leftFree: 280, rightFree: 20)
        XCTAssertEqual(sides, HUDSides(left: 224, right: 0, merged: true))
        let narrow = HUDSides.make(desired: 112, leftFree: 100, rightFree: 20)
        XCTAssertEqual(narrow.left, 96)
    }

    func testNoNoticeNoGrowth() {
        XCTAssertEqual(HUDSides.make(desired: 0, leftFree: 10, rightFree: 10), HUDSides(left: 0, right: 0, merged: false))
    }
}
