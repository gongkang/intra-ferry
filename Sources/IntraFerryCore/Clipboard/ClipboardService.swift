import Foundation

public final class ClipboardService: @unchecked Sendable {
    private let localDeviceId: UUID
    private let pasteboard: PasteboardClient
    private let serializer: ClipboardSerializer
    private var lastAppliedRemoteEnvelopeId: UUID?
    private var lastAppliedRemoteChangeCount: Int?
    private var lastCapturedLocalChangeCount: Int?

    public init(localDeviceId: UUID, pasteboard: PasteboardClient, serializer: ClipboardSerializer) {
        self.localDeviceId = localDeviceId
        self.pasteboard = pasteboard
        self.serializer = serializer
    }

    public func captureLocalEnvelope() throws -> ClipboardEnvelope {
        let envelope = try serializer.envelope(from: pasteboard.readItems())
        lastCapturedLocalChangeCount = pasteboard.changeCount
        return envelope
    }

    public func applyRemoteEnvelope(_ envelope: ClipboardEnvelope) throws {
        guard envelope.sourceDeviceId != localDeviceId else {
            return
        }

        try pasteboard.writeItems(envelope.items)
        lastAppliedRemoteEnvelopeId = envelope.id
        lastAppliedRemoteChangeCount = pasteboard.changeCount
    }

    public func shouldSendCurrentPasteboard() -> Bool {
        let currentChangeCount = pasteboard.changeCount
        return currentChangeCount != lastAppliedRemoteChangeCount &&
            currentChangeCount != lastCapturedLocalChangeCount
    }
}
