import XCTest
@testable import NotchBuddyCore

final class AgentSetupTests: XCTestCase {
    var home = ""
    let hook = "/Apps/Notch Buddy.app/Contents/Helpers/notchbuddy-hook"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("nb-home-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: home) }

    func put(_ rel: String, _ s: String) throws {
        let p = home + "/" + rel
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try s.write(toFile: p, atomically: true, encoding: .utf8)
    }
    func obj(_ rel: String) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: home + "/" + rel))) as? NSDictionary)
    }

    func roundTrip(_ a: AgentKind, file: String?, userContent: String?) throws {
        if let file, let userContent { try put(file, userContent) }
        let before = file.flatMap { try? obj($0) }
        let install = try AgentSetup.plan(a, install: true, hookPath: hook, home: home)
        XCTAssertFalse(install.isEmpty, "\(a)")
        XCTAssertFalse(try AgentSetup.diff(install).isEmpty)
        _ = try AgentSetup.apply(install)
        XCTAssertTrue(AgentSetup.isInstalled(a, hookPath: hook, home: home), "\(a) installed")
        XCTAssertEqual(try AgentSetup.plan(a, install: true, hookPath: hook, home: home), [], "\(a) install is idempotent")
        _ = try AgentSetup.apply(try AgentSetup.plan(a, install: false, hookPath: hook, home: home))
        XCTAssertFalse(AgentSetup.isInstalled(a, hookPath: hook, home: home), "\(a) removed")
        if let file, let before { XCTAssertEqual(try obj(file), before, "\(a): user's own config restored exactly") }
    }

    func testJSONMergeAgentsKeepUserContent() throws {
        try roundTrip(.codex, file: ".codex/hooks.json",
                      userContent: #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        try roundTrip(.geminiCLI, file: ".gemini/settings.json",
                      userContent: #"{"ide":{"enabled":true},"security":{"auth":{"selectedType":"gemini-api-key"}}}"#)
        try roundTrip(.cursor, file: ".cursor/hooks.json",
                      userContent: #"{"version":1,"hooks":{"stop":[{"command":"./mine.sh"}]}}"#)
        try roundTrip(.antigravity, file: ".gemini/config/hooks.json",
                      userContent: #"{"my-linter":{"PostToolUse":[{"matcher":"run_command","hooks":[{"command":"./lint.sh"}]}]}}"#)
    }

    func testOwnedFilesAgents() throws {
        try roundTrip(.copilot, file: nil, userContent: nil)
        try roundTrip(.openCode, file: nil, userContent: nil)
        try roundTrip(.cline, file: nil, userContent: nil)
        try roundTrip(.claudeCode, file: ".claude/settings.json", userContent: #"{"theme":"dark"}"#)
    }

    func testClineScriptsAreExecutableAndNeverOverwriteUserHooks() throws {
        _ = try AgentSetup.apply(try AgentSetup.plan(.cline, install: true, hookPath: hook, home: home))
        let p = home + "/Documents/Cline/Hooks/PreToolUse"
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: p))
        XCTAssertTrue(try String(contentsOfFile: p, encoding: .utf8).contains("--agent cline --event PreToolUse"))
        _ = try AgentSetup.apply(try AgentSetup.plan(.cline, install: false, hookPath: hook, home: home))
        try put("Documents/Cline/Hooks/TaskStart", "#!/bin/sh\necho mine\n")
        XCTAssertThrowsError(try AgentSetup.plan(.cline, install: true, hookPath: hook, home: home))
        XCTAssertThrowsError(try AgentSetup.plan(.cline, install: false, hookPath: hook, home: home), "never deletes the user's hook")
    }

    func testCommandsQuotePathsAndCarryAgent() {
        let c = AgentSetup.command(hook, .antigravity, event: "PreToolUse", fallback: #"{"decision":"allow"}"#)
        XCTAssertEqual(c, #"'/Apps/Notch Buddy.app/Contents/Helpers/notchbuddy-hook' --agent antigravity --event PreToolUse --default '{"decision":"allow"}'"#)
    }
}
