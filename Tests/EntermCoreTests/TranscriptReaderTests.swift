import EntermCore
import XCTest

final class TranscriptReaderTests: XCTestCase {
    private func file(_ text: String) throws -> String {
        let path = NSTemporaryDirectory() + "transcript-\(UUID().uuidString).jsonl"
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    func testReadsWholeLinesThenOnlyWhatIsNew() throws {
        let path = try file("{\"a\":1}\n{\"b\":2}\n{\"half\":")
        let first = TranscriptReader.read(path: path, from: nil)
        XCTAssertEqual(first.text, "{\"a\":1}\n{\"b\":2}\n")
        XCTAssertFalse(first.reset)

        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: path))
        handle.seekToEndOfFile()
        handle.write(Data("3}\n".utf8))
        try handle.close()
        let second = TranscriptReader.read(path: path, from: first.offset)
        XCTAssertEqual(second.text, "{\"half\":3}\n")
        XCTAssertEqual(TranscriptReader.read(path: path, from: second.offset).text, "")
    }

    func testShorterFileStartsOver() throws {
        let path = try file("{\"x\":1}\n")
        let read = TranscriptReader.read(path: path, from: 5000)
        XCTAssertTrue(read.reset)
        XCTAssertEqual(read.text, "{\"x\":1}\n")
    }

    func testLongFileStartsNearTheEndOnALineBoundary() throws {
        let line = "{\"t\":\"" + String(repeating: "x", count: 1000) + "\"}\n"
        let path = try file(String(repeating: line, count: 600))
        let read = TranscriptReader.read(path: path, from: nil)
        XCTAssertTrue(read.text.hasPrefix("{\"t\""))
        XCTAssertTrue(read.text.hasSuffix("\"}\n"))
        XCTAssertLessThanOrEqual(Int64(read.text.utf8.count), TranscriptReader.window)
    }
}
