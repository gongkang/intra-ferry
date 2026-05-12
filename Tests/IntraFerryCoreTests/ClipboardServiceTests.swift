import XCTest
@testable import IntraFerryCore

final class ClipboardServiceTests: XCTestCase {
    func testRemoteWriteIsNotEchoedBack() throws {
        let pasteboard = FakePasteboardClient()
        let localDevice = UUID()
        let remoteDevice = UUID()
        let service = ClipboardService(
            localDeviceId: localDevice,
            pasteboard: pasteboard,
            serializer: ClipboardSerializer(localDeviceId: localDevice)
        )
        let envelope = ClipboardEnvelope(
            id: UUID(),
            sourceDeviceId: remoteDevice,
            kind: .text,
            items: [ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))],
            createdAt: Date()
        )

        try service.applyRemoteEnvelope(envelope)

        XCTAssertFalse(service.shouldSendCurrentPasteboard())
    }

    func testCapturedLocalClipboardIsNotSentAgainWithoutChange() throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.changeCount = 1
        pasteboard.items = [ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))]
        let localDevice = UUID()
        let service = ClipboardService(
            localDeviceId: localDevice,
            pasteboard: pasteboard,
            serializer: ClipboardSerializer(localDeviceId: localDevice)
        )

        _ = try service.captureLocalEnvelope()

        XCTAssertFalse(service.shouldSendCurrentPasteboard())
    }
}
