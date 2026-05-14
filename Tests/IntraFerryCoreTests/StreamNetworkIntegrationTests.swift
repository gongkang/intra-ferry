import Darwin
import XCTest
@testable import IntraFerryCore

final class StreamNetworkIntegrationTests: XCTestCase {
    func testURLSessionClientStreamsFolderThroughNetworkServer() async throws {
        let temp = try TemporaryDirectory()
        let receiveRoot = temp.url.appendingPathComponent("Inbox", isDirectory: true)
        let sourceRoot = temp.url.appendingPathComponent("Project", isDirectory: true)
        let nested = sourceRoot.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: receiveRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("Hello".utf8).write(to: sourceRoot.appendingPathComponent("README.md"))
        try Data("World".utf8).write(to: nested.appendingPathComponent("main.swift"))

        let pathService = AuthorizedPathService(roots: [
            AuthorizedRoot(id: UUID(), displayName: "Inbox", path: receiveRoot.path)
        ])
        let receiver = FileTransferReceiver(
            pathService: pathService,
            store: TransferReceiverStore(baseDirectory: receiveRoot.appendingPathComponent(".intra-ferry-tmp"))
        )
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: pathService),
            receiver: receiver
        )
        let handler = PeerHTTPHandler(router: router)
        let port = try Self.availablePort()
        let server = NetworkHTTPServer(
            port: port,
            handler: { request in
                await handler.handle(request)
            },
            streamHandler: { request in
                await handler.handleStream(request)
            }
        )
        try server.start()
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 100_000_000)

        let peer = try PeerConfig(
            id: UUID(),
            displayName: "Local",
            host: "127.0.0.1",
            port: Int(port),
            tokenKey: "peer.local",
            localDeviceName: "Test"
        )
        let coordinator = TransferCoordinator(
            planner: TransferPlanner(chunkSize: 3),
            client: URLSessionPeerClient(session: URLSession(configuration: .ephemeral))
        )

        let result = try await coordinator.send(
            items: [sourceRoot],
            destinationPath: receiveRoot.path,
            peer: peer,
            token: AuthToken(rawValue: "secret")
        )

        let finalURL = URL(fileURLWithPath: result.finalPath, isDirectory: true)
        XCTAssertEqual(finalURL.lastPathComponent, "Project")
        XCTAssertEqual(try String(contentsOf: finalURL.appendingPathComponent("README.md")), "Hello")
        XCTAssertEqual(try String(contentsOf: finalURL.appendingPathComponent("Sources/main.swift")), "World")
    }

    private static func availablePort() throws -> UInt16 {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw FerryError.peerOffline(host: "127.0.0.1", port: 0)
        }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = in_addr_t(INADDR_LOOPBACK.bigEndian)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw FerryError.peerOffline(host: "127.0.0.1", port: 0)
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(socketDescriptor, socketAddress, &length)
            }
        }
        guard nameResult == 0 else {
            throw FerryError.peerOffline(host: "127.0.0.1", port: 0)
        }

        return UInt16(bigEndian: address.sin_port)
    }
}
