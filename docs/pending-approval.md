# Claude Code hook install

**Installed 2026-11-12 with your OK** (backup: `~/.claude/settings.json.notchbuddy-backup-2026-11-11T18-19-54Z`).
Originally prepared for approval; nothing below had been run before that. Installing edits `~/.claude/settings.json`, so it waits for your OK.

## What it changes

Only a new `"hooks"` block is added; your permissions, plugins, env and other keys are untouched.
Every event runs the same tiny binary from the app bundle, which forwards the event to Notch Buddy over a
local socket (`~/Library/Application Support/NotchBuddy/hook.sock`, owner-only). If Notch Buddy is not
running, the hook exits immediately with no output, so Claude Code behaves exactly as today.
Nothing leaves this Mac.

```diff
--- settings.json (now)
+++ settings.json (after)
@@ -112,5 +112,117 @@
     ]
   },
   "model": "opusplan",
-  "env": {}
+  "env": {},
+  "hooks": {
+    "SessionStart": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 5
+          }
+        ]
+      }
+    ],
+    "UserPromptSubmit": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 5
+          }
+        ]
+      }
+    ],
+    "PreToolUse": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 5
+          }
+        ]
+      }
+    ],
+    "PostToolUse": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 5
+          }
+        ]
+      }
+    ],
+    "PostToolUseFailure": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 5
+          }
+        ]
+      }
+    ],
+    "PermissionRequest": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 600
+          }
+        ]
+      }
+    ],
+    "Notification": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 5
+          }
+        ]
+      }
+    ],
+    "Stop": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 5
+          }
+        ]
+      }
+    ],
+    "StopFailure": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 5
+          }
+        ]
+      }
+    ],
+    "SessionEnd": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "'/Users/heyhadi/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook'",
+            "timeout": 5
+          }
+        ]
+      }
+    ]
+  }
 }
```

## How to install (after reviewing the diff)

```bash
cd ~/notch-buddy && scripts/make-app.sh && build/NotchBuddy.app/Contents/MacOS/NotchBuddy --install-hook
```

It copies the current file to `~/.claude/settings.json.notchbuddy-backup-<time>` first and prints that path.
Start the app with `open build/NotchBuddy.app`, then start a new Claude Code session (hooks load at startup).

## How to undo

```bash
~/notch-buddy/build/NotchBuddy.app/Contents/MacOS/NotchBuddy --uninstall-hook
```

or copy the backup file back over `~/.claude/settings.json`.

## Notes
- The hook path points into `~/notch-buddy/build/`. If you move the app (e.g. to /Applications), uninstall, move, then install again.
- Commands you already allow in `permissions.allow` never trigger a permission request, so they never show in the notch.
