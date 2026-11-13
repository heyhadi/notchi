import Foundation

/// One Claude Code hook payload (stdin JSON of the hook), reduced to what the app shows.
public struct HookEvent: Sendable, Equatable {
    public var agent: AgentKind = .claudeCode
    public var surface: String?          // "VS Code", "Desktop"… when not a plain terminal
    public var name: String
    public var sessionID: String
    public var cwd: String
    public var toolName: String?
    public var command: String?          // Bash tool_input.command
    public var filePath: String?         // Write/Edit/Read tool_input.file_path
    public var toolInputJSON: String?    // full tool_input, for the approval card when it is not Bash
    public var message: String?          // Notification message, Stop last_assistant_message, failure error
    public var notificationType: String?
    public var tty: String?              // /dev/ttysNNN of the terminal the agent runs in (sent by the hook helper), for jumping to its tab
    public var permissionSuggestions: String? // PermissionRequest permission_suggestions (JSON array), Claude Code's own "don't ask again" options

    public init(name: String, sessionID: String, cwd: String = "", toolName: String? = nil, command: String? = nil,
                filePath: String? = nil, toolInputJSON: String? = nil, message: String? = nil, notificationType: String? = nil) {
        self.name = name; self.sessionID = sessionID; self.cwd = cwd; self.toolName = toolName; self.command = command
        self.filePath = filePath; self.toolInputJSON = toolInputJSON; self.message = message; self.notificationType = notificationType
    }

    /// Returns nil for anything that is not a JSON object with hook_event_name and session_id.
    public init?(json data: Data) {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = o["hook_event_name"] as? String,
              let sid = o["session_id"] as? String else { return nil }
        let input = o["tool_input"] as? [String: Any]
        self.init(name: name, sessionID: sid, cwd: o["cwd"] as? String ?? "",
                  toolName: o["tool_name"] as? String,
                  command: input?["command"] as? String,
                  filePath: input?["file_path"] as? String,
                  toolInputJSON: input.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) }
                      .flatMap { String(data: $0, encoding: .utf8) },
                  message: (o["message"] ?? o["last_assistant_message"] ?? o["error"]) as? String,
                  notificationType: o["notification_type"] as? String)
        permissionSuggestions = (o["permission_suggestions"] as? [Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
            .map { String(decoding: $0, as: UTF8.self) }
    }

    public var project: String { (cwd as NSString).lastPathComponent }

    /// "Claude Code" or "Claude Code (VS Code)".
    public var agentLabel: String { surface.map { "\(agent.displayName) (\($0))" } ?? agent.displayName }

    /// Short "last step" text, e.g. "Bash: npm test" or "Edit: Foo.swift".
    public var stepSummary: String? {
        guard let tool = toolName else { return nil }
        if let c = command { return "\(tool): \(c.split(separator: "\n").first.map(String.init) ?? c)" }
        if let p = filePath { return "\(tool): \((p as NSString).lastPathComponent)" }
        return tool
    }
}

/// The app's answer to a PermissionRequest hook.
public enum PermissionDecision: Sendable {
    case allow
    case allowInSession(String)          // allow, plus `updatedPermissions` (JSON array from HookEvent.sessionRules)
    case deny(String)

    public var hookOutput: Data {
        var decision: [String: Any]
        switch self {
        case .allow: decision = ["behavior": "allow"]
        case .allowInSession(let rules):
            decision = ["behavior": "allow"]
            decision["updatedPermissions"] = (try? JSONSerialization.jsonObject(with: Data(rules.utf8))) as? [Any]
        case .deny(let msg): decision = ["behavior": "deny", "message": msg]
        }
        let out = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
    }
}

extension HookEvent {
    /// Session-only rules for "Always allow in this session", or nil when there is nothing safe to add.
    /// Bash gets the exact command only: a prefix rule (Claude Code often suggests `npm:*`) could later run a risky command with no card.
    /// Other tools echo Claude Code's own suggestions (allow rules, or accept-edits mode), always narrowed to this session.
    public var sessionRules: String? {
        var out: [[String: Any]] = []
        if toolName == "Bash" {
            if let c = command { out = [["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": c]], "behavior": "allow", "destination": "session"]] }
        } else if let s = permissionSuggestions, let list = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [[String: Any]] {
            out = list.compactMap { var r = $0
                let rules = r["rules"] as? [[String: Any]] ?? []
                let addAllow = r["type"] as? String == "addRules" && r["behavior"] as? String == "allow" && !rules.isEmpty
                    && !rules.contains { $0["toolName"] as? String == "Bash" }
                let acceptEdits = r["type"] as? String == "setMode" && r["mode"] as? String == "acceptEdits"
                guard addAllow || acceptEdits else { return nil }
                r["destination"] = "session"
                return r
            }
        }
        guard !out.isEmpty, let d = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }
}

/// Only a plain /dev/ttysNNN is ever kept: the value ends up in an AppleScript, so nothing else may pass.
public func validTTY(_ s: String?) -> String? {
    guard let s, s.range(of: #"^/dev/ttys[0-9]{1,4}$"#, options: .regularExpression) != nil else { return nil }
    return s
}
