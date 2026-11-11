import XCTest
@testable import NotchBuddyCore

final class HookInstallerTests: XCTestCase {
    let path = "/Applications/Notch Buddy.app/Contents/Helpers/notchbuddy-hook"

    func testInstallIsIdempotentAndUninstallRestores() throws {
        let original = """
        {
          "permissions": {
            "allow": ["Bash(ls)"]
          },
          "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]
          },
          "theme": "dark"
        }
        """
        let once = try HookInstaller.installed(original, hookPath: path)
        let twice = try HookInstaller.installed(once, hookPath: path)
        XCTAssertEqual(once, twice)
        XCTAssertTrue(HookInstaller.isInstalled(once, hookPath: path))

        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(once.utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(obj["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(Set(hooks.keys), Set(HookInstaller.events))
        XCTAssertEqual(hooks["Stop"]?.count, 2, "keeps the user's own Stop hook")
        let pr = try XCTUnwrap((hooks["PermissionRequest"]?.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(pr["timeout"] as? Int, 600)
        XCTAssertEqual(pr["command"] as? String, "'\(path)'")
        XCTAssertNotNil(obj["permissions"])

        let removed = try HookInstaller.uninstalled(once, hookPath: path)
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(removed.utf8)) as? NSDictionary)
        let orig = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(original.utf8)) as? NSDictionary)
        XCTAssertEqual(back, orig)
        XCTAssertFalse(HookInstaller.isInstalled(removed, hookPath: path))
    }

    func testEmptySettingsAndDiff() throws {
        let new = try HookInstaller.installed("", hookPath: path)
        XCTAssertTrue(new.contains("PermissionRequest"))
        let removed = try HookInstaller.uninstalled(new, hookPath: path)
        XCTAssertEqual(removed.trimmingCharacters(in: .whitespacesAndNewlines), "{}")
        let d = try HookInstaller.diff(old: "{}\n", new: new)
        XCTAssertTrue(d.contains("+") && d.contains("settings.json (after)"))
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(try HookInstaller.installed("{ not json", hookPath: path))
    }
}
