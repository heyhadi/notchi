import XCTest
@testable import NotchBuddyCore

final class TerminalReplyTests: XCTestCase {
    private func session(state: AgentState = .done, label: String = "Claude Code", tty: String? = "/dev/ttys004") -> AgentSession {
        var s = AgentSession(id: "claude-code:a", project: "p", cwd: "/p", updated: Date())
        s.state = state; s.agentLabel = label; s.tty = tty
        return s
    }

    func testTypesOnlyIntoAnIdleCLISession() {
        XCTAssertTrue(TerminalReply.canType(session()))
        XCTAssertFalse(TerminalReply.canType(session(state: .working)), "never mid-turn")
        XCTAssertFalse(TerminalReply.canType(session(state: .thinking)))
        XCTAssertFalse(TerminalReply.canType(session(state: .needsYou)))
        XCTAssertFalse(TerminalReply.canType(session(label: "Claude Code (Desktop)")))
        XCTAssertFalse(TerminalReply.canType(session(tty: nil)))
        XCTAssertFalse(TerminalReply.canType(session(tty: "/dev/ttys1\"; do shell script \"x")))
    }

    func testEscapesTextIntoOneAppleScriptString() throws {
        let s = try XCTUnwrap(TerminalReply.script(app: "Terminal", tty: "/dev/ttys004", text: "say \"hi\" \\ now\nrm -rf x\u{1B}[A"))
        XCTAssertTrue(s.contains(#"do script "say \"hi\" \\ now rm -rf x [A" in t"#), s)
        XCTAssertTrue(s.contains(#"if tty of t is "/dev/ttys004" then"#))
        XCTAssertTrue(TerminalReply.script(app: "iTerm2", tty: "/dev/ttys004", text: "ok")?.contains(#"write text "ok""#) == true)
    }

    func testRefusesBadTTYEmptyTextAndUnknownApps() {
        XCTAssertNil(TerminalReply.script(app: "Terminal", tty: "/dev/tty.evil", text: "hi"))
        XCTAssertNil(TerminalReply.script(app: "Terminal", tty: "/dev/ttys004", text: " \n\t "))
        XCTAssertNil(TerminalReply.script(app: "Ghostty", tty: "/dev/ttys004", text: "hi"))
    }

    func testFindsTheWezTermPaneByTTY() {
        let list = Data(#"[{"pane_id":0,"tty_name":"/dev/ttys001"},{"pane_id":7,"tty_name":"/dev/ttys004"}]"#.utf8)
        XCTAssertEqual(TerminalReply.wezTermPane(tty: "/dev/ttys004", listJSON: list), 7)
        XCTAssertNil(TerminalReply.wezTermPane(tty: "/dev/ttys009", listJSON: list))
        XCTAssertNil(TerminalReply.wezTermPane(tty: "/dev/ttys004\n", listJSON: list), "only a valid tty")
        XCTAssertNil(TerminalReply.wezTermPane(tty: "/dev/ttys004", listJSON: Data("not json".utf8)))
        XCTAssertEqual(TerminalReply.oneLine(" a\nb\u{7}c "), "a b c")
    }

    func testFindOnlyScriptTypesNothing() throws {
        let s = try XCTUnwrap(TerminalReply.script(app: "Terminal", tty: "/dev/ttys004", text: nil))
        XCTAssertTrue(s.contains(#"if tty of t is "/dev/ttys004" then"#))
        XCTAssertFalse(s.contains("do script"))
        XCTAssertFalse(TerminalReply.script(app: "iTerm2", tty: "/dev/ttys004", text: nil)?.contains("write text") ?? true)
    }
}
