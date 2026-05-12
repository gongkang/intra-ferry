import Foundation
import SwiftUI
import IntraFerryCore

@MainActor
final class AppState: ObservableObject {
    @Published var configuration: AppConfiguration?
    @Published var clipboardSyncEnabled = true
    @Published var connectionStatus = "Not configured"
    @Published var latestClipboardStatus = "No clipboard sync yet"
    @Published var transferSummary = "No active transfers"

    let environment: AppEnvironment
    private var peerServiceRuntime: PeerServiceRuntime?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func loadAndStartServices() {
        do {
            let config = try environment.configurationStore.load()
            configuration = config
            clipboardSyncEnabled = config.clipboardSyncEnabled
            if let peer = config.peers.first,
               let token = try environment.secretStore.load(for: peer.tokenKey) {
                let runtime = PeerServiceRuntime(configuration: config, token: token, pasteboard: environment.pasteboard)
                try runtime.start()
                peerServiceRuntime = runtime
                connectionStatus = "Listening on port \(config.localDevice.servicePort)"
            }
        } catch {
            connectionStatus = "Not configured"
        }
    }
}
