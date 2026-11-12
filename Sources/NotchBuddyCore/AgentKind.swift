import Foundation

/// Agents Notch Buddy can listen to. Raw value is the `--agent` id written into each agent's hook config.
public enum AgentKind: String, CaseIterable, Sendable, Codable {
    case claudeCode = "claude-code"
    case codex
    case antigravity
    case geminiCLI = "gemini-cli"
    case cursor
    case copilot
    case cline
    case openCode = "opencode"

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .geminiCLI: "Gemini CLI"
        case .cursor: "Cursor"
        case .copilot: "GitHub Copilot"
        case .cline: "Cline"
        case .openCode: "OpenCode"
        }
    }

    /// Agents with a real "permission requested" hook whose answer we can give. Everyone else is status-only:
    /// their own approval prompt stays in charge, and Notch Buddy never approves on their behalf.
    public var approvesInNotch: Bool { [.claudeCode, .codex, .openCode].contains(self) }

    /// Answer to an approval made in the notch, in the agent's own hook format.
    public func output(for d: PermissionDecision) -> Data? {
        switch self {
        case .claudeCode, .codex:
            return d.hookOutput
        case .openCode:
            if case .deny = d { return json(["status": "deny"]) }
            return json(["status": "allow"])
        default:
            return nil
        }
    }

    /// Agents you can reply to from the notch. Messages are delivered at the end of a turn (Stop hook): that's the
    /// one place the agent treats injected text as coming from the user (mid-turn context is treated as tool output).
    public var supportsChat: Bool { [.claudeCode, .codex, .antigravity, .openCode].contains(self) }

    /// Stop-hook answer that makes the agent continue with the user's message.
    public func chatOutput(_ text: String) -> Data? {
        // Chat UIs show this as a hook message, not a user bubble, so the quote keeps the message visible in the history.
        let framed = "Message from the user, sent from Notchi. Start your reply with the message quoted on one line as "
            + "\"> From notch: <message>\", then act on it.\n\n" + text
        switch self {
        case .claudeCode, .codex: return json(["decision": "block", "reason": framed])
        case .antigravity: return json(["decision": "continue", "reason": framed])
        case .openCode: return json(["prompt": text]) // the plugin sends it as a real prompt
        default: return nil
        }
    }

    /// A chat message delivered in the middle of a turn (after a tool call) instead of at its end. Claude Code only: its PostToolUse hook
    /// can add context the model reads before its next step. Others wait for the Stop hook.
    public func midTurnOutput(_ text: String) -> Data? {
        guard self == .claudeCode else { return nil }
        let framed = "Message from the user, sent from Notchi while you were working. Start your next reply text with the message quoted on one line as "
            + "\"> From notch: <message>\", then act on it.\n\n" + text
        return json(["hookSpecificOutput": ["hookEventName": "PostToolUse", "additionalContext": framed]])
    }

    /// For a risky command: force the agent's own prompt where the hook format allows it (nil = leave the agent alone).
    public func forceAskOutput(reasons: [String]) -> Data? {
        let reason = "Notchi: " + reasons.joined(separator: ", ") + ". Approve this yourself."
        switch self {
        case .antigravity: return json(["decision": "force_ask", "reason": reason])
        case .copilot: return json(["permissionDecision": "ask", "permissionDecisionReason": reason])
        default: return nil
        }
    }
}

private func json(_ o: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) }

extension HookEvent {
    /// Parses one hook message: optional "NB1 agent=<id> [entry=<x>] [event=<Name>]\n" header (no header = Claude Code),
    /// then the agent's JSON. Every agent is mapped onto Claude Code's event vocabulary. Unknown agents and malformed
    /// payloads return nil.
    public static func parse(message data: Data) -> HookEvent? {
        var agent = AgentKind.claudeCode
        var kv: [String: String] = [:]
        var body = data
        if data.starts(with: Data("NB1 ".utf8)), let nl = data.firstIndex(of: UInt8(ascii: "\n")) {
            let fields = String(decoding: data[data.startIndex..<nl], as: UTF8.self).split(separator: " ").dropFirst()
            kv = Dictionary(fields.map { $0.split(separator: "=", maxSplits: 1).map(String.init) }.filter { $0.count == 2 }.map { ($0[0], $0[1]) },
                            uniquingKeysWith: { a, _ in a })
            guard let id = kv["agent"], let kind = AgentKind(rawValue: id) else { return nil }
            agent = kind
            body = data[(nl + 1)...]
        }
        guard let o = (try? JSONSerialization.jsonObject(with: Data(body))) as? [String: Any] else { return nil }
        // The event name comes from the hook config (--event) when the agent's payload doesn't carry one.
        let event = kv["event"].flatMap { $0.isEmpty ? nil : $0 } ?? (o["hook_event_name"] ?? o["hookEventName"]) as? String

        var e: HookEvent?
        switch agent {
        case .claudeCode, .codex, .openCode:
            e = HookEvent(json: Data(body)) // OpenCode's plugin sends Claude-shaped JSON itself
        case .geminiCLI:
            e = HookEvent(json: Data(body))
            let raw = e?.name ?? ""
            e?.name = ["BeforeAgent": "UserPromptSubmit", "BeforeTool": "PreToolUse", "AfterTool": "PostToolUse", "AfterAgent": "Stop"][raw] ?? raw
        case .antigravity:
            e = antigravity(o, event: event)
        case .cursor:
            e = cursor(o, event: event)
        case .copilot:
            e = copilot(o, event: event)
        case .cline:
            e = cline(o, event: event)
        }
        e?.agent = agent
        e?.tty = validTTY(kv["tty"])
        if agent == .claudeCode { e?.surface = surfaceLabel(kv["entry"] ?? "") } // other agents inherit a stray env var
        return e
    }

    private static func tool(_ name: String, session: String, cwd: String, tool: String?, args: Any?, message: String? = nil) -> HookEvent {
        let a = args as? [String: Any] ?? (args as? String).flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
        func str(_ keys: [String]) -> String? { keys.lazy.compactMap { a?[$0] as? String }.first }
        return HookEvent(name: name, sessionID: session, cwd: cwd, toolName: tool,
                         command: str(["command", "CommandLine", "cmd"]),
                         filePath: str(["file_path", "filePath", "TargetFile", "path", "AbsolutePath"]),
                         toolInputJSON: a.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) }
                             .flatMap { String(data: $0, encoding: .utf8) } ?? (args as? String),
                         message: message)
    }

    // https://antigravity.google/docs/hooks — camelCase, conversationId, toolCall {name, args}
    private static func antigravity(_ o: [String: Any], event: String?) -> HookEvent? {
        guard let sid = o["conversationId"] as? String, let event else { return nil }
        let cwd = o["cwd"] as? String ?? (o["workspacePaths"] as? [String])?.first ?? ""
        let call = o["toolCall"] as? [String: Any]
        let err = (o["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let name: String
        switch event {
        case "SessionStart": name = "SessionStart"
        case "PreInvocation": name = "UserPromptSubmit" // model call: thinking
        case "PreToolUse": name = "PreToolUse"
        case "PostToolUse": name = err == nil ? "PostToolUse" : "PostToolUseFailure"
        case "Stop": name = err == nil ? "Stop" : "StopFailure"
        default: return nil
        }
        return tool(name, session: sid, cwd: cwd, tool: call?["name"] as? String, args: call?["args"], message: err)
    }

    // https://cursor.com/docs/hooks — only non-gating events are registered (a gating hook that fails would block Cursor).
    private static func cursor(_ o: [String: Any], event: String?) -> HookEvent? {
        guard let sid = o["conversation_id"] as? String, let event else { return nil }
        let cwd = o["cwd"] as? String ?? (o["workspace_roots"] as? [String])?.first ?? ""
        switch event {
        case "sessionStart": return HookEvent(name: "SessionStart", sessionID: sid, cwd: cwd)
        case "sessionEnd": return HookEvent(name: "SessionEnd", sessionID: sid, cwd: cwd)
        case "afterAgentThought": return HookEvent(name: "UserPromptSubmit", sessionID: sid, cwd: cwd)
        case "postToolUse": return tool("PostToolUse", session: sid, cwd: cwd, tool: o["tool_name"] as? String, args: o["tool_input"])
        case "postToolUseFailure": return tool("PostToolUseFailure", session: sid, cwd: cwd, tool: o["tool_name"] as? String, args: o["tool_input"])
        case "afterShellExecution": return tool("PostToolUse", session: sid, cwd: cwd, tool: "Shell", args: ["command": o["command"] ?? ""])
        case "afterFileEdit": return tool("PostToolUse", session: sid, cwd: cwd, tool: "Edit", args: ["file_path": o["file_path"] ?? ""])
        case "stop":
            let failed = (o["status"] as? String) == "error"
            return HookEvent(name: failed ? "StopFailure" : "Stop", sessionID: sid, cwd: cwd)
        default: return nil
        }
    }

    // https://docs.github.com/en/copilot/reference/hooks-reference — camelCase sessionId/toolName/toolArgs
    private static func copilot(_ o: [String: Any], event: String?) -> HookEvent? {
        guard let sid = (o["sessionId"] ?? o["session_id"]) as? String, let event else { return nil }
        let cwd = o["cwd"] as? String ?? ""
        let tname = (o["toolName"] ?? o["tool_name"]) as? String
        let args = o["toolArgs"] ?? o["tool_input"]
        switch event {
        case "sessionStart": return HookEvent(name: "SessionStart", sessionID: sid, cwd: cwd)
        case "sessionEnd": return HookEvent(name: "SessionEnd", sessionID: sid, cwd: cwd)
        case "userPromptSubmitted": return HookEvent(name: "UserPromptSubmit", sessionID: sid, cwd: cwd)
        case "preToolUse": return tool("PreToolUse", session: sid, cwd: cwd, tool: tname, args: args)
        case "postToolUse": return tool("PostToolUse", session: sid, cwd: cwd, tool: tname, args: args)
        case "agentStop": return HookEvent(name: "Stop", sessionID: sid, cwd: cwd)
        default: return nil
        }
    }

    // Cline hook scripts (~/Documents/Cline/Hooks/<Event>): taskId + an event-keyed object, e.g. preToolUse.toolName/parameters.
    private static func cline(_ o: [String: Any], event: String?) -> HookEvent? {
        guard let sid = o["taskId"] as? String, let event else { return nil }
        let cwd = (o["workspaceRoots"] as? [String])?.first ?? ""
        let key = event.prefix(1).lowercased() + event.dropFirst()
        let d = o[key] as? [String: Any]
        switch event {
        case "TaskStart", "TaskResume", "UserPromptSubmit": return HookEvent(name: "UserPromptSubmit", sessionID: sid, cwd: cwd)
        case "PreToolUse": return tool("PreToolUse", session: sid, cwd: cwd, tool: d?["toolName"] as? String, args: d?["parameters"])
        case "PostToolUse":
            let failed = (d?["success"] as? Bool) == false
            return tool(failed ? "PostToolUseFailure" : "PostToolUse", session: sid, cwd: cwd, tool: d?["toolName"] as? String, args: d?["parameters"])
        case "TaskComplete": return HookEvent(name: "Stop", sessionID: sid, cwd: cwd)
        case "TaskCancel": return HookEvent(name: "SessionEnd", sessionID: sid, cwd: cwd)
        default: return nil
        }
    }
}

/// Human label for CLAUDE_CODE_ENTRYPOINT-style values; nil for the plain CLI.
func surfaceLabel(_ entry: String) -> String? {
    if entry.contains("vscode") { return "VS Code" }
    if entry.contains("jetbrains") { return "JetBrains" }
    if entry.contains("desktop") { return "Desktop" }
    return nil
}
