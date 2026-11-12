import Foundation
import NotchBuddyCore

/// Token totals from Claude Code's own transcripts on this Mac (no network): per session, and for today.
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
                    if size > u.offset, let h = FileHandle(forReadingAtPath: path) {
                        try? h.seek(toOffset: u.offset)
                        if let data = try? h.readToEnd() { u.consume(data) { $0 >= start } }
                        try? h.close()
                    }
                    files[path] = u
                }
            }
            var bySession: [String: Int] = [:]
            for (path, u) in files {
                let sid = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                bySession[AgentKind.claudeCode.rawValue + ":" + sid] = u.all.total
            }
            let today = files.values.reduce(0) { $0 + $1.today.total }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(bySession, today) } }
        }
    }
}
