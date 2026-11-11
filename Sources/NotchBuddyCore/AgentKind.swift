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
        var entry = ""
        var body = data
        if data.starts(with: Data("NB1 ".utf8)), let nl = data.firstIndex(of: UInt8(ascii: "\n")) {
            let fields = String(decoding: data[data.startIndex..<nl], as: UTF8.self).split(separator: " ").dropFirst()
            let kv = Dictionary(fields.map { $0.split(separator: "=", maxSplits: 1).map(String.init) }.filter { $0.count == 2 }.map { ($0[0], $0[1]) },
                                uniquingKeysWith: { a, _ in a })
            guard let id = kv["agent"], let kind = AgentKind(rawValue: id) else { return nil }
            agent = kind
            entry = kv["entry"] ?? ""
            body = data[(nl + 1)...]
        }
        var e: HookEvent?
        switch agent {
        case .claudeCode:
            e = HookEvent(json: Data(body))
        }
        e?.agent = agent
        e?.surface = surfaceLabel(entry)
        return e
    }
}

/// Human label for CLAUDE_CODE_ENTRYPOINT-style values; nil for the plain CLI.
func surfaceLabel(_ entry: String) -> String? {
    if entry.contains("vscode") { return "VS Code" }
    if entry.contains("jetbrains") { return "JetBrains" }
    if entry.contains("desktop") { return "Desktop" }
    return nil
}
