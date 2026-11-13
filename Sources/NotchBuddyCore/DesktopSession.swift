import Foundation

/// The Claude desktop app keeps one file per Code session, local_<id>.json, holding its own id and the Claude Code CLI
/// session id that hooks report. Matching them lets a click open that exact chat (claude://code/continue?session=…).
public enum DesktopSession {
    public static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    /// The app's session id for a CLI session id, or nil. Reads only the id fields; never the chat.
    public static func appSessionID(forCLI cli: String, in root: URL = root) -> String? {
        guard let accounts = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        var best: (id: String, at: Double)?
        for workspace in accounts.flatMap({ (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }) {
            for f in (try? FileManager.default.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)) ?? []
            where f.lastPathComponent.hasPrefix("local_") && f.pathExtension == "json" {
                guard let o = (try? JSONSerialization.jsonObject(with: Data(contentsOf: f))) as? [String: Any],
                      o["cliSessionId"] as? String == cli || o["lastAssistantCliSessionId"] as? String == cli,
                      let id = o["sessionId"] as? String, isValid(id) else { continue }
                let at = o["lastActivityAt"] as? Double ?? 0
                if best == nil || at > best!.at { best = (id, at) }
            }
        }
        return best?.id
    }

    /// The deep link that opens it; the id goes into a URL, so only the app's own shape passes.
    public static func url(appSessionID id: String) -> URL? {
        guard isValid(id) else { return nil }
        var c = URLComponents(string: "claude://code/continue")!
        c.queryItems = [URLQueryItem(name: "session", value: id), URLQueryItem(name: "source", value: "notchi")]
        return c.url
    }

    static func isValid(_ id: String) -> Bool { id.range(of: #"^local_[0-9a-fA-F-]{8,64}$"#, options: .regularExpression) != nil }
}
