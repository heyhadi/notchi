import Foundation

/// One Claude Code hook payload (stdin JSON of the hook), reduced to what the app shows.
public struct HookEvent: Sendable, Equatable {
    public var agent: AgentKind = .claudeCode
    public var name: String
    public var sessionID: String
    public var cwd: String
    public var toolName: String?
    public var command: String?          // Bash tool_input.command
    public var filePath: String?         // Write/Edit/Read tool_input.file_path
    public var toolInputJSON: String?    // full tool_input, for the approval card when it is not Bash
    public var message: String?          // Notification message, Stop last_assistant_message, failure error
    public var notificationType: String?

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
    }

    public var project: String { (cwd as NSString).lastPathComponent }

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
    case deny(String)

    public var hookOutput: Data {
        var decision: [String: Any]
        switch self {
        case .allow: decision = ["behavior": "allow"]
        case .deny(let msg): decision = ["behavior": "deny", "message": msg]
        }
        let out = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
    }
}
