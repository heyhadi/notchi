import Foundation

/// "Stop after this step" requests, by SessionStore key. The session's next PreToolUse answers with the agent's stop output,
/// so that tool never runs and the turn ends; a finished turn, an ended session or a new prompt drops the request.
public struct StopRequests: Sendable, Equatable {
    public private(set) var keys: Set<String> = []
    public init() {}

    public mutating func toggle(_ key: String) { if keys.remove(key) == nil { keys.insert(key) } }
    public func contains(_ key: String) -> Bool { keys.contains(key) }

    /// The hook answer for `e` (nil = carry on as usual), dropping the request once it fired or no longer applies.
    public mutating func apply(_ e: HookEvent) -> Data? {
        let key = SessionStore.key(e)
        guard keys.contains(key) else { return nil }
        switch e.name {
        case "PreToolUse": keys.remove(key); return e.agent.stopOutput
        case "Stop", "StopFailure", "SessionEnd", "UserPromptSubmit": keys.remove(key)
        default: break
        }
        return nil
    }
}

extension AgentKind {
    /// PreToolUse answer that stops the agent before the tool runs (Claude Code only: Codex parses `continue` but ignores it).
    /// `continue: false` ends the turn; the deny makes sure the tool doesn't run either way.
    public var stopOutput: Data? {
        guard self == .claudeCode else { return nil }
        let reason = "Stopped from Notchi"
        return try? JSONSerialization.data(withJSONObject: [
            "continue": false, "stopReason": reason,
            "hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason],
        ] as [String: Any], options: [.sortedKeys])
    }
}
