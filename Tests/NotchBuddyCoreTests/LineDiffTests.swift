import XCTest
@testable import NotchBuddyCore

final class LineDiffTests: XCTestCase {
    private func ev(_ tool: String, _ input: [String: Any]) -> HookEvent {
        let json = String(data: try! JSONSerialization.data(withJSONObject: input), encoding: .utf8)
        return HookEvent(name: "PermissionRequest", sessionID: "s", toolName: tool, toolInputJSON: json)
    }

    func testIdenticalHasNoChanges() {
        XCTAssertTrue(LineDiff.lines(old: "a\nb\n", new: "a\nb\n").allSatisfy { $0.kind == .same } )
        XCTAssertEqual(LineDiff.lines(old: "a\nb", new: "a\nb").filter { $0.kind != .same }.count, 0)
    }

    func testMiddleChangeKeepsContextAndGap() {
        let old = (1...10).map { "l\($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "l5", with: "X")
        let d = LineDiff.lines(old: old, new: new)
        XCTAssertEqual(d.map(\.text), ["l3", "l4", "l5", "X", "l6", "l7"])
        XCTAssertEqual(d.map(\.kind), [.same, .same, .removed, .added, .same, .same])
        let far = LineDiff.lines(old: old, new: new, context: 1)
        XCTAssertEqual(far.map(\.text), ["l4", "l5", "X", "l6"])
        let two = LineDiff.lines(old: old, new: old.replacingOccurrences(of: "l1\n", with: "Y\n")
            .replacingOccurrences(of: "l10", with: "Z"))
        XCTAssertTrue(two.contains(DiffLine(kind: .same, text: "…")))
    }

    func testWriteAllAdded() {
        let d = ev("Write", ["content": "a\nb\n"]).editDiff
        XCTAssertEqual(d, [DiffLine(kind: .added, text: "a"), DiffLine(kind: .added, text: "b")])
    }

    func testMultiEditSeparatedByGap() {
        let d = ev("MultiEdit", ["edits": [["old_string": "a", "new_string": "b"], ["old_string": "c", "new_string": "d"]]]).editDiff
        XCTAssertEqual(d?.map(\.text), ["a", "b", "…", "c", "d"])
    }

    func testCapped() {
        let l = (0..<5).map { DiffLine(kind: .added, text: "\($0)") }
        let c = LineDiff.capped(l, limit: 3)
        XCTAssertEqual(c.shown.count, 3)
        XCTAssertEqual(c.more, 2)
    }

    func testNonEditToolIsNil() {
        XCTAssertNil(ev("Bash", ["command": "ls"]).editDiff)
    }

    func testEmptyOldString() {
        let d = ev("Edit", ["old_string": "", "new_string": "x"]).editDiff
        XCTAssertEqual(d, [DiffLine(kind: .added, text: "x")])
    }
}
