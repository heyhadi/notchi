import XCTest
@testable import NotchBuddyCore

final class StopRequestsTests: XCTestCase {
    func ev(_ name: String, _ sid: String = "s") -> HookEvent { HookEvent(name: name, sessionID: sid, toolName: "Bash", command: "ls") }

    func testFiresOnceOnNextPreToolUse() throws {
        var r = StopRequests()
        XCTAssertNil(r.apply(ev("PreToolUse")), "nothing armed")
        r.toggle("claude-code:s")
        XCTAssertNil(r.apply(ev("PreToolUse", "other")), "other sessions carry on")
        XCTAssertNil(r.apply(ev("PostToolUse")))
        let out = try XCTUnwrap(r.apply(ev("PreToolUse")))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: Any])
        XCTAssertEqual(o["continue"] as? Bool, false)
        XCTAssertEqual(o["stopReason"] as? String, "Stopped from Notchi")
        XCTAssertEqual((o["hookSpecificOutput"] as? [String: Any])?["permissionDecision"] as? String, "deny")
        XCTAssertNil(r.apply(ev("PreToolUse")), "only once")
    }

    func testClearedByStopEndOrNewPromptAndToggle() {
        for name in ["Stop", "StopFailure", "SessionEnd", "UserPromptSubmit"] {
            var r = StopRequests(); r.toggle("claude-code:s")
            _ = r.apply(ev(name))
            XCTAssertFalse(r.contains("claude-code:s"), name)
        }
        var r = StopRequests(); r.toggle("claude-code:s"); r.toggle("claude-code:s")
        XCTAssertNil(r.apply(ev("PreToolUse")), "toggled off")
    }

    func testClaudeCodeOnly() {
        XCTAssertNotNil(AgentKind.claudeCode.stopOutput)
        XCTAssertTrue(AgentKind.allCases.filter { $0 != .claudeCode }.allSatisfy { $0.stopOutput == nil })
    }
}
