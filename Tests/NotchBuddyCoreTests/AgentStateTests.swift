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
