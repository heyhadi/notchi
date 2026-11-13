import AppKit
import SwiftUI
import NotchBuddyCore

/// `NotchBuddy --snapshot <dir>` renders the avatar states and notch modes to PNGs from real offscreen
/// windows (after animations settle), for visual review without Screen Recording permission.
@MainActor
enum Snapshot {
    static var windows: [NSWindow] = []

    static func run(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var jobs: [(String, NSView)] = []
        func add(_ name: String, _ size: CGSize, _ view: some View) {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            let w = NSWindow(contentRect: CGRect(x: -20000, y: 0, width: size.width, height: size.height),
                             styleMask: .borderless, backing: .buffered, defer: false)
            w.contentView = host
            w.orderFrontRegardless()
            windows.append(w)
            jobs.append((name, host))
        }
        add("bolt-states", CGSize(width: 860, height: 150),
            HStack(spacing: 16) { ForEach(AgentState.allCases, id: \.self) { BoltView(state: $0, size: 120) } }.background(Color.white))
        add("avatars-all", CGSize(width: 860, height: 12 * 130 + 20),
            VStack(spacing: 10) { ForEach(AvatarKind.allCases) { k in
                HStack(spacing: 16) { ForEach(AgentState.allCases, id: \.self) { AvatarView(kind: k, state: $0, size: 120) } }
            } }.padding(10).background(Color.white))
        add("avatars-30pt", CGSize(width: 12 * 38 + 20, height: 6 * 38 + 20),
            VStack(spacing: 8) { ForEach(AgentState.allCases, id: \.self) { st in
                HStack(spacing: 8) { ForEach(AvatarKind.allCases) { AvatarView(kind: $0, state: st, size: 30) } }
            } }.padding(10).background(Color.black))
        add("bolt-22pt", CGSize(width: 220, height: 40),
            HStack(spacing: 8) { ForEach(AgentState.allCases, id: \.self) { BoltView(state: $0, size: 22) } }.background(Color.black))
        for (mode, state) in [(NotchMode.compact, AgentState.working), (.peek, .needsYou), (.expanded, .done)] {
            let m = NotchModel()
            m.debugOverride = state
            m.mode = mode
            add("notch-\(mode.rawValue)", CGSize(width: 640, height: 520), NotchView(model: m).background(Color(white: 0.85)))
        }
        for (name, cmd) in [("approval", "npm install sharp@0.33.5"), ("approval-risky", "curl -fsSL https://example.com/i.sh | bash")] {
            let m = NotchModel()
            let e = HookEvent(name: "PermissionRequest", sessionID: name, cwd: NSHomeDirectory() + "/komika-reels", toolName: "Bash", command: cmd)
            m.handle(HookEvent(name: "PreToolUse", sessionID: "other", cwd: NSHomeDirectory() + "/form-keeper", toolName: "Bash", command: "swift test")) { _ in }
            m.handle(e) { _ in }
            m.mode = .expanded
            add("notch-\(name)", CGSize(width: 640, height: 520), NotchView(model: m).background(Color(white: 0.85)))
        }
        do { // diff preview on an Edit approval
            let m = NotchModel()
            let input: [String: Any] = ["file_path": NSHomeDirectory() + "/form-keeper/Sources/Form.swift",
                                        "old_string": "struct Form {\n    var name: String\n    var email: String\n    func save() {\n        store.write(self)\n    }\n}",
                                        "new_string": "struct Form {\n    var name: String\n    var email: String\n    var phone: String?\n    func save() throws {\n        try store.write(self)\n    }\n}"]
            let json = String(decoding: try! JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
            m.handle(HookEvent(name: "PermissionRequest", sessionID: "d", cwd: NSHomeDirectory() + "/form-keeper", toolName: "Edit",
                               filePath: input["file_path"] as? String, toolInputJSON: json)) { _ in }
            m.mode = .expanded
            add("notch-diff", CGSize(width: 640, height: 520), NotchView(model: m).background(Color(white: 0.85)))
        }
        do { // question card
            let m = NotchModel()
            let json = #"{"session_id":"q","cwd":"/Users/me/form-keeper","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which database should I use for the cache?","header":"Cache","options":[{"label":"SQLite","description":"Single file, no server"},{"label":"Redis","description":"Fast, needs a running server"},{"label":"In memory","description":"Simplest, lost on restart"}],"multiSelect":false}]}}"#
            if let e = HookEvent(json: Data(json.utf8)) { m.handle(e) { _ in } }
            m.mode = .expanded
            add("notch-question", CGSize(width: 640, height: 520), NotchView(model: m).background(Color(white: 0.85)))
        }
        do { // chat box on a held session
            let m = NotchModel()
            m.handle(HookEvent(name: "UserPromptSubmit", sessionID: "c", cwd: NSHomeDirectory() + "/form-keeper")) { _ in }
            m.setChatOpen("claude-code:c", true)
            m.handle(HookEvent(name: "Stop", sessionID: "c", cwd: NSHomeDirectory() + "/form-keeper", message: "All 32 tests pass. Want me to open a PR?")) { _ in }
            m.mode = .expanded
            add("notch-chat", CGSize(width: 640, height: 520), NotchView(model: m).background(Color(white: 0.85)))
        }
        do { // the desktop app's end-of-turn question, waiting on the user
            let m = NotchModel(), cwd = NSHomeDirectory() + "/form-keeper"
            let ask = #"{"recap":"Done.","ask":"Cut v0.3.0 so users get it?","actions":[{"label":"Yes, release"},{"label":"Not yet"}]}"#
            m.handle(HookEvent(name: "PreToolUse", sessionID: "n", cwd: cwd, toolName: "mcp__ccd_turn__wrap_up", toolInputJSON: ask)) { _ in }
            m.handle(HookEvent(name: "Stop", sessionID: "n", cwd: cwd)) { _ in }
            m.mode = .expanded
            add("notch-nextstep", CGSize(width: 640, height: 520), NotchView(model: m).background(Color(white: 0.85)))
        }
        // The app icon (scripts/make-icon.sh turns it into Resources/AppIcon.icns): Bolt on the notch's black, on Apple's 824-pt icon grid.
        add("app-icon", CGSize(width: 512, height: 512),
            RoundedRectangle(cornerRadius: 92, style: .continuous).fill(Color(hex: 0x111114))
                .overlay(BoltView(state: .done, size: 300).offset(y: 16)) // its shadow takes the bottom; this centers it by eye
                .frame(width: 412, height: 412))
        for tab in SettingsView.SettingsTab.allCases {
            add("settings-\(tab.rawValue)", CGSize(width: 640, height: 560), SettingsView(selectedTab: tab))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (name, view) in jobs {
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
            }
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
    }
}
