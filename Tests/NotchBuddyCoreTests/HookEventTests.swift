import XCTest
@testable import NotchBuddyCore

final class HookEventTests: XCTestCase {
    func testParsePermissionRequest() throws {
        let json = #"{"session_id":"abc","cwd":"/Users/me/form-keeper","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"},"permission_mode":"default"}"#
        let e = try XCTUnwrap(HookEvent(json: Data(json.utf8)))
        XCTAssertEqual(e.name, "PermissionRequest")
        XCTAssertEqual(e.project, "form-keeper")
        XCTAssertEqual(e.command, "npm test")
        XCTAssertEqual(e.stepSummary, "Bash: npm test")
        XCTAssertTrue(e.toolInputJSON?.contains("Run tests") ?? false)
    }

    func testParseNotificationAndStop() throws {
        let n = try XCTUnwrap(HookEvent(json: Data(#"{"session_id":"a","cwd":"/x","hook_event_name":"Notification","message":"Claude needs your permission","notification_type":"permission_prompt"}"#.utf8)))
        XCTAssertEqual(n.notificationType, "permission_prompt")
        XCTAssertEqual(n.message, "Claude needs your permission")
        let s = try XCTUnwrap(HookEvent(json: Data(#"{"session_id":"a","cwd":"/x","hook_event_name":"Stop","last_assistant_message":"All done"}"#.utf8)))
        XCTAssertEqual(s.message, "All done")
    }

    func testRejectsGarbage() {
        XCTAssertNil(HookEvent(json: Data("not json".utf8)))
        XCTAssertNil(HookEvent(json: Data(#"{"session_id":"a"}"#.utf8)))
        XCTAssertNil(HookEvent(json: Data(#"[1,2]"#.utf8)))
    }

    func testMessageHeader() throws {
        let body = #"{"session_id":"a","cwd":"/x","hook_event_name":"Stop"}"#
        XCTAssertEqual(HookEvent.parse(message: Data(body.utf8))?.agent, .claudeCode, "no header = Claude Code")
        XCTAssertEqual(HookEvent.parse(message: Data(("NB1 agent=claude-code\n" + body).utf8))?.name, "Stop")
        XCTAssertNil(HookEvent.parse(message: Data(("NB1 agent=evil\n" + body).utf8)), "unknown agent rejected")
        let vs = HookEvent.parse(message: Data(("NB1 agent=claude-code entry=claude-vscode\n" + body).utf8))
        XCTAssertEqual(vs?.agentLabel, "Claude Code (VS Code)")
        XCTAssertEqual(HookEvent.parse(message: Data(("NB1 agent=claude-code entry=cli\n" + body).utf8))?.agentLabel, "Claude Code")
    }

    func testDecisionOutput() throws {
        let allow = try XCTUnwrap(JSONSerialization.jsonObject(with: PermissionDecision.allow.hookOutput) as? [String: Any])
        let hso = try XCTUnwrap(allow["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hso["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual((hso["decision"] as? [String: Any])?["behavior"] as? String, "allow")
        let deny = String(decoding: PermissionDecision.deny("no").hookOutput, as: UTF8.self)
        XCTAssertTrue(deny.contains(#""behavior":"deny""#) && deny.contains(#""message":"no""#))
    }

    func testSessionRules() throws {
        let bash = #"{"session_id":"a","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm:*"}],"behavior":"allow","destination":"localSettings"}]}"#
        let e = try XCTUnwrap(HookEvent(json: Data(bash.utf8)))
        let rules = try XCTUnwrap(e.sessionRules)
        XCTAssertEqual(rules, #"[{"behavior":"allow","destination":"session","rules":[{"ruleContent":"npm test","toolName":"Bash"}],"type":"addRules"}]"#,
                       "Bash: the exact command, never Claude's prefix suggestion")
        let out = String(decoding: try XCTUnwrap(AgentKind.claudeCode.output(for: .allowInSession(rules))), as: UTF8.self)
        XCTAssertEqual(out, #"{"hookSpecificOutput":{"decision":{"behavior":"allow","updatedPermissions":[{"behavior":"allow","destination":"session","rules":[{"ruleContent":"npm test","toolName":"Bash"}],"type":"addRules"}]},"hookEventName":"PermissionRequest"}}"#)
        XCTAssertFalse(String(decoding: try XCTUnwrap(AgentKind.codex.output(for: .allowInSession(rules))), as: UTF8.self).contains("updatedPermissions"),
                       "Codex fails closed on updatedPermissions")
        XCTAssertTrue(AgentKind.claudeCode.allowsInSession); XCTAssertFalse(AgentKind.codex.allowsInSession); XCTAssertFalse(AgentKind.openCode.allowsInSession)

        let edit = #"{"session_id":"a","hook_event_name":"PermissionRequest","tool_name":"Edit","tool_input":{"file_path":"/p/a.swift"},"permission_suggestions":[{"type":"setMode","mode":"acceptEdits","destination":"session"},{"type":"setMode","mode":"bypassPermissions","destination":"session"},{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"rm:*"}],"behavior":"allow","destination":"userSettings"},{"type":"addRules","rules":[{"toolName":"WebFetch","ruleContent":"domain:x.dev"}],"behavior":"allow","destination":"userSettings"}]}"#
        XCTAssertEqual(HookEvent(json: Data(edit.utf8))?.sessionRules,
                       #"[{"destination":"session","mode":"acceptEdits","type":"setMode"},{"behavior":"allow","destination":"session","rules":[{"ruleContent":"domain:x.dev","toolName":"WebFetch"}],"type":"addRules"}]"#,
                       "accept-edits and allow rules only, narrowed to the session; never bypass mode or a Bash rule")
        XCTAssertNil(HookEvent(name: "PermissionRequest", sessionID: "a", toolName: "Edit").sessionRules, "no suggestion → no button")
    }
}

final class SessionStoreTests: XCTestCase {
    func ev(_ name: String, _ sid: String = "s1", type: String? = nil) -> HookEvent {
        HookEvent(name: name, sessionID: sid, cwd: "/p/proj", toolName: "Bash", command: "ls", notificationType: type)
    }

    func testLifecycle() {
        var st = SessionStore()
        let t = Date()
        st.apply(ev("UserPromptSubmit"), at: t); XCTAssertEqual(st.topState(at: t), .thinking)
        st.apply(ev("PreToolUse"), at: t); XCTAssertEqual(st.topState(at: t), .working)
        st.apply(ev("PostToolUse"), at: t); XCTAssertEqual(st.current(at: t).first?.steps, 1)
        st.apply(ev("PermissionRequest"), at: t); XCTAssertEqual(st.topState(at: t), .needsYou)
        st.resolvePermission(sessionID: "claude-code:s1", at: t); XCTAssertEqual(st.topState(at: t), .working)
        st.apply(ev("Stop"), at: t); XCTAssertEqual(st.topState(at: t), .done)
        XCTAssertEqual(st.topState(at: t.addingTimeInterval(121)), .sleeping)
        st.apply(ev("SessionEnd"), at: t); XCTAssertTrue(st.current(at: t).isEmpty)
    }

    func testIdleNotificationIgnoredAndPriorityAcrossSessions() {
        var st = SessionStore()
        let t = Date()
        st.apply(ev("Stop", "a"), at: t)
        st.apply(ev("Notification", "a", type: "idle_prompt"), at: t)
        XCTAssertEqual(st.topState(at: t), .done)
        st.apply(ev("PreToolUse", "b"), at: t)
        st.apply(ev("PostToolUseFailure", "c"), at: t)
        XCTAssertEqual(st.topState(at: t), .error)
        st.apply(ev("Notification", "b", type: "permission_prompt"), at: t)
        XCTAssertEqual(st.current(at: t).map(\.state), [.needsYou, .error, .done])
        st.apply(ev("Stop", "c"), at: t)
        XCTAssertEqual(st.sessions["claude-code:c"]?.state, .error, "Stop after a failure keeps Error")
    }
}
