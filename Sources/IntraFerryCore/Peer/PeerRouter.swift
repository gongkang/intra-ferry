import Foundation

public final class PeerRouter: @unchecked Sendable {
    private let localDeviceId: UUID
    private let expectedToken: AuthToken
    private let authorizedRoots: [AuthorizedRoot]
    private let browser: RemoteFileBrowsing
    private let receiver: FileTransferReceiver?
    private let clipboard: ClipboardService?

    public init(
        localDeviceId: UUID,
        expectedToken: AuthToken,
        authorizedRoots: [AuthorizedRoot] = [],
        browser: RemoteFileBrowsing,
        receiver: FileTransferReceiver?,
        clipboard: ClipboardService? = nil
    ) {
        self.localDeviceId = localDeviceId
        self.expectedToken = expectedToken
        self.authorizedRoots = authorizedRoots
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

    public func listAuthorizedRoots(request: PeerRequest) throws -> [AuthorizedRoot] {
        try authenticate(request)
        return authorizedRoots
    }

    public func receiveTransferStream(manifest: TransferManifest, decoder: TransferStreamDecoder, request: PeerRequest) async throws -> URL? {
        try authenticate(request)
        return try await receiver?.receiveStream(manifest: manifest, decoder: decoder)
    }

    public func applyClipboard(_ envelope: ClipboardEnvelope, request: PeerRequest) throws {
        try authenticate(request)
        try clipboard?.applyRemoteEnvelope(envelope)
    }
}
