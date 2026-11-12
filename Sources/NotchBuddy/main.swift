import AppKit
import NotchBuddyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var notchPanel: NotchPanel?
    private var roamManager: RoamManager?
    private let model = NotchModel()
    private var debugSubmenu: NSMenu?
    private let hookServer = HookServer()
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupEditMenu()
        setupStatusItem()

        let panel = NotchPanel(model: model)
        self.notchPanel = panel
        panel.orderFrontRegardless()
        roamManager = RoamManager(model: model)

        hookServer.onEvent = { [model] event, respond in model.handle(event, respond: respond) }
        do { try hookServer.start() } catch { NSLog("Notchi: hook socket failed: \(error)") }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [model] _ in
            MainActor.assumeIsolated { model.refresh(after: nil) }
        }
    }

    /// Accessory apps have no menu bar, but Cmd-C/V/X/A/Z only work through Edit menu key equivalents.
    /// This menu is never shown; it just makes copy and paste work in the chat and question boxes.
    private func setupEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "Notchi", action: nil, keyEquivalent: ""))
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: L("Notchi"))
        }

        let menu = NSMenu()
        menu.delegate = self

        // Debug submenu
        let debugItem = NSMenuItem(title: L("Debug: force state"), action: nil, keyEquivalent: "")
        let debugMenu = NSMenu(title: L("Debug: force state"))
        debugMenu.delegate = self

        let autoItem = NSMenuItem(title: L("Automatic"), action: #selector(selectAutomatic), keyEquivalent: "")
        autoItem.target = self
        debugMenu.addItem(autoItem)

        for state in AgentState.allCases {
            let stateItem = NSMenuItem(
                title: stateName(state),
                action: #selector(selectState(_:)),
                keyEquivalent: ""
            )
            stateItem.target = self
            stateItem.representedObject = state.rawValue
            debugMenu.addItem(stateItem)
        }

        debugItem.submenu = debugMenu
        self.debugSubmenu = debugMenu
        menu.addItem(debugItem)

        let settingsItem = NSMenuItem(
            title: L("Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: L("Quit Notchi"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item

        updateDebugCheckmarks()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateDebugCheckmarks()
    }

    private func updateDebugCheckmarks() {
        guard let debugMenu = debugSubmenu else { return }
        for item in debugMenu.items {
            if item.action == #selector(selectAutomatic) {
                item.state = (model.debugOverride == nil) ? .on : .off
            } else if let raw = item.representedObject as? String,
                      let state = AgentState(rawValue: raw) {
                item.state = (model.debugOverride == state) ? .on : .off
            }
        }
    }

    @objc private func selectAutomatic() {
        model.debugOverride = nil
        updateDebugCheckmarks()
    }

    @objc private func selectState(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let state = AgentState(rawValue: raw) {
            model.debugOverride = state
            updateDebugCheckmarks()
        }
    }

    @objc private func openSettings() {
        SettingsWindow.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    Prefs.register()
    if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
        Snapshot.run(to: CommandLine.arguments[i + 1])
        exit(0)
    }
    if let i = CommandLine.arguments.firstIndex(of: "--selftest"), i + 1 < CommandLine.arguments.count {
        SelfTest.run(hook: CommandLine.arguments[i + 1])
    }
    let args = CommandLine.arguments
    if args.contains(where: { ["--hook-diff", "--install-hook", "--uninstall-hook", "--diff", "--connect", "--disconnect"].contains($0) }) {
        HookSetup.runCLI(args)
    }
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
