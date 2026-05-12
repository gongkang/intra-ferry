import XCTest
@testable import IntraFerryCore

final class ClipboardSerializerTests: XCTestCase {
    func testSerializesTextEnvelope() throws {
        let serializer = ClipboardSerializer(localDeviceId: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
        let item = ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))

        let envelope = try serializer.envelope(from: [item])

        XCTAssertEqual(envelope.kind, .text)
        XCTAssertEqual(envelope.items, [item])
    }
}
