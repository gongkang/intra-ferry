import Foundation
import XCTest

final class TemporaryDirectory {
    let url: URL

    private let fileManager: FileManager

    init(function: StaticString = #function, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager

        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("IntraFerryTests", isDirectory: true)
            .appendingPathComponent(String(describing: function), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory
    }

    deinit {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            XCTFail("Failed to remove temporary directory \(url.path): \(error)")
        }
    }
}
