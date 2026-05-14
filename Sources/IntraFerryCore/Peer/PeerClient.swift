import Foundation

public protocol PeerClient: Sendable {
    func listAuthorizedRoots(peer: PeerConfig, token: AuthToken) async throws -> [AuthorizedRoot]
    func listDirectory(peer: PeerConfig, token: AuthToken, path: String) async throws -> [RemoteFileEntry]
    func streamTransfer(peer: PeerConfig, token: AuthToken, plan: TransferPlan) async throws -> String
    func sendClipboard(peer: PeerConfig, token: AuthToken, envelope: ClipboardEnvelope) async throws
}
