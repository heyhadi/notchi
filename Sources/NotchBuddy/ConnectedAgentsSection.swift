import SwiftUI
import NotchBuddyCore

/// Claude Code hook install/remove. Always shows the exact diff of ~/.claude/settings.json first,
/// writes only after the user presses Apply, and backs the file up before writing.
struct ConnectedAgentsSection: View {
    private struct Plan: Identifiable {
        let id = UUID()
        let install: Bool
        let new: String
        let diff: String
    }

    @State private var installed = HookSetup.isInstalled
    @State private var plan: Plan?
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code").font(.system(size: 14, weight: .medium))
                    Text(L("via hooks")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(installed ? L("Connected") : L("Not connected"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(installed ? Color(hex: 0x1E8E66) : .secondary)
                Button(installed ? L("Remove…") : L("Connect…")) { prepare(install: !installed) }
            }
            ForEach(["Antigravity", "Gemini CLI"], id: \.self) { name in
                HStack {
                    Text(name).font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text(L("Not supported yet")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if let message {
                Text(message).font(.system(size: 12)).foregroundColor(failed ? Color(hex: 0xD93636) : .secondary)
                    .textSelection(.enabled)
            }
        }
        .sheet(item: $plan) { p in diffSheet(p) }
    }

    private func diffSheet(_ p: Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(p.install ? L("Connect Claude Code") : L("Disconnect Claude Code"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(L("This exact change will be made to ~/.claude/settings.json. A backup copy is saved next to it first."))
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(p.diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        Text(String(line)).font(.system(size: 11, design: .monospaced))
                            .foregroundColor(line.hasPrefix("+") ? Color(hex: 0x1E8E66) : line.hasPrefix("-") ? Color(hex: 0xD93636) : .primary)
                    }
                }
                .textSelection(.enabled)
                .padding(10)
            }
            .frame(height: 280)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Spacer()
                Button(L("Cancel")) { plan = nil }.keyboardShortcut(.cancelAction)
                Button(p.install ? L("Connect") : L("Disconnect")) { apply(p) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func prepare(install: Bool) {
        do {
            let (new, diff) = try HookSetup.plan(install: install)
            if diff.isEmpty { installed = HookSetup.isInstalled; return }
            plan = Plan(install: install, new: new, diff: diff)
        } catch {
            show(L("Couldn't read ~/.claude/settings.json: ") + error.localizedDescription, failed: true)
        }
    }

    private func apply(_ p: Plan) {
        plan = nil
        do {
            // The file may have changed while the sheet was open: never write a diff the user didn't see.
            let (new, diff) = try HookSetup.plan(install: p.install)
            guard diff == p.diff else {
                plan = Plan(install: p.install, new: new, diff: diff)
                return
            }
            let backup = try HookInstaller.write(new)
            installed = HookSetup.isInstalled
            show(L("Saved. New Claude Code sessions will use it.") + (backup.map { "\n" + L("Backup: ") + $0 } ?? ""), failed: false)
        } catch {
            show(L("Couldn't update settings: ") + error.localizedDescription, failed: true)
        }
    }

    private func show(_ text: String, failed: Bool) {
        message = text
        self.failed = failed
    }
}
