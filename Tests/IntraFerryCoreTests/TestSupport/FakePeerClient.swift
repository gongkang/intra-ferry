import Foundation
@testable import IntraFerryCore

final actor FakePeerClient: PeerClient {
    var sentClipboard: ClipboardEnvelope?
    var streamedTransfer: TransferStreamCapture?

    func listAuthorizedRoots(peer: PeerConfig, token: AuthToken) async throws -> [AuthorizedRoot] {
        []
    }

    func listDirectory(peer: PeerConfig, token: AuthToken, path: String) async throws -> [RemoteFileEntry] {
        []
    }

    func streamTransfer(peer: PeerConfig, token: AuthToken, plan: TransferPlan) async throws -> String {
        streamedTransfer = TransferStreamCapture(manifest: plan.manifest, chunks: plan.chunks)
        return "/Users/task/inbox"
    }

    func sendClipboard(peer: PeerConfig, token: AuthToken, envelope: ClipboardEnvelope) async throws {
        sentClipboard = envelope
    }
}

struct TransferStreamCapture: Equatable {
    var manifest: TransferManifest
    var chunks: [ChunkDescriptor]
}
