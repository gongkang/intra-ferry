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
}
