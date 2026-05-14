import XCTest
@testable import IntraFerryCore

final class LocalPeerIntegrationTests: XCTestCase {
    func testCoordinatorStreamsPlannedTransferInSingleRequest() async throws {
        let temp = try TemporaryDirectory()
        let file = temp.url.appendingPathComponent("hello.txt")
        try Data("HelloWorld".utf8).write(to: file)
        let client = FakePeerClient()
        let coordinator = TransferCoordinator(planner: TransferPlanner(chunkSize: 5), client: client)
        let peer = try PeerConfig(
            id: UUID(),
            displayName: "Task",
            host: "127.0.0.1",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily"
        )
        let token = AuthToken(rawValue: "secret")

        let result = try await coordinator.send(
            items: [file],
            destinationPath: "/Users/task/inbox",
            peer: peer,
            token: token
        )

        XCTAssertEqual(result.finalPath, "/Users/task/inbox")
        let streamed = await client.streamedTransfer
        XCTAssertEqual(streamed?.manifest.transferId, result.transferId)
        XCTAssertEqual(streamed?.chunks.map(\.chunkIndex), [0, 1])
    }
}
