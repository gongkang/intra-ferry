import Foundation
@testable import IntraFerryCore

final actor FakePeerClient: PeerClient {
    var prepared: TransferManifest?
    var uploadedChunks: [ChunkDescriptor: Data] = [:]
    var finalized: UUID?
    var sentClipboard: ClipboardEnvelope?

    func listDirectory(peer: PeerConfig, token: AuthToken, path: String) async throws -> [RemoteFileEntry] {
        []
    }

    func prepareTransfer(peer: PeerConfig, token: AuthToken, manifest: TransferManifest) async throws {
        prepared = manifest
    }

    func uploadChunk(
        peer: PeerConfig,
        token: AuthToken,
        transferId: UUID,
        fileId: String,
        chunkIndex: Int,
        data: Data
    ) async throws {
        uploadedChunks[ChunkDescriptor(fileId: fileId, chunkIndex: chunkIndex, offset: 0, length: data.count)] = data
    }

    func finalizeTransfer(peer: PeerConfig, token: AuthToken, transferId: UUID) async throws -> String {
        finalized = transferId
        return "/Users/task/inbox"
    }

    func sendClipboard(peer: PeerConfig, token: AuthToken, envelope: ClipboardEnvelope) async throws {
        sentClipboard = envelope
    }
}
