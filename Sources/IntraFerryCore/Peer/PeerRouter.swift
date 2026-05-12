import Foundation

public final class PeerRouter: @unchecked Sendable {
    private let localDeviceId: UUID
    private let expectedToken: AuthToken
    private let browser: RemoteFileBrowsing
    private let receiver: FileTransferReceiver?
    private let clipboard: ClipboardService?

    public init(
        localDeviceId: UUID,
        expectedToken: AuthToken,
        browser: RemoteFileBrowsing,
        receiver: FileTransferReceiver?,
        clipboard: ClipboardService? = nil
    ) {
        self.localDeviceId = localDeviceId
        self.expectedToken = expectedToken
        self.browser = browser
        self.receiver = receiver
        self.clipboard = clipboard
    }

    public func authenticate(_ request: PeerRequest) throws {
        guard request.protocolVersion == IntraFerryCore.protocolVersion else {
            throw FerryError.unsupportedProtocolVersion(request.protocolVersion)
        }
        guard request.token == expectedToken else {
            throw FerryError.invalidToken
        }
    }

    public func listDirectory(path: String, request: PeerRequest) throws -> [RemoteFileEntry] {
        try authenticate(request)
        return try browser.listDirectory(path: path)
    }

    public func prepareTransfer(_ manifest: TransferManifest, request: PeerRequest) throws {
        try authenticate(request)
        try receiver?.prepare(manifest)
    }

    public func writeChunk(transferId: UUID, fileId: String, chunkIndex: Int, data: Data, request: PeerRequest) throws {
        try authenticate(request)
        try receiver?.writeChunk(transferId: transferId, fileId: fileId, chunkIndex: chunkIndex, data: data)
    }

    public func finalizeTransfer(transferId: UUID, request: PeerRequest) throws -> URL? {
        try authenticate(request)
        return try receiver?.finalize(transferId: transferId)
    }

    public func applyClipboard(_ envelope: ClipboardEnvelope, request: PeerRequest) throws {
        try authenticate(request)
        try clipboard?.applyRemoteEnvelope(envelope)
    }
}
