import Foundation

/// Adds/removes Notch Buddy's hook in ~/.claude/settings.json. Uses the system /usr/bin/jq so the
/// user's key order and formatting survive and the diff they approve is minimal.
public enum HookInstaller {
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                                "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
    public static let settingsPath = NSHomeDirectory() + "/.claude/settings.json"

    /// Shell command string Claude Code runs; single-quoted so paths with spaces work.
    public static func command(hookPath: String) -> String { "'" + hookPath.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static let installFilter = """
    reduce $events[] as $e (.;
      if any(.hooks[$e][]?.hooks[]?; .command == $cmd) then .
      else .hooks[$e] += [{"hooks": [{"type": "command", "command": $cmd, "timeout": (if $e == "PermissionRequest" then 600 else 5 end)}]}]
      end)
    """
    private static let uninstallFilter = """
    if .hooks then
      .hooks |= (with_entries(.value |= (map(.hooks |= map(select(.command != $cmd))) | map(select(.hooks | length > 0))))
                 | with_entries(select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end
    else . end
    """

    public static func installed(_ settings: String, hookPath: String) throws -> String {
        try jq(installFilter, settings, hookPath: hookPath)
    }

    public static func uninstalled(_ settings: String, hookPath: String) throws -> String {
        try jq(uninstallFilter, settings, hookPath: hookPath)
    }

    public static func isInstalled(_ settings: String, hookPath: String) -> Bool {
        settings.contains(command(hookPath: hookPath))
    }

    /// Unified diff of the change, for the user to read before confirming.
    public static func diff(old: String, new: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("settings.json"), b = dir.appendingPathComponent("settings.json.new")
        try old.write(to: a, atomically: true, encoding: .utf8)
        try new.write(to: b, atomically: true, encoding: .utf8)
        return try run("/usr/bin/diff", ["-u", "--label", "settings.json (now)", "--label", "settings.json (after)", a.path, b.path], okCodes: [0, 1])
    }

    /// Backs up the current file next to it (settings.json.notchbuddy-backup-<time>) then writes atomically.
    @discardableResult
    public static func write(_ new: String, path: String = settingsPath) throws -> String? {
        let fm = FileManager.default
        var backup: String?
        if fm.fileExists(atPath: path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            backup = path + ".notchbuddy-backup-" + stamp
            try fm.copyItem(atPath: path, toPath: backup!)
        } else {
            try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        }
        try new.write(toFile: path, atomically: true, encoding: .utf8)
        return backup
    }

    private static func jq(_ filter: String, _ input: String, hookPath: String) throws -> String {
        let src = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : input
        let eventsJSON = String(decoding: try JSONSerialization.data(withJSONObject: events), as: UTF8.self)
        return try run("/usr/bin/jq", ["--indent", "2", "--arg", "cmd", command(hookPath: hookPath), "--argjson", "events", eventsJSON, filter],
                       stdin: src)
    }

    private static func run(_ tool: String, _ args: [String], stdin: String? = nil, okCodes: Set<Int32> = [0]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = inp
        try p.run()
        if let stdin { inp.fileHandleForWriting.write(Data(stdin.utf8)) }
        try inp.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard okCodes.contains(p.terminationStatus) else {
            throw NSError(domain: "HookInstaller", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: String(decoding: errData, as: UTF8.self)])
        }
        return String(decoding: data, as: UTF8.self)
    }
}
