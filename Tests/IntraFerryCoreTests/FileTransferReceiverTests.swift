import XCTest
@testable import IntraFerryCore

final class FileTransferReceiverTests: XCTestCase {
    func testUploadsChunksAndFinalizesFile() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pathService = AuthorizedPathService(roots: [
            AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
        ])
        let store = TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        let receiver = FileTransferReceiver(pathService: pathService, store: store)
        let transferId = UUID()
        let fileId = "file-1"
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: root.path,
            rootName: "hello.txt",
            files: [TransferFileManifest(fileId: fileId, relativePath: "hello.txt", size: 10, chunkCount: 2)],
            chunkSize: 5
        )

        try receiver.prepare(manifest)
        try receiver.writeChunk(transferId: transferId, fileId: fileId, chunkIndex: 1, data: Data("World".utf8))
        try receiver.writeChunk(transferId: transferId, fileId: fileId, chunkIndex: 0, data: Data("Hello".utf8))
        let finalURL = try receiver.finalize(transferId: transferId)

        XCTAssertEqual(finalURL.lastPathComponent, "hello.txt")
        XCTAssertEqual(try String(contentsOf: finalURL), "HelloWorld")
    }

    func testDuplicateChunkIsIdempotent() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let receiver = FileTransferReceiver(
            pathService: AuthorizedPathService(roots: [AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)]),
            store: TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        )
        let transferId = UUID()
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: root.path,
            rootName: "a.txt",
            files: [TransferFileManifest(fileId: "a", relativePath: "a.txt", size: 1, chunkCount: 1)],
            chunkSize: 1
        )

        try receiver.prepare(manifest)
        try receiver.writeChunk(transferId: transferId, fileId: "a", chunkIndex: 0, data: Data("A".utf8))
        try receiver.writeChunk(transferId: transferId, fileId: "a", chunkIndex: 0, data: Data("A".utf8))

        XCTAssertEqual(try receiver.missingChunks(transferId: transferId), [])
    }

    func testFinalizesNestedFolderUnderRootName() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let receiver = FileTransferReceiver(
            pathService: AuthorizedPathService(roots: [AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)]),
            store: TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        )
        let transferId = UUID()
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: root.path,
            rootName: "Project",
            files: [TransferFileManifest(fileId: "main", relativePath: "Sources/main.swift", size: 4, chunkCount: 1)],
            chunkSize: 4
        )

        try receiver.prepare(manifest)
        try receiver.writeChunk(transferId: transferId, fileId: "main", chunkIndex: 0, data: Data("code".utf8))
        let finalURL = try receiver.finalize(transferId: transferId)

        XCTAssertEqual(finalURL.path, root.appendingPathComponent("Project").path)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Project/Sources/main.swift")), "code")
    }

    func testFinalizationRenamesWhenDestinationExists() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: root.appendingPathComponent("hello.txt"))
        let receiver = FileTransferReceiver(
            pathService: AuthorizedPathService(roots: [AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)]),
            store: TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        )
        let transferId = UUID()
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: root.path,
            rootName: "hello.txt",
            files: [TransferFileManifest(fileId: "hello", relativePath: "hello.txt", size: 3, chunkCount: 1)],
            chunkSize: 3
        )

        try receiver.prepare(manifest)
        try receiver.writeChunk(transferId: transferId, fileId: "hello", chunkIndex: 0, data: Data("new".utf8))
        let finalURL = try receiver.finalize(transferId: transferId)

        XCTAssertEqual(finalURL.lastPathComponent, "hello copy.txt")
        XCTAssertEqual(try String(contentsOf: finalURL), "new")
    }

    func testRejectsManifestRelativePathEscapingOutputDirectory() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let receiver = FileTransferReceiver(
            pathService: AuthorizedPathService(roots: [AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)]),
            store: TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        )
        let transferId = UUID()
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: root.path,
            rootName: "Project",
            files: [TransferFileManifest(fileId: "escape", relativePath: "../escape.txt", size: 1, chunkCount: 1)],
            chunkSize: 1
        )

        try receiver.prepare(manifest)
        try receiver.writeChunk(transferId: transferId, fileId: "escape", chunkIndex: 0, data: Data("x".utf8))

        XCTAssertThrowsError(try receiver.finalize(transferId: transferId)) { error in
            guard case .pathOutsideAuthorizedRoots = error as? FerryError else {
                return XCTFail("Expected pathOutsideAuthorizedRoots, got \(error)")
            }
        }
    }
}
