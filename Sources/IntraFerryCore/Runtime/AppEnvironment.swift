import Foundation

public struct AppEnvironment: Sendable {
    public var configurationStore: ConfigurationStore
    public var secretStore: SecretStore
    public var peerClient: PeerClient
    public var pasteboard: PasteboardClient

    public init(
        configurationStore: ConfigurationStore,
        secretStore: SecretStore,
        peerClient: PeerClient,
        pasteboard: PasteboardClient
    ) {
        self.configurationStore = configurationStore
        self.secretStore = secretStore
        self.peerClient = peerClient
        self.pasteboard = pasteboard
    }

    public static func production() -> AppEnvironment {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IntraFerry", isDirectory: true)

        return AppEnvironment(
            configurationStore: FileConfigurationStore(fileURL: support.appendingPathComponent("config.json")),
            secretStore: FileSecretStore(fileURL: support.appendingPathComponent("secrets.json")),
            peerClient: URLSessionPeerClient(),
            pasteboard: NSPasteboardClient()
        )
    }
}
