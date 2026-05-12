import XCTest
@testable import IntraFerryCore

final class PeerModelsTests: XCTestCase {
    func testPeerBaseURLUsesHostAndPort() throws {
        let peer = try PeerConfig(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Task Mac",
            host: "task-mac.local",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily Mac"
        )

        XCTAssertEqual(peer.baseURL.absoluteString, "http://task-mac.local:49491")
    }

    func testPeerBaseURLSupportsIPv6Host() throws {
        let peer = try PeerConfig(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Task Mac",
            host: "::1",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily Mac"
        )

        XCTAssertEqual(peer.baseURL.absoluteString, "http://[::1]:49491")
    }

    func testPeerConfigRejectsInvalidHosts() {
        XCTAssertThrowsError(try PeerConfig(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Task Mac",
            host: "",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily Mac"
        ))

        XCTAssertThrowsError(try PeerConfig(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Task Mac",
            host: "task mac.local",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily Mac"
        ))
    }

    func testPeerConfigRejectsInvalidPorts() {
        XCTAssertThrowsError(try PeerConfig(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Task Mac",
            host: "task-mac.local",
            port: 0,
            tokenKey: "peer.task",
            localDeviceName: "Daily Mac"
        ))

        XCTAssertThrowsError(try PeerConfig(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Task Mac",
            host: "task-mac.local",
            port: 65536,
            tokenKey: "peer.task",
            localDeviceName: "Daily Mac"
        ))
    }

    func testPeerConfigRejectsInvalidDecodedHostValues() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "displayName": "Task Mac",
            "host": "task mac.local",
            "port": 49491,
            "tokenKey": "peer.task",
            "localDeviceName": "Daily Mac"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(PeerConfig.self, from: json))
    }

    func testPeerConfigRejectsInvalidDecodedPortValues() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "displayName": "Task Mac",
            "host": "task-mac.local",
            "port": 70000,
            "tokenKey": "peer.task",
            "localDeviceName": "Daily Mac"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(PeerConfig.self, from: json))
    }

    func testAuthTokenRedactionDoesNotExposeSecret() {
        let token = AuthToken(rawValue: "secret-token-123")

        XCTAssertEqual(token.redacted, "sec...123")
    }

    func testFerryErrorDescriptionIsHumanReadable() {
        let error = FerryError.peerOffline(host: "task-mac.local", port: 49491)

        XCTAssertEqual(error.errorDescription, "Peer task-mac.local:49491 is offline.")
    }

    func testFerryRequestFailureDescriptionKeepsUnderlyingReason() {
        let error = FerryError.peerRequestFailed(host: "task-mac.local", port: 49491, reason: "The request timed out.")

        XCTAssertEqual(error.errorDescription, "Request to peer task-mac.local:49491 failed: The request timed out.")
    }
}
