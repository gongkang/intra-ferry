import Foundation

public protocol PeerClient: Sendable {
    func listAuthorizedRoots(peer: PeerConfig, token: AuthToken) async throws -> [AuthorizedRoot]
    func listDirectory(peer: PeerConfig, token: AuthToken, path: String) async throws -> [RemoteFileEntry]
    func prepareTransfer(peer: PeerConfig, token: AuthToken, manifest: TransferManifest) async throws
    func uploadChunk(peer: PeerConfig, token: AuthToken, transferId: UUID, fileId: String, chunkIndex: Int, data: Data) async throws
    func finalizeTransfer(peer: PeerConfig, token: AuthToken, transferId: UUID) async throws -> String
    func sendClipboard(peer: PeerConfig, token: AuthToken, envelope: ClipboardEnvelope) async throws
}
