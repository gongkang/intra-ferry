import Foundation

public final class ClipboardService: @unchecked Sendable {
    private static let stateRegistry = ClipboardSyncStateRegistry()

    private let localDeviceId: UUID
    private let pasteboard: PasteboardClient
    private let serializer: ClipboardSerializer
    private let state: ClipboardSyncState

    public init(localDeviceId: UUID, pasteboard: PasteboardClient, serializer: ClipboardSerializer) {
        self.localDeviceId = localDeviceId
        self.pasteboard = pasteboard
        self.serializer = serializer
        self.state = Self.stateRegistry.state(for: pasteboard)
    }

    public func captureLocalEnvelope() throws -> ClipboardEnvelope {
        let envelope = try serializer.envelope(from: pasteboard.readItems())
        state.recordCapturedLocalChangeCount(pasteboard.changeCount)
        return envelope
    }

    public func applyRemoteEnvelope(_ envelope: ClipboardEnvelope) throws {
        guard envelope.sourceDeviceId != localDeviceId else {
            return
        }

        try pasteboard.writeItems(envelope.items)
        state.recordAppliedRemoteEnvelope(id: envelope.id, changeCount: pasteboard.changeCount)
    }

    public func shouldSendCurrentPasteboard() -> Bool {
        state.shouldSend(changeCount: pasteboard.changeCount)
    }
}

private final class ClipboardSyncState: @unchecked Sendable {
    private let lock = NSLock()
    private var lastAppliedRemoteEnvelopeId: UUID?
    private var lastAppliedRemoteChangeCount: Int?
    private var lastCapturedLocalChangeCount: Int?

    func recordAppliedRemoteEnvelope(id: UUID, changeCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        lastAppliedRemoteEnvelopeId = id
        lastAppliedRemoteChangeCount = changeCount
    }

    func recordCapturedLocalChangeCount(_ changeCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        lastCapturedLocalChangeCount = changeCount
    }

    func shouldSend(changeCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return changeCount != lastAppliedRemoteChangeCount &&
            changeCount != lastCapturedLocalChangeCount
    }
}

private final class ClipboardSyncStateRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private let statesByPasteboard = NSMapTable<AnyObject, ClipboardSyncState>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

    func state(for pasteboard: PasteboardClient) -> ClipboardSyncState {
        lock.lock()
        defer { lock.unlock() }

        let key = pasteboard as AnyObject
        if let state = statesByPasteboard.object(forKey: key) {
            return state
        }

        let state = ClipboardSyncState()
        statesByPasteboard.setObject(state, forKey: key)
        return state
    }
}
