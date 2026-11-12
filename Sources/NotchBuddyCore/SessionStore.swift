import Foundation

/// One Claude Code session as the notch sees it.
public struct AgentSession: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public var agent: AgentKind = .claudeCode
    public var agentLabel = "Claude Code"
    public var project: String
    public var cwd: String
    public var state: AgentState = .sleeping
    public var lastStep: String?
    public var message: String?
    public var steps = 0          // tool calls since the last prompt ("progress")
    public var updated: Date
    public var tty: String?        // terminal the agent runs in, when its hook could tell
    public var started: Date?      // first event we saw for it (nil for sessions saved before this existed)
}

/// Pure reducer from hook events to sessions; the app owns one and publishes its output.
public struct SessionStore: Sendable {
    public private(set) var sessions: [String: AgentSession] = [:]
    /// done/error/thinking sessions with no event for this long fall back to sleeping.
    public var idleAfter: TimeInterval = 120

    public init() {}

    /// Sessions as saved at the last quit, minus anything older than `maxAge`; they come back sleeping until a new event arrives.
    public static func restored(from data: Data, maxAge: TimeInterval = 12 * 3600, at now: Date = Date()) -> [String: AgentSession] {
        guard let list = try? JSONDecoder().decode([AgentSession].self, from: data) else { return [:] }
        return Dictionary(list.filter { now.timeIntervalSince($0.updated) <= maxAge }.map { s -> (String, AgentSession) in
            var s = s; s.state = .sleeping; s.message = nil; return (s.id, s)
        }, uniquingKeysWith: { a, _ in a })
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(Array(sessions.values)) }

    public mutating func restore(_ restored: [String: AgentSession]) { sessions.merge(restored) { live, _ in live } }

    public mutating func apply(_ e: HookEvent, at now: Date = Date()) {
        let key = Self.key(e)
        if e.name == "SessionEnd" { sessions[key] = nil; return }
        var s = sessions[key] ?? AgentSession(id: key, agent: e.agent, project: e.project, cwd: e.cwd, updated: now)
        if !e.cwd.isEmpty { s.cwd = e.cwd; s.project = e.project }
        s.agentLabel = e.agentLabel
        s.updated = now
        s.started = s.started ?? now
        if let t = e.tty { s.tty = t }
        switch e.name {
        case "SessionStart": s.state = .sleeping
        case "UserPromptSubmit": s.state = .thinking; s.steps = 0; s.message = nil
        case "PreToolUse": s.state = .working; s.lastStep = e.stepSummary ?? s.lastStep
        case "PostToolUse": s.state = .working; s.steps += 1
        case "PostToolUseFailure", "StopFailure": s.state = .error; s.message = e.message
        case "PermissionRequest": s.state = .needsYou; s.lastStep = e.stepSummary ?? s.lastStep
        case "Notification":
            // Only prompts that block on the user; idle reminders would nag.
            guard ["permission_prompt", "elicitation_dialog"].contains(e.notificationType ?? "") else { break }
            s.state = .needsYou; s.message = e.message
        case "Stop" where s.state != .error: s.state = .done; s.message = e.message // an idle right after a failure keeps the error
        default: break
        }
        sessions[key] = s
    }

    /// Session ids are only unique per agent.
    public static func key(_ e: HookEvent) -> String { "\(e.agent.rawValue):\(e.sessionID)" }

    /// The user answered a pending request in the notch; the tool will run (or not) next.
    public mutating func resolvePermission(sessionID: String, at now: Date = Date()) {
        guard var s = sessions[sessionID], s.state == .needsYou else { return }
        s.state = .working; s.updated = now
        sessions[sessionID] = s
    }

    /// The user replied from the notch; the agent is about to continue.
    public mutating func markThinking(key: String, at now: Date = Date()) {
        guard var s = sessions[key] else { return }
        s.state = .thinking; s.steps = 0; s.message = nil; s.updated = now
        sessions[key] = s
    }

    public func current(at now: Date = Date()) -> [AgentSession] {
        sessions.values.map { s in
            var s = s
            if [.done, .error, .thinking].contains(s.state), now.timeIntervalSince(s.updated) > idleAfter { s.state = .sleeping }
            return s
        }.sorted { $0.state.priority != $1.state.priority ? $0.state.priority > $1.state.priority : $0.updated > $1.updated }
    }

    public func topState(at now: Date = Date()) -> AgentState { AgentState.top(current(at: now).map(\.state)) }
}
