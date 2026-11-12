import XCTest
@testable import NotchBuddyCore

final class AgentStateTests: XCTestCase {
    func testPriorityOrder() {
        XCTAssertEqual(AgentState.top([]), .sleeping)
        XCTAssertEqual(AgentState.top([.working, .thinking]), .working)
        XCTAssertEqual(AgentState.top([.done, .working, .error]), .error)
        XCTAssertEqual(AgentState.top([.error, .needsYou, .done]), .needsYou)
        let ordered: [AgentState] = [.sleeping, .thinking, .working, .done, .error, .needsYou]
        XCTAssertEqual(ordered.map(\.priority), ordered.map(\.priority).sorted())
    }
}

final class SessionPersistenceTests: XCTestCase {
    func testRoundTripDropsOldAndSleeps() throws {
        let now = Date()
        var fresh = AgentSession(id: "a:1", project: "p", cwd: "/p", updated: now.addingTimeInterval(-60)); fresh.state = .working
        let old = AgentSession(id: "a:2", project: "q", cwd: "/q", updated: now.addingTimeInterval(-13 * 3600))
        var st = SessionStore(); st.restore([fresh.id: fresh, old.id: old])
        let back = SessionStore.restored(from: try XCTUnwrap(st.encoded()), at: now)
        XCTAssertEqual(Array(back.keys), ["a:1"])
        XCTAssertEqual(back["a:1"]?.state, .sleeping)
    }
}
