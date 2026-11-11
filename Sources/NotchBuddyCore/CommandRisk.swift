import Foundation

/// Flags commands that must only be approved in the terminal, never from the notch.
/// Errs on the side of flagging: a false positive only costs a trip to the terminal.
public enum CommandRisk {
    private static let rules: [(reason: String, pattern: String)] = [
        ("Runs as root (sudo)", #"(^|[\s;&|(`])(sudo|doas)\b"#),
        ("Recursive delete", #"\brm\s+([^;&|]*\s)?(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)\b"#),
        ("Pipes a download into a shell", #"\b(curl|wget)\b[^;&]*\|\s*(sudo\s+)?(\S*/)?(ba|z|da|k|fi|c|tc)?sh\b"#),
        ("Pipes a download into an interpreter", #"\b(curl|wget)\b[^;&]*\|\s*(sudo\s+)?(\S*/)?(python\d?|perl|ruby|node|osascript)\b"#),
        ("Runs a downloaded script", #"(\$\(|<\(|`)\s*(curl|wget)\b"#),
        ("Runs AppleScript (osascript)", #"\bosascript\b"#),
        ("Decodes base64", #"\bbase64\b[^;&|]*(\s-d\b|\s-D\b|--decode)"#),
        ("Decodes base64", #"(-d|-D|--decode)\b[^;&|]*\bbase64\b"#),
        ("Evaluates generated code", #"(^|[\s;&|(])eval\b"#),
        ("Touches SSH keys or config", #"\.ssh(/|\b)"#),
        ("Touches login items (LaunchAgents/Daemons)", #"Launch(Agents|Daemons)|\blaunchctl\b"#),
        ("Schedules a job (crontab)", #"\bcrontab\b"#),
        ("Removes download quarantine", #"\bxattr\b[^;&|]*com\.apple\.quarantine|\bxattr\s+-[a-zA-Z]*c"#),
        ("Changes system security", #"\b(spctl|csrutil)\b"#),
        ("Reads the keychain", #"\bsecurity\s+(find-(generic|internet)-password|dump-keychain|export)\b"#),
        ("Edits shell startup files", #">\s*\S*\.(zshrc|zprofile|zshenv|bashrc|bash_profile|profile)\b"#),
        ("Edits Claude Code settings", #"\.claude/settings[^/\s]*\.json"#),
        ("Erases a disk", #"\b(mkfs|diskutil\s+(erase\w*|zero\w*|secureErase))|\bdd\b[^;&|]*\bof=/dev/"#),
    ]
    private static let compiled = rules.map { ($0.reason, try! NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive])) }

    /// Reasons this command is risky; empty means it may be approved from the notch.
    public static func reasons(command: String) -> [String] {
        let s = command.replacingOccurrences(of: "\\\n", with: " ")
        var out: [String] = []
        for (reason, re) in compiled where re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil && !out.contains(reason) {
            out.append(reason)
        }
        return out
    }

    /// Risk for a whole permission request: Bash commands, plus file writes to sensitive places.
    public static func reasons(for e: HookEvent) -> [String] {
        var r = e.command.map { reasons(command: $0) } ?? []
        if let p = e.filePath {
            for x in reasons(command: p) where !r.contains(x) { r.append(x) }
            if p.range(of: #"/\.(zshrc|zprofile|zshenv|bashrc|bash_profile|profile)$"#, options: .regularExpression) != nil {
                r.append("Edits shell startup files")
            }
        }
        return r
    }
}
