import XCTest
@testable import NotchBuddyCore

/// Claude Code's settings.json, including upgrading the config installed on 2026-11-12 (Stop had a 5 s timeout).
final class ClaudeSetupTests: XCTestCase {
    let hook = "/Users/me/notch-buddy/build/NotchBuddy.app/Contents/Helpers/notchbuddy-hook"
    var home = ""

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("nb-claude-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: home) }

    func hooks(_ s: String) throws -> [String: [[String: Any]]] {
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
        return try XCTUnwrap(o["hooks"] as? [String: [[String: Any]]])
    }

    func testUpgradeFromFirstInstallOnlyChangesStop() throws {
        let q = "'\(hook)'"
        let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                      "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
        var old: [String: Any] = ["theme": "dark", "permissions": ["allow": ["Bash(ls)"]]]
        var h: [String: Any] = [:]
        for e in events { h[e] = [["hooks": [["type": "command", "command": q, "timeout": e == "PermissionRequest" ? 600 : 5]]]] }
        h["Stop"] = [["hooks": [["type": "command", "command": "say done"]]], ["hooks": [["type": "command", "command": q, "timeout": 5]]]]
        old["hooks"] = h
        let oldText = String(decoding: try JSONSerialization.data(withJSONObject: old, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
        try oldText.write(toFile: home + "/.claude/settings.json", atomically: true, encoding: .utf8)

        XCTAssertTrue(AgentSetup.isInstalled(.claudeCode, hookPath: hook, home: home))
        let changes = try AgentSetup.plan(.claudeCode, install: true, hookPath: hook, home: home)
        XCTAssertEqual(changes.count, 1)
        let new = try XCTUnwrap(changes.first?.new)
        let before = try hooks(oldText), after = try hooks(new)
        for e in events where e != "Stop" {
            XCTAssertEqual(NSArray(array: before[e]!), NSArray(array: after[e]!), "\(e) unchanged")
        }
        let stop = try XCTUnwrap(after["Stop"])
        XCTAssertEqual(stop.count, 2, "user's own Stop hook kept, ours replaced not duplicated")
        XCTAssertEqual((stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String, "say done")
        let ours = try XCTUnwrap((stop[1]["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(ours["command"] as? String, q + " --wait 590")
        XCTAssertEqual(ours["timeout"] as? Int, 600)

        _ = try AgentSetup.apply(changes)
        XCTAssertEqual(try AgentSetup.plan(.claudeCode, install: true, hookPath: hook, home: home), [], "idempotent after upgrade")
        _ = try AgentSetup.apply(try AgentSetup.plan(.claudeCode, install: false, hookPath: hook, home: home))
        let removed = try String(contentsOfFile: home + "/.claude/settings.json", encoding: .utf8)
        XCTAssertFalse(removed.contains(q))
        XCTAssertTrue(removed.contains("say done"))
    }

    func testRejectsInvalidJSON() throws {
        try "{ not json".write(toFile: home + "/.claude/settings.json", atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AgentSetup.plan(.claudeCode, install: true, hookPath: hook, home: home))
    }
}
