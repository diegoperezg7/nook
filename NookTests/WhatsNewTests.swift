import XCTest
@testable import Nook

final class WhatsNewTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "WhatsNewTests")
        defaults.removePersistentDomain(forName: "WhatsNewTests")
    }

    func testNotShownOnFirstInstall() {
        XCTAssertFalse(WhatsNew.shouldShow(defaults: defaults, firstLaunch: true))
        XCTAssertFalse(WhatsNew.shouldShow(defaults: defaults, firstLaunch: false))
    }

    func testShownOnceAfterUpdate() {
        defaults.set("0.0.1", forKey: WhatsNew.seenKey)
        XCTAssertTrue(WhatsNew.shouldShow(defaults: defaults, firstLaunch: false))
        XCTAssertFalse(WhatsNew.shouldShow(defaults: defaults, firstLaunch: false))
    }

    func testShownToUsersUpdatingFromBeforeThisFeature() {
        XCTAssertTrue(WhatsNew.shouldShow(defaults: defaults, firstLaunch: false))
    }
}
