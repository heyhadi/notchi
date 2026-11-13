import Foundation

/// Typing a notch reply into the terminal tab a Claude Code CLI session runs in, as if you typed it there.
/// Terminal.app's `do script … in <tab>` and iTerm2's `write text` send text plus Return to the tab's program; no Accessibility needed.
public enum TerminalReply {
    /// Only a plain CLI session (no VS Code/Desktop surface) whose turn has ended: typing into a turn in progress would land mid-answer.
    /// `s` must be the store's raw session, not `current()`'s, which turns an old Done into Sleeping.
    public static func canType(_ s: AgentSession) -> Bool {
        s.agent == .claudeCode && s.agentLabel == AgentKind.claudeCode.displayName && s.state == .done && validTTY(s.tty) != nil
    }

    /// AppleScript that types `text` into the tab on `tty` and presses Return; returns true if it found the tab.
    /// nil for an invalid tty or empty text. `app` is "Terminal" or "iTerm2".
    public static func script(app: String, tty: String?, text: String) -> String? {
        guard let tty = validTTY(tty) else { return nil }
        // One line: an embedded newline would submit early. Control characters never reach the terminal.
        let line = String(String.UnicodeScalarView(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : $0 }))
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        let quoted = "\"" + line.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        switch app {
        case "Terminal":
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            do script \(quoted) in t
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case "iTerm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                tell s to write text \(quoted)
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }
}
