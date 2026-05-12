import Foundation
@testable import IntraFerryCore

final class FakePasteboardClient: PasteboardClient, @unchecked Sendable {
    var changeCount: Int = 0
    var items: [ClipboardItem] = []

    func readItems() throws -> [ClipboardItem] {
        items
    }

    func writeItems(_ items: [ClipboardItem]) throws {
        self.items = items
        changeCount += 1
    }
}
