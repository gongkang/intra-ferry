import Foundation
import XCTest
@testable import IntraFerryCore

final class URLSessionPeerClientTests: XCTestCase {
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

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: Self.error ?? URLError(.unknown))
    }

    override func stopLoading() {}
}
