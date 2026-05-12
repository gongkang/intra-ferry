import XCTest
@testable import IntraFerryCore

final class PeerModelsTests: XCTestCase {
    func testPeerBaseURLUsesHostAndPort() throws {
        let peer = PeerConfig(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Task Mac",
            host: "task-mac.local",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily Mac"
        )

        XCTAssertEqual(peer.baseURL.absoluteString, "http://task-mac.local:49491")
    }

    func testAuthTokenRedactionDoesNotExposeSecret() {
        let token = AuthToken(rawValue: "secret-token-123")

        XCTAssertEqual(token.redacted, "sec...123")
    }

    func testFerryErrorDescriptionIsHumanReadable() {
        let error = FerryError.peerOffline(host: "task-mac.local", port: 49491)

        XCTAssertEqual(error.errorDescription, "Peer task-mac.local:49491 is offline.")
    }
}
