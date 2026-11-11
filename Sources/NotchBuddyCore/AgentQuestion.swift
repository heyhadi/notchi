import Foundation

/// A question an agent asks with choices (Claude Code's AskUserQuestion tool), answerable from the notch.
public struct AgentQuestion: Sendable, Equatable {
    public struct Option: Sendable, Equatable {
        public let label: String
        public let description: String
    }
    public let question: String
    public let header: String
    public let options: [Option]
    public let multiSelect: Bool
}

extension HookEvent {
    /// Questions when this is an AskUserQuestion permission request (verified live: answering it with
    /// `updatedInput.answers` completes the tool with those answers).
    public var questions: [AgentQuestion]? {
        guard toolName == "AskUserQuestion", let json = toolInputJSON,
              let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let qs = o["questions"] as? [[String: Any]], !qs.isEmpty else { return nil }
        let parsed = qs.compactMap { q -> AgentQuestion? in
            guard let text = q["question"] as? String else { return nil }
            let opts = (q["options"] as? [[String: Any]] ?? []).compactMap { o -> AgentQuestion.Option? in
                guard let l = o["label"] as? String else { return nil }
                return .init(label: l, description: o["description"] as? String ?? "")
            }
            return AgentQuestion(question: text, header: q["header"] as? String ?? "", options: opts,
                                 multiSelect: q["multiSelect"] as? Bool ?? false)
        }
        return parsed.isEmpty ? nil : parsed
    }
}

extension AgentKind {
    /// PermissionRequest answer that fills in the user's choices: question text → chosen label(s), comma-separated
    /// for multi-select, or free text.
    public func answerOutput(for e: HookEvent, answers: [String: String]) -> Data? {
        guard self == .claudeCode, let json = e.toolInputJSON,
              var input = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return nil }
        input["answers"] = answers
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                                          "decision": ["behavior": "allow", "updatedInput": input]]]
        return try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    }
}
