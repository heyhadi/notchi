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

    static func current() -> String { (try? String(contentsOfFile: HookInstaller.settingsPath, encoding: .utf8)) ?? "" }
    static var isInstalled: Bool { HookInstaller.isInstalled(current(), hookPath: hookPath) }

    /// (new file content, unified diff) for installing or removing.
    static func plan(install: Bool) throws -> (String, String) {
        let old = current()
        let new = install ? try HookInstaller.installed(old, hookPath: hookPath) : try HookInstaller.uninstalled(old, hookPath: hookPath)
        return (new, try HookInstaller.diff(old: old, new: new))
    }

    static func runCLI(_ args: [String]) -> Never {
        do {
            let install = !args.contains("--uninstall-hook")
            let (new, diff) = try plan(install: install)
            if args.contains("--hook-diff") {
                print(diff.isEmpty ? "No change: already \(install ? "installed" : "removed")." : diff)
            } else if diff.isEmpty {
                print("No change.")
            } else {
                let backup = try HookInstaller.write(new)
                print("Updated \(HookInstaller.settingsPath)" + (backup.map { "\nBackup: \($0)" } ?? ""))
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
