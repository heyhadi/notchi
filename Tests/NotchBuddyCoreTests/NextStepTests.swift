import XCTest
@testable import NotchBuddyCore

final class NextStepTests: XCTestCase {
    private let wrap = "mcp__ccd_turn__wrap_up"
    private let input = #"{"recap":"Done.","ask":"Cut v0.2.0?","actions":[{"label":"Yes, release"},{"action":"create_pr"}],"blocked":true}"#

    func testParsesAskAndChoices() {
        XCTAssertEqual(NextStep(toolName: wrap, toolInputJSON: input), NextStep(ask: "Cut v0.2.0?", choices: ["Yes, release", "Create Pr"]))
    }

    func testIgnoresOtherToolsAndRecapOnly() {
        XCTAssertNil(NextStep(toolName: "Bash", toolInputJSON: input))
        XCTAssertNil(NextStep(toolName: wrap, toolInputJSON: #"{"recap":"All done."}"#))
        XCTAssertNil(NextStep(toolName: wrap, toolInputJSON: #"{"recap":"x","ask":"  "}"#))
    }

    func testTurnEndsWaitingOnTheUser() {
        var store = SessionStore()
        let t = Date()
        store.apply(HookEvent(name: "UserPromptSubmit", sessionID: "a", cwd: "/p"), at: t)
        store.apply(HookEvent(name: "PreToolUse", sessionID: "a", cwd: "/p", toolName: wrap, toolInputJSON: input), at: t)
        store.apply(HookEvent(name: "Stop", sessionID: "a", cwd: "/p", message: "Here you go"), at: t)
        var s = store.current(at: t.addingTimeInterval(600))[0]
        XCTAssertEqual(s.state, .needsYou, "a question keeps waiting; it never falls back to sleeping")
        XCTAssertEqual(s.message, "Cut v0.2.0?")
        store.apply(HookEvent(name: "UserPromptSubmit", sessionID: "a", cwd: "/p"), at: t)
        s = store.current(at: t)[0]
        XCTAssertEqual(s.state, .thinking)
        XCTAssertNil(s.nextStep)
    }

    func testRecapWithoutQuestionEndsDone() {
        var store = SessionStore()
        store.apply(HookEvent(name: "PreToolUse", sessionID: "a", cwd: "/p", toolName: wrap, toolInputJSON: #"{"recap":"x"}"#))
        store.apply(HookEvent(name: "Stop", sessionID: "a", cwd: "/p"))
        XCTAssertEqual(store.current()[0].state, .done)
    }
}
