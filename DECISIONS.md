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
