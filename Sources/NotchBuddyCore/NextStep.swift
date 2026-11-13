import Foundation

/// The question and answer buttons the Claude desktop app shows at the end of a turn (its `wrap_up` tool).
/// The app answers it in its own window, so the notch can only show it and send you there.
public struct NextStep: Sendable, Equatable, Codable {
    public var ask: String
    public var choices: [String]

    public init(ask: String, choices: [String]) { self.ask = ask; self.choices = choices }

    /// nil unless this is the desktop app's wrap-up call and it asks something.
    public init?(toolName: String?, toolInputJSON: String?) {
        guard let toolName, toolName.hasPrefix("mcp__ccd_turn__"), toolName.hasSuffix("wrap_up"),
              let data = toolInputJSON?.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ask = (o["ask"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty else { return nil }
        // A reply button has a label; an app action ("commit", "create_pr") may only name itself.
        let choices = (o["actions"] as? [[String: Any]] ?? []).compactMap { a -> String? in
            if let l = a["label"] as? String, !l.isEmpty { return l }
            return (a["action"] as? String).map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        }
        self.init(ask: ask, choices: Array(choices.prefix(3)))
    }
}
