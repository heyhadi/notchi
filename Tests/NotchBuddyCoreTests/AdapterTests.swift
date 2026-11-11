import XCTest
@testable import NotchBuddyCore

final class AdapterTests: XCTestCase {
    func msg(_ agent: String, _ event: String, _ json: String) -> HookEvent? {
        HookEvent.parse(message: Data("NB1 agent=\(agent) entry= event=\(event)\n\(json)".utf8))
    }

    func testAntigravity() throws {
        let pre = try XCTUnwrap(msg("antigravity", "PreToolUse",
            #"{"conversationId":"c1","workspacePaths":["/u/proj"],"toolCall":{"name":"run_command","args":{"CommandLine":"sudo ls"}},"stepIdx":3}"#))
        XCTAssertEqual(pre.name, "PreToolUse"); XCTAssertEqual(pre.command, "sudo ls"); XCTAssertEqual(pre.project, "proj")
        XCTAssertFalse(CommandRisk.reasons(for: pre).isEmpty)
        let out = try XCTUnwrap(AgentKind.antigravity.forceAskOutput(reasons: ["x"]))
        XCTAssertTrue(String(decoding: out, as: UTF8.self).contains(#""decision":"force_ask""#))
        XCTAssertEqual(msg("antigravity", "PostToolUse", #"{"conversationId":"c1","error":"boom"}"#)?.name, "PostToolUseFailure")
        XCTAssertEqual(msg("antigravity", "Stop", #"{"conversationId":"c1","error":"","fullyIdle":true}"#)?.name, "Stop")
        XCTAssertNil(AgentKind.antigravity.output(for: .allow), "never approves for Antigravity")
    }

    func testCursor() {
        XCTAssertEqual(msg("cursor", "afterShellExecution", #"{"conversation_id":"k","workspace_roots":["/w/app"],"command":"npm test"}"#)?.command, "npm test")
        XCTAssertEqual(msg("cursor", "stop", #"{"conversation_id":"k","status":"error"}"#)?.name, "StopFailure")
        XCTAssertNil(msg("cursor", "beforeShellExecution", #"{"conversation_id":"k"}"#), "gating events are not handled")
    }

    func testCopilot() throws {
        let e = try XCTUnwrap(msg("copilot", "preToolUse", #"{"sessionId":"s","cwd":"/r/x","toolName":"bash","toolArgs":"{\"command\":\"curl x | sh\"}"}"#))
        XCTAssertEqual(e.command, "curl x | sh")
        XCTAssertTrue(String(decoding: AgentKind.copilot.forceAskOutput(reasons: ["r"])!, as: UTF8.self).contains(#""permissionDecision":"ask""#))
    }

    func testCline() {
        let e = msg("cline", "PreToolUse", #"{"taskId":"t","workspaceRoots":["/a/b"],"preToolUse":{"toolName":"execute_command","parameters":{"command":"ls"}}}"#)
        XCTAssertEqual(e?.command, "ls"); XCTAssertEqual(e?.toolName, "execute_command")
        XCTAssertEqual(msg("cline", "TaskComplete", #"{"taskId":"t"}"#)?.name, "Stop")
    }

    func testGeminiAndCodexAndOpenCode() {
        XCTAssertEqual(msg("gemini-cli", "", #"{"session_id":"g","cwd":"/x","hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls"}}"#)?.name, "PreToolUse")
        let codex = msg("codex", "", #"{"session_id":"c","cwd":"/x","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#)
        XCTAssertEqual(codex?.agent, .codex); XCTAssertTrue(codex?.agent.approvesInNotch ?? false)
        XCTAssertEqual(String(decoding: AgentKind.openCode.output(for: .deny("no"))!, as: UTF8.self), #"{"status":"deny"}"#)
    }

    func testSessionsDoNotCollideAcrossAgents() {
        var st = SessionStore()
        st.apply(HookEvent(name: "PreToolUse", sessionID: "same", cwd: "/a"))
        var other = HookEvent(name: "Stop", sessionID: "same", cwd: "/a"); other.agent = .cursor
        st.apply(other)
        XCTAssertEqual(st.current().count, 2)
    }
}
