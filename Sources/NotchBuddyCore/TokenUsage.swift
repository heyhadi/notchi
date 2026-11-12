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
    private var recentIDs: [String] = [] // streaming writes one line per content block, each repeating the message's usage; repeats sit next to each other, so only the last few ids matter

    public init() {}

    /// Cheap pre-filter: most lines have no usage, and parsing them as JSON is the expensive part.
    private static func hasUsage(_ line: Data.SubSequence) -> Bool {
        let needle = Array("\"usage\"".utf8)
        return line.withUnsafeBytes { buf in
            buf.baseAddress.map { memmem($0, buf.count, needle, needle.count) != nil } ?? false
        }
    }

    /// Full JSON parse of one line: the fallback when a line isn't in the compact shape `scan` relies on.
    private static func parseJSON(_ line: Data.SubSequence) -> (id: String?, c: TokenCount, ts: String?)? {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
              o["type"] as? String == "assistant",
              let msg = o["message"] as? [String: Any], let u = msg["usage"] as? [String: Any] else { return nil }
        var c = TokenCount()
        c.input = u["input_tokens"] as? Int ?? 0
        c.output = u["output_tokens"] as? Int ?? 0
        c.cacheWrite = u["cache_creation_input_tokens"] as? Int ?? 0
        c.cacheRead = u["cache_read_input_tokens"] as? Int ?? 0
        return (msg["id"] as? String, c, o["timestamp"] as? String)
    }

    /// Reads an assistant line's numbers straight from its bytes, with no JSON tree: for the big lines this is where the time
    /// and memory went. Quotes inside strings are escaped in JSON, so these unescaped patterns only match real structure.
    /// nil when the line isn't in the compact `"key":value` shape (then the JSON parse decides).
    private static func scan(_ line: Data.SubSequence) -> (id: String?, c: TokenCount, ts: String?)? {
        line.withUnsafeBytes { buf -> (id: String?, c: TokenCount, ts: String?)? in
            guard let base = buf.baseAddress, find("\"type\":\"assistant\"", base, buf.count) != nil else { return nil }
            var usage: Int?, from = 0   // the last "usage":{ in the line is the message's own
            while let i = find("\"usage\":{", base + from, buf.count - from) { usage = from + i; from += i + 1 }
            guard let u = usage else { return nil }
            func number(_ key: String) -> Int {
                guard let j = find("\"\(key)\":", base + u, buf.count - u) else { return 0 }
                var k = u + j + key.utf8.count + 3, n = 0
                while k < buf.count, buf[k] >= 48, buf[k] <= 57 { n = n * 10 + Int(buf[k] - 48); k += 1 }
                return n
            }
            func text(_ prefix: String, after: Int = 0) -> String? {
                guard let j = find(prefix, base + after, buf.count - after) else { return nil }
                let startAt = after + j + prefix.utf8.count
                var k = startAt
                while k < buf.count, buf[k] != UInt8(ascii: "\"") { k += 1 }
                return String(decoding: UnsafeRawBufferPointer(rebasing: buf[startAt..<k]), as: UTF8.self)
            }
            var c = TokenCount()
            c.input = number("input_tokens"); c.output = number("output_tokens")
            c.cacheWrite = number("cache_creation_input_tokens"); c.cacheRead = number("cache_read_input_tokens")
            let msgAt = find("\"message\":{", base, buf.count) ?? 0 // the first "id" inside the message object is the message's own
            return (text("\"id\":\"", after: msgAt), c, text("\"timestamp\":\""))
        }
    }

    /// Byte offset of `needle` in the buffer, nil if absent.
    private static func find(_ needle: String, _ base: UnsafeRawPointer, _ count: Int) -> Int? {
        let n = Array(needle.utf8)
        guard count >= n.count, let p = memmem(base, count, n, n.count) else { return nil }
        return base.distance(to: UnsafeRawPointer(p))
    }

    /// Feeds bytes read from `offset`. Only whole lines are used; a half-written last line is read again next time.
    public mutating func consume(_ data: Data, isToday: (Date) -> Bool) {
        guard let lastNL = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in data[data.startIndex...lastNL].split(separator: UInt8(ascii: "\n")) {
            // Per line: the parsed JSON of a big transcript would otherwise pile up until the whole read finishes.
            autoreleasepool {
                guard line.count > 20, Self.hasUsage(line) else { return }
                let parsed: (id: String?, c: TokenCount, ts: String?)
                if let fast = Self.scan(line) { parsed = fast }
                else if let slow = Self.parseJSON(line) { parsed = slow }
                else { return }
                if let id = parsed.id {
                    if recentIDs.contains(id) { return }
                    recentIDs.append(id)
                    if recentIDs.count > 16 { recentIDs.removeFirst() }
                }
                all.add(parsed.c)
                if let ts = parsed.ts.flatMap(iso.date(from:)), isToday(ts) { today.add(parsed.c) }
            }
        }
        offset += UInt64(lastNL - data.startIndex + 1)
    }
}

extension TokenCount {
    mutating func add(_ c: TokenCount) {
        input += c.input; output += c.output; cacheWrite += c.cacheWrite; cacheRead += c.cacheRead
    }
}
