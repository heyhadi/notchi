import Foundation

/// One line of a diff preview.
public struct DiffLine: Sendable, Equatable {
    public enum Kind: Sendable { case same, added, removed }
    public let kind: Kind
    public let text: String
}

public enum LineDiff {
    static func split(_ s: String) -> [String] {
        s.isEmpty ? [] : s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLastIf("")
    }

    /// Lines of `old` → `new` (LCS-based), keeping only changed lines plus `context` unchanged lines around each change; a gap is one `.same` line with text "…".
    public static func lines(old: String, new: String, context: Int = 2) -> [DiffLine] {
        let a = split(old), b = split(new)
        var all: [DiffLine] = []
        if a.count * b.count > 250_000 {
            all = a.map { DiffLine(kind: .removed, text: $0) } + b.map { DiffLine(kind: .added, text: $0) }
        } else {
            var t = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
                }
            }
            var i = 0, j = 0
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, a[i] == b[j] { all.append(.init(kind: .same, text: a[i])); i += 1; j += 1 }
                else if i < a.count, j == b.count || t[i + 1][j] >= t[i][j + 1] { all.append(.init(kind: .removed, text: a[i])); i += 1 }
                else { all.append(.init(kind: .added, text: b[j])); j += 1 }
            }
        }
        let keep = all.indices.filter { all[$0].kind != .same }.flatMap { max(0, $0 - context)...min(all.count - 1, $0 + context) }
        let kept = Set(keep)
        var out: [DiffLine] = []
        for (n, l) in all.enumerated() where kept.contains(n) {
            if n > 0, !kept.contains(n - 1), !out.isEmpty { out.append(.init(kind: .same, text: "…")) }
            out.append(l)
        }
        return out
    }

    /// The first `limit` lines, and how many were left out (for a "+N more" label).
    public static func capped(_ lines: [DiffLine], limit: Int = 40) -> (shown: [DiffLine], more: Int) {
        (Array(lines.prefix(limit)), max(0, lines.count - limit))
    }
}

private extension Array where Element == String {
    func dropLastIf(_ s: String) -> [String] { last == s ? Array(dropLast()) : self }
}

extension HookEvent {
    /// Diff preview for an Edit/Write/MultiEdit tool call, from `toolInputJSON` (nil for other tools or unparsable input).
    public var editDiff: [DiffLine]? {
        guard let json = toolInputJSON,
              let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return nil }
        switch toolName {
        case "Edit":
            guard let old = o["old_string"] as? String, let new = o["new_string"] as? String else { return nil }
            return LineDiff.lines(old: old, new: new)
        case "Write":
            guard let c = o["content"] as? String else { return nil }
            return LineDiff.lines(old: "", new: c)
        case "MultiEdit":
            guard let es = o["edits"] as? [[String: Any]] else { return nil }
            let parts = es.compactMap { e -> [DiffLine]? in
                guard let old = e["old_string"] as? String, let new = e["new_string"] as? String else { return nil }
                return LineDiff.lines(old: old, new: new)
            }
            return Array(parts.joined(separator: [DiffLine(kind: .same, text: "…")]))
        default: return nil
        }
    }
}
