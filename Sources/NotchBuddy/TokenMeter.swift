import Foundation
import SQLite3
import NotchBuddyCore

/// Token totals from Claude Code's own transcripts and OpenCode's local database on this Mac (no network): per session, and for today.
/// Codex (not installed here) and Antigravity (protobuf only) are not covered.
/// Only transcripts touched today are read, each incrementally from where the last read stopped.
final class TokenMeter: @unchecked Sendable { // all state lives on `queue`
    private let queue = DispatchQueue(label: "NotchBuddy.TokenMeter", qos: .utility)
    private var files: [String: TranscriptUsage] = [:]
    private var day = Date.distantPast

    func update(_ done: @escaping @MainActor (_ bySession: [String: Int], _ today: Int) -> Void) {
        queue.async { [self] in
            let start = Calendar.current.startOfDay(for: Date())
            if start != day { files = [:]; day = start }
            let fm = FileManager.default
            let root = NSHomeDirectory() + "/.claude/projects"
            for dir in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
                let d = root + "/" + dir
                for name in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where name.hasSuffix(".jsonl") {
                    let path = d + "/" + name
                    guard let a = try? fm.attributesOfItem(atPath: path), let mod = a[.modificationDate] as? Date, mod >= start,
                          let size = (a[.size] as? NSNumber)?.uint64Value else { continue }
                    var u = files[path] ?? TranscriptUsage()
                    if size < u.offset { u = TranscriptUsage() } // rewritten
                    // Memory-mapped: only the new bytes are touched, and their pages are clean file pages, not heap the app has to hold.
                    if size > u.offset, let mapped = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) {
                        u.consume(mapped.dropFirst(Int(u.offset))) { $0 >= start }
                    }
                    files[path] = u
                }
            }
            var bySession: [String: Int] = [:]
            for (path, u) in files {
                let sid = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                bySession[AgentKind.claudeCode.rawValue + ":" + sid] = u.all.total
            }
            var today = files.values.reduce(0) { $0 + $1.today.total }
            let oc = Self.openCodeUsage(since: start)
            for (sid, usage) in oc.bySession { bySession[AgentKind.openCode.rawValue + ":" + sid] = usage }
            today += oc.today
            DispatchQueue.main.async { MainActor.assumeIsolated { done(bySession, today) } }
        }

    }

    /// OpenCode keeps every message (with its token counts) in one SQLite file; opened read-only, never written.
    private static func openCodeUsage(since start: Date) -> (bySession: [String: Int], today: Int) {
        let path = NSHomeDirectory() + "/.local/share/opencode/opencode.db"
        var db: OpaquePointer?
        guard FileManager.default.fileExists(atPath: path),
              sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return ([:], 0) }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        let n = "(COALESCE(json_extract(data,'$.tokens.input'),0) + COALESCE(json_extract(data,'$.tokens.output'),0)"
              + " + COALESCE(json_extract(data,'$.tokens.reasoning'),0) + COALESCE(json_extract(data,'$.tokens.cache.write'),0))"
        let sql = "SELECT session_id, SUM(\(n)), SUM(CASE WHEN time_created >= ?1 THEN \(n) ELSE 0 END) FROM message "
                + "WHERE session_id IN (SELECT session_id FROM message WHERE time_updated >= ?1) GROUP BY session_id"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return ([:], 0) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(start.timeIntervalSince1970 * 1000))
        var by: [String: Int] = [:], today = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            by[String(cString: c)] = Int(sqlite3_column_int64(stmt, 1))
            today += Int(sqlite3_column_int64(stmt, 2))
        }
        return (by, today)
    }
}
