import Foundation
import NotchBuddyCore

/// Hook install/uninstall shared by Settings and the CLI flags
/// (`--hook-diff`, `--install-hook`, `--uninstall-hook`).
enum HookSetup {
    /// notchbuddy-hook inside the .app (Contents/Helpers), or next to the binary in a SwiftPM build.
    static var hookPath: String {
        let exe = Bundle.main.executableURL!.resolvingSymlinksInPath()
        let helpers = exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Helpers/notchbuddy-hook")
        return FileManager.default.fileExists(atPath: helpers.path) ? helpers.path
            : exe.deletingLastPathComponent().appendingPathComponent("notchbuddy-hook").path
    }

    /// `--diff|--connect|--disconnect <agent>` (also the older `--hook-diff|--install-hook|--uninstall-hook` for Claude Code).
    /// NB_HOME redirects every write to a test folder.
    static func runCLI(_ args: [String]) -> Never {
        let legacy = ["--hook-diff": "--diff", "--install-hook": "--connect", "--uninstall-hook": "--disconnect"]
        let verb = args.first { legacy[$0] != nil || ["--diff", "--connect", "--disconnect"].contains($0) }.map { legacy[$0] ?? $0 } ?? "--diff"
        let id = args.firstIndex(of: verb).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let agent = id.flatMap(AgentKind.init(rawValue:)) ?? .claudeCode
        let home = ProcessInfo.processInfo.environment["NB_HOME"] ?? NSHomeDirectory()
        do {
            let changes = try AgentSetup.plan(agent, install: verb != "--disconnect", hookPath: hookPath, home: home)
            if changes.isEmpty { print("No change for \(agent.displayName)."); exit(0) }
            if verb == "--diff" { print(try AgentSetup.diff(changes)); exit(0) }
            let backups = try AgentSetup.apply(changes)
            print("Updated: " + changes.map(\.path).joined(separator: ", "))
            for b in backups { print("Backup: \(b)") }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
