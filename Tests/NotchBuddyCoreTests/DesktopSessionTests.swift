import XCTest
@testable import NotchBuddyCore

final class DesktopSessionTests: XCTestCase {
    func testFindsTheAppSessionForACLISession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ds-\(UUID())")
        let dir = root.appendingPathComponent("acct/ws")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ name: String, _ o: [String: Any]) throws {
            try JSONSerialization.data(withJSONObject: o).write(to: dir.appendingPathComponent(name))
        }
        try write("local_aaaa1111-0000-0000-0000-000000000000.json", ["sessionId": "local_aaaa1111-0000-0000-0000-000000000000", "cliSessionId": "cli-1", "lastActivityAt": 1.0])
        try write("local_bbbb2222-0000-0000-0000-000000000000.json", ["sessionId": "local_bbbb2222-0000-0000-0000-000000000000", "cliSessionId": "cli-2"])
        try write("local_evil.json", ["sessionId": "local_x\"; rm -rf ~", "cliSessionId": "cli-3"])
        XCTAssertEqual(DesktopSession.appSessionID(forCLI: "cli-1", in: root), "local_aaaa1111-0000-0000-0000-000000000000")
        XCTAssertEqual(DesktopSession.appSessionID(forCLI: "cli-2", in: root), "local_bbbb2222-0000-0000-0000-000000000000")
        XCTAssertNil(DesktopSession.appSessionID(forCLI: "cli-3", in: root), "odd ids never reach a URL")
        XCTAssertNil(DesktopSession.appSessionID(forCLI: "nope", in: root))
    }

    func testURL() {
        XCTAssertEqual(DesktopSession.url(appSessionID: "local_aaaa1111-0000-0000-0000-000000000000")?.absoluteString,
                       "claude://code/continue?session=local_aaaa1111-0000-0000-0000-000000000000&source=notchi")
        XCTAssertNil(DesktopSession.url(appSessionID: "local_../x"))
        XCTAssertEqual(DesktopSession.vsCodeURL(cliSessionID: "703d4dcd-cbb1-4788-94dc-786b4f157e06")?.absoluteString,
                       "vscode://anthropic.claude-code/open?session=703d4dcd-cbb1-4788-94dc-786b4f157e06")
        XCTAssertNil(DesktopSession.vsCodeURL(cliSessionID: "x&prompt=rm"))
    }
}
