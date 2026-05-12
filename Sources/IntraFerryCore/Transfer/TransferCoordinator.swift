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
        try await client.prepareTransfer(peer: peer, token: token, manifest: plan.manifest)

        for chunk in plan.chunks {
            guard let fileURL = plan.sourceFiles[chunk.fileId] else {
                throw FerryError.pathMissing(chunk.fileId)
            }

            let data = try readChunk(
                fileURL: fileURL,
                offset: chunk.offset,
                length: chunk.length,
                transferId: plan.manifest.transferId
            )
            try await client.uploadChunk(
                peer: peer,
                token: token,
                transferId: plan.manifest.transferId,
                fileId: chunk.fileId,
                chunkIndex: chunk.chunkIndex,
                data: data
            )
        }

        let finalPath = try await client.finalizeTransfer(peer: peer, token: token, transferId: plan.manifest.transferId)
        return TransferResult(transferId: plan.manifest.transferId, finalPath: finalPath)
    }

    private func readChunk(fileURL: URL, offset: Int64, length: Int, transferId: UUID) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: length) ?? Data()
        guard data.count == length else {
            throw FerryError.transferIncomplete(transferId)
        }
        return data
    }
}
