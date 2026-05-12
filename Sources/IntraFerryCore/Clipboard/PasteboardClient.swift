import AppKit
import Foundation

public protocol PasteboardClient: AnyObject, Sendable {
    var changeCount: Int { get }
    func readItems() throws -> [ClipboardItem]
    func writeItems(_ items: [ClipboardItem]) throws
}

public final class NSPasteboardClient: PasteboardClient, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public func readItems() throws -> [ClipboardItem] {
        pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in
                item.data(forType: type).map {
                    ClipboardItem(typeIdentifier: type.rawValue, data: $0)
                }
            }
        } ?? []
    }

    public func writeItems(_ items: [ClipboardItem]) throws {
        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        for item in items {
            pasteboardItem.setData(item.data, forType: NSPasteboard.PasteboardType(item.typeIdentifier))
        }

        guard pasteboard.writeObjects([pasteboardItem]) else {
            throw FerryError.clipboardWriteFailed("NSPasteboard rejected clipboard items")
        }
    }
}
