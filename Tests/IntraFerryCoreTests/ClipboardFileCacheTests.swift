import XCTest
@testable import IntraFerryCore

final class ClipboardFileCacheTests: XCTestCase {
    func testCachesCopiedFileAndReturnsLocalFileURLItem() throws {
        let temp = try TemporaryDirectory()
        let source = temp.url.appendingPathComponent("source.txt")
        try Data("cached".utf8).write(to: source)
        let cache = ClipboardFileCache(cacheDirectory: temp.url.appendingPathComponent("ClipboardCache"))

        let items = try cache.cacheFilesForPasteboard([source])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].typeIdentifier, "public.file-url")
        let cachedURL = URL(string: String(decoding: items[0].data, as: UTF8.self))!
        XCTAssertEqual(try String(contentsOf: cachedURL), "cached")
    }
}
