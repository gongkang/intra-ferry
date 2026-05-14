import Foundation
import XCTest
@testable import IntraFerryCore

final class URLSessionPeerClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FailingURLProtocol.error = nil
        FailingURLProtocol.responseData = Data("[]".utf8)
        FailingURLProtocol.capturedRequests = []
    }

    func testRequestsAskServerToCloseConnection() async throws {
        let client = URLSessionPeerClient(session: Self.failingSession())
        let peer = try Self.peer()

        _ = try await client.listAuthorizedRoots(peer: peer, token: AuthToken(rawValue: "secret"))

        XCTAssertEqual(FailingURLProtocol.capturedRequests.last?.value(forHTTPHeaderField: "Connection"), "close")
    }

    func testStreamTransferUsesSingleStreamEndpointRequest() async throws {
        FailingURLProtocol.responseData = Data("/Users/task/inbox/hello.txt".utf8)
        let temp = try TemporaryDirectory()
        let file = temp.url.appendingPathComponent("hello.txt")
        try Data("HelloWorld".utf8).write(to: file)
        let plan = try TransferPlanner(chunkSize: 5).plan(items: [file], destinationPath: "/Users/task/inbox")
        let client = URLSessionPeerClient(session: Self.failingSession())
        let peer = try Self.peer()

        let finalPath = try await client.streamTransfer(peer: peer, token: AuthToken(rawValue: "secret"), plan: plan)

        XCTAssertEqual(finalPath, "/Users/task/inbox/hello.txt")
        XCTAssertEqual(FailingURLProtocol.capturedRequests.count, 1)
        XCTAssertEqual(FailingURLProtocol.capturedRequests.first?.url?.path, "/transfers/stream")
    }

    func testTimedOutRequestIsReportedAsRequestFailureNotOffline() async throws {
        FailingURLProtocol.error = URLError(.timedOut)
        let client = URLSessionPeerClient(session: Self.failingSession())
        let peer = try Self.peer()

        do {
            _ = try await client.listAuthorizedRoots(peer: peer, token: AuthToken(rawValue: "secret"))
            XCTFail("Expected request failure")
        } catch let error as FerryError {
            XCTAssertEqual(
                error,
                .peerRequestFailed(
                    host: "task-mac.local",
                    port: 49491,
                    reason: URLError(.timedOut).localizedDescription
                )
            )
        }
    }

    func testCannotConnectRequestIsReportedAsOffline() async throws {
        FailingURLProtocol.error = URLError(.cannotConnectToHost)
        let client = URLSessionPeerClient(session: Self.failingSession())
        let peer = try Self.peer()

        do {
            _ = try await client.listAuthorizedRoots(peer: peer, token: AuthToken(rawValue: "secret"))
            XCTFail("Expected offline failure")
        } catch let error as FerryError {
            XCTAssertEqual(error, .peerOffline(host: "task-mac.local", port: 49491))
        }
    }

    private static func failingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func peer() throws -> PeerConfig {
        try PeerConfig(
            id: UUID(),
            displayName: "Task Mac",
            host: "task-mac.local",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily Mac"
        )
    }
}

private final class FailingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var error: Error?
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedRequests.append(request)
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
