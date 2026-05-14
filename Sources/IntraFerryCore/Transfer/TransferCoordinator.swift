import Foundation

public struct TransferResult: Equatable, Sendable {
    public var transferId: UUID
    public var finalPath: String

    public init(transferId: UUID, finalPath: String) {
        self.transferId = transferId
        self.finalPath = finalPath
    }
}

public final class TransferCoordinator: @unchecked Sendable {
    private let planner: TransferPlanner
    private let client: PeerClient

    public init(planner: TransferPlanner, client: PeerClient) {
        self.planner = planner
        self.client = client
    }

    public func send(items: [URL], destinationPath: String, peer: PeerConfig, token: AuthToken) async throws -> TransferResult {
        let plan = try planner.plan(items: items, destinationPath: destinationPath)
        let finalPath = try await client.streamTransfer(peer: peer, token: token, plan: plan)
        return TransferResult(transferId: plan.manifest.transferId, finalPath: finalPath)
    }
}
