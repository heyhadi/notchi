import Foundation

/// Token totals. `total` leaves out cache reads: they are cheap re-reads of context already counted when it was written.
public struct TokenCount: Equatable, Sendable {
    public var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    public var total: Int { input + output + cacheWrite }
    public init() {}

    /// "850", "48.2k", "1.3M".
    public static func short(_ n: Int) -> String {
        switch n {
        case ..<1000: return "\(n)"
        case ..<1_000_000: return String(format: "%.1fk", Double(n) / 1000).replacingOccurrences(of: ".0k", with: "k")
        default: return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}

/// Usage from one Claude Code transcript (~/.claude/projects/<dir>/<session>.jsonl), read incrementally as it grows.
public struct TranscriptUsage: Sendable {
    public private(set) var all = TokenCount()
    public private(set) var today = TokenCount()
    public private(set) var offset: UInt64 = 0
    private var seen: Set<String> = [] // streaming writes one line per content block, each repeating the message's usage

    public init() {}

    /// Feeds bytes read from `offset`. Only whole lines are used; a half-written last line is read again next time.
    public mutating func consume(_ data: Data, isToday: (Date) -> Bool) {
        guard let lastNL = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in data[data.startIndex...lastNL].split(separator: UInt8(ascii: "\n")) {
            guard line.count > 20, line.firstRange(of: Data("\"usage\"".utf8)) != nil,
                  let o = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  o["type"] as? String == "assistant",
                  let msg = o["message"] as? [String: Any], let u = msg["usage"] as? [String: Any] else { continue }
            if let id = msg["id"] as? String {
                guard seen.insert(id).inserted else { continue }
            }
            var c = TokenCount()
            c.input = u["input_tokens"] as? Int ?? 0
            c.output = u["output_tokens"] as? Int ?? 0
            c.cacheWrite = u["cache_creation_input_tokens"] as? Int ?? 0
            c.cacheRead = u["cache_read_input_tokens"] as? Int ?? 0
            all.add(c)
            if let ts = (o["timestamp"] as? String).flatMap(iso.date(from:)), isToday(ts) { today.add(c) }
        }
        offset += UInt64(lastNL - data.startIndex + 1)
    }
}

extension TokenCount {
    mutating func add(_ c: TokenCount) {
        input += c.input; output += c.output; cacheWrite += c.cacheWrite; cacheRead += c.cacheRead
    }
}
