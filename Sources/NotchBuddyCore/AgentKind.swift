import Foundation

/// Agents Notch Buddy can listen to. Raw value is the `--agent` id written into each agent's hook config.
public enum AgentKind: String, CaseIterable, Sendable, Codable {
    case claudeCode = "claude-code"

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        }
    }
}

extension HookEvent {
    /// Parses one hook message: optional "NB1 agent=<id>\n" header (no header = Claude Code), then the agent's JSON.
    /// Unknown agents and malformed payloads return nil.
    public static func parse(message data: Data) -> HookEvent? {
        var agent = AgentKind.claudeCode
        var body = data
        if data.starts(with: Data("NB1 ".utf8)), let nl = data.firstIndex(of: UInt8(ascii: "\n")) {
            let header = String(decoding: data[data.startIndex..<nl], as: UTF8.self)
            guard let id = header.split(separator: "=", maxSplits: 1).last, let kind = AgentKind(rawValue: String(id)) else { return nil }
            agent = kind
            body = data[(nl + 1)...]
        }
        switch agent {
        case .claudeCode:
            return HookEvent(json: Data(body))
        }
    }
}
