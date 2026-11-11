import Foundation

/// One Claude Code session as the notch sees it.
public struct AgentSession: Identifiable, Sendable, Equatable {
    public let id: String
    public var agent: AgentKind = .claudeCode
    public var project: String
    public var cwd: String
    public var state: AgentState = .sleeping
    public var lastStep: String?
    public var message: String?
    public var steps = 0          // tool calls since the last prompt ("progress")
    public var updated: Date
}

/// Pure reducer from hook events to sessions; the app owns one and publishes its output.
public struct SessionStore: Sendable {
    public private(set) var sessions: [String: AgentSession] = [:]
    /// done/error/thinking sessions with no event for this long fall back to sleeping.
    public var idleAfter: TimeInterval = 120

    public init() {}

    public mutating func apply(_ e: HookEvent, at now: Date = Date()) {
        let key = Self.key(e)
        if e.name == "SessionEnd" { sessions[key] = nil; return }
        var s = sessions[key] ?? AgentSession(id: key, agent: e.agent, project: e.project, cwd: e.cwd, updated: now)
        if !e.cwd.isEmpty { s.cwd = e.cwd; s.project = e.project }
        s.updated = now
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
        case "Stop": s.state = .done; s.message = e.message
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

    public func current(at now: Date = Date()) -> [AgentSession] {
        sessions.values.map { s in
            var s = s
            if [.done, .error, .thinking].contains(s.state), now.timeIntervalSince(s.updated) > idleAfter { s.state = .sleeping }
            return s
        }.sorted { $0.state.priority != $1.state.priority ? $0.state.priority > $1.state.priority : $0.updated > $1.updated }
    }

    public func topState(at now: Date = Date()) -> AgentState { AgentState.top(current(at: now).map(\.state)) }
}
