import XCTest
@testable import NotchBuddyCore

final class AgentQuestionTests: XCTestCase {
    // Payload recorded from a real interactive Claude Code session (2026-11-12).
    let real = #"{"session_id":"s","cwd":"/p","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which fruit do you prefer?","header":"Fruit","options":[{"label":"Apple","description":"Apple"},{"label":"Banana","description":"Banana"},{"label":"Cherry","description":"Cherry"}],"multiSelect":false}]}}"#

    func testParseAndAnswer() throws {
        let e = try XCTUnwrap(HookEvent(json: Data(real.utf8)))
        let q = try XCTUnwrap(e.questions?.first)
        XCTAssertEqual(q.question, "Which fruit do you prefer?")
        XCTAssertEqual(q.options.map(\.label), ["Apple", "Banana", "Cherry"])
        XCTAssertFalse(q.multiSelect)
        XCTAssertEqual(CommandRisk.reasons(for: e), [])

        let out = try XCTUnwrap(AgentKind.claudeCode.answerOutput(for: e, answers: [q.question: "Banana"]))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: Any])
        let d = try XCTUnwrap((o["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        XCTAssertEqual(d["behavior"] as? String, "allow")
        let input = try XCTUnwrap(d["updatedInput"] as? [String: Any])
        XCTAssertEqual((input["answers"] as? [String: String])?[q.question], "Banana")
        XCTAssertNotNil(input["questions"], "original questions kept")
    }

    func testOtherToolsHaveNoQuestions() {
        XCTAssertNil(HookEvent(name: "PermissionRequest", sessionID: "s", toolName: "Bash", command: "ls").questions)
        XCTAssertNil(AgentKind.antigravity.answerOutput(for: HookEvent(json: Data(real.utf8))!, answers: [:]))
    }
}
