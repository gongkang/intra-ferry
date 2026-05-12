import XCTest
@testable import IntraFerryCore

final class PeerModelsTests: XCTestCase {
    func testProtocolVersionStartsAtOne() {
        XCTAssertEqual(IntraFerryCore.protocolVersion, "1")
    }
}
