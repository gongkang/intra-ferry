import XCTest
@testable import IntraFerryCore

final class PeerHTTPHandlerTests: XCTestCase {
    func testDirectoryRouteRejectsInvalidToken() async throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )
        let handler = PeerHTTPHandler(router: router)
        let request = HTTPRequest(
            method: "GET",
            path: "/directories?path=\(root.path)",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "wrong"
            ],
            body: Data()
        )

        let response = await handler.handle(request)

        XCTAssertEqual(response.statusCode, 401)
    }

    func testDirectoryRouteListsAuthorizedPath() async throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: root.appendingPathComponent("ok.txt"))
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )
        let handler = PeerHTTPHandler(router: router)
        let encodedPath = root.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let request = HTTPRequest(
            method: "GET",
            path: "/directories?path=\(encodedPath)",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "secret"
            ],
            body: Data()
        )

        let response = await handler.handle(request)
        let entries = try JSONDecoder().decode([RemoteFileEntry].self, from: response.body)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(entries.map(\.name), ["ok.txt"])
    }

    func testClipboardRouteAppliesEnvelope() async throws {
        let pasteboard = FakePasteboardClient()
        let localDevice = UUID()
        let router = PeerRouter(
            localDeviceId: localDevice,
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [])),
            receiver: nil,
            clipboard: ClipboardService(
                localDeviceId: localDevice,
                pasteboard: pasteboard,
                serializer: ClipboardSerializer(localDeviceId: localDevice)
            )
        )
        let handler = PeerHTTPHandler(router: router)
        let envelope = ClipboardEnvelope(
            id: UUID(),
            sourceDeviceId: UUID(),
            kind: .text,
            items: [ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("remote".utf8))],
            createdAt: Date()
        )
        let request = HTTPRequest(
            method: "POST",
            path: "/clipboard",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "secret"
            ],
            body: try JSONEncoder().encode(envelope)
        )

        let response = await handler.handle(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(pasteboard.items, envelope.items)
    }

    func testLegacyChunkTransferRoutesAreNotAvailable() async throws {
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [])),
            receiver: nil
        )
        let handler = PeerHTTPHandler(router: router)
        let transferId = UUID()
        let headers = [
            "X-Intra-Ferry-Protocol": "1",
            "X-Intra-Ferry-Device-Id": UUID().uuidString,
            "X-Intra-Ferry-Token": "secret"
        ]
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: "/tmp",
            rootName: "file.txt",
            files: [TransferFileManifest(fileId: "file", relativePath: "file.txt", size: 5, chunkCount: 1)],
            chunkSize: 5
        )

        let prepareResponse = await handler.handle(HTTPRequest(
            method: "POST",
            path: "/transfers",
            headers: headers,
            body: try JSONEncoder().encode(manifest)
        ))
        let chunkResponse = await handler.handle(HTTPRequest(
            method: "PUT",
            path: "/transfers/\(transferId.uuidString)/files/file/chunks/0",
            headers: headers,
            body: Data("chunk".utf8)
        ))
        let finalizeResponse = await handler.handle(HTTPRequest(
            method: "POST",
            path: "/transfers/\(transferId.uuidString)/finalize",
            headers: headers,
            body: Data()
        ))

        XCTAssertEqual(prepareResponse.statusCode, 404)
        XCTAssertEqual(chunkResponse.statusCode, 404)
        XCTAssertEqual(finalizeResponse.statusCode, 404)
    }

    func testStreamRouteRejectsInvalidTokenBeforeReadingBody() async throws {
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [])),
            receiver: nil
        )
        let handler = PeerHTTPHandler(router: router)
        let body = CountingStreamBody()

        let response = await handler.handleStream(HTTPStreamRequest(
            method: "POST",
            path: "/transfers/stream",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "wrong"
            ],
            body: body
        ))

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(body.readCount, 0)
    }

    func testStreamRouteReceivesChunksAndFinalizesTransfer() async throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        let source = temp.url.appendingPathComponent("hello.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("HelloWorld".utf8).write(to: source)
        let pathService = AuthorizedPathService(roots: [
            AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
        ])
        let receiver = FileTransferReceiver(
            pathService: pathService,
            store: TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        )
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: pathService),
            receiver: receiver
        )
        let handler = PeerHTTPHandler(router: router)
        let plan = try TransferPlanner(chunkSize: 5).plan(items: [source], destinationPath: root.path)
        let payloadURL = temp.url.appendingPathComponent("stream.bin")
        try TransferStreamEncoder.write(plan: plan, to: payloadURL)

        let response = await handler.handleStream(HTTPStreamRequest(
            method: "POST",
            path: "/transfers/stream",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "secret"
            ],
            body: DataTransferStreamReader(data: try Data(contentsOf: payloadURL))
        ))

        let finalPath = String(decoding: response.body, as: UTF8.self)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: finalPath)), "HelloWorld")
    }

    func testStreamRouteDoesNotPersistReceiverStateForEveryChunk() async throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        let source = temp.url.appendingPathComponent("hello.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("HelloWorld".utf8).write(to: source)
        let pathService = AuthorizedPathService(roots: [
            AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
        ])
        let store = CountingTransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        let receiver = FileTransferReceiver(pathService: pathService, store: store)
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: pathService),
            receiver: receiver
        )
        let handler = PeerHTTPHandler(router: router)
        let plan = try TransferPlanner(chunkSize: 5).plan(items: [source], destinationPath: root.path)
        let payloadURL = temp.url.appendingPathComponent("stream.bin")
        try TransferStreamEncoder.write(plan: plan, to: payloadURL)

        let response = await handler.handleStream(HTTPStreamRequest(
            method: "POST",
            path: "/transfers/stream",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "secret"
            ],
            body: DataTransferStreamReader(data: try Data(contentsOf: payloadURL))
        ))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.loadCount, 0)
    }
}

private final class CountingStreamBody: TransferStreamReading, @unchecked Sendable {
    private(set) var readCount = 0

    func readExact(_ count: Int) async throws -> Data {
        readCount += 1
        throw FerryError.pathMissing("Body should not be read.")
    }
}

private final class CountingTransferReceiverStore: TransferReceiverStoring, @unchecked Sendable {
    private let wrapped: TransferReceiverStore
    private(set) var saveCount = 0
    private(set) var loadCount = 0

    init(baseDirectory: URL) {
        wrapped = TransferReceiverStore(baseDirectory: baseDirectory)
    }

    func taskDirectory(for transferId: UUID) -> URL {
        wrapped.taskDirectory(for: transferId)
    }

    func chunksDirectory(for transferId: UUID) -> URL {
        wrapped.chunksDirectory(for: transferId)
    }

    func loadState(transferId: UUID) throws -> TransferReceiverState {
        loadCount += 1
        return try wrapped.loadState(transferId: transferId)
    }

    func saveState(_ state: TransferReceiverState) throws {
        saveCount += 1
        try wrapped.saveState(state)
    }

    func deleteTask(transferId: UUID) throws {
        try wrapped.deleteTask(transferId: transferId)
    }
}
