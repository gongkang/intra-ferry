import Foundation

public final class PeerServiceRuntime: @unchecked Sendable {
    private let server: NetworkHTTPServer

    public init(configuration: AppConfiguration, token: AuthToken, pasteboard: PasteboardClient) {
        let pathService = AuthorizedPathService(roots: configuration.authorizedRoots)
        let receiveTempRoot = configuration.authorizedRoots.first
            .map { URL(fileURLWithPath: $0.path).appendingPathComponent(".intra-ferry-tmp", isDirectory: true) }
            ?? URL(fileURLWithPath: configuration.stagingDirectoryPath).appendingPathComponent("receive-tasks", isDirectory: true)
        let receiverStore = TransferReceiverStore(baseDirectory: receiveTempRoot)
        let receiver = FileTransferReceiver(pathService: pathService, store: receiverStore)
        let clipboard = ClipboardService(
            localDeviceId: configuration.localDevice.id,
            pasteboard: pasteboard,
            serializer: ClipboardSerializer(localDeviceId: configuration.localDevice.id)
        )
        let router = PeerRouter(
            localDeviceId: configuration.localDevice.id,
            expectedToken: token,
            authorizedRoots: configuration.authorizedRoots,
            browser: LocalRemoteFileBrowser(pathService: pathService),
            receiver: receiver,
            clipboard: clipboard
        )
        let handler = PeerHTTPHandler(router: router)
        let port = UInt16(exactly: configuration.localDevice.servicePort) ?? 49491
        self.server = NetworkHTTPServer(port: port) { request in
            await handler.handle(request)
        }
    }

    public func start() throws {
        try server.start()
    }

    public func stop() {
        server.stop()
    }
}
