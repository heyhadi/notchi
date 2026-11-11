import AppKit
import SwiftUI

/// Hosts the standalone Settings window.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if let window = window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = L("Notch Buddy Settings")
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = NSHostingView(rootView: SettingsView())
        newWindow.center()
        self.window = newWindow

        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }
}
