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

final class SessionHistoryTests: XCTestCase {
    func testNewestFirstAndCapped() {
        var data: Data?
        for i in 0..<5 {
            data = SessionHistory.appending(HistoryEntry(agentLabel: "A", project: "p\(i)", started: nil, ended: Date(timeIntervalSince1970: Double(i)), tokens: nil), to: data, limit: 3)
        }
        XCTAssertEqual(SessionHistory.load(data).map(\.project), ["p4", "p3", "p2"])
        XCTAssertEqual(SessionHistory.load(Data("junk".utf8)), [])
    }
}

final class MidTurnChatTests: XCTestCase {
    func testOnlyClaudeCodeGetsMidTurnContext() throws {
        let out = try XCTUnwrap(AgentKind.claudeCode.midTurnOutput("hi"))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: Any])
        let h = try XCTUnwrap(o["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(h["hookEventName"] as? String, "PostToolUse")
        XCTAssertTrue((h["additionalContext"] as? String ?? "").hasSuffix("hi"))
        XCTAssertNil(AgentKind.codex.midTurnOutput("hi"))
    }
}
