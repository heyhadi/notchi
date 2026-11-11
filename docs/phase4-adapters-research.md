# Phase 4 research: Antigravity and Gemini CLI adapters (not built yet)

Researched 2026-11-12 from official docs plus read-only local checks. Needs your go-ahead before building.

## Antigravity (IDE + `agy` 1.5.6): hooks exist, approve/deny possible
- Docs: https://antigravity.google/docs/hooks (live page should be re-checked; third-party articles disagree on paths).
- Events: SessionStart, PreToolUse, PostToolUse, PreInvocation, PostInvocation, Stop (`terminationReason`, `fullyIdle`).
- Config: global `~/.gemini/config/hooks.json`, per project `.agents/hooks.json`. Verify with `/hooks` inside `agy`.
- stdin is camelCase: `conversationId`, `workspacePaths`, `toolCall {name,args}`, `stepIdx`, `error`.
- PreToolUse can answer `decision`: allow / deny / ask / force_ask / … There is no separate "permission requested" event,
  so the adapter would hold PreToolUse for tools Antigravity would ask about, or answer `ask` to fall back to its own prompt.
- Unconfirmed: exit-code contract; whether the IDE and the CLI read the same hook files.
- Fallbacks: `agy --output-format stream-json` (print mode), logs in `~/.gemini/antigravity-cli/log/`; conversation stores are binary protobuf (don't parse).

## Gemini CLI: hooks exist, approve/deny possible
- Docs: https://geminicli.com/docs/hooks/
- Events: SessionStart, SessionEnd, BeforeAgent, AfterAgent, BeforeModel, AfterModel, BeforeToolSelection, BeforeTool, AfterTool, PreCompress, Notification.
- Config: `~/.gemini/settings.json` → `"hooks"` (same shape as Claude Code). BeforeTool can return `decision: allow|deny`; no "ask".
- Not installed on this Mac; reportedly being superseded by `agy` (unconfirmed), so Antigravity first.

## Proposed plan
Reuse `notchbuddy-hook` + the socket: add an `agent` field and a small per-agent mapping in NotchBuddyCore
(Antigravity camelCase → HookEvent), same risky-command classifier, same "show diff, back up, ask first" installer
for `~/.gemini/config/hooks.json`.
