import SwiftUI
import NotchBuddyCore

/// Connect/disconnect each agent. Always shows the exact diff of the agent's config files first, writes only after
/// the user presses Apply, re-checks that nothing changed meanwhile, and backs every file up before writing.
struct ConnectedAgentsSection: View {
    private struct Plan: Identifiable {
        let id = UUID()
        let agent: AgentKind
        let install: Bool
        let changes: [FileChange]
        let diff: String
    }

    @State private var installed: Set<AgentKind> = Set(AgentKind.allCases.filter { AgentSetup.isInstalled($0, hookPath: HookSetup.hookPath) })
    @State private var outdated: Set<AgentKind> = []
    @State private var plan: Plan?
    @State private var message: String?
    @State private var failed = false

    /// Popular agents without an official hook API yet (checked Nov 2026).
    private let unsupported = [("Kilo Code", "No official hooks yet"), ("Roo Code", "No official hooks yet"),
                               ("Windsurf", "Hook format not documented clearly yet")]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AgentKind.allCases, id: \.self) { a in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.displayName).font(.system(size: 14, weight: .medium))
                        Text(subtitle(a)).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(installed.contains(a) ? L("Connected") : L("Not connected"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(installed.contains(a) ? Color(hex: 0x1E8E66) : .secondary)
                    if outdated.contains(a) {
                        Button(L("Update…")) { prepare(a, install: true) }
                    }
                    Button(installed.contains(a) ? L("Remove…") : L("Connect…")) { prepare(a, install: !installed.contains(a)) }
                        .accessibilityLabel(installed.contains(a) ? String(format: L("Remove %@"), a.displayName) : String(format: L("Connect %@"), a.displayName))
                }
            }
            ForEach(unsupported, id: \.0) { name, why in
                HStack {
                    Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(L(why)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if let message {
                Text(message).font(.system(size: 12)).foregroundColor(failed ? Color(hex: 0xD93636) : .secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $plan) { p in diffSheet(p) }
        .onAppear(perform: refresh)
    }

    private func subtitle(_ a: AgentKind) -> String {
        let how = a.approvesInNotch ? L("Status and approvals") : L("Status; risky commands stay with the agent")
        switch a {
        case .claudeCode: return how + " · " + L("CLI, VS Code, Desktop")
        case .cline, .copilot: return how + " · " + L("VS Code")
        default: return how
        }
    }

    private func diffSheet(_ p: Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: p.install ? L("Connect %@") : L("Disconnect %@"), p.agent.displayName))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(L("These exact changes will be made. Existing files are backed up next to themselves first."))
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(p.diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        Text(String(line)).font(.system(size: 11, design: .monospaced))
                            .foregroundColor(line.hasPrefix("###") ? .primary : line.hasPrefix("+") ? Color(hex: 0x1E8E66) : line.hasPrefix("-") ? Color(hex: 0xD93636) : .secondary)
                    }
                }
                .textSelection(.enabled)
                .padding(10)
            }
            .frame(height: 300)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Spacer()
                Button(L("Cancel")) { plan = nil }.keyboardShortcut(.cancelAction)
                Button(p.install ? L("Connect") : L("Disconnect")) { apply(p) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private func prepare(_ a: AgentKind, install: Bool) {
        do {
            let changes = try AgentSetup.plan(a, install: install, hookPath: HookSetup.hookPath)
            if changes.isEmpty { refresh(); return }
            plan = Plan(agent: a, install: install, changes: changes, diff: try AgentSetup.diff(changes))
        } catch {
            show(error.localizedDescription, failed: true)
        }
    }

    private func apply(_ p: Plan) {
        plan = nil
        do {
            // A file may have changed while the sheet was open: never write a diff the user didn't see.
            let changes = try AgentSetup.plan(p.agent, install: p.install, hookPath: HookSetup.hookPath)
            guard changes == p.changes else {
                plan = Plan(agent: p.agent, install: p.install, changes: changes, diff: try AgentSetup.diff(changes))
                return
            }
            let backups = try AgentSetup.apply(changes)
            refresh()
            var text = L("Saved. New sessions will use it.")
            if p.install, let note = afterInstallNote(p.agent) { text += " " + note }
            for b in backups { text += "\n" + L("Backup: ") + b }
            show(text, failed: false)
        } catch {
            show(L("Couldn't update settings: ") + error.localizedDescription, failed: true)
        }
    }

    private func afterInstallNote(_ a: AgentKind) -> String? {
        switch a {
        case .codex: L("In Codex, run /hooks once to trust the new hooks.")
        case .cline: L("In Cline settings, make sure Hooks are enabled.")
        case .cursor, .copilot, .antigravity: L("Restart the app or extension to load the hooks.")
        case .openCode: L("Restart OpenCode to load the plugin.")
        default: nil
        }
    }

    private func refresh() {
        installed = Set(AgentKind.allCases.filter { AgentSetup.isInstalled($0, hookPath: HookSetup.hookPath) })
        // Connected, but our entries differ from what this version writes (e.g. Stop now waits for chat replies).
        outdated = installed.filter { !((try? AgentSetup.plan($0, install: true, hookPath: HookSetup.hookPath)) ?? []).isEmpty }
    }

    private func show(_ text: String, failed: Bool) {
        message = text
        self.failed = failed
    }
}
