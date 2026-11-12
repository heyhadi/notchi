import XCTest
@testable import NotchBuddyCore

final class TokenUsageTests: XCTestCase {
    private func line(_ id: String, _ ts: String, input: Int, output: Int, write: Int = 0, read: Int = 0) -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","message":{"id":"\#(id)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(write),"cache_read_input_tokens":\#(read)}}}"#
    }

    func testCountsEachMessageOnceAndSplitsToday() {
        let today = "2026-11-12T01:00:00.000Z", yesterday = "2026-11-11T01:00:00.000Z"
        let text = [line("a", yesterday, input: 10, output: 5),
                    line("b", today, input: 2, output: 100, write: 1000, read: 9999),
                    line("b", today, input: 2, output: 100, write: 1000, read: 9999), // same message, second content block
                    #"{"type":"user","message":{"content":"hi"}}"#].joined(separator: "\n") + "\n"
        var u = TranscriptUsage()
        u.consume(Data(text.utf8)) { $0 > ISO8601DateFormatter().date(from: "2026-11-12T00:00:00Z")! }
        XCTAssertEqual(u.all.total, 15 + 1102)
        XCTAssertEqual(u.all.cacheRead, 9999)
        XCTAssertEqual(u.today.total, 1102)
        XCTAssertEqual(u.offset, UInt64(text.utf8.count))
    }

    func testHalfWrittenLineWaits() {
        let full = line("a", "2026-11-12T01:00:00.000Z", input: 1, output: 1) + "\n"
        var u = TranscriptUsage()
        u.consume(Data((full + #"{"type":"assist"#).utf8)) { _ in true }
        XCTAssertEqual(u.all.total, 2)
        XCTAssertEqual(u.offset, UInt64(full.utf8.count))
    }

    func testShort() {
        XCTAssertEqual(TokenCount.short(850), "850")
        XCTAssertEqual(TokenCount.short(48_200), "48.2k")
        XCTAssertEqual(TokenCount.short(2_000_000), "2M")
    }
}
