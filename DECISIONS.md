# Decisions

Defaults chosen while building without the user; change freely.

- **Build system:** Swift Package (no .xcodeproj). `xcodebuild -scheme NotchBuddy -destination 'platform=macOS' build` and `swift build` both work; `scripts/make-app.sh` wraps the binary into `build/NotchBuddy.app` (LSUIElement, ad-hoc signed). No xcodegen or other tools needed.
- **Fonts:** system fonts instead of bundling Fredoka/Inter/JetBrains Mono: SF Rounded semibold for headings, SF for UI text, SF Mono for commands and timers. Avoids shipping font files; looks close.
- **Hook transport:** one tiny Swift binary (`notchbuddy-hook`) per hook call → Unix socket `~/Library/Application Support/NotchBuddy/hook.sock` (folder 0700, socket 0600, peer UID checked). App not running → hook exits 0 with no output, Claude Code behaves as if there were no hook.
- **Hook events:** SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Notification, Stop, StopFailure, SessionEnd. Timeout 5 s, except PermissionRequest 600 s (hook gives up at 590 s and falls back to the terminal prompt).
- **State mapping:** prompt → Thinking; tool use → Working; PermissionRequest or a `permission_prompt` notification → Needs you; tool failure → Error; Stop → Done. `idle_prompt` notifications are ignored (would nag). Done/Error/Thinking fall back to Sleeping after 2 minutes without events.
- **Progress:** Claude Code does not report "14 of 32 tests"; the panel shows the number of tool steps since the last prompt instead.
- **Risky commands:** flagged red and never approvable from the notch. The app answers the hook immediately with *no decision*, so Claude Code's own terminal prompt handles it. Patterns cover more than the brief (eval, xattr quarantine removal, keychain reads, crontab, shell rc edits, Claude settings edits, disk erase); a false positive only costs a trip to the terminal.
- **Settings.json editing:** via the system `/usr/bin/jq` so the user's key order and formatting survive and the diff stays small; timestamped backup next to the file before every write.
- **Sounds:** off by default (opt-in). All synthesized in code with AVAudioEngine, no sound files.
- **"Mute during Focus, meetings and screen share"** became **"Mute during calls and meetings"**: it mutes while the microphone is in use (CoreAudio, no permission). Reading Focus status needs a permission prompt and screen-share detection has no reliable public API without Screen Recording, so both are left out.
- **One sound per minute is a hard limit**, so a soft "Working" tick can use up the minute and swallow a "Needs you" beep that follows. Kept as specified; set Working to Off if that bothers you.
- **Other 11 avatars** show as "Soon" in the picker until Phase 4.
- **Status-menu titles** pick up a language change after restarting the app; the notch panel and Settings switch immediately.

## Multiple agents (added 2026-11-12)

| Agent | How | Notch can approve? | Verified live |
|---|---|---|---|
| Claude Code (CLI, VS Code, Desktop) | `~/.claude/settings.json` hooks | Yes (PermissionRequest) | Yes |
| Codex (CLI + IDE) | `~/.codex/hooks.json` (same shape as Claude) | Yes (PermissionRequest) | No (not installed); trust hooks with `/hooks` |
| Antigravity (IDE + `agy`) | `~/.gemini/config/hooks.json`, group `notch-buddy` | No: status; risky → `force_ask` | `agy`: global hooks file read, events and chat replies (Stop `continue`) work. IDE: restart needed after connecting; not yet confirmed |
| Gemini CLI | `~/.gemini/settings.json` hooks | No: status only | No (not installed) |
| Cursor | `~/.cursor/hooks.json`, non-gating events only | No: status only | No (not installed) |
| GitHub Copilot (VS Code agent, CLI) | `~/.copilot/hooks/notch-buddy.json` | No: status; risky → `ask` | No (not installed) |
| Cline (VS Code) | scripts in `~/Documents/Cline/Hooks/` | No: status only | No (needs VS Code UI) |
| OpenCode | plugin `~/.config/opencode/plugins/notch-buddy.js` | Yes (`permission.ask`) | Plugin loads and sends events; permission path untested |
| Kilo Code, Roo Code, Windsurf | — | — | No official hooks / unclear docs: listed as unsupported |

- Approving from the notch only where the agent has a real "permission requested" hook. Elsewhere Notch Buddy never approves; a hook that would have to say "allow" for every tool would quietly replace the agent's own safety prompt.
- Cursor: only non-gating hooks (a gating hook that fails or isn't answered blocks Cursor).
- Every file Notch Buddy writes carries "notch-buddy: managed by Notch Buddy" or its exact hook path; removal only touches those entries. Existing Cline hook scripts are never overwritten.
- Hook binary prints a per-agent `--default` answer when the app is not running, so no agent breaks if Notch Buddy is closed.
