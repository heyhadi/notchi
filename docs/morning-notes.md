# Morning notes (12 Nov 2026)

## What works (tested live with you last night)
- **Claude Code** (terminal, VS Code, Desktop): status in the notch, **approve/deny** from the notch, **questions with answer buttons**,
  **chat** (reply from the notch, delivered when Claude finishes its turn), risky commands (sudo, curl|sh, …) always
  go back to the terminal. All four were checked in a real session in `~/nb-playground`.
- Cmd+C/V/X/A/Z work in the notch text boxes.
- **All 12 avatars** are in: Settings → Avatar, pick any (the notch switches right away). Each shows the six states.
- The chat box now shows "You: …" for the last message you sent. The double message last night looked like a re-send, not a bug.

## Agents
| Agent | State |
|---|---|
| Claude Code | Works (tested) |
| Antigravity `agy` (terminal) | Works (tested: status + chat) |
| Antigravity **IDE** 2.31.1 | Does **not** run hooks at all: restarted, conversations active, our hook never invoked and no failures logged. Most likely a server-side feature flag on Google's side. Nothing to fix on our side; re-test after an Antigravity update. |
| Codex, Gemini CLI, Cursor, Copilot, Cline, OpenCode | Built from their docs, connectable in Settings → Agents, not tested (not installed / need their UI) |
| Kilo Code, Roo Code, Windsurf | No usable official hooks yet |

## Diagnostics you can check yourself
- `~/Library/Logs/NotchBuddy/events.log`: one line per event the notch received (time, agent, event, session id prefix).
- `~/Library/Logs/NotchBuddy/hook-failures.log`: a hook ran but couldn't reach the app (e.g. app closed).

## Settings changed with your OK
- `~/.claude/settings.json`: hooks added, then `Stop` waits for chat replies (backups next to the file, `*.notchbuddy-backup-*`).
- `~/.gemini/config/hooks.json`: Antigravity hooks (you connected it from Settings).

## Cleanup you may want
- `~/nb-playground` (test folder with `notes.txt`, `hello.txt`) can be deleted.

## Not built yet (your call)
- **Roaming mode** (avatar walking on window tops, drag and throw). It changes how the whole desktop behaves, so I'd rather you
  try the notch first. It can be done without Accessibility or Screen Recording permission (window bounds only).
- **Token usage meter**. Possible from Claude Code's local transcripts (no network); say if you want it.
