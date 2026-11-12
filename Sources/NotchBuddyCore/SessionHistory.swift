import Foundation

/// One finished session, kept on this Mac only (history.json).
public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var agentLabel: String
    public var project: String
    public var started: Date?
    public var ended: Date
    public var tokens: Int?
    public var id: String { "\(agentLabel)|\(project)|\(ended.timeIntervalSince1970)" }

    public init(agentLabel: String, project: String, started: Date?, ended: Date, tokens: Int?) {
        self.agentLabel = agentLabel; self.project = project; self.started = started; self.ended = ended; self.tokens = tokens
    }
    public var duration: TimeInterval? { started.map { ended.timeIntervalSince($0) } }
}

public enum SessionHistory {
    /// Newest first; bad or missing data reads as empty.
    public static func load(_ data: Data?) -> [HistoryEntry] {
        data.flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? []
    }

    public static func appending(_ e: HistoryEntry, to data: Data?, limit: Int = 100) -> Data? {
        try? JSONEncoder().encode(Array(([e] + load(data)).prefix(limit)))
    }
}
