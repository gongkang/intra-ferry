import XCTest
@testable import IntraFerryCore

final class ClipboardSyncServiceTests: XCTestCase {
    func testTickSendsLocalClipboardWhenChanged() async throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.items = [ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))]
        pasteboard.changeCount = 1
        let client = FakePeerClient()
        let localDevice = UUID()
        let peer = try PeerConfig(
            id: UUID(),
            displayName: "Task",
            host: "127.0.0.1",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily"
        )
        let service = ClipboardSyncService(
            clipboard: ClipboardService(
                localDeviceId: localDevice,
                pasteboard: pasteboard,
                serializer: ClipboardSerializer(localDeviceId: localDevice)
            ),
            peer: peer,
            token: AuthToken(rawValue: "secret"),
            client: client
        )

        try await service.tick()

        XCTAssertEqual(await client.sentClipboard?.kind, .text)
    }

    func testTickDoesNotEchoRemoteClipboardAppliedByAnotherServiceInstance() async throws {
        let pasteboard = FakePasteboardClient()
        let client = FakePeerClient()
        let localDevice = UUID()
        let peer = try PeerConfig(
            id: UUID(),
            displayName: "Task",
            host: "127.0.0.1",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily"
        )
        let inboundClipboard = ClipboardService(
            localDeviceId: localDevice,
            pasteboard: pasteboard,
            serializer: ClipboardSerializer(localDeviceId: localDevice)
        )
        let outboundClipboard = ClipboardService(
            localDeviceId: localDevice,
            pasteboard: pasteboard,
            serializer: ClipboardSerializer(localDeviceId: localDevice)
        )
        let sync = ClipboardSyncService(
            clipboard: outboundClipboard,
            peer: peer,
            token: AuthToken(rawValue: "secret"),
            client: client
        )
        let remoteEnvelope = ClipboardEnvelope(
            id: UUID(),
            sourceDeviceId: UUID(),
            kind: .text,
            items: [ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("remote".utf8))],
            createdAt: Date()
        )

        try inboundClipboard.applyRemoteEnvelope(remoteEnvelope)
        try await sync.tick()

        XCTAssertNil(await client.sentClipboard)
    }
}
