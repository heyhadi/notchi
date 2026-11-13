import AppKit
import NotchBuddyCore

/// Finds a newer Notchi on GitHub Releases and swaps it in place: download the DMG, check it, replace the app, relaunch.
/// The only network call the app makes; it sends nothing but the request itself.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum Status: Equatable {
        case idle, checking, upToDate
        case available(version: String)
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    private var dmgURL: URL?
    private var timer: Timer?
    private var isIdle: () -> Bool = { true }

    static let releasesPage = URL(string: "https://github.com/heyhadi/notchi/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/heyhadi/notchi/releases/latest")!
    private static let downloadPrefix = "https://github.com/heyhadi/notchi/releases/download/"

    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    /// Only the released Notchi.app updates itself; a dev build (build/NotchBuddy.app) would be overwritten by the release.
    let canUpdate = Bundle.main.bundleURL.lastPathComponent == "Notchi.app"

    /// Checks shortly after launch, then every 6 hours. With automatic updates on, installs once no agent is busy.
    func start(isIdle: @escaping () -> Bool) {
        self.isIdle = isIdle
        guard canUpdate else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard UserDefaults.standard.bool(forKey: Prefs.autoUpdate) else { return }
        Task {
            await check()
            guard case .available = status else { return }
            if isIdle() { await install() } else { NSLog("Notchi: update waits until no agent is busy") }
        }
    }

    func check() async {
        guard canUpdate, status != .installing else { return }
        status = .checking
        do {
            var req = URLRequest(url: Self.latestAPI, timeoutInterval: 20)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = o["tag_name"] as? String else { throw Fail(L("Couldn't read the latest release.")) }
            let dmg = (o["assets"] as? [[String: Any]] ?? [])
                .first { $0["name"] as? String == "Notchi.dmg" }?["browser_download_url"] as? String
            guard AppVersion.isNewer(tag, than: current),
                  let dmg, dmg.hasPrefix(Self.downloadPrefix), let url = URL(string: dmg) else { status = .upToDate; return }
            dmgURL = url
            status = .available(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag)
            NSLog("Notchi: update \(tag) available (have \(current))")
        } catch {
            NSLog("Notchi: update check failed: \(error)")
            status = .failed((error as? Fail)?.message ?? L("Couldn't reach GitHub."))
        }
    }

    func install() async {
        guard case .available(let version) = status, let dmgURL else { return }
        status = .installing
        let app = Bundle.main.bundleURL
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("notchi-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }

            // URLSession downloads carry no quarantine flag, so the swapped-in app opens without the Gatekeeper prompt.
            let (tmp, resp) = try await URLSession.shared.download(from: dmgURL)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Fail(L("The download failed.")) }
            let dmg = work.appendingPathComponent("Notchi.dmg")
            try FileManager.default.moveItem(at: tmp, to: dmg)

            let mount = work.appendingPathComponent("mnt")
            try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
            defer { Task.detached { try? await Self.runDetached("/usr/bin/hdiutil", ["detach", "-force", mount.path]) } }

            let fresh = mount.appendingPathComponent("Notchi.app")
            let info = Bundle(url: fresh)?.infoDictionary
            guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  info?["CFBundleShortVersionString"] as? String == version else { throw Fail(L("The download isn't the expected Notchi version.")) }
            try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", fresh.path])

            // Stage next to the running app (same volume), then swap: macOS keeps the running copy alive until it quits.
            let staged = app.deletingLastPathComponent().appendingPathComponent(".Notchi-update.app")
            try? FileManager.default.removeItem(at: staged)
            try await run("/usr/bin/ditto", [fresh.path, staged.path])
            _ = try FileManager.default.replaceItemAt(app, withItemAt: staged)
        } catch {
            NSLog("Notchi: update install failed: \(error)")
            status = .failed((error as? Fail)?.message ?? L("Couldn't replace the app. Download it from GitHub instead."))
            return
        }
        relaunch(app)
    }

    /// A tiny shell waits for this process to exit, then opens the new copy.
    private func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private struct Fail: Error { let message: String; init(_ m: String) { message = m } }

    private func run(_ tool: String, _ args: [String]) async throws {
        try await Self.runDetached(tool, args)
    }

    private nonisolated static func runDetached(_ tool: String, _ args: [String]) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { p in
                p.terminationStatus == 0 ? c.resume() : c.resume(throwing: Fail("\(URL(fileURLWithPath: tool).lastPathComponent) failed (\(p.terminationStatus))"))
            }
            do { try p.run() } catch { c.resume(throwing: error) }
        }
    }
}
