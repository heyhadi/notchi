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
        add("bolt-22pt", CGSize(width: 220, height: 40),
            HStack(spacing: 8) { ForEach(AgentState.allCases, id: \.self) { BoltView(state: $0, size: 22) } }.background(Color.black))
        for (mode, state) in [(NotchMode.compact, AgentState.working), (.peek, .needsYou), (.expanded, .done)] {
            let m = NotchModel()
            m.debugOverride = state
            m.mode = mode
            add("notch-\(mode.rawValue)", CGSize(width: 640, height: 520), NotchView(model: m).background(Color(white: 0.85)))
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
