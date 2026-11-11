import XCTest
@testable import NotchBuddyCore

final class SoundGateTests: XCTestCase {
    func testOneSoundPerMinute() {
        var g = SoundGate()
        let t = Date()
        XCTAssertTrue(g.allow(at: t))
        XCTAssertFalse(g.allow(at: t.addingTimeInterval(1)))
        XCTAssertFalse(g.allow(at: t.addingTimeInterval(59.9)))
        XCTAssertTrue(g.allow(at: t.addingTimeInterval(60)))
        XCTAssertFalse(g.allow(at: t.addingTimeInterval(61)), "blocked calls must not reset the window either way")
    }
}
