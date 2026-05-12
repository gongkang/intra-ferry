import Foundation
import SwiftUI
import IntraFerryCore

@MainActor
final class AppState: ObservableObject {
    @Published var configuration: AppConfiguration?
    @Published var clipboardSyncEnabled = true {
        didSet {
            clipboardSyncEnabled ? clipboardSyncService?.start() : clipboardSyncService?.stop()
        }
    }
    @Published var connectionStatus = "Not configured"
    @Published var latestClipboardStatus = "No clipboard sync yet"
    @Published var transferSummary = "No active transfers"
    @Published var transferProgress = 0.0
    @Published var localName = "Daily Mac"
    @Published var peerHost = ""
    @Published var peerPort = 49491
    @Published var sharedToken = ""
    @Published var authorizedReceivePath = ""
    @Published var remotePath = ""
    @Published var remoteEntries: [RemoteFileEntry] = []

    let environment: AppEnvironment
    private var peerServiceRuntime: PeerServiceRuntime?
    private var clipboardSyncService: ClipboardSyncService?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func loadAndStartServices() {
        do {
            let config = try environment.configurationStore.load()
            apply(config)
            if let peer = config.peers.first,
               let token = try environment.secretStore.load(for: peer.tokenKey) {
                sharedToken = token.rawValue
                try startPeerServices(config: config, peer: peer, token: token)
            }
        } catch {
            connectionStatus = "Not configured"
        }
    }

    func saveSettings() {
        do {
            let local = LocalDeviceConfig(
                id: configuration?.localDevice.id ?? UUID(),
                displayName: localName,
                servicePort: 49491
            )
            let peer = try PeerConfig(
                id: configuration?.peers.first?.id ?? UUID(),
                displayName: "Peer",
                host: peerHost,
                port: peerPort,
                tokenKey: "peer.default",
                localDeviceName: localName
            )
            let roots = authorizedReceivePath.isEmpty ? [] : [
                AuthorizedRoot(id: configuration?.authorizedRoots.first?.id ?? UUID(), displayName: "Receive", path: authorizedReceivePath)
            ]
            let staging = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("IntraFerry", isDirectory: true)
                .path
            let config = AppConfiguration(
                localDevice: local,
                peers: [peer],
                authorizedRoots: roots,
                clipboardSyncEnabled: clipboardSyncEnabled,
                stagingDirectoryPath: staging
            )

            try environment.configurationStore.save(config)
            let token = AuthToken(rawValue: sharedToken)
            try environment.secretStore.save(token, for: peer.tokenKey)
            apply(config)
            try startPeerServices(config: config, peer: peer, token: token)
            connectionStatus = "Saved settings"
        } catch {
            connectionStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    func refreshRemotePath() async {
        guard let peer = configuration?.peers.first else {
            return
        }

        do {
            guard let token = try environment.secretStore.load(for: peer.tokenKey) else {
                return
            }
            remoteEntries = try await environment.peerClient.listDirectory(peer: peer, token: token, path: remotePath)
        } catch {
            transferSummary = "Remote browse failed: \(error.localizedDescription)"
        }
    }

    func sendDroppedFiles(_ urls: [URL]) async {
        guard let peer = configuration?.peers.first else {
            return
        }

        do {
            guard let token = try environment.secretStore.load(for: peer.tokenKey) else {
                return
            }
            transferProgress = 0
            transferSummary = "Sending \(urls.count) item(s)"
            let coordinator = TransferCoordinator(planner: TransferPlanner(), client: environment.peerClient)
            let result = try await coordinator.send(items: urls, destinationPath: remotePath, peer: peer, token: token)
            transferProgress = 1
            transferSummary = "Sent to \(result.finalPath)"
        } catch {
            transferSummary = "Transfer failed: \(error.localizedDescription)"
        }
    }

    private func apply(_ config: AppConfiguration) {
        configuration = config
        clipboardSyncEnabled = config.clipboardSyncEnabled
        localName = config.localDevice.displayName
        peerHost = config.peers.first?.host ?? ""
        peerPort = config.peers.first?.port ?? 49491
        authorizedReceivePath = config.authorizedRoots.first?.path ?? ""
        remotePath = config.authorizedRoots.first?.path ?? remotePath
    }

    private func startPeerServices(config: AppConfiguration, peer: PeerConfig, token: AuthToken) throws {
        peerServiceRuntime?.stop()
        clipboardSyncService?.stop()

        let runtime = PeerServiceRuntime(configuration: config, token: token, pasteboard: environment.pasteboard)
        try runtime.start()
        peerServiceRuntime = runtime
        startClipboardSync(peer: peer, token: token, config: config)
        connectionStatus = "Listening on port \(config.localDevice.servicePort)"
    }

    private func startClipboardSync(peer: PeerConfig, token: AuthToken, config: AppConfiguration) {
        let clipboard = ClipboardService(
            localDeviceId: config.localDevice.id,
            pasteboard: environment.pasteboard,
            serializer: ClipboardSerializer(localDeviceId: config.localDevice.id)
        )
        let sync = ClipboardSyncService(clipboard: clipboard, peer: peer, token: token, client: environment.peerClient)
        if clipboardSyncEnabled {
            sync.start()
        }
        clipboardSyncService = sync
    }
}
