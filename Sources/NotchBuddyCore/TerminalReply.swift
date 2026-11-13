import Foundation

/// Typing a notch reply into the terminal tab a Claude Code CLI session runs in, as if you typed it there.
/// Terminal.app's `do script … in <tab>`, iTerm2's `write text` and `wezterm cli send-text` send text plus Return to the tab's program;
/// no Accessibility needed.
public enum TerminalReply {
    /// Only a plain CLI session (no VS Code/Desktop surface) whose turn has ended: typing into a turn in progress would land mid-answer.
    /// `s` must be the store's raw session, not `current()`'s, which turns an old Done into Sleeping.
    public static func canType(_ s: AgentSession) -> Bool {
        s.agent == .claudeCode && s.agentLabel == AgentKind.claudeCode.displayName && s.state == .done && validTTY(s.tty) != nil
    }

    /// The text as one line: an embedded newline would submit early, and control characters never reach the terminal. nil if nothing is left.
    public static func oneLine(_ text: String) -> String? {
        let line = String(String.UnicodeScalarView(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : $0 }))
            .trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }

    /// WezTerm: the id of the pane on `tty`, from `wezterm cli list --format json`.
    public static func wezTermPane(tty: String?, listJSON: Data) -> Int? {
        guard let tty = validTTY(tty), let panes = (try? JSONSerialization.jsonObject(with: listJSON)) as? [[String: Any]] else { return nil }
        return panes.first { $0["tty_name"] as? String == tty }?["pane_id"] as? Int
    }

    /// AppleScript that types `text` into the tab on `tty` and presses Return; returns true if it found the tab.
    /// nil for an invalid tty or empty text. `app` is "Terminal" or "iTerm2".
    public static func script(app: String, tty: String?, text: String) -> String? {
        guard let tty = validTTY(tty), let line = oneLine(text) else { return nil }
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
