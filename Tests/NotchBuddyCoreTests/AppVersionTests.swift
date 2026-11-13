import XCTest
@testable import NotchBuddyCore

final class AppVersionTests: XCTestCase {
    func testNewer() {
        XCTAssertTrue(AppVersion.isNewer("v0.2.0", than: "0.1.0"))
        XCTAssertTrue(AppVersion.isNewer("0.1.10", than: "0.1.9"), "numeric, not text order")
        XCTAssertTrue(AppVersion.isNewer("1.0", than: "0.9.9"))
        XCTAssertTrue(AppVersion.isNewer("0.1.0.1", than: "0.1.0"))
    }

    func testNotNewer() {
        XCTAssertFalse(AppVersion.isNewer("v0.1.0", than: "0.1.0"))
        XCTAssertFalse(AppVersion.isNewer("0.1", than: "0.1.0"))
        XCTAssertFalse(AppVersion.isNewer("0.0.9", than: "0.1.0"))
        XCTAssertFalse(AppVersion.isNewer("v0.2.0-beta", than: "0.1.0"), "unparsable tags never update")
        XCTAssertFalse(AppVersion.isNewer("", than: "0.1.0"))
    }
}
