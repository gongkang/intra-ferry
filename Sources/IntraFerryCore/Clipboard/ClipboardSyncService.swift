import Foundation

public final class ClipboardSyncService: @unchecked Sendable {
    private let clipboard: ClipboardService
    private let peer: PeerConfig
    private let token: AuthToken
    private let client: PeerClient
    private var timer: Timer?

    public init(clipboard: ClipboardService, peer: PeerConfig, token: AuthToken, client: PeerClient) {
        self.clipboard = clipboard
        self.peer = peer
        self.token = token
        self.client = client
    }

    public func start(interval: TimeInterval = 0.5) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                guard let self else {
                    return
                }
                try? await self.tick()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func tick() async throws {
        guard clipboard.shouldSendCurrentPasteboard() else {
            return
        }

        let envelope = try clipboard.captureLocalEnvelope()
        guard envelope.kind != .unsupported else {
            return
        }

        try await client.sendClipboard(peer: peer, token: token, envelope: envelope)
    }
}
