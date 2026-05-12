import Foundation
import XCTest
@testable import IntraFerryCore

final class AuthorizedPathServiceTests: XCTestCase {
    func testAllowsExactAuthorizedRoot() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let service = AuthorizedPathService(rootPaths: [temporaryDirectory.url.path])

        XCTAssertTrue(service.isAuthorized(path: temporaryDirectory.url.path))
    }

    func testAllowsChildInsideAuthorizedRoot() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let childURL = temporaryDirectory.url.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        let service = AuthorizedPathService(rootPaths: [temporaryDirectory.url.path])

        XCTAssertTrue(service.isAuthorized(path: childURL.path))
    }

    func testAllowsFutureLeafInsideAuthorizedRoot() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let parentURL = temporaryDirectory.url.appendingPathComponent("incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let service = AuthorizedPathService(rootPaths: [temporaryDirectory.url.path])

        XCTAssertTrue(service.isAuthorized(path: parentURL.appendingPathComponent("new-file.txt").path))
    }

    func testRejectsSiblingWithSimilarPrefix() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let service = AuthorizedPathService(rootPaths: [temporaryDirectory.url.path])

        XCTAssertFalse(service.isAuthorized(path: temporaryDirectory.url.path + "-copy"))
    }

    func testRejectsDotDotEscapeToSibling() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let rootURL = temporaryDirectory.url.appendingPathComponent("root", isDirectory: true)
        let siblingURL = temporaryDirectory.url.appendingPathComponent("root-sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingURL, withIntermediateDirectories: true)
        let service = AuthorizedPathService(rootPaths: [rootURL.path])

        XCTAssertFalse(service.isAuthorized(path: rootURL.path + "/../root-sibling"))
    }

    func testRejectsSymlinkInsideRootPointingOutsideRoot() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let rootURL = temporaryDirectory.url.appendingPathComponent("root", isDirectory: true)
        let outsideURL = temporaryDirectory.url.appendingPathComponent("outside", isDirectory: true)
        let linkURL = rootURL.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideURL)
        let service = AuthorizedPathService(rootPaths: [rootURL.path])

        XCTAssertFalse(service.isAuthorized(path: linkURL.appendingPathComponent("subdir").path))
    }

    func testLocalRemoteFileBrowserListsExistingDirectoryChildren() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let rootURL = temporaryDirectory.url
        let dataURL = rootURL.appendingPathComponent("data", isDirectory: true)
        let notesURL = rootURL.appendingPathComponent("notes.txt")
        let hiddenURL = rootURL.appendingPathComponent(".hidden.txt")
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: notesURL)
        try Data("hidden".utf8).write(to: hiddenURL)

        let service = AuthorizedPathService(rootPaths: [rootURL.path])
        let browser = LocalRemoteFileBrowser(pathService: service)

        let entries = try browser.listDirectory(path: rootURL.path)

        XCTAssertEqual(entries.map(\.name), ["data", "notes.txt"])
        XCTAssertEqual(entries.map(\.isDirectory), [true, false])
        XCTAssertEqual(entries.first?.size, nil)
        XCTAssertEqual(entries.last?.size, 5)
    }

    func testLocalRemoteFileBrowserThrowsPathMissingForMissingPath() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let missingPath = temporaryDirectory.url.appendingPathComponent("missing", isDirectory: true).path
        let service = AuthorizedPathService(rootPaths: [temporaryDirectory.url.path])
        let browser = LocalRemoteFileBrowser(pathService: service)

        XCTAssertThrowsError(try browser.listDirectory(path: missingPath)) { error in
            XCTAssertEqual(error as? FerryError, .pathMissing(missingPath))
        }
    }

    func testLocalRemoteFileBrowserThrowsPathMissingForExistingFilePath() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let fileURL = temporaryDirectory.url.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: fileURL)
        let service = AuthorizedPathService(rootPaths: [temporaryDirectory.url.path])
        let browser = LocalRemoteFileBrowser(pathService: service)

        XCTAssertThrowsError(try browser.listDirectory(path: fileURL.path)) { error in
            XCTAssertEqual(error as? FerryError, .pathMissing(fileURL.path))
        }
    }

    func testLocalRemoteFileBrowserMapsReadFailureToPermissionDenied() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let service = AuthorizedPathService(rootPaths: [temporaryDirectory.url.path])
        let browser = LocalRemoteFileBrowser(
            pathService: service,
            fileManager: ThrowingContentsFileManager()
        )

        XCTAssertThrowsError(try browser.listDirectory(path: temporaryDirectory.url.path)) { error in
            XCTAssertEqual(error as? FerryError, .permissionDenied(temporaryDirectory.url.path))
        }
    }

    func testLocalRemoteFileBrowserMapsChildResourceFailureToPermissionDenied() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let childURL = temporaryDirectory.url.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: childURL)
        let service = AuthorizedPathService(rootPaths: [temporaryDirectory.url.path])
        let browser = LocalRemoteFileBrowser(
            pathService: service,
            entryLoader: { _ -> RemoteFileEntry in
                throw CocoaError(.fileReadNoPermission)
            }
        )

        XCTAssertThrowsError(try browser.listDirectory(path: temporaryDirectory.url.path)) { error in
            XCTAssertEqual(error as? FerryError, .permissionDenied(temporaryDirectory.url.path))
        }
    }
}

private final class ThrowingContentsFileManager: FileManager {
    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        isDirectory?.pointee = true
        return true
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        throw CocoaError(.fileReadNoPermission)
    }
}
