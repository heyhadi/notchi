import Foundation

/// One file Notch Buddy would create, change or delete to connect an agent.
public struct FileChange: Equatable, Sendable {
    public let path: String
    public let old: String?      // nil = file does not exist yet
    public let new: String?      // nil = delete the file
    public var executable = false
}

/// How each agent is connected. JSON configs are merged with /usr/bin/jq (user content untouched);
/// files Notch Buddy owns are written whole. Every change is shown as a diff and backed up before writing.
public enum AgentSetup {
    /// Marker in every file and command Notch Buddy writes, so removal never touches the user's own hooks.
    static let marker = "notch-buddy"
    /// Text in every file Notch Buddy owns (the folder name "notch-buddy" alone is not proof).
    static let managed = "notch-buddy: managed by Notch Buddy"

    public static func configPaths(_ a: AgentKind, home: String = NSHomeDirectory()) -> [String] {
        switch a {
        case .claudeCode: [home + "/.claude/settings.json"]
        case .codex: [home + "/.codex/hooks.json"]
        case .geminiCLI: [home + "/.gemini/settings.json"]
        case .antigravity: [home + "/.gemini/config/hooks.json"]
        case .cursor: [home + "/.cursor/hooks.json"]
        case .copilot: [home + "/.copilot/hooks/notch-buddy.json"]
        case .openCode: [home + "/.config/opencode/plugins/notch-buddy.js"]
        case .cline: clineEvents.map { home + "/Documents/Cline/Hooks/" + $0 }
        }
    }

    /// Single-quote for /bin/sh.
    static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func command(_ hook: String, _ a: AgentKind, event: String, wait: Int? = nil, fallback: String? = nil) -> String {
        var c = "\(q(hook)) --agent \(a.rawValue) --event \(event)"
        if let wait { c += " --wait \(wait)" }
        if let fallback { c += " --default \(q(fallback))" }
        return c
    }

    static let clineEvents = ["TaskStart", "TaskResume", "UserPromptSubmit", "PreToolUse", "PostToolUse", "TaskComplete", "TaskCancel"]

    /// Changes needed to install (or remove) the hooks; empty when already in that state.
    public static func plan(_ a: AgentKind, install: Bool, hookPath hook: String, home: String = NSHomeDirectory()) throws -> [FileChange] {
        let paths = configPaths(a, home: home)
        func read(_ p: String) -> String? { try? String(contentsOfFile: p, encoding: .utf8) }
        var changes: [FileChange] = []
        func add(_ path: String, _ new: String?, executable: Bool = false) {
            let old = read(path)
            if old != new { changes.append(FileChange(path: path, old: old, new: new, executable: executable)) }
        }

        switch a {
        case .claudeCode, .codex, .geminiCLI, .cursor:
            let spec = jsonSpec(a, hook: hook)
            // Install = remove our old entries, then add current ones, so upgrades replace instead of duplicating.
            let filter = a == .cursor ? (install ? flatUninstall + " | " + flatInstall : flatUninstall)
                                      : (install ? nestedUninstall + " | " + nestedInstall : nestedUninstall)
            let specJSON = String(decoding: try JSONSerialization.data(withJSONObject: spec, options: [.sortedKeys]), as: UTF8.self)
            let new = try HookInstaller.jq(filter, read(paths[0]) ?? "", args: ["--argjson", "spec", specJSON, "--arg", "prefix", q(hook)])
            // Removing everything from a file we created leaves "{}"; fine to keep.
            if read(paths[0]) != nil || install { add(paths[0], new) }

        case .antigravity:
            let group = String(decoding: try JSONSerialization.data(withJSONObject: antigravityGroup(hook), options: [.sortedKeys]), as: UTF8.self)
            let filter = install ? ".[$name] = $group" : "del(.[$name])"
            let new = try HookInstaller.jq(filter, read(paths[0]) ?? "", args: ["--arg", "name", marker, "--argjson", "group", group])
            if read(paths[0]) != nil || install { add(paths[0], new) }

        case .copilot:
            add(paths[0], install ? copilotFile(hook) : nil)

        case .openCode:
            add(paths[0], install ? openCodePlugin : nil)

        case .cline:
            for (event, path) in zip(clineEvents, paths) {
                if let existing = read(path), !existing.contains(managed) {
                    throw NSError(domain: "AgentSetup", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        "You already have a Cline hook at \(path). Notch Buddy won't overwrite it."])
                }
                let script = "#!/bin/sh\n# \(marker): managed by Notch Buddy, remove from Settings → Agents\nexec "
                    + command(hook, .cline, event: event, fallback: #"{"cancel":false}"#) + "\n"
                add(path, install ? script : nil, executable: true)
            }
        }
        return changes
    }

    public static func isInstalled(_ a: AgentKind, hookPath: String, home: String = NSHomeDirectory()) -> Bool {
        configPaths(a, home: home).allSatisfy { p in
            guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { return false }
            switch a {
            case .claudeCode, .codex, .geminiCLI, .cursor: return s.replacingOccurrences(of: "\\/", with: "/").contains(q(hookPath))
            case .antigravity: return ((try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any])?[marker] != nil
            case .copilot, .openCode, .cline: return s.contains(managed)
            }
        }
    }

    /// Unified diff of all changes.
    public static func diff(_ changes: [FileChange]) throws -> String {
        try changes.map { c in
            let d = try HookInstaller.diff(old: c.old ?? "", new: c.new ?? "")
            let head = c.old == nil ? "new file" : c.new == nil ? "delete file" : "change"
            return "### \(c.path) (\(head))\n" + d
        }.joined(separator: "\n")
    }

    /// Backs up each existing file next to itself, then writes/deletes. Returns the backup paths.
    public static func apply(_ changes: [FileChange]) throws -> [String] {
        var backups: [String] = []
        let fm = FileManager.default
        for c in changes {
            if let new = c.new {
                if let b = try HookInstaller.write(new, path: c.path) { backups.append(b) }
                if c.executable { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: c.path) }
            } else if fm.fileExists(atPath: c.path) {
                let b = HookInstaller.uniqueBackupPath(c.path)
                try fm.moveItem(atPath: c.path, toPath: b) // "delete" keeps a copy
                backups.append(b)
            }
        }
        return backups
    }

    // MARK: - Per-agent config

    /// event → hook group (Claude-style nested) or handler (Cursor-style flat).
    static func jsonSpec(_ a: AgentKind, hook: String) -> [String: Any] {
        switch a {
        case .claudeCode:
            // Plain command (older installs used it; the binary detects PermissionRequest itself). Stop waits so the
            // notch can hold a finished session while you type a reply.
            let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                          "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
            return Dictionary(uniqueKeysWithValues: events.map { e in
                let long = e == "PermissionRequest" || e == "Stop"
                return (e, ["hooks": [["type": "command", "command": q(hook) + (e == "Stop" ? " --wait 590" : ""), "timeout": long ? 600 : 5]]])
            })
        case .codex:
            let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
            return Dictionary(uniqueKeysWithValues: events.map { e in
                let long = e == "PermissionRequest" || e == "Stop"
                return (e, ["hooks": [["type": "command", "command": command(hook, a, event: e, wait: long ? 590 : nil), "timeout": long ? 600 : 5]]])
            })
        case .geminiCLI:
            let events = ["SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "BeforeTool", "AfterTool", "Notification"]
            return Dictionary(uniqueKeysWithValues: events.map { e in
                (e, ["matcher": "*", "hooks": [["type": "command", "name": marker, "command": command(hook, a, event: e), "timeout": 5000]]])
            })
        case .cursor:
            let events = ["sessionStart", "sessionEnd", "afterAgentThought", "postToolUse", "postToolUseFailure", "afterShellExecution", "afterFileEdit", "stop"]
            return Dictionary(uniqueKeysWithValues: events.map { e in (e, ["command": command(hook, a, event: e, fallback: "{}")]) })
        default:
            return [:]
        }
    }

    static let nestedInstall = """
    reduce ($spec | to_entries[]) as $x (.;
      if any(.hooks[$x.key][]?.hooks[]?; .command == $x.value.hooks[0].command) then . else .hooks[$x.key] += [$x.value] end)
    """
    static let nestedUninstall = """
    if .hooks then
      .hooks |= (with_entries(.value |= (map(.hooks |= map(select(.command | startswith($prefix) | not))) | map(select(.hooks | length > 0))))
                 | with_entries(select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end
    else . end
    """
    static let flatInstall = """
    .version //= 1
    | reduce ($spec | to_entries[]) as $x (.;
        if any(.hooks[$x.key][]?; .command == $x.value.command) then . else .hooks[$x.key] += [$x.value] end)
    """
    static let flatUninstall = """
    if .hooks then
      .hooks |= (with_entries(.value |= map(select(.command | startswith($prefix) | not))) | with_entries(select(.value | length > 0)))
    else . end
    """

    // https://antigravity.google/docs/hooks: named groups; tool events use matcher + hooks[], others a handler list.
    static func antigravityGroup(_ hook: String) -> [String: Any] {
        func h(_ e: String, _ fallback: String) -> [String: Any] {
            let stop = e == "Stop" // waits so the notch can hold a finished session for a reply
            return ["type": "command", "command": command(hook, .antigravity, event: e, wait: stop ? 590 : nil, fallback: fallback), "timeout": stop ? 600 : 10]
        }
        return [
            "SessionStart": [h("SessionStart", "{}")],
            "PreInvocation": [h("PreInvocation", "{}")],
            "PreToolUse": [["matcher": ".*", "hooks": [h("PreToolUse", #"{"decision":"allow"}"#)]]],
            "PostToolUse": [["matcher": ".*", "hooks": [h("PostToolUse", "{}")]]],
            "Stop": [h("Stop", #"{"decision":"stop"}"#)],
        ]
    }

    static func copilotFile(_ hook: String) -> String {
        let events = ["sessionStart", "sessionEnd", "userPromptSubmitted", "preToolUse", "postToolUse", "agentStop"]
        let hooks = Dictionary(uniqueKeysWithValues: events.map { e in
            (e, [["type": "command", "command": command(hook, .copilot, event: e, fallback: "{}"), "timeoutSec": 10]])
        })
        let o: [String: Any] = ["version": 1, "hooks": hooks, "_comment": "\(marker): managed by Notch Buddy"]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self) + "\n"
    }

    /// OpenCode plugin (JS, runs inside OpenCode): forwards events over the same socket in Claude-shaped JSON.
    static let openCodePlugin = """
    // notch-buddy: managed by Notch Buddy (remove from Settings → Agents). Sends OpenCode status to the
    // Notch Buddy app over its local socket; nothing leaves this Mac. If the app isn't running, nothing changes.
    import { connect } from "node:net"
    import { homedir } from "node:os"

    const SOCK = homedir() + "/Library/Application Support/NotchBuddy/hook.sock"

    function send(payload, waitMs = 2000) {
      return new Promise((resolve) => {
        let out = "", done = false
        const finish = () => { if (!done) { done = true; resolve(out) } }
        const s = connect(SOCK)
        s.setTimeout(waitMs, () => { s.destroy(); finish() })
        s.on("error", finish)
        s.on("data", (d) => { out += d })
        s.on("end", finish)
        s.on("close", finish)
        s.on("connect", () => s.end("NB1 agent=opencode entry= event=\\n" + JSON.stringify(payload)))
      })
    }

    export const NotchBuddy = async ({ directory, client }) => {
      const ev = (sessionID, name, extra = {}) => ({ session_id: sessionID ?? "opencode", cwd: directory, hook_event_name: name, ...extra })
      return {
        "chat.message": async (input) => { await send(ev(input.sessionID, "UserPromptSubmit")) },
        "tool.execute.before": async (input, output) => {
          await send(ev(input.sessionID, "PreToolUse", { tool_name: input.tool, tool_input: output.args }))
        },
        "tool.execute.after": async (input) => {
          await send(ev(input.sessionID, "PostToolUse", { tool_name: input.tool, tool_input: input.args }))
        },
        "permission.ask": async (input, output) => {
          const command = input.metadata?.command ?? [].concat(input.pattern ?? input.title).join(" ")
          const reply = await send(ev(input.sessionID, "PermissionRequest",
            { tool_name: input.type, tool_input: { command, description: input.title } }), 590000)
          try {
            const r = JSON.parse(reply)
            if (r.status === "allow" || r.status === "deny") output.status = r.status
          } catch {} // no answer: OpenCode asks as usual
        },
        event: async ({ event }) => {
          const sid = event.properties?.sessionID
          if (event.type === "session.idle" && sid) {
            // Not awaited: the app may hold this until you reply in the notch, then we send your reply as a prompt.
            send(ev(sid, "Stop"), 590000).then(async (reply) => {
              try {
                const r = JSON.parse(reply)
                if (typeof r.prompt === "string" && r.prompt)
                  await client.session.prompt({ path: { id: sid }, body: { parts: [{ type: "text", text: r.prompt }] } })
              } catch {}
            })
          }
          else if (event.type === "session.error") await send(ev(sid, "StopFailure", { error: String(event.properties?.error?.name ?? "error") }))
        },
      }
    }

    """
}
