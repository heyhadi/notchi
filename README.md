# Notchi

Your coding agents, living in the notch.

Notchi is a small native macOS app that turns the MacBook notch into a home for your AI coding agents. A buddy in the notch shows what each agent is doing, lets you approve commands and reply without going back to the terminal, and beeps like a tiny robot when an agent needs you.

**[Download for Mac](https://github.com/heyhadi/notchi/releases/latest/download/Notchi.dmg)** · [Website](https://heyhadi.github.io/notchi/) · [Releases](https://github.com/heyhadi/notchi/releases)

## What it does

- **Live status per agent**: working, thinking, done, needs you or error, with a step count and timer.
- **Approve from the notch**: see the full command and folder, then Allow once or Deny. Risky commands (pipes into a shell, disk erase, keychain reads, settings edits and so on) can only be answered in the terminal.
- **Chat mid-turn**: send Claude Code a note while it works; it reads it after its next tool call.
- **Jump back**: click a session to bring its terminal tab (Terminal.app) or app to the front.
- **Daily token meter** and an optional daily limit, plus session history.
- **Roaming buddies**: one per agent, walking along your Dock. Drag them, poke them, watch them bump into each other and doze off when things go quiet.
- **Robot sounds**: a synthesized "bip bup" voice for needs-you, done, greetings and reactions. Mutes during calls.
- **Opens at login and updates itself**: new releases install automatically when no agent is busy (or use Check for Updates in the menu).
- **Private**: everything stays on your Mac. No account, no telemetry. The only network request is the update check to GitHub, which you can turn off in Settings → Behavior.

## Supported agents

| Agent | Status in the notch | Approve from the notch |
|---|---|---|
| Claude Code (CLI, VS Code, Desktop) | Yes | Yes |
| OpenCode | Yes | Yes |
| Codex | Yes | Yes |
| Antigravity (`agy`) | Yes | No, status only |
| Gemini CLI, Cursor, GitHub Copilot, Cline | Yes | No, status only |

Claude Code and OpenCode are tested live; the others follow each agent's documented hooks. Details in [DECISIONS.md](DECISIONS.md).

## Install

1. [Download Notchi.dmg](https://github.com/heyhadi/notchi/releases/latest/download/Notchi.dmg) and drag **Notchi** into Applications. Needs macOS 14 or later, Apple Silicon or Intel. Notch Macs look best; others get the same panel under the menu bar.
2. Notchi isn't notarized yet, so macOS blocks the first launch. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway** next to Notchi. You only do this once.
3. Click the menu bar icon → **Settings → Agents → Connect** for each agent you use.

Notchi adds itself as a login item on first launch (macOS shows a notice) and keeps itself up to date from GitHub Releases. Both can be turned off in **Settings → Behavior**. Updates are checked against the bundle id, version and code signature before the app replaces itself; until Notchi is notarized there is no Developer ID signature to check, so the update trusts GitHub's HTTPS.

Connecting adds a hook to that agent's own config (for Claude Code, `~/.claude/settings.json`) and makes a timestamped backup first. Every entry is marked as managed by Notch Buddy, and Disconnect removes only those. If Notchi isn't running, the hook steps aside and the agent behaves as if it weren't there.

## Build from source

```bash
git clone https://github.com/heyhadi/notchi.git
cd notchi
./scripts/make-app.sh          # builds build/NotchBuddy.app
open build/NotchBuddy.app
swift test
```

`UNIVERSAL=1 ./scripts/make-app.sh && ./scripts/make-dmg.sh` builds the universal `build/Notchi.dmg` that releases ship.

## Releasing

Push a version tag and GitHub Actions builds, tests and publishes the DMG:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Every push to `master` also runs the build, the tests and a DMG build.

## License

[MIT](LICENSE)
