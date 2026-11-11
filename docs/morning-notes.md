# Morning notes

## Needs you
1. **Approve the hook install**: see `docs/pending-approval.md` (exact diff, one command, backup + undo).
2. **Try it live**: `open build/NotchBuddy.app`, start a new `claude` session, and check how the notch feels
   (hover/click to open, approval buttons, avatar size). I could only check the UI through offscreen snapshots,
   because a real screenshot would need Screen Recording permission.

## Verified overnight
- A real headless Claude Code 2.1.312 session (`claude -p --settings <temp file>`, your settings.json untouched)
  sent SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, Stop, SessionEnd through
  `notchbuddy-hook`, and an `allow` answer over the socket made Claude run the command.
- `--selftest`: hook binary → socket → app model → Allow/Deny → hook output, risky command handed back to the
  terminal immediately, card cleared by later progress.

## Still unknown (test when you're back)
- In an **interactive** terminal session, does Claude Code show its own permission prompt while our hook is waiting
  for a click in the notch? Docs don't say. If it does not, the terminal waits until you answer in the notch
  (or press "Answer in terminal", which hands it back right away). Up to 590 s worst case.
- Xcode prints `CoreSimulator is out of date` warnings on every `xcodebuild`. Harmless for this macOS app;
  opening Xcode once and letting it install components would silence it.
