import XCTest
@testable import BudgetBot

final class SSEParserTests: XCTestCase {

    func test_parses_singleCompleteFrame() {
        var p = SSEParser()
        let payload = "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"hi\"}}\n\n"
        let events = p.feed(Data(payload.utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "content_block_delta")
        XCTAssertTrue(events.first?.data.contains("\"text\":\"hi\"") == true)
    }

    func test_handlesChunkedDelivery() {
        var p = SSEParser()
        XCTAssertTrue(p.feed(Data("event: foo\n".utf8)).isEmpty)
        XCTAssertTrue(p.feed(Data("data: {\"a\":1}\n".utf8)).isEmpty)
        let events = p.feed(Data("\n".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "foo")
        XCTAssertEqual(events.first?.data, "{\"a\":1}")
    }

    func test_handlesMultipleFramesInOneChunk() {
        var p = SSEParser()
        let payload = "event: a\ndata: 1\n\nevent: b\ndata: 2\n\n"
        let events = p.feed(Data(payload.utf8))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].name, "a")
        XCTAssertEqual(events[1].name, "b")
    }

    func test_concatenatesMultilineDataFields() {
        var p = SSEParser()
        let payload = "event: thing\ndata: line1\ndata: line2\n\n"
        let events = p.feed(Data(payload.utf8))
        XCTAssertEqual(events.first?.data, "line1\nline2")
    }

    func test_skipsCommentLines() {
        var p = SSEParser()
        let payload = ": keep-alive\nevent: ping\ndata: pong\n\n"
        let events = p.feed(Data(payload.utf8))
        XCTAssertEqual(events.first?.name, "ping")
        XCTAssertEqual(events.first?.data, "pong")
    }

    func test_flushReturnsTrailingFrame() {
        var p = SSEParser()
        _ = p.feed(Data("event: end\ndata: bye".utf8))   // no trailing blank
        let flushed = p.flush()
        XCTAssertEqual(flushed?.name, "end")
        XCTAssertEqual(flushed?.data, "bye")
    }

    func test_ignoresFramesWithNoData() {
        var p = SSEParser()
        let events = p.feed(Data("event: noop\n\n".utf8))
        XCTAssertTrue(events.isEmpty)
    }

    func test_byteAtATime_chunking() {
        var p = SSEParser()
        let payload = "event: x\ndata: y\n\n"
        var seen: [SSEParser.Event] = []
        for byte in payload.utf8 {
            seen.append(contentsOf: p.feed(Data([byte])))
        }
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.name, "x")
        XCTAssertEqual(seen.first?.data, "y")
    }
}
